# shellcheck shell=bash

refresh_telegram_config() {
  require_root
  require_installed

  if engine_requires_telegram_upstream; then
    download_proxy_files
    apply_permissions
    apply_engine_runtime_tuning
    restart_managed_services
    log "Конфиг Telegram обновлен"
  else
    warn "refresh-telegram-config не требуется для ENGINE=stealth"
  fi
}

rotate_link() {
  local target_name="${1:-}"
  local name profile secret_file raw_secret desired_value found=0

  require_root
  require_installed

  [[ -n "${target_name}" ]] || die "Укажи имя ссылки: rotate-link <name>"

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

  engine_render_runtime_artifacts
  render_decoy_runtime_artifacts
  build_link_bundle
  apply_permissions
  apply_engine_runtime_tuning
  restart_managed_services

  log "Link ${target_name} обновлен"
}

rotate_all_links() {
  local name profile secret_file raw_secret desired_value

  require_root
  require_installed

  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue
    secret_file="$(secret_file_for_name "${name}")"
    raw_secret="$(generate_raw_secret_hex)"
    desired_value="$(format_slot_secret_for_engine_profile "${ENGINE}" "${profile}" "${raw_secret}")"
    log "Ротирую link ${name} (${profile})..."
    printf '%s\n' "${desired_value}" > "${secret_file}"
  done < "${LINK_DEFINITIONS_PATH}"

  engine_render_runtime_artifacts
  render_decoy_runtime_artifacts
  build_link_bundle
  apply_permissions
  apply_engine_runtime_tuning
  restart_managed_services

  log "Все link slots обновлены"
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
  require_installed

  echo "Links (redacted):"
  print_links_table "no"
}
