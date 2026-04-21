# shellcheck shell=bash

print_decoy_summary_lines() {
  if ! engine_supports_decoy; then
    return 0
  fi

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
}

print_runtime_summary_lines() {
  local service_state="$1"
  local timer_state="$2"

  echo "Service:    ${service_state}"
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
  echo "Timer:      ${timer_state}"
}

show_post_install_summary() {
  local timer_state="n/a"

  if engine_requires_telegram_upstream; then
    timer_state="$(systemctl is-active "${REFRESH_TIMER_NAME}" 2>/dev/null || true)"
  fi

  echo
  echo "========================================"
  echo "MTProxy установлен"
  print_runtime_summary_lines "$(systemctl is-active "${SERVICE_NAME}" 2>/dev/null || true)" "${timer_state}"
  echo "Links:      $(awk 'END {print NR+0}' "${LINK_BUNDLE_PATH}")"
  echo
  echo "Секреты и tg:// ссылки по умолчанию не печатаются."
  echo "Чтобы намеренно открыть bundle, выполни:"
  echo "  sudo bash $0 share-links"
  echo
  echo "Проверка:"
  echo "  sudo bash $0 status"
  echo "  sudo bash $0 health"
  echo "========================================"
  echo
}
