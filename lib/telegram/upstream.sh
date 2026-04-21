# shellcheck shell=bash

download_proxy_files() {
  local tmp_secret
  local tmp_conf

  tmp_secret="$(mktemp)"
  tmp_conf="$(mktemp)"

  trap 'rm -f "${tmp_secret}" "${tmp_conf}"' RETURN

  log "Скачиваю proxy-secret..."
  curl -fsSL https://core.telegram.org/getProxySecret -o "${tmp_secret}"

  log "Скачиваю proxy-multi.conf..."
  curl -fsSL https://core.telegram.org/getProxyConfig -o "${tmp_conf}"

  install -o root -g "${RUN_GROUP}" -m 0640 "${tmp_secret}" "${PROXY_SECRET_PATH}"
  install -o root -g "${RUN_GROUP}" -m 0640 "${tmp_conf}" "${PROXY_MULTI_CONF_PATH}"

  rm -f "${tmp_secret}" "${tmp_conf}"
  trap - RETURN
}
