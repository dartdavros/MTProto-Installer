# shellcheck shell=bash

rotation_backup_id_from_path() {
  basename "$1"
}

rotation_backup_metadata_path() {
  local backup_dir="$1"
  printf '%s/metadata.env\n' "${backup_dir}"
}

rotation_backup_count() {
  find "${ROTATION_BACKUPS_DIR}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l
}

latest_rotation_backup_id() {
  local latest_dir
  latest_dir="$(resolve_rotation_backup_ref latest 2>/dev/null || true)"
  [[ -n "${latest_dir}" ]] || return 1
  rotation_backup_id_from_path "${latest_dir}"
}

resolve_rotation_backup_ref() {
  local ref="$1"

  [[ -n "${ref}" ]] || return 1

  case "${ref}" in
    latest)
      [[ -L "${ROTATION_BACKUP_LATEST_LINK}" ]] || return 1
      readlink -f "${ROTATION_BACKUP_LATEST_LINK}"
      ;;
    *)
      [[ -d "${ROTATION_BACKUPS_DIR}/${ref}" ]] || return 1
      printf '%s\n' "${ROTATION_BACKUPS_DIR}/${ref}"
      ;;
  esac
}

record_rotation_backup_metadata() {
  local backup_dir="$1"
  local operation="$2"
  local slot_name="$3"
  local metadata_path

  metadata_path="$(rotation_backup_metadata_path "${backup_dir}")"
  {
    quote_kv BACKUP_ID "$(rotation_backup_id_from_path "${backup_dir}")"
    quote_kv CREATED_AT "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    quote_kv OPERATION "${operation}"
    quote_kv SLOT_NAME "${slot_name}"
    quote_kv ENGINE "${ENGINE}"
    quote_kv PUBLIC_DOMAIN "${PUBLIC_DOMAIN}"
    quote_kv PUBLIC_PORT "${PUBLIC_PORT}"
    quote_kv LINK_STRATEGY "${LINK_STRATEGY}"
  } > "${metadata_path}"
}

create_rotation_backup() {
  local operation="$1"
  local slot_name="${2:-}"
  local backup_id backup_dir

  mkdir -p "${ROTATION_BACKUPS_DIR}"
  chown root:"${RUN_GROUP}" "${ROTATION_BACKUPS_DIR}"
  chmod 750 "${ROTATION_BACKUPS_DIR}"

  backup_id="$(date -u '+%Y%m%dT%H%M%SZ')-${operation}"
  if [[ -n "${slot_name}" ]]; then
    backup_id+="-${slot_name//[^a-zA-Z0-9._-]/-}"
  fi

  backup_dir="${ROTATION_BACKUPS_DIR}/${backup_id}"
  mkdir -p "${backup_dir}/links" "${backup_dir}/secrets"

  cp -f "${LINK_DEFINITIONS_PATH}" "${backup_dir}/links/definitions.tsv"
  cp -f "${LINK_BUNDLE_PATH}" "${backup_dir}/links/bundle.tsv"
  cp -f "${SECRETS_DIR}"/*.secret "${backup_dir}/secrets/"
  record_rotation_backup_metadata "${backup_dir}" "${operation}" "${slot_name}"
  ln -sfn "${backup_dir}" "${ROTATION_BACKUP_LATEST_LINK}"

  apply_permissions >/dev/null 2>&1 || true
  printf '%s\n' "${backup_dir}"
}

restore_rotation_backup_from_path() {
  local backup_dir="$1"

  [[ -d "${backup_dir}" ]] || die "Backup directory not found: ${backup_dir}"
  [[ -f "${backup_dir}/links/definitions.tsv" ]] || die "Backup is missing link definitions: ${backup_dir}"
  [[ -f "${backup_dir}/links/bundle.tsv" ]] || die "Backup is missing link bundle snapshot: ${backup_dir}"
  compgen -G "${backup_dir}/secrets/*.secret" >/dev/null || die "Backup has no secret slots: ${backup_dir}"

  find "${SECRETS_DIR}" -maxdepth 1 -type f -name '*.secret' -delete
  cp -f "${backup_dir}/links/definitions.tsv" "${LINK_DEFINITIONS_PATH}"
  cp -f "${backup_dir}/secrets"/*.secret "${SECRETS_DIR}/"

  reconcile_and_restart_managed_runtime
}

restore_rotation_backup() {
  local ref="$1"
  local backup_dir

  require_root
  require_installed

  [[ -n "${ref}" ]] || die "Укажи backup id или latest: restore-rotation-backup <backup-id|latest>"
  backup_dir="$(resolve_rotation_backup_ref "${ref}")" || die "Rotation backup not found: ${ref}"
  warn "Восстанавливаю состояние links/secrets из backup $(rotation_backup_id_from_path "${backup_dir}")..."
  restore_rotation_backup_from_path "${backup_dir}"
  log "Состояние восстановлено из backup $(rotation_backup_id_from_path "${backup_dir}")"
}

list_rotation_backups() {
  local backup_dir metadata_path
  local backup_id created_at operation slot_name engine domain port

  require_root
  require_installed

  echo "Rotation backups:"

  if ! compgen -G "${ROTATION_BACKUPS_DIR}/*/metadata.env" >/dev/null; then
    echo "  (none)"
    return 0
  fi

  while IFS= read -r backup_dir; do
    [[ -d "${backup_dir}" ]] || continue
    metadata_path="$(rotation_backup_metadata_path "${backup_dir}")"
    backup_id="$(rotation_backup_id_from_path "${backup_dir}")"
    created_at="n/a"
    operation="n/a"
    slot_name="-"
    engine="${ENGINE}"
    domain="${PUBLIC_DOMAIN}"
    port="${PUBLIC_PORT}"

    if [[ -f "${metadata_path}" ]]; then
      while IFS=$'	' read -r backup_id created_at operation slot_name engine domain port; do
        :
      done < <(
        METADATA_PATH_INPUT="${metadata_path}" bash -c '
          set -Eeuo pipefail
          # shellcheck disable=SC1090
          source "$METADATA_PATH_INPUT"
          printf "%s	%s	%s	%s	%s	%s	%s
"             "${BACKUP_ID:-}"             "${CREATED_AT:-}"             "${OPERATION:-}"             "${SLOT_NAME:-}"             "${ENGINE:-}"             "${PUBLIC_DOMAIN:-}"             "${PUBLIC_PORT:-}"
        '
      )
      backup_id="${backup_id:-$(rotation_backup_id_from_path "${backup_dir}")}" 
      created_at="${created_at:-n/a}"
      operation="${operation:-n/a}"
      slot_name="${slot_name:--}"
      engine="${engine:-${ENGINE}}"
      domain="${domain:-${PUBLIC_DOMAIN}}"
      port="${port:-${PUBLIC_PORT}}"
    fi

    printf '  %-44s %-20s %-16s %-14s %s:%s\n' "${backup_id}" "${created_at}" "${operation}" "${slot_name}" "${domain}" "${port}"
  done < <(find "${ROTATION_BACKUPS_DIR}" -mindepth 1 -maxdepth 1 -type d | sort -r)
}

rotation_runtime_healthy() {
  systemctl is-active --quiet "${SERVICE_NAME}" || return 1
  runtime_config_consistent || return 1
  link_model_healthy || return 1
  return 0
}

run_rotation_transaction() {
  local operation="$1"
  local slot_name="$2"
  local backup_dir
  shift 2

  backup_dir="$(create_rotation_backup "${operation}" "${slot_name}")"
  info "Создан backup перед ротацией: $(rotation_backup_id_from_path "${backup_dir}")"

  if ! "$@"; then
    warn "Операция ${operation} не завершилась успешно. Выполняю rollback..."
    restore_rotation_backup_from_path "${backup_dir}" || die "Rollback after failed ${operation} also failed; inspect backup $(rotation_backup_id_from_path "${backup_dir}")"
    die "${operation} завершилась неуспешно; исходное состояние восстановлено"
  fi

  if ! rotation_runtime_healthy; then
    warn "После ${operation} проверка runtime не прошла. Выполняю rollback..."
    restore_rotation_backup_from_path "${backup_dir}" || die "Rollback after unhealthy ${operation} also failed; inspect backup $(rotation_backup_id_from_path "${backup_dir}")"
    die "${operation} завершилась, но runtime unhealthy; исходное состояние восстановлено"
  fi

  log "Операция ${operation} завершена; backup сохранен: $(rotation_backup_id_from_path "${backup_dir}")"
}

rotate_link_secret_slot() {
  local target_name="$1"
  local name profile secret_file raw_secret desired_value found=0

  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue

    if [[ "${name}" == "${target_name}" ]]; then
      secret_file="$(secret_file_for_name "${name}")"
      raw_secret="$(generate_raw_secret_hex)"
      desired_value="$(format_slot_secret_for_engine_profile "${ENGINE}" "${profile}" "${raw_secret}")"
      log "Ротирую link ${name} (${profile})..."
      printf '%s\n' "${desired_value}" > "${secret_file}"
      found=1
      break
    fi
  done < "${LINK_DEFINITIONS_PATH}"

  (( found == 1 )) || die "Link slot не найден: ${target_name}"

  reconcile_and_restart_managed_runtime
}

rotate_all_link_secret_slots() {
  local name profile secret_file raw_secret desired_value

  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue
    secret_file="$(secret_file_for_name "${name}")"
    raw_secret="$(generate_raw_secret_hex)"
    desired_value="$(format_slot_secret_for_engine_profile "${ENGINE}" "${profile}" "${raw_secret}")"
    log "Ротирую link ${name} (${profile})..."
    printf '%s\n' "${desired_value}" > "${secret_file}"
  done < "${LINK_DEFINITIONS_PATH}"

  reconcile_and_restart_managed_runtime
}

refresh_telegram_config() {
  require_root
  require_installed

  if engine_requires_telegram_upstream; then
    download_proxy_files
    apply_permissions
    restart_managed_runtime
    log "Конфиг Telegram обновлен"
  else
    warn "refresh-telegram-config не требуется для ENGINE=${ENGINE}"
  fi
}

rotate_link() {
  local target_name="${1:-}"

  require_root
  require_installed

  [[ -n "${target_name}" ]] || die "Укажи имя ссылки: rotate-link <name>"
  run_rotation_transaction "rotate-link" "${target_name}" rotate_link_secret_slot "${target_name}"
}

rotate_all_links() {
  require_root
  require_installed

  run_rotation_transaction "rotate-all-links" "all" rotate_all_link_secret_slots
}

rotate_secret_legacy_alias() {
  require_installed
  local first_name
  first_name="$(awk 'NR==1 {print $1}' "${LINK_DEFINITIONS_PATH}")"
  [[ -n "${first_name}" ]] || die "Не найден primary link slot"
  rotate_link "${first_name}"
}

share_links() {
  require_root
  require_installed

  echo "Links:"
  print_links_table "yes"
}

list_links() {
  require_root
  require_installed

  echo "Links (redacted):"
  print_links_table "no"
}
