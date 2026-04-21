# shellcheck shell=bash

refresh_state_clear() {
  REFRESH_LAST_ATTEMPT_EPOCH=""
  REFRESH_LAST_ATTEMPT_HUMAN=""
  REFRESH_LAST_RESULT=""
  REFRESH_LAST_SUCCESS_EPOCH=""
  REFRESH_LAST_SUCCESS_HUMAN=""
}

refresh_state_load() {
  refresh_state_clear

  [[ -f "${REFRESH_STATE_PATH}" ]] || return 1

  # shellcheck disable=SC1090
  source "${REFRESH_STATE_PATH}"

  REFRESH_LAST_ATTEMPT_EPOCH="${LAST_ATTEMPT_EPOCH:-}"
  REFRESH_LAST_ATTEMPT_HUMAN="${LAST_ATTEMPT_HUMAN:-}"
  REFRESH_LAST_RESULT="${LAST_RESULT:-}"
  REFRESH_LAST_SUCCESS_EPOCH="${LAST_SUCCESS_EPOCH:-}"
  REFRESH_LAST_SUCCESS_HUMAN="${LAST_SUCCESS_HUMAN:-}"

  return 0
}

systemd_unit_property() {
  local unit_name="$1"
  local property_name="$2"

  systemctl show -p "${property_name}" --value "${unit_name}" 2>/dev/null || true
}

normalized_systemd_value() {
  local value="$1"

  case "${value}" in
    ''|'n/a'|'[not set]')
      printf 'n/a\n'
      ;;
    *)
      printf '%s\n' "${value}"
      ;;
  esac
}

human_time_to_epoch() {
  local value="$1"

  [[ -n "${value}" && "${value}" != "n/a" ]] || return 1
  date -d "${value}" '+%s' 2>/dev/null
}

format_time_value() {
  local value="$1"

  case "${value}" in
    ''|'n/a'|'[not set]')
      printf 'n/a\n'
      ;;
    *[!0-9]*)
      printf '%s\n' "${value}"
      ;;
    *)
      date -d "@$(( value / 1000000 ))" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || printf '%s\n' "${value}"
      ;;
  esac
}

refresh_last_attempt_human() {
  local value

  if refresh_state_load && [[ -n "${REFRESH_LAST_ATTEMPT_HUMAN}" ]]; then
    printf '%s\n' "${REFRESH_LAST_ATTEMPT_HUMAN}"
    return 0
  fi

  value="$(systemd_unit_property "${REFRESH_SERVICE_NAME}" "ExecMainStartTimestamp")"
  normalized_systemd_value "${value}"
}

refresh_last_attempt_epoch() {
  local value

  if refresh_state_load && [[ -n "${REFRESH_LAST_ATTEMPT_EPOCH}" ]]; then
    printf '%s\n' "${REFRESH_LAST_ATTEMPT_EPOCH}"
    return 0
  fi

  value="$(refresh_last_attempt_human)"
  human_time_to_epoch "${value}" || return 1
}

refresh_last_result() {
  local value

  if refresh_state_load && [[ -n "${REFRESH_LAST_RESULT}" ]]; then
    printf '%s\n' "${REFRESH_LAST_RESULT}"
    return 0
  fi

  value="$(systemd_unit_property "${REFRESH_SERVICE_NAME}" "Result")"
  normalized_systemd_value "${value}"
}

refresh_last_success_human() {
  local result

  if refresh_state_load && [[ -n "${REFRESH_LAST_SUCCESS_HUMAN}" ]]; then
    printf '%s\n' "${REFRESH_LAST_SUCCESS_HUMAN}"
    return 0
  fi

  result="$(refresh_last_result)"
  if [[ "${result}" == "success" ]]; then
    refresh_last_attempt_human
  else
    printf 'n/a\n'
  fi
}

refresh_last_success_epoch() {
  local result

  if refresh_state_load && [[ -n "${REFRESH_LAST_SUCCESS_EPOCH}" ]]; then
    printf '%s\n' "${REFRESH_LAST_SUCCESS_EPOCH}"
    return 0
  fi

  result="$(refresh_last_result)"
  if [[ "${result}" == "success" ]]; then
    refresh_last_attempt_epoch
  else
    return 1
  fi
}

refresh_next_human() {
  local value

  value="$(systemd_unit_property "${REFRESH_TIMER_NAME}" "NextElapseUSecRealtime")"
  format_time_value "${value}"
}

refresh_has_recorded_attempt() {
  local value
  value="$(refresh_last_attempt_human)"
  [[ "${value}" != "n/a" ]]
}

refresh_last_result_successful() {
  [[ "$(refresh_last_result)" == "success" ]]
}

refresh_success_is_stale() {
  local now_epoch success_epoch max_age_seconds=172800

  success_epoch="$(refresh_last_success_epoch 2>/dev/null || true)"
  [[ -n "${success_epoch}" ]] || return 1

  now_epoch="$(date '+%s')"
  (( now_epoch - success_epoch > max_age_seconds ))
}

refresh_next_scheduled() {
  [[ "$(refresh_next_human)" != "n/a" ]]
}

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
  local refresh_last="n/a"
  local refresh_next="n/a"
  local refresh_result="n/a"

  if engine_requires_telegram_upstream; then
    refresh_last="$(refresh_last_attempt_human)"
    refresh_next="$(refresh_next_human)"
    refresh_result="$(refresh_last_result)"
  fi

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
  if engine_requires_telegram_upstream; then
    echo "Refresh last:   ${refresh_last}"
    echo "Refresh next:   ${refresh_next}"
    echo "Refresh result: ${refresh_result}"
  fi
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
