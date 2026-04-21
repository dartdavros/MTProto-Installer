# shellcheck shell=bash

check_domain_command() {
  read_manifest_contract

  local domain="${REQUESTED_PUBLIC_DOMAIN:-${MANIFEST_PUBLIC_DOMAIN:-}}"
  local tls_domain="${REQUESTED_TLS_DOMAIN:-${MANIFEST_TLS_DOMAIN:-}}"

  [[ -n "${domain}" ]] || die "Укажи PUBLIC_DOMAIN либо выполни команду на установленной системе"

  print_domain_diagnostics "${domain,,}" "Public domain"

  if [[ -n "${tls_domain}" && "${tls_domain,,}" != "${domain,,}" ]]; then
    echo
    print_domain_diagnostics "${tls_domain,,}" "TLS domain"
  fi
}

test_decoy_command() {
  require_installed

  [[ "${ENGINE}" == "stealth" ]] || die "test-decoy поддержан только для ENGINE=stealth"
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

status() {
  require_installed

  echo "Service:    $(systemctl is-active "${SERVICE_NAME}" 2>/dev/null || true)"
  echo "Domain:     ${PUBLIC_DOMAIN}"
  echo "Port:       ${PUBLIC_PORT}"
  echo "Engine:     ${ENGINE}"
  echo "Strategy:   ${LINK_STRATEGY}"
  if [[ "${LINK_STRATEGY}" == "per-device" ]]; then
    echo "Devices:    ${DEVICE_NAMES}"
  fi
  echo "TLS domain: ${TLS_DOMAIN}"
  echo "Decoy:      ${DECOY_MODE}"
  if [[ "${ENGINE}" == "stealth" && "${DECOY_MODE}" == "upstream-forward" ]]; then
    echo "Decoy upstream: ${DECOY_TARGET_HOST}:${DECOY_TARGET_PORT}"
  elif [[ "${ENGINE}" == "stealth" && "${DECOY_MODE}" == "local-https" ]]; then
    echo "Decoy domain: ${DECOY_DOMAIN}"
    echo "Decoy local:  127.0.0.1:${DECOY_LOCAL_PORT}"
    echo "Decoy svc:    $(systemctl is-active "${DECOY_SERVICE_NAME}" 2>/dev/null || true)"
  fi

  if [[ "${ENGINE}" == "official" ]]; then
    echo "Timer:      $(systemctl is-active "${REFRESH_TIMER_NAME}" 2>/dev/null || true)"
  else
    echo "Timer:      n/a"
  fi

  echo
  echo "Links (redacted):"
  print_links_table "no"
  echo
  echo "Recent logs:"
  journalctl -u "${SERVICE_NAME}" -n 20 --no-pager || true
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

  case "${ENGINE}" in
    official)
      if systemctl is-enabled --quiet "${REFRESH_TIMER_NAME}" 2>/dev/null; then
        echo "  [ok] refresh timer enabled"
      else
        echo "  [fail] refresh timer disabled"
        failed=1
      fi

      if [[ -f "${PROXY_SECRET_PATH}" && -f "${PROXY_MULTI_CONF_PATH}" && -x "${OFFICIAL_BIN_PATH}" ]]; then
        echo "  [ok] official runtime artifacts present"
      else
        echo "  [fail] official runtime artifacts missing"
        failed=1
      fi
      ;;
    stealth)
      if [[ -f "${STEALTH_CONFIG_PATH}" && -x "${STEALTH_BIN_PATH}" ]]; then
        echo "  [ok] stealth runtime artifacts present"
      else
        echo "  [fail] stealth runtime artifacts missing"
        failed=1
      fi

      if [[ "${DECOY_MODE}" == "upstream-forward" ]]; then
        if [[ -n "${DECOY_TARGET_HOST}" ]]; then
          echo "  [ok] decoy target recorded (${DECOY_TARGET_HOST}:${DECOY_TARGET_PORT})"
        else
          echo "  [fail] decoy target missing"
          failed=1
        fi
      elif [[ "${DECOY_MODE}" == "local-https" ]]; then
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
      else
        echo "  [ok] decoy mode ${DECOY_MODE}"
      fi
      ;;
  esac

  if (( failed == 0 )); then
    echo
    log "Health check passed"
  else
    echo
    die "Health check failed"
  fi
}

share_links() {
  require_root
  require_installed

  echo "Links:"
  print_links_table "yes"
}

list_links() {
  require_installed

  echo "Links (redacted):"
  print_links_table "no"
}
