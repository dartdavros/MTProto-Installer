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

reconcile_managed_runtime_artifacts() {
  engine_render_runtime_artifacts
  render_decoy_runtime_artifacts
  build_link_bundle
  apply_permissions
}

restart_managed_runtime() {
  apply_engine_runtime_tuning
  restart_managed_services
}

reconcile_and_restart_managed_runtime() {
  reconcile_managed_runtime_artifacts
  restart_managed_runtime
}
