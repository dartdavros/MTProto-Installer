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
  print_decoy_summary_lines

  if engine_uses_local_decoy_service; then
    echo "Decoy svc:    $(systemctl is-active "${DECOY_SERVICE_NAME}" 2>/dev/null || true)"
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
