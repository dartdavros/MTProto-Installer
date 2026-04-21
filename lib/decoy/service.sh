# shellcheck shell=bash

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
