# shellcheck shell=bash

write_decoy_site_content() {
  cat > "${DECOY_WWW_DIR}/index.html" <<EOF_DECOY_HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${DECOY_DOMAIN}</title>
  <style>
    :root { color-scheme: light dark; }
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f7f9fc; color: #1f2937; }
    main { max-width: 720px; margin: 12vh auto; padding: 0 24px; }
    h1 { font-size: 32px; margin: 0 0 12px; }
    p { line-height: 1.6; color: #4b5563; }
    .card { background: #fff; border-radius: 18px; padding: 28px 32px; box-shadow: 0 18px 48px rgba(15, 23, 42, 0.08); }
  </style>
</head>
<body>
  <main>
    <section class="card">
      <h1>Welcome to ${DECOY_DOMAIN}</h1>
      <p>This service is online.</p>
      <p>Please contact the site owner if you expected a different destination.</p>
    </section>
  </main>
</body>
</html>
EOF_DECOY_HTML
}

ensure_decoy_tls_material() {
  local tmp_cert tmp_key

  if [[ -n "${DECOY_CERT_SOURCE_PATH}" && -n "${DECOY_KEY_SOURCE_PATH}" ]]; then
    log "Копирую предоставленный decoy TLS certificate..."
    install -o root -g "${RUN_GROUP}" -m 0640 "${DECOY_CERT_SOURCE_PATH}" "${DECOY_MANAGED_CERT_PATH}"
    install -o root -g "${RUN_GROUP}" -m 0640 "${DECOY_KEY_SOURCE_PATH}" "${DECOY_MANAGED_KEY_PATH}"
    return 0
  fi

  if [[ -f "${DECOY_MANAGED_CERT_PATH}" && -f "${DECOY_MANAGED_KEY_PATH}" ]]; then
    info "Decoy TLS certificate уже существует, переиспользую"
    return 0
  fi

  warn "DECOY_CERT_PATH/DECOY_KEY_PATH не заданы, генерирую self-signed certificate для ${DECOY_DOMAIN}"
  tmp_cert="$(mktemp)"
  tmp_key="$(mktemp)"
  trap 'rm -f "${tmp_cert}" "${tmp_key}"' RETURN

  openssl req \
    -x509 \
    -newkey rsa:2048 \
    -sha256 \
    -nodes \
    -days 397 \
    -subj "/CN=${DECOY_DOMAIN}" \
    -addext "subjectAltName=DNS:${DECOY_DOMAIN}" \
    -keyout "${tmp_key}" \
    -out "${tmp_cert}" >/dev/null 2>&1

  install -o root -g "${RUN_GROUP}" -m 0640 "${tmp_cert}" "${DECOY_MANAGED_CERT_PATH}"
  install -o root -g "${RUN_GROUP}" -m 0640 "${tmp_key}" "${DECOY_MANAGED_KEY_PATH}"

  rm -f "${tmp_cert}" "${tmp_key}"
  trap - RETURN
}

render_decoy_server_script() {
  cat > "${DECOY_SERVER_PATH}" <<EOF_DECOY_SERVER
#!/usr/bin/env python3
import functools
import ssl
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = ${DECOY_LOCAL_PORT}
ROOT = r"${DECOY_WWW_DIR}"
CERT = r"${DECOY_MANAGED_CERT_PATH}"
KEY = r"${DECOY_MANAGED_KEY_PATH}"

class DecoyHandler(SimpleHTTPRequestHandler):
    server_version = "nginx"
    sys_version = ""

    def log_message(self, format, *args):
        return

handler = functools.partial(DecoyHandler, directory=ROOT)
server = ThreadingHTTPServer((HOST, PORT), handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_2
context.load_cert_chain(CERT, KEY)
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
EOF_DECOY_SERVER
}

render_decoy_service_file() {
  cat > "${DECOY_SERVICE_PATH}" <<EOF_DECOY_SERVICE
[Unit]
Description=Local HTTPS decoy for Telegram MTProxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
Environment=PYTHONDONTWRITEBYTECODE=1
WorkingDirectory=${DECOY_WWW_DIR}
ExecStartPre=/usr/bin/test -x ${DECOY_SERVER_PATH}
ExecStartPre=/usr/bin/test -r ${DECOY_MANAGED_CERT_PATH}
ExecStartPre=/usr/bin/test -r ${DECOY_MANAGED_KEY_PATH}
ExecStart=${DECOY_SERVER_PATH}
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=${CONFIG_ROOT} ${STATE_DIR}
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
EOF_DECOY_SERVICE
}

render_decoy_runtime_artifacts() {
  if [[ "${ENGINE}" == "stealth" && "${DECOY_MODE}" == "local-https" ]]; then
    ensure_decoy_tls_material
    write_decoy_site_content
    render_decoy_server_script
    render_decoy_service_file
  else
    rm -f "${DECOY_SERVER_PATH}" "${DECOY_SERVICE_PATH}"
  fi
}

effective_decoy_cert_path() {
  if [[ -f "${DECOY_MANAGED_CERT_PATH}" ]]; then
    printf '%s
' "${DECOY_MANAGED_CERT_PATH}"
  else
    printf '%s
' "${DECOY_CERT_SOURCE_PATH}"
  fi
}

effective_decoy_key_path() {
  if [[ -f "${DECOY_MANAGED_KEY_PATH}" ]]; then
    printf '%s
' "${DECOY_MANAGED_KEY_PATH}"
  else
    printf '%s
' "${DECOY_KEY_SOURCE_PATH}"
  fi
}
