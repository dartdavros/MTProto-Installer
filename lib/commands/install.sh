# shellcheck shell=bash

install_all() {
  local previous_public_port=""
  local previous_internal_port=""
  local previous_decoy_local_port=""

  require_root

  if has_manifest; then
    read_manifest_contract
    previous_public_port="${MANIFEST_PUBLIC_PORT:-}"
    previous_internal_port="${MANIFEST_INTERNAL_PORT:-}"
    previous_decoy_local_port="${MANIFEST_DECOY_LOCAL_PORT:-}"
  fi

  resolve_install_contract
  validate_install_contract
  run_install_preflight_checks

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
