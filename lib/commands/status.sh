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
  echo "Rotation backups: $(rotation_backup_count)"
  echo "Install backups:  $(install_backup_count)"
  if latest_rotation_backup_id >/dev/null 2>&1; then
    echo "Last rotation backup: $(latest_rotation_backup_id)"
  fi
  if latest_install_backup_id >/dev/null 2>&1; then
    echo "Last install backup:  $(latest_install_backup_id)"
  fi

  echo
  echo "Links (redacted):"
  print_links_table "no"
  echo
  echo "Recent logs:"
  journalctl -u "${SERVICE_NAME}" -n 20 --no-pager || true
}
