# shellcheck shell=bash

install_backup_id_from_path() {
  basename "$1"
}

install_backup_metadata_path() {
  local backup_dir="$1"
  printf '%s/metadata.env\n' "${backup_dir}"
}

install_backup_count() {
  find "${INSTALL_BACKUPS_DIR}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l
}

latest_install_backup_id() {
  local latest_dir
  latest_dir="$(resolve_install_backup_ref latest 2>/dev/null || true)"
  [[ -n "${latest_dir}" ]] || return 1
  install_backup_id_from_path "${latest_dir}"
}

resolve_install_backup_ref() {
  local ref="$1"

  [[ -n "${ref}" ]] || return 1

  case "${ref}" in
    latest)
      [[ -L "${INSTALL_BACKUP_LATEST_LINK}" ]] || return 1
      readlink -f "${INSTALL_BACKUP_LATEST_LINK}"
      ;;
    *)
      [[ -d "${INSTALL_BACKUPS_DIR}/${ref}" ]] || return 1
      printf '%s\n' "${INSTALL_BACKUPS_DIR}/${ref}"
      ;;
  esac
}

install_backup_preserve_owner_group() {
  if getent group "${RUN_GROUP}" >/dev/null 2>&1; then
    printf 'root:%s\n' "${RUN_GROUP}"
  else
    printf 'root:root\n'
  fi
}

backup_directory_contents() {
  local source_dir="$1"
  local destination_dir="$2"

  [[ -d "${source_dir}" ]] || return 0
  mkdir -p "${destination_dir}"
  cp -a "${source_dir}/." "${destination_dir}/"
}

backup_file_if_exists() {
  local source_path="$1"
  local destination_path="$2"

  [[ -f "${source_path}" ]] || return 0
  mkdir -p "$(dirname -- "${destination_path}")"
  cp -a "${source_path}" "${destination_path}"
}

legacy_install_state_present() {
  [[ -f "${LEGACY_SECRET_PATH}" || -f "${LEGACY_PROXY_SECRET_PATH}" || -f "${LEGACY_PROXY_MULTI_CONF_PATH}" || -f "${SERVICE_PATH}" ]]
}

current_runtime_ports_snapshot() {
  local current_public_port=""
  local current_internal_port=""
  local current_decoy_local_port=""

  if has_manifest; then
    read_manifest_contract
    current_public_port="${MANIFEST_PUBLIC_PORT:-}"
    current_internal_port="${MANIFEST_INTERNAL_PORT:-}"
    current_decoy_local_port="${MANIFEST_DECOY_LOCAL_PORT:-}"
  elif [[ -f "${SERVICE_PATH}" ]]; then
    current_public_port="$(parse_legacy_service_exec_flag '-H' || true)"
    current_internal_port="$(parse_legacy_service_exec_flag '-p' || true)"
  fi

  printf '%s\t%s\t%s\n' "${current_public_port}" "${current_internal_port}" "${current_decoy_local_port}"
}

record_install_backup_metadata() {
  local backup_dir="$1"
  local backup_mode="$2"
  local previous_public_port="$3"
  local previous_internal_port="$4"
  local previous_decoy_local_port="$5"
  local metadata_path

  metadata_path="$(install_backup_metadata_path "${backup_dir}")"
  {
    quote_kv BACKUP_ID "$(install_backup_id_from_path "${backup_dir}")"
    quote_kv CREATED_AT "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    quote_kv BACKUP_MODE "${backup_mode}"
    quote_kv PREVIOUS_PUBLIC_PORT "${previous_public_port}"
    quote_kv PREVIOUS_INTERNAL_PORT "${previous_internal_port}"
    quote_kv PREVIOUS_DECOY_LOCAL_PORT "${previous_decoy_local_port}"
    quote_kv HAD_MANIFEST "$([[ -f "${backup_dir}/config-root/config/manifest.env" ]] && printf yes || printf no)"
  } > "${metadata_path}"
}

create_install_backup() {
  local backup_mode="$1"
  local previous_public_port="$2"
  local previous_internal_port="$3"
  local previous_decoy_local_port="$4"
  local backup_id backup_dir owner_group

  mkdir -p "${INSTALL_BACKUPS_DIR}"
  owner_group="$(install_backup_preserve_owner_group)"
  chown "${owner_group}" "${INSTALL_BACKUPS_DIR}"
  chmod 750 "${INSTALL_BACKUPS_DIR}"

  backup_id="$(date -u '+%Y%m%dT%H%M%SZ')-${backup_mode}-install"
  backup_dir="${INSTALL_BACKUPS_DIR}/${backup_id}"

  mkdir -p "${backup_dir}/config-root" "${backup_dir}/systemd" "${backup_dir}/libexec" "${backup_dir}/bin" "${backup_dir}/sysctl"

  backup_directory_contents "${CONFIG_ROOT}" "${backup_dir}/config-root"
  backup_file_if_exists "${SERVICE_PATH}" "${backup_dir}/systemd/$(basename -- "${SERVICE_PATH}")"
  backup_file_if_exists "${REFRESH_SERVICE_PATH}" "${backup_dir}/systemd/$(basename -- "${REFRESH_SERVICE_PATH}")"
  backup_file_if_exists "${REFRESH_TIMER_PATH}" "${backup_dir}/systemd/$(basename -- "${REFRESH_TIMER_PATH}")"
  backup_file_if_exists "${DECOY_SERVICE_PATH}" "${backup_dir}/systemd/$(basename -- "${DECOY_SERVICE_PATH}")"
  backup_file_if_exists "${RUNNER_PATH}" "${backup_dir}/libexec/$(basename -- "${RUNNER_PATH}")"
  backup_file_if_exists "${REFRESH_HELPER_PATH}" "${backup_dir}/libexec/$(basename -- "${REFRESH_HELPER_PATH}")"
  backup_file_if_exists "${DECOY_SERVER_PATH}" "${backup_dir}/libexec/$(basename -- "${DECOY_SERVER_PATH}")"
  backup_file_if_exists "${OFFICIAL_BIN_PATH}" "${backup_dir}/bin/$(basename -- "${OFFICIAL_BIN_PATH}")"
  backup_file_if_exists "${STEALTH_BIN_PATH}" "${backup_dir}/bin/$(basename -- "${STEALTH_BIN_PATH}")"
  backup_file_if_exists "${SYSCTL_FILE}" "${backup_dir}/sysctl/$(basename -- "${SYSCTL_FILE}")"

  record_install_backup_metadata "${backup_dir}" "${backup_mode}" "${previous_public_port}" "${previous_internal_port}" "${previous_decoy_local_port}"
  ln -sfn "${backup_dir}" "${INSTALL_BACKUP_LATEST_LINK}"

  if getent group "${RUN_GROUP}" >/dev/null 2>&1; then
    apply_permissions >/dev/null 2>&1 || true
  fi

  printf '%s\n' "${backup_dir}"
}

restore_directory_from_backup() {
  local backup_dir="$1"
  local target_dir="$2"

  rm -rf "${target_dir}"
  if [[ -d "${backup_dir}" ]]; then
    mkdir -p "${target_dir}"
    cp -a "${backup_dir}/." "${target_dir}/"
  fi
}

restore_file_from_backup() {
  local backup_path="$1"
  local target_path="$2"

  rm -f "${target_path}"
  if [[ -f "${backup_path}" ]]; then
    mkdir -p "$(dirname -- "${target_path}")"
    cp -a "${backup_path}" "${target_path}"
  fi
}

restore_managed_install_backup_tree() {
  local backup_dir="$1"

  restore_directory_from_backup "${backup_dir}/config-root" "${CONFIG_ROOT}"
  restore_file_from_backup "${backup_dir}/systemd/$(basename -- "${SERVICE_PATH}")" "${SERVICE_PATH}"
  restore_file_from_backup "${backup_dir}/systemd/$(basename -- "${REFRESH_SERVICE_PATH}")" "${REFRESH_SERVICE_PATH}"
  restore_file_from_backup "${backup_dir}/systemd/$(basename -- "${REFRESH_TIMER_PATH}")" "${REFRESH_TIMER_PATH}"
  restore_file_from_backup "${backup_dir}/systemd/$(basename -- "${DECOY_SERVICE_PATH}")" "${DECOY_SERVICE_PATH}"
  restore_file_from_backup "${backup_dir}/libexec/$(basename -- "${RUNNER_PATH}")" "${RUNNER_PATH}"
  restore_file_from_backup "${backup_dir}/libexec/$(basename -- "${REFRESH_HELPER_PATH}")" "${REFRESH_HELPER_PATH}"
  restore_file_from_backup "${backup_dir}/libexec/$(basename -- "${DECOY_SERVER_PATH}")" "${DECOY_SERVER_PATH}"
  restore_file_from_backup "${backup_dir}/bin/$(basename -- "${OFFICIAL_BIN_PATH}")" "${OFFICIAL_BIN_PATH}"
  restore_file_from_backup "${backup_dir}/bin/$(basename -- "${STEALTH_BIN_PATH}")" "${STEALTH_BIN_PATH}"
  restore_file_from_backup "${backup_dir}/sysctl/$(basename -- "${SYSCTL_FILE}")" "${SYSCTL_FILE}"
}

restore_install_backup_from_path() {
  local backup_dir="$1"
  local previous_public_port="$2"
  local previous_internal_port="$3"
  local previous_decoy_local_port="$4"

  [[ -d "${backup_dir}" ]] || die "Install backup directory not found: ${backup_dir}"

  systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
  systemctl stop "${REFRESH_TIMER_NAME}" >/dev/null 2>&1 || true
  systemctl stop "${DECOY_SERVICE_NAME}" >/dev/null 2>&1 || true

  restore_managed_install_backup_tree "${backup_dir}"

  systemctl daemon-reload

  if [[ -f "${MANIFEST_PATH}" ]]; then
    load_runtime_context
    apply_permissions
    apply_engine_runtime_tuning
    reload_and_enable_units
    configure_firewall "${previous_public_port}" "${previous_internal_port}" "${previous_decoy_local_port}"
    start_managed_services
  else
    systemctl disable --now "${REFRESH_TIMER_NAME}" >/dev/null 2>&1 || true
    systemctl disable --now "${DECOY_SERVICE_NAME}" >/dev/null 2>&1 || true

    PUBLIC_PORT="$(parse_legacy_service_exec_flag '-H' || true)"
    INTERNAL_PORT="$(parse_legacy_service_exec_flag '-p' || true)"
    DECOY_MODE="disabled"
    configure_firewall "${previous_public_port}" "${previous_internal_port}" "${previous_decoy_local_port}"

    if [[ -f "${SERVICE_PATH}" ]]; then
      systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1 || true
      systemctl restart "${SERVICE_NAME}" >/dev/null 2>&1 || true
    fi
  fi
}

list_install_backups() {
  local backup_dir metadata_path
  local backup_id created_at backup_mode had_manifest previous_public_port previous_internal_port previous_decoy_local_port

  require_root

  echo "Install backups:"

  if ! compgen -G "${INSTALL_BACKUPS_DIR}/*/metadata.env" >/dev/null; then
    echo "  (none)"
    return 0
  fi

  while IFS= read -r backup_dir; do
    [[ -d "${backup_dir}" ]] || continue
    metadata_path="$(install_backup_metadata_path "${backup_dir}")"
    backup_id="$(install_backup_id_from_path "${backup_dir}")"
    created_at="n/a"
    backup_mode="n/a"
    had_manifest="n/a"
    previous_public_port="-"
    previous_internal_port="-"
    previous_decoy_local_port="-"

    if [[ -f "${metadata_path}" ]]; then
      while IFS=$'\t' read -r backup_id created_at backup_mode had_manifest previous_public_port previous_internal_port previous_decoy_local_port; do
        :
      done < <(
        METADATA_PATH_INPUT="${metadata_path}" bash -c '
          set -Eeuo pipefail
          # shellcheck disable=SC1090
          source "$METADATA_PATH_INPUT"
          printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "${BACKUP_ID:-}" \
            "${CREATED_AT:-}" \
            "${BACKUP_MODE:-}" \
            "${HAD_MANIFEST:-}" \
            "${PREVIOUS_PUBLIC_PORT:-}" \
            "${PREVIOUS_INTERNAL_PORT:-}" \
            "${PREVIOUS_DECOY_LOCAL_PORT:-}"
        '
      )
    fi

    printf '  %-44s %-20s %-10s manifest=%-3s public=%-5s internal=%-5s decoy=%s\n' \
      "${backup_id}" "${created_at}" "${backup_mode}" "${had_manifest}" "${previous_public_port}" "${previous_internal_port}" "${previous_decoy_local_port}"
  done < <(find "${INSTALL_BACKUPS_DIR}" -mindepth 1 -maxdepth 1 -type d | sort -r)
}

restore_install_backup() {
  local ref="$1"
  local backup_dir current_public_port current_internal_port current_decoy_local_port

  require_root

  [[ -n "${ref}" ]] || die "Укажи backup id или latest: restore-install-backup <backup-id|latest>"
  backup_dir="$(resolve_install_backup_ref "${ref}")" || die "Install backup not found: ${ref}"

  IFS=$'\t' read -r current_public_port current_internal_port current_decoy_local_port <<< "$(current_runtime_ports_snapshot)"

  warn "Восстанавливаю install state из backup $(install_backup_id_from_path "${backup_dir}")..."
  restore_install_backup_from_path "${backup_dir}" "${current_public_port}" "${current_internal_port}" "${current_decoy_local_port}"
  log "Install state восстановлен из backup $(install_backup_id_from_path "${backup_dir}")"
}

install_steps() {
  local previous_public_port="$1"
  local previous_internal_port="$2"
  local previous_decoy_local_port="$3"

  ensure_packages
  ensure_user_and_dirs
  clone_or_update_engine_repo
  engine_build_binary
  write_managed_link_definitions
  migrate_legacy_layout_if_present
  ensure_link_secrets

  if engine_requires_telegram_upstream; then
    if [[ ! -f "${PROXY_SECRET_PATH}" || ! -f "${PROXY_MULTI_CONF_PATH}" ]]; then
      download_proxy_files
    else
      info "Proxy upstream artifacts уже существуют, обновление не требуется"
    fi
  fi

  persist_manifest
  reconcile_managed_runtime_artifacts
  render_runner_script
  render_refresh_helper
  render_service_file
  render_refresh_units
  apply_permissions
  apply_engine_runtime_tuning
  reload_and_enable_units
  configure_firewall "${previous_public_port}" "${previous_internal_port}" "${previous_decoy_local_port}"
  start_managed_services
  show_post_install_summary
}

run_install_transaction() {
  local previous_public_port="$1"
  local previous_internal_port="$2"
  local previous_decoy_local_port="$3"
  local backup_dir=""
  local backup_mode=""

  if has_manifest; then
    backup_mode="managed"
  elif legacy_install_state_present; then
    backup_mode="legacy"
  fi

  if [[ -n "${backup_mode}" ]]; then
    backup_dir="$(create_install_backup "${backup_mode}" "${previous_public_port}" "${previous_internal_port}" "${previous_decoy_local_port}")"
    info "Создан install backup: $(install_backup_id_from_path "${backup_dir}")"
  fi

  if ! install_steps "${previous_public_port}" "${previous_internal_port}" "${previous_decoy_local_port}"; then
    if [[ -n "${backup_dir}" ]]; then
      warn "install не завершился успешно. Выполняю rollback из backup..."
      restore_install_backup_from_path "${backup_dir}" "${PUBLIC_PORT}" "${INTERNAL_PORT}" "${DECOY_LOCAL_PORT}" || die "Rollback after failed install also failed; inspect backup $(install_backup_id_from_path "${backup_dir}")"
      die "install завершился неуспешно; исходное состояние восстановлено"
    fi

    die "install завершился неуспешно"
  fi

  if ! health >/dev/null 2>&1; then
    if [[ -n "${backup_dir}" ]]; then
      warn "После install проверка health не прошла. Выполняю rollback..."
      restore_install_backup_from_path "${backup_dir}" "${PUBLIC_PORT}" "${INTERNAL_PORT}" "${DECOY_LOCAL_PORT}" || die "Rollback after unhealthy install also failed; inspect backup $(install_backup_id_from_path "${backup_dir}")"
      die "install завершился, но runtime unhealthy; исходное состояние восстановлено"
    fi

    die "install завершился, но runtime unhealthy"
  fi

  if [[ -n "${backup_dir}" ]]; then
    log "install завершен; backup сохранен: $(install_backup_id_from_path "${backup_dir}")"
  fi
}

install_all() {
  local previous_public_port=""
  local previous_internal_port=""
  local previous_decoy_local_port=""

  require_root

  IFS=$'\t' read -r previous_public_port previous_internal_port previous_decoy_local_port <<< "$(current_runtime_ports_snapshot)"

  resolve_install_contract
  validate_install_contract
  run_install_preflight_checks

  run_install_transaction "${previous_public_port}" "${previous_internal_port}" "${previous_decoy_local_port}"
}
