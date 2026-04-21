# shellcheck shell=bash

show_post_install_summary() {
  echo
  echo "========================================"
  echo "MTProxy установлен"
  echo "Domain:     ${PUBLIC_DOMAIN}"
  echo "Port:       ${PUBLIC_PORT}"
  echo "Engine:     ${ENGINE}"
  echo "Strategy:   ${LINK_STRATEGY}"
  if [[ "${LINK_STRATEGY}" == "per-device" ]]; then
    echo "Devices:    ${DEVICE_NAMES}"
  fi
  echo "TLS domain: ${TLS_DOMAIN}"
  echo "Decoy:      ${DECOY_MODE}"
  if [[ "${ENGINE}" == "stealth" && "${DECOY_MODE}" == "upstream-forward" ]]; then
    echo "Decoy upstream: ${DECOY_TARGET_HOST}:${DECOY_TARGET_PORT}"
  elif [[ "${ENGINE}" == "stealth" && "${DECOY_MODE}" == "local-https" ]]; then
    echo "Decoy domain: ${DECOY_DOMAIN}"
    echo "Decoy local:  127.0.0.1:${DECOY_LOCAL_PORT}"
  fi
  echo "Links:      $(awk 'END {print NR+0}' "${LINK_BUNDLE_PATH}")"
  echo
  echo "Секреты и tg:// ссылки по умолчанию не печатаются."
  echo "Чтобы намеренно открыть bundle, выполни:"
  echo "  sudo bash $0 share-links"
  echo
  echo "Проверка:"
  echo "  sudo bash $0 status"
  echo "  sudo bash $0 health"
  echo "========================================"
  echo
}

install_all() {
  require_root
  resolve_install_contract
  validate_install_contract

  ensure_packages
  ensure_user_and_dirs
  clone_or_update_engine_repo
  build_engine_binary
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
  render_engine_runtime_artifacts
  render_decoy_runtime_artifacts
  build_link_bundle
  render_runner_script
  render_refresh_helper
  render_service_file
  render_refresh_units
  apply_permissions
  apply_engine_runtime_tuning
  reload_and_enable_units
  configure_firewall
  start_managed_services
  show_post_install_summary
}

uninstall_all() {
  require_root

  warn "Останавливаю и удаляю сервисы..."
  systemctl disable --now "${REFRESH_TIMER_NAME}" 2>/dev/null || true
  systemctl disable --now "${DECOY_SERVICE_NAME}" 2>/dev/null || true
  systemctl disable --now "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "${SERVICE_PATH}" "${REFRESH_SERVICE_PATH}" "${REFRESH_TIMER_PATH}" "${DECOY_SERVICE_PATH}"
  systemctl daemon-reload

  warn "Удаляю бинарники, исходники и helper scripts..."
  rm -f "${OFFICIAL_BIN_PATH}" "${STEALTH_BIN_PATH}" "${RUNNER_PATH}" "${REFRESH_HELPER_PATH}" "${DECOY_SERVER_PATH}"
  rm -rf "${OFFICIAL_SRC_DIR}" "${STEALTH_SRC_DIR}"

  warn "Удаляю sysctl workaround..."
  rm -f "${SYSCTL_FILE}"
  sysctl --system >/dev/null 2>&1 || true

  warn "Удаляю конфиги и state..."
  rm -rf "${CONFIG_ROOT}" "${STATE_DIR}"

  if id -u "${RUN_USER}" >/dev/null 2>&1; then
    userdel "${RUN_USER}" 2>/dev/null || true
  fi

  if getent group "${RUN_GROUP}" >/dev/null 2>&1; then
    groupdel "${RUN_GROUP}" 2>/dev/null || true
  fi

  log "MTProxy удален"
}
