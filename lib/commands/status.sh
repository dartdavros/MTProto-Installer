# shellcheck shell=bash

status() {
  local timer_state="n/a"

  require_installed

  if engine_requires_telegram_upstream; then
    timer_state="$(systemctl is-active "${REFRESH_TIMER_NAME}" 2>/dev/null || true)"
  fi

  print_runtime_summary_lines \
    "$(systemctl is-active "${SERVICE_NAME}" 2>/dev/null || true)" \
    "${timer_state}"

  echo
  echo "Links (redacted):"
  print_links_table "no"
  echo
  echo "Recent logs:"
  journalctl -u "${SERVICE_NAME}" -n 20 --no-pager || true
}
