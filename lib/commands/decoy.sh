# shellcheck shell=bash

test_decoy_command() {
  require_installed

  engine_supports_decoy || die "test-decoy поддержан только для ENGINE=stealth"
  [[ "${DECOY_MODE}" != "disabled" ]] || die "Decoy отключен: DECOY_MODE=disabled"

  local failed=0
  local cert_path key_path

  echo "Decoy diagnostics:"
  echo "  mode: ${DECOY_MODE}"

  case "${DECOY_MODE}" in
    upstream-forward)
      echo "  target: ${DECOY_TARGET_HOST}:${DECOY_TARGET_PORT}"

      if timeout 10 bash -lc "cat < /dev/null > /dev/tcp/${DECOY_TARGET_HOST}/${DECOY_TARGET_PORT}" 2>/dev/null; then
        echo "  [ok] upstream target accepts TCP connection"
      else
        echo "  [fail] upstream target TCP connection failed"
        failed=1
      fi

      if curl -skI --connect-timeout 5 --max-time 10 "https://${DECOY_TARGET_HOST}:${DECOY_TARGET_PORT}/" >/dev/null; then
        echo "  [ok] upstream HTTPS probe succeeded"
      else
        echo "  [fail] upstream HTTPS probe failed"
        failed=1
      fi
      ;;
    local-https)
      echo "  domain: ${DECOY_DOMAIN}"
      echo "  local:  127.0.0.1:${DECOY_LOCAL_PORT}"

      if systemctl is-active --quiet "${DECOY_SERVICE_NAME}"; then
        echo "  [ok] decoy service active"
      else
        echo "  [fail] decoy service inactive"
        failed=1
      fi

      cert_path="$(effective_decoy_cert_path)"
      key_path="$(effective_decoy_key_path)"

      if [[ -f "${cert_path}" && -f "${key_path}" ]]; then
        echo "  [ok] decoy TLS material present"
      else
        echo "  [fail] decoy TLS material missing"
        failed=1
      fi

      if curl -sk --resolve "${DECOY_DOMAIN}:${DECOY_LOCAL_PORT}:127.0.0.1" "https://${DECOY_DOMAIN}:${DECOY_LOCAL_PORT}/" >/dev/null; then
        echo "  [ok] local HTTPS probe succeeded"
      else
        echo "  [fail] local HTTPS probe failed"
        failed=1
      fi

      if [[ -f "${cert_path}" ]] && openssl x509 -in "${cert_path}" -noout -ext subjectAltName 2>/dev/null | grep -Fq "DNS:${DECOY_DOMAIN}"; then
        echo "  [ok] certificate SAN contains ${DECOY_DOMAIN}"
      else
        echo "  [warn] certificate SAN does not contain ${DECOY_DOMAIN}"
      fi
      ;;
    *)
      die "Неподдерживаемый decoy mode: ${DECOY_MODE}"
      ;;
  esac

  if (( failed == 0 )); then
    echo
    log "Decoy diagnostics passed"
  else
    echo
    die "Decoy diagnostics failed"
  fi
}
