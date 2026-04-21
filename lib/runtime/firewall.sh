# shellcheck shell=bash

configure_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    info "Открываю порт ${PUBLIC_PORT}/tcp в ufw..."
    ufw allow "${PUBLIC_PORT}/tcp" >/dev/null 2>&1 || true
  fi
}
