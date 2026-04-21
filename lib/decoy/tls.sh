# shellcheck shell=bash

ensure_decoy_tls_material() {
  local tmp_cert tmp_key

  if [[ -n "${DECOY_CERT_SOURCE_PATH}" && -n "${DECOY_KEY_SOURCE_PATH}" ]]; then
    log "Копирую предоставленный decoy TLS certificate..."
    install -o root -g "${RUN_GROUP}" -m 0640 "${DECOY_CERT_SOURCE_PATH}" "${DECOY_MANAGED_CERT_PATH}"
    install -o root -g "${RUN_GROUP}" -m 0640 "${DECOY_KEY_SOURCE_PATH}" "${DECOY_MANAGED_KEY_PATH}"
    return 0
  fi

  if [[ -f "${DECOY_MANAGED_CERT_PATH}" && -f "${DECOY_MANAGED_KEY_PATH}" ]]; then
    info "Decoy TLS certificate уже существует, переиспользую"
    return 0
  fi

  warn "DECOY_CERT_PATH/DECOY_KEY_PATH не заданы, генерирую self-signed certificate для ${DECOY_DOMAIN}"
  tmp_cert="$(mktemp)"
  tmp_key="$(mktemp)"
  trap 'rm -f "${tmp_cert}" "${tmp_key}"' RETURN

  openssl req \
    -x509 \
    -newkey rsa:2048 \
    -sha256 \
    -nodes \
    -days 397 \
    -subj "/CN=${DECOY_DOMAIN}" \
    -addext "subjectAltName=DNS:${DECOY_DOMAIN}" \
    -keyout "${tmp_key}" \
    -out "${tmp_cert}" >/dev/null 2>&1

  install -o root -g "${RUN_GROUP}" -m 0640 "${tmp_cert}" "${DECOY_MANAGED_CERT_PATH}"
  install -o root -g "${RUN_GROUP}" -m 0640 "${tmp_key}" "${DECOY_MANAGED_KEY_PATH}"

  rm -f "${tmp_cert}" "${tmp_key}"
  trap - RETURN
}


effective_decoy_cert_path() {
  if [[ -f "${DECOY_MANAGED_CERT_PATH}" ]]; then
    printf '%s\n' "${DECOY_MANAGED_CERT_PATH}"
  else
    printf '%s\n' "${DECOY_CERT_SOURCE_PATH}"
  fi
}


effective_decoy_key_path() {
  if [[ -f "${DECOY_MANAGED_KEY_PATH}" ]]; then
    printf '%s\n' "${DECOY_MANAGED_KEY_PATH}"
  else
    printf '%s\n' "${DECOY_KEY_SOURCE_PATH}"
  fi
}
