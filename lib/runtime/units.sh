# shellcheck shell=bash

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
  if engine_requires_telegram_upstream; then
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

  if engine_requires_telegram_upstream; then
    systemctl enable "${REFRESH_TIMER_NAME}" >/dev/null
  else
    systemctl disable --now "${REFRESH_TIMER_NAME}" >/dev/null 2>&1 || true
  fi

  if engine_uses_local_decoy_service; then
    systemctl enable "${DECOY_SERVICE_NAME}" >/dev/null
  else
    systemctl disable --now "${DECOY_SERVICE_NAME}" >/dev/null 2>&1 || true
  fi
}
