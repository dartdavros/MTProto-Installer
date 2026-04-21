# shellcheck shell=bash

link_model_healthy() {
  local definitions_count bundle_count tmp_bundle previous_bundle_path
  local build_rc=0 compare_rc=0

  [[ -f "${LINK_DEFINITIONS_PATH}" && -f "${LINK_BUNDLE_PATH}" ]] || return 1

  definitions_count="$(awk 'NF {count++} END {print count+0}' "${LINK_DEFINITIONS_PATH}")"
  bundle_count="$(awk 'NF {count++} END {print count+0}' "${LINK_BUNDLE_PATH}")"

  (( definitions_count >= 1 )) || return 1
  (( definitions_count == bundle_count )) || return 1

  tmp_bundle="$(mktemp)"
  previous_bundle_path="${LINK_BUNDLE_PATH}"
  trap 'LINK_BUNDLE_PATH="${previous_bundle_path}"; rm -f "${tmp_bundle}"' RETURN

  LINK_BUNDLE_PATH="${tmp_bundle}"
  build_link_bundle || build_rc=$?

  if (( build_rc == 0 )); then
    cmp -s "${tmp_bundle}" "${previous_bundle_path}" || compare_rc=$?
  fi

  return $(( build_rc != 0 ? build_rc : compare_rc ))
}

service_unit_consistent() {
  [[ -f "${SERVICE_PATH}" && -f "${RUNNER_PATH}" ]] || return 1
  grep -Fq "ExecStart=${RUNNER_PATH}" "${SERVICE_PATH}" || return 1
  grep -Fq "source \"${MANIFEST_PATH}\"" "${RUNNER_PATH}" || return 1
}

stealth_runtime_consistent() {
  [[ -f "${STEALTH_CONFIG_PATH}" ]] || return 1
  grep -Fq "public_host = \"${PUBLIC_DOMAIN}\"" "${STEALTH_CONFIG_PATH}" || return 1
  grep -Fq "public_port = ${PUBLIC_PORT}" "${STEALTH_CONFIG_PATH}" || return 1
  grep -Fq "tls_domain = \"${TLS_DOMAIN}\"" "${STEALTH_CONFIG_PATH}" || return 1

  case "${DECOY_MODE}" in
    upstream-forward)
      grep -Fq "mask = true" "${STEALTH_CONFIG_PATH}" || return 1
      grep -Fq "mask_host = \"${DECOY_TARGET_HOST}\"" "${STEALTH_CONFIG_PATH}" || return 1
      grep -Fq "mask_port = ${DECOY_TARGET_PORT}" "${STEALTH_CONFIG_PATH}" || return 1
      ;;
    local-https)
      grep -Fq "mask = true" "${STEALTH_CONFIG_PATH}" || return 1
      grep -Fq 'mask_host = "127.0.0.1"' "${STEALTH_CONFIG_PATH}" || return 1
      grep -Fq "mask_port = ${DECOY_LOCAL_PORT}" "${STEALTH_CONFIG_PATH}" || return 1
      ;;
    disabled)
      grep -Fq "mask = false" "${STEALTH_CONFIG_PATH}" || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

official_runtime_consistent() {
  [[ -f "${PROXY_SECRET_PATH}" && -f "${PROXY_MULTI_CONF_PATH}" ]] || return 1
}

runtime_config_consistent() {
  if ! service_unit_consistent; then
    return 1
  fi

  case "${ENGINE}" in
    official)
      official_runtime_consistent
      ;;
    stealth)
      stealth_runtime_consistent
      ;;
    *)
      return 1
      ;;
  esac
}

public_domain_health_check() {
  local resolved_ips

  resolved_ips="$(domain_resolved_ips "${PUBLIC_DOMAIN}")"
  [[ -n "${resolved_ips}" ]] || return 1
  domain_matches_local_host "${PUBLIC_DOMAIN}"
}

health() {
  require_installed

  local failed=0

  echo "Health checks:"
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo "  [ok] service active"
  else
    echo "  [fail] service inactive"
    failed=1
  fi

  if ss -ltn "( sport = :${PUBLIC_PORT} )" | tail -n +2 | grep -q .; then
    echo "  [ok] listener present on ${PUBLIC_PORT}/tcp"
  else
    echo "  [fail] listener missing on ${PUBLIC_PORT}/tcp"
    failed=1
  fi

  if [[ -f "${MANIFEST_PATH}" && -f "${LINK_BUNDLE_PATH}" && -f "${LINK_DEFINITIONS_PATH}" ]]; then
    echo "  [ok] manifest/link artifacts present"
  else
    echo "  [fail] manifest/link artifacts missing"
    failed=1
  fi

  if [[ -n "${PUBLIC_DOMAIN}" ]]; then
    echo "  [ok] public domain recorded (${PUBLIC_DOMAIN})"
  else
    echo "  [fail] public domain missing from manifest"
    failed=1
  fi

  if public_domain_health_check; then
    echo "  [ok] public domain resolves to the current VPS"
  else
    echo "  [fail] public domain DNS does not match this VPS"
    failed=1
  fi

  if engine_requires_telegram_upstream; then
    if systemctl is-enabled --quiet "${REFRESH_TIMER_NAME}" 2>/dev/null; then
      echo "  [ok] refresh timer enabled"
    else
      echo "  [fail] refresh timer disabled"
      failed=1
    fi
  fi

  if engine_runtime_artifacts_present; then
    echo "  [ok] runtime artifacts present"
  else
    echo "  [fail] runtime artifacts missing"
    failed=1
  fi

  if runtime_config_consistent; then
    echo "  [ok] runtime config consistent with manifest"
  else
    echo "  [fail] runtime config drift detected"
    failed=1
  fi

  if link_model_healthy; then
    echo "  [ok] link bundle consistent with definitions and secrets"
  else
    echo "  [fail] link bundle drift detected"
    failed=1
  fi

  if engine_supports_decoy; then
    case "${DECOY_MODE}" in
      upstream-forward)
        if [[ -n "${DECOY_TARGET_HOST}" ]]; then
          echo "  [ok] decoy target recorded (${DECOY_TARGET_HOST}:${DECOY_TARGET_PORT})"
        else
          echo "  [fail] decoy target missing"
          failed=1
        fi
        ;;
      local-https)
        if systemctl is-active --quiet "${DECOY_SERVICE_NAME}"; then
          echo "  [ok] local decoy service active"
        else
          echo "  [fail] local decoy service inactive"
          failed=1
        fi

        if ss -ltn "( sport = :${DECOY_LOCAL_PORT} )" | tail -n +2 | grep -q "127.0.0.1:${DECOY_LOCAL_PORT}"; then
          echo "  [ok] local decoy listener present on 127.0.0.1:${DECOY_LOCAL_PORT}"
        else
          echo "  [fail] local decoy listener missing on 127.0.0.1:${DECOY_LOCAL_PORT}"
          failed=1
        fi

        if curl -sk --resolve "${DECOY_DOMAIN}:${DECOY_LOCAL_PORT}:127.0.0.1" "https://${DECOY_DOMAIN}:${DECOY_LOCAL_PORT}/" >/dev/null; then
          echo "  [ok] local decoy HTTPS probe succeeded"
        else
          echo "  [fail] local decoy HTTPS probe failed"
          failed=1
        fi
        ;;
      *)
        echo "  [ok] decoy mode ${DECOY_MODE}"
        ;;
    esac
  fi

  if (( failed == 0 )); then
    echo
    log "Health check passed"
  else
    echo
    die "Health check failed"
  fi
}
