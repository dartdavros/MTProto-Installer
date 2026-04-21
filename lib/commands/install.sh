# shellcheck shell=bash

install_all() {
  require_root
  resolve_install_contract
  validate_install_contract

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
  engine_render_runtime_artifacts
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
