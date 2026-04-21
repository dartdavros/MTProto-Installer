# shellcheck shell=bash

ufw_available() {
  command -v ufw >/dev/null 2>&1
}

ufw_active() {
  ufw status 2>/dev/null | grep -q '^Status: active$'
}

ufw_allow_tcp_port() {
  local port="$1"
  [[ -n "${port}" ]] || return 0
  ufw allow "${port}/tcp" >/dev/null 2>&1 || true
}

ufw_delete_allow_tcp_port() {
  local port="$1"
  [[ -n "${port}" ]] || return 0
  ufw --force delete allow "${port}/tcp" >/dev/null 2>&1 || true
}

ufw_deny_tcp_port() {
  local port="$1"
  [[ -n "${port}" ]] || return 0
  ufw deny "${port}/tcp" >/dev/null 2>&1 || true
}

firewall_can_manage_local_only_port() {
  local port="$1"

  [[ -n "${port}" ]] || return 1

  case "${port}" in
    "${PUBLIC_PORT}")
      return 1
      ;;
    22)
      warn "Пропускаю firewall deny для 22/tcp: защитное правило, чтобы не сломать SSH"
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

configure_firewall() {
  local previous_public_port="${1:-}"
  local previous_internal_port="${2:-}"
  local previous_decoy_local_port="${3:-}"
  local managed_local_only_ports=()
  local port
  local seen=" "

  if ! ufw_available; then
    info "ufw не установлен: firewall policy не применяется автоматически"
    return 0
  fi

  if ! ufw_active; then
    warn "ufw установлен, но не активен: public surface не будет ограничен автоматически"
    return 0
  fi

  log "Привожу public surface к managed policy через ufw..."
  info "Открываю intended entrypoint ${PUBLIC_PORT}/tcp"
  ufw_allow_tcp_port "${PUBLIC_PORT}"

  if [[ -n "${previous_public_port}" && "${previous_public_port}" != "${PUBLIC_PORT}" ]]; then
    info "Закрываю предыдущий managed public port ${previous_public_port}/tcp"
    ufw_delete_allow_tcp_port "${previous_public_port}"
    if firewall_can_manage_local_only_port "${previous_public_port}"; then
      ufw_deny_tcp_port "${previous_public_port}"
    fi
  fi

  managed_local_only_ports+=("${INTERNAL_PORT}" "9091")

  if [[ -n "${previous_internal_port}" ]]; then
    managed_local_only_ports+=("${previous_internal_port}")
  fi

  if [[ "${DECOY_MODE}" == "local-https" ]]; then
    managed_local_only_ports+=("${DECOY_LOCAL_PORT}")
  fi

  if [[ -n "${previous_decoy_local_port}" ]]; then
    managed_local_only_ports+=("${previous_decoy_local_port}")
  fi

  for port in "${managed_local_only_ports[@]}"; do
    [[ -n "${port}" ]] || continue
    if [[ "${seen}" == *" ${port} "* ]]; then
      continue
    fi
    seen+="${port} "

    if firewall_can_manage_local_only_port "${port}"; then
      info "Ограничиваю loopback-only port ${port}/tcp"
      ufw_deny_tcp_port "${port}"
    fi
  done
}
