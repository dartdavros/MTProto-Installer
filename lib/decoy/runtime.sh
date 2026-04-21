# shellcheck shell=bash

render_decoy_runtime_artifacts() {
  if engine_uses_local_decoy_service; then
    ensure_decoy_tls_material
    write_decoy_site_content
    render_decoy_server_script
    render_decoy_service_file
  else
    rm -f "${DECOY_SERVER_PATH}" "${DECOY_SERVICE_PATH}"
  fi
}
