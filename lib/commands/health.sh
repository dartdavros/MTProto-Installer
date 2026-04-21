# shellcheck shell=bash

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
