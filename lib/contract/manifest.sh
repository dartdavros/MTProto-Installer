# shellcheck shell=bash

manifest_contract_fields() {
  cat <<'EOF_FIELDS'
PUBLIC_DOMAIN
PUBLIC_PORT
INTERNAL_PORT
WORKERS
ENGINE
PRIMARY_PROFILE
LINK_STRATEGY
DEVICE_NAMES
TLS_DOMAIN
DECOY_MODE
DECOY_TARGET_HOST
DECOY_TARGET_PORT
DECOY_DOMAIN
DECOY_LOCAL_PORT
DECOY_CERT_PATH
DECOY_KEY_PATH
OFFICIAL_REPO_URL
OFFICIAL_REPO_BRANCH
STEALTH_REPO_URL
STEALTH_REPO_BRANCH
EOF_FIELDS
}

clear_manifest_contract() {
  MANIFEST_PUBLIC_DOMAIN=""
  MANIFEST_PUBLIC_PORT=""
  MANIFEST_INTERNAL_PORT=""
  MANIFEST_WORKERS=""
  MANIFEST_ENGINE=""
  MANIFEST_PRIMARY_PROFILE=""
  MANIFEST_LINK_STRATEGY=""
  MANIFEST_DEVICE_NAMES=""
  MANIFEST_TLS_DOMAIN=""
  MANIFEST_DECOY_MODE=""
  MANIFEST_DECOY_TARGET_HOST=""
  MANIFEST_DECOY_TARGET_PORT=""
  MANIFEST_DECOY_DOMAIN=""
  MANIFEST_DECOY_LOCAL_PORT=""
  MANIFEST_DECOY_CERT_SOURCE_PATH=""
  MANIFEST_DECOY_KEY_SOURCE_PATH=""
  MANIFEST_OFFICIAL_REPO_URL=""
  MANIFEST_OFFICIAL_REPO_BRANCH=""
  MANIFEST_STEALTH_REPO_URL=""
  MANIFEST_STEALTH_REPO_BRANCH=""
}

has_manifest() {
  [[ -f "${MANIFEST_PATH}" ]]
}

emit_manifest_contract_snapshot() {
  local field emit_script=""

  [[ -f "${MANIFEST_PATH}" ]] || return 0

  while IFS= read -r field; do
    [[ -n "${field}" ]] || continue
    printf -v emit_script '%sprintf "%%s\\n" "${%s-}"\n' "${emit_script}" "${field}"
  done < <(manifest_contract_fields)

  MANIFEST_PATH_INPUT="${MANIFEST_PATH}" \
  MANIFEST_EMIT_SCRIPT="${emit_script}" \
  bash -c '
    set -Eeuo pipefail
    # shellcheck disable=SC1090
    source "$MANIFEST_PATH_INPUT"
    eval "$MANIFEST_EMIT_SCRIPT"
  '
}

read_manifest_contract() {
  local fields values i field value

  clear_manifest_contract
  [[ -f "${MANIFEST_PATH}" ]] || return 0

  fields=()
  while IFS= read -r field; do
    [[ -n "${field}" ]] || continue
    fields+=("${field}")
  done < <(manifest_contract_fields)

  values=()
  while IFS= read -r value; do
    values+=("${value}")
  done < <(emit_manifest_contract_snapshot)

  (( ${#fields[@]} == ${#values[@]} )) || die "Не удалось корректно прочитать manifest: ${MANIFEST_PATH}"

  for i in "${!fields[@]}"; do
    field="${fields[i]}"
    value="${values[i]}"

    case "${field}" in
      DECOY_CERT_PATH)
        MANIFEST_DECOY_CERT_SOURCE_PATH="${value}"
        ;;
      DECOY_KEY_PATH)
        MANIFEST_DECOY_KEY_SOURCE_PATH="${value}"
        ;;
      *)
        printf -v "MANIFEST_${field}" '%s' "${value}"
        ;;
    esac
  done
}

persist_manifest() {
  log "Сохраняю deployment manifest..."

  {
    quote_kv APP_NAME "${APP_NAME}"
    quote_kv RUN_USER "${RUN_USER}"
    quote_kv RUN_GROUP "${RUN_GROUP}"
    quote_kv OFFICIAL_REPO_URL "${OFFICIAL_REPO_URL}"
    quote_kv OFFICIAL_REPO_BRANCH "${OFFICIAL_REPO_BRANCH}"
    quote_kv STEALTH_REPO_URL "${STEALTH_REPO_URL}"
    quote_kv STEALTH_REPO_BRANCH "${STEALTH_REPO_BRANCH}"
    quote_kv OFFICIAL_SRC_DIR "${OFFICIAL_SRC_DIR}"
    quote_kv STEALTH_SRC_DIR "${STEALTH_SRC_DIR}"
    quote_kv OFFICIAL_BIN_PATH "${OFFICIAL_BIN_PATH}"
    quote_kv STEALTH_BIN_PATH "${STEALTH_BIN_PATH}"
    quote_kv CONFIG_ROOT "${CONFIG_ROOT}"
    quote_kv MANIFEST_DIR "${MANIFEST_DIR}"
    quote_kv SECRETS_DIR "${SECRETS_DIR}"
    quote_kv LINKS_DIR "${LINKS_DIR}"
    quote_kv RUNTIME_DIR "${RUNTIME_DIR}"
    quote_kv STATE_DIR "${STATE_DIR}"
    quote_kv STEALTH_TLS_FRONT_DIR "${STEALTH_TLS_FRONT_DIR}"
    quote_kv MANIFEST_PATH "${MANIFEST_PATH}"
    quote_kv PROXY_SECRET_PATH "${PROXY_SECRET_PATH}"
    quote_kv PROXY_MULTI_CONF_PATH "${PROXY_MULTI_CONF_PATH}"
    quote_kv STEALTH_CONFIG_PATH "${STEALTH_CONFIG_PATH}"
    quote_kv LINK_DEFINITIONS_PATH "${LINK_DEFINITIONS_PATH}"
    quote_kv LINK_BUNDLE_PATH "${LINK_BUNDLE_PATH}"
    quote_kv SERVICE_NAME "${SERVICE_NAME}"
    quote_kv DECOY_SERVICE_NAME "${DECOY_SERVICE_NAME}"
    quote_kv PUBLIC_DOMAIN "${PUBLIC_DOMAIN}"
    quote_kv PUBLIC_PORT "${PUBLIC_PORT}"
    quote_kv INTERNAL_PORT "${INTERNAL_PORT}"
    quote_kv WORKERS "${WORKERS}"
    quote_kv ENGINE "${ENGINE}"
    quote_kv PRIMARY_PROFILE "${PRIMARY_PROFILE}"
    quote_kv LINK_STRATEGY "${LINK_STRATEGY}"
    quote_kv DEVICE_NAMES "${DEVICE_NAMES}"
    quote_kv TLS_DOMAIN "${TLS_DOMAIN}"
    quote_kv DECOY_MODE "${DECOY_MODE}"
    quote_kv DECOY_TARGET_HOST "${DECOY_TARGET_HOST}"
    quote_kv DECOY_TARGET_PORT "${DECOY_TARGET_PORT}"
    quote_kv DECOY_DOMAIN "${DECOY_DOMAIN}"
    quote_kv DECOY_LOCAL_PORT "${DECOY_LOCAL_PORT}"
    quote_kv DECOY_CERT_PATH "${DECOY_CERT_SOURCE_PATH}"
    quote_kv DECOY_KEY_PATH "${DECOY_KEY_SOURCE_PATH}"
  } > "${MANIFEST_PATH}"
}
