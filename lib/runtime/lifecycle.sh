# shellcheck shell=bash

restart_managed_services() {
  if engine_uses_local_decoy_service; then
    systemctl restart "${DECOY_SERVICE_NAME}"
  fi

  systemctl restart "${SERVICE_NAME}"
}

start_managed_services() {
  if engine_uses_local_decoy_service; then
    log "Запускаю ${DECOY_SERVICE_NAME}..."
    systemctl restart "${DECOY_SERVICE_NAME}"
  fi

  log "Запускаю ${SERVICE_NAME}..."
  systemctl restart "${SERVICE_NAME}"

  if engine_requires_telegram_upstream; then
    systemctl start "${REFRESH_TIMER_NAME}"
  fi
}
