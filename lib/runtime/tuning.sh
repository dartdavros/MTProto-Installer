# shellcheck shell=bash

ensure_pid_workaround() {
  local current_pid_max
  current_pid_max="$(cat /proc/sys/kernel/pid_max)"

  if (( current_pid_max > 65535 )); then
    warn "Текущий kernel.pid_max=${current_pid_max}, выставляю 65535 из-за бага MTProxy..."
    cat > "${SYSCTL_FILE}" <<EOF_SYSCTL
kernel.pid_max = 65535
EOF_SYSCTL
    sysctl -w kernel.pid_max=65535 >/dev/null
  else
    info "kernel.pid_max уже в безопасном диапазоне: ${current_pid_max}"
  fi

  if [[ -w /proc/sys/kernel/ns_last_pid ]]; then
    echo 30000 > /proc/sys/kernel/ns_last_pid || true
  fi
}

cleanup_pid_workaround() {
  if [[ -f "${SYSCTL_FILE}" ]]; then
    warn "Удаляю sysctl workaround, не нужный для engine=${ENGINE}..."
    rm -f "${SYSCTL_FILE}"
    sysctl --system >/dev/null 2>&1 || true
  fi
}

apply_engine_runtime_tuning() {
  if engine_requires_pid_workaround; then
    ensure_pid_workaround
  else
    cleanup_pid_workaround
  fi
}
