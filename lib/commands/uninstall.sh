# shellcheck shell=bash

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
