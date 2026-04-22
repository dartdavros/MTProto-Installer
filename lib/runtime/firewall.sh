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

ufw_delete_deny_tcp_port() {
  local port="$1"
  [[ -n "${port}" ]] || return 0
  ufw --force delete deny "${port}/tcp" >/dev/null 2>&1 || true
}

firewall_current_public_port() {
  local public_port="${PUBLIC_PORT:-}"

  if [[ -z "${public_port}" ]]; then
    public_port="$(manifest_default_value PUBLIC_PORT 2>/dev/null || printf '443')"
  fi

  printf '%s
' "${public_port}"
}

firewall_current_internal_port() {
  local internal_port="${INTERNAL_PORT:-}"

  if [[ -z "${internal_port}" ]]; then
    internal_port="$(manifest_default_value INTERNAL_PORT 2>/dev/null || printf '8888')"
  fi

  printf '%s
' "${internal_port}"
}

firewall_current_decoy_mode() {
  local decoy_mode="${DECOY_MODE:-}"

  if [[ -z "${decoy_mode}" ]]; then
    decoy_mode="$(manifest_default_value DECOY_MODE 2>/dev/null || printf 'disabled')"
  fi

  printf '%s
' "${decoy_mode}"
}

firewall_current_decoy_local_port() {
  local decoy_local_port="${DECOY_LOCAL_PORT:-}"

  if [[ -z "${decoy_local_port}" ]]; then
    decoy_local_port="$(manifest_default_value DECOY_LOCAL_PORT 2>/dev/null || true)"
  fi

  printf '%s
' "${decoy_local_port}"
}

firewall_can_manage_local_only_port() {
  local port="$1"
  local public_port

  public_port="$(firewall_current_public_port)"

  [[ -n "${port}" ]] || return 1

  case "${port}" in
    "${public_port}")
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

remove_managed_firewall_policy() {
  local public_port internal_port decoy_mode decoy_local_port
  local managed_local_only_ports
  local port
  local seen=" "

  public_port="$(firewall_current_public_port)"
  internal_port="$(firewall_current_internal_port)"
  decoy_mode="$(firewall_current_decoy_mode)"
  decoy_local_port="$(firewall_current_decoy_local_port)"
  managed_local_only_ports=("${internal_port}" "9091")

  if ! ufw_available || ! ufw_active; then
    return 0
  fi

  info "Удаляю managed firewall policy..."
  ufw_delete_allow_tcp_port "${public_port}"

  if [[ "${decoy_mode}" == "local-https" ]]; then
    managed_local_only_ports+=("${decoy_local_port}")
  fi

  for port in "${managed_local_only_ports[@]}"; do
    [[ -n "${port}" ]] || continue
    if [[ "${seen}" == *" ${port} "* ]]; then
      continue
    fi
    seen+="${port} "

    if firewall_can_manage_local_only_port "${port}"; then
      ufw_delete_deny_tcp_port "${port}"
    fi
  done
}
