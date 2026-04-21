# shellcheck shell=bash

render_runner_script() {
  cat > "${RUNNER_PATH}" <<'EOF_RUNNER'
#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1090
source "__MANIFEST_PATH__"

case "${ENGINE}" in
  official)
    secret_args=()
    while IFS=$'\t' read -r name profile; do
      [[ -n "${name}" ]] || continue
      secret_file="${SECRETS_DIR}/${name}.secret"
      [[ -f "${secret_file}" ]] || { echo "Secret slot not found: ${secret_file}" >&2; exit 1; }
      secret="$(tr -d '\n\r' < "${secret_file}")"
      [[ -n "${secret}" ]] || { echo "Secret slot is empty: ${secret_file}" >&2; exit 1; }
      secret_args+=("-S" "${secret}")
    done < "${LINK_DEFINITIONS_PATH}"

    exec "${OFFICIAL_BIN_PATH}" -u "${RUN_USER}" -p "${INTERNAL_PORT}" -H "${PUBLIC_PORT}" "${secret_args[@]}" --aes-pwd "${PROXY_SECRET_PATH}" "${PROXY_MULTI_CONF_PATH}" -M "${WORKERS}"
    ;;
  stealth)
    [[ -x "${STEALTH_BIN_PATH}" ]] || { echo "Stealth binary not found: ${STEALTH_BIN_PATH}" >&2; exit 1; }
    [[ -r "${STEALTH_CONFIG_PATH}" ]] || { echo "Stealth config not found: ${STEALTH_CONFIG_PATH}" >&2; exit 1; }
    exec "${STEALTH_BIN_PATH}" "${STEALTH_CONFIG_PATH}"
    ;;
  *)
    echo "Unsupported engine in manifest: ${ENGINE}" >&2
    exit 1
    ;;
esac
EOF_RUNNER

  sed -i "s#__MANIFEST_PATH__#${MANIFEST_PATH}#g" "${RUNNER_PATH}"
}

render_refresh_helper() {
  cat > "${REFRESH_HELPER_PATH}" <<'EOF_REFRESH'
#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1090
source "__MANIFEST_PATH__"

LAST_ATTEMPT_EPOCH="$(date +%s)"
LAST_ATTEMPT_HUMAN="$(date -d "@${LAST_ATTEMPT_EPOCH}" "+%Y-%m-%d %H:%M:%S %Z")"
LAST_RESULT="unknown"
LAST_SUCCESS_EPOCH=""
LAST_SUCCESS_HUMAN=""

if [[ -f "${REFRESH_STATE_PATH}" ]]; then
  # shellcheck disable=SC1090
  source "${REFRESH_STATE_PATH}" || true
  LAST_SUCCESS_EPOCH="${LAST_SUCCESS_EPOCH:-}"
  LAST_SUCCESS_HUMAN="${LAST_SUCCESS_HUMAN:-}"
fi

persist_refresh_state() {
  {
    printf "LAST_ATTEMPT_EPOCH=%q\n" "${LAST_ATTEMPT_EPOCH}"
    printf "LAST_ATTEMPT_HUMAN=%q\n" "${LAST_ATTEMPT_HUMAN}"
    printf "LAST_RESULT=%q\n" "${LAST_RESULT}"
    printf "LAST_SUCCESS_EPOCH=%q\n" "${LAST_SUCCESS_EPOCH}"
    printf "LAST_SUCCESS_HUMAN=%q\n" "${LAST_SUCCESS_HUMAN}"
  } > "${REFRESH_STATE_PATH}"

  chown root:"__RUN_GROUP__" "${REFRESH_STATE_PATH}"
  chmod 0640 "${REFRESH_STATE_PATH}"
}

finalize_refresh_state() {
  local rc=$?

  if (( rc == 0 )); then
    LAST_RESULT="success"
    LAST_SUCCESS_EPOCH="${LAST_ATTEMPT_EPOCH}"
    LAST_SUCCESS_HUMAN="${LAST_ATTEMPT_HUMAN}"
  elif [[ "${LAST_RESULT}" == "unknown" ]]; then
    LAST_RESULT="failure"
  fi

  persist_refresh_state
  exit ${rc}
}

trap finalize_refresh_state EXIT

case "${ENGINE}" in
  official)
    tmp_secret="$(mktemp)"
    tmp_conf="$(mktemp)"
    trap 'rm -f "${tmp_secret}" "${tmp_conf}"; finalize_refresh_state' EXIT

    curl -fsSL https://core.telegram.org/getProxySecret -o "${tmp_secret}"
    curl -fsSL https://core.telegram.org/getProxyConfig -o "${tmp_conf}"

    install -o root -g "__RUN_GROUP__" -m 0640 "${tmp_secret}" "${PROXY_SECRET_PATH}"
    install -o root -g "__RUN_GROUP__" -m 0640 "${tmp_conf}" "${PROXY_MULTI_CONF_PATH}"

    systemctl restart "${SERVICE_NAME}"
    ;;
  stealth)
    LAST_RESULT="not-required"
    echo "refresh-telegram-config не требуется для ENGINE=stealth" >&2
    ;;
  *)
    echo "Unsupported engine in manifest: ${ENGINE}" >&2
    exit 1
    ;;
esac
EOF_REFRESH

  sed -i "s#__MANIFEST_PATH__#${MANIFEST_PATH}#g; s#__RUN_GROUP__#${RUN_GROUP}#g" "${REFRESH_HELPER_PATH}"
}
