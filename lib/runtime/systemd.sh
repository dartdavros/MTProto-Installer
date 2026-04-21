# shellcheck shell=bash

apply_permissions() {
  log "Применяю права..."

  chown root:"${RUN_GROUP}" "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}"
  chmod 750 "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}"

  [[ -f "${MANIFEST_PATH}" ]] && chown root:"${RUN_GROUP}" "${MANIFEST_PATH}" && chmod 0640 "${MANIFEST_PATH}"
  [[ -f "${PROXY_SECRET_PATH}" ]] && chown root:"${RUN_GROUP}" "${PROXY_SECRET_PATH}" && chmod 0640 "${PROXY_SECRET_PATH}"
  [[ -f "${PROXY_MULTI_CONF_PATH}" ]] && chown root:"${RUN_GROUP}" "${PROXY_MULTI_CONF_PATH}" && chmod 0640 "${PROXY_MULTI_CONF_PATH}"
  [[ -f "${STEALTH_CONFIG_PATH}" ]] && chown root:"${RUN_GROUP}" "${STEALTH_CONFIG_PATH}" && chmod 0640 "${STEALTH_CONFIG_PATH}"
  [[ -f "${LINK_DEFINITIONS_PATH}" ]] && chown root:"${RUN_GROUP}" "${LINK_DEFINITIONS_PATH}" && chmod 0640 "${LINK_DEFINITIONS_PATH}"
  [[ -f "${LINK_BUNDLE_PATH}" ]] && chown root:"${RUN_GROUP}" "${LINK_BUNDLE_PATH}" && chmod 0640 "${LINK_BUNDLE_PATH}"
  [[ -f "${DECOY_MANAGED_CERT_PATH}" ]] && chown root:"${RUN_GROUP}" "${DECOY_MANAGED_CERT_PATH}" && chmod 0640 "${DECOY_MANAGED_CERT_PATH}"
  [[ -f "${DECOY_MANAGED_KEY_PATH}" ]] && chown root:"${RUN_GROUP}" "${DECOY_MANAGED_KEY_PATH}" && chmod 0640 "${DECOY_MANAGED_KEY_PATH}"

  if compgen -G "${SECRETS_DIR}/*.secret" >/dev/null; then
    chown root:"${RUN_GROUP}" "${SECRETS_DIR}"/*.secret
    chmod 0640 "${SECRETS_DIR}"/*.secret
  fi

  [[ -f "${RUNNER_PATH}" ]] && chown root:"${RUN_GROUP}" "${RUNNER_PATH}" && chmod 0750 "${RUNNER_PATH}"
  [[ -f "${REFRESH_HELPER_PATH}" ]] && chown root:"${RUN_GROUP}" "${REFRESH_HELPER_PATH}" && chmod 0750 "${REFRESH_HELPER_PATH}"
  [[ -f "${DECOY_SERVER_PATH}" ]] && chown root:"${RUN_GROUP}" "${DECOY_SERVER_PATH}" && chmod 0750 "${DECOY_SERVER_PATH}"

  chown -R "${RUN_USER}:${RUN_GROUP}" "${STATE_DIR}"
  chmod 750 "${STATE_DIR}" "${STEALTH_TLS_FRONT_DIR}" "${DECOY_WWW_DIR}"
}

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
  case "${ENGINE}" in
    official)
      ensure_pid_workaround
      ;;
    stealth)
      cleanup_pid_workaround
      ;;
  esac
}

render_runner_script() {
  cat > "${RUNNER_PATH}" <<'EOF_RUNNER'
#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1090
source "__MANIFEST_PATH__"

case "${ENGINE}" in
  official)
    secret_args=()
    while IFS=$'\t' read -r name profile; do
      [[ -n "${name}" ]] || continue
      secret_file="${SECRETS_DIR}/${name}.secret"
      [[ -f "${secret_file}" ]] || { echo "Secret slot not found: ${secret_file}" >&2; exit 1; }
      secret="$(tr -d '\n\r' < "${secret_file}")"
      [[ -n "${secret}" ]] || { echo "Secret slot is empty: ${secret_file}" >&2; exit 1; }
      secret_args+=("-S" "${secret}")
    done < "${LINK_DEFINITIONS_PATH}"

    exec "${OFFICIAL_BIN_PATH}" -u "${RUN_USER}" -p "${INTERNAL_PORT}" -H "${PUBLIC_PORT}" "${secret_args[@]}" --aes-pwd "${PROXY_SECRET_PATH}" "${PROXY_MULTI_CONF_PATH}" -M "${WORKERS}"
    ;;
  stealth)
    [[ -x "${STEALTH_BIN_PATH}" ]] || { echo "Stealth binary not found: ${STEALTH_BIN_PATH}" >&2; exit 1; }
    [[ -r "${STEALTH_CONFIG_PATH}" ]] || { echo "Stealth config not found: ${STEALTH_CONFIG_PATH}" >&2; exit 1; }
    exec "${STEALTH_BIN_PATH}" "${STEALTH_CONFIG_PATH}"
    ;;
  *)
    echo "Unsupported engine in manifest: ${ENGINE}" >&2
    exit 1
    ;;
esac
EOF_RUNNER

  sed -i "s#__MANIFEST_PATH__#${MANIFEST_PATH}#g" "${RUNNER_PATH}"
}

render_refresh_helper() {
  cat > "${REFRESH_HELPER_PATH}" <<'EOF_REFRESH'
#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1090
source "__MANIFEST_PATH__"

case "${ENGINE}" in
  official)
    tmp_secret="$(mktemp)"
    tmp_conf="$(mktemp)"
    trap 'rm -f "${tmp_secret}" "${tmp_conf}"' EXIT

    curl -fsSL https://core.telegram.org/getProxySecret -o "${tmp_secret}"
    curl -fsSL https://core.telegram.org/getProxyConfig -o "${tmp_conf}"

    install -o root -g "__RUN_GROUP__" -m 0640 "${tmp_secret}" "${PROXY_SECRET_PATH}"
    install -o root -g "__RUN_GROUP__" -m 0640 "${tmp_conf}" "${PROXY_MULTI_CONF_PATH}"

    systemctl restart "${SERVICE_NAME}"
    ;;
  stealth)
    echo "refresh-telegram-config не требуется для ENGINE=stealth" >&2
    ;;
  *)
    echo "Unsupported engine in manifest: ${ENGINE}" >&2
    exit 1
    ;;
esac
EOF_REFRESH

  sed -i "s#__MANIFEST_PATH__#${MANIFEST_PATH}#g; s#__RUN_GROUP__#${RUN_GROUP}#g" "${REFRESH_HELPER_PATH}"
}

render_service_file() {
  cat > "${SERVICE_PATH}" <<EOF_SERVICE
[Unit]
Description=Telegram MTProxy (${ENGINE})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
WorkingDirectory=${STATE_DIR}
ExecStartPre=/usr/bin/test -x ${RUNNER_PATH}
ExecStartPre=/usr/bin/test -r ${MANIFEST_PATH}
ExecStart=${RUNNER_PATH}
Restart=on-failure
RestartSec=5
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${STATE_DIR}
LimitNOFILE=65535
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF_SERVICE
}

render_refresh_units() {
  if [[ "${ENGINE}" == "official" ]]; then
    cat > "${REFRESH_SERVICE_PATH}" <<EOF_REFRESH_SERVICE
[Unit]
Description=Refresh Telegram MTProxy upstream configuration
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${REFRESH_HELPER_PATH}
EOF_REFRESH_SERVICE

    cat > "${REFRESH_TIMER_PATH}" <<EOF_REFRESH_TIMER
[Unit]
Description=Daily refresh for Telegram MTProxy upstream configuration

[Timer]
OnCalendar=daily
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF_REFRESH_TIMER
  else
    rm -f "${REFRESH_SERVICE_PATH}" "${REFRESH_TIMER_PATH}"
  fi
}

reload_and_enable_units() {
  log "Перезагружаю systemd..."
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" >/dev/null

  if [[ "${ENGINE}" == "official" ]]; then
    systemctl enable "${REFRESH_TIMER_NAME}" >/dev/null
  else
    systemctl disable --now "${REFRESH_TIMER_NAME}" >/dev/null 2>&1 || true
  fi

  if [[ "${ENGINE}" == "stealth" && "${DECOY_MODE}" == "local-https" ]]; then
    systemctl enable "${DECOY_SERVICE_NAME}" >/dev/null
  else
    systemctl disable --now "${DECOY_SERVICE_NAME}" >/dev/null 2>&1 || true
  fi
}

start_service() {
  if [[ "${ENGINE}" == "stealth" && "${DECOY_MODE}" == "local-https" ]]; then
    log "Запускаю ${DECOY_SERVICE_NAME}..."
    systemctl restart "${DECOY_SERVICE_NAME}"
  fi

  log "Запускаю ${SERVICE_NAME}..."
  systemctl restart "${SERVICE_NAME}"

  if [[ "${ENGINE}" == "official" ]]; then
    systemctl start "${REFRESH_TIMER_NAME}"
  fi
}

configure_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    info "Открываю порт ${PUBLIC_PORT}/tcp в ufw..."
    ufw allow "${PUBLIC_PORT}/tcp" >/dev/null 2>&1 || true
  fi
}
