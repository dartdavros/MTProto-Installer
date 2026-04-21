# shellcheck shell=bash

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

  if engine_supports_decoy; then
    case "${DECOY_MODE}" in
      upstream-forward)
        echo "Decoy upstream: ${DECOY_TARGET_HOST}:${DECOY_TARGET_PORT}"
        ;;
      local-https)
        echo "Decoy domain: ${DECOY_DOMAIN}"
        echo "Decoy local:  127.0.0.1:${DECOY_LOCAL_PORT}"
        echo "Decoy svc:    $(systemctl is-active "${DECOY_SERVICE_NAME}" 2>/dev/null || true)"
        ;;
    esac
  fi

  if engine_requires_telegram_upstream; then
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
