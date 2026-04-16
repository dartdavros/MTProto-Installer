#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="mtproxy"
RUN_USER="mtproxy"
RUN_GROUP="mtproxy"

REPO_URL="${REPO_URL:-https://github.com/TelegramMessenger/MTProxy.git}"
REPO_BRANCH="${REPO_BRANCH:-master}"

SRC_DIR="/opt/mtproxy-src"
BIN_PATH="/usr/local/bin/mtproto-proxy"

CONFIG_DIR="/etc/mtproxy"
STATE_DIR="/var/lib/mtproxy"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="mtproxy.service"
SERVICE_PATH="${SYSTEMD_DIR}/${SERVICE_NAME}"

SYSCTL_FILE="/etc/sysctl.d/90-mtproxy.conf"

PORT="${PORT:-443}"
INTERNAL_PORT="${INTERNAL_PORT:-8888}"
WORKERS="${WORKERS:-1}"

CURL_BIN="$(command -v curl || true)"
GIT_BIN="$(command -v git || true)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[*]${NC} $*"; }
info() { echo -e "${BLUE}[-]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*" >&2; }

die() {
  err "$*"
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Запусти от root: sudo bash $0 <command>"
}

validate_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || die "Некорректный порт: ${value}"
  (( value >= 1 && value <= 65535 )) || die "Порт вне диапазона 1..65535: ${value}"
}

validate_runtime_settings() {
  validate_port "${PORT}"
  validate_port "${INTERNAL_PORT}"

  [[ "${WORKERS}" =~ ^[0-9]+$ ]] || die "WORKERS должен быть числом"
  (( WORKERS >= 1 )) || die "WORKERS должен быть >= 1"
}

ensure_packages() {
  log "Устанавливаю зависимости..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git \
    curl \
    ca-certificates \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    xxd \
    ufw \
    libcap2-bin
}

ensure_user_and_dirs() {
  if ! getent group "${RUN_GROUP}" >/dev/null 2>&1; then
    log "Создаю группу ${RUN_GROUP}..."
    groupadd --system "${RUN_GROUP}"
  fi

  if ! id -u "${RUN_USER}" >/dev/null 2>&1; then
    log "Создаю пользователя ${RUN_USER}..."
    useradd \
      --system \
      --home-dir "${STATE_DIR}" \
      --shell /usr/sbin/nologin \
      --gid "${RUN_GROUP}" \
      "${RUN_USER}"
  fi

  mkdir -p "${CONFIG_DIR}" "${STATE_DIR}"
  chown root:"${RUN_GROUP}" "${CONFIG_DIR}"
  chmod 750 "${CONFIG_DIR}"

  chown "${RUN_USER}:${RUN_GROUP}" "${STATE_DIR}"
  chmod 750 "${STATE_DIR}"
}

clone_or_update_repo() {
  if [[ -d "${SRC_DIR}/.git" ]]; then
    log "Обновляю исходники MTProxy..."
    git -C "${SRC_DIR}" fetch --all --tags
    git -C "${SRC_DIR}" checkout "${REPO_BRANCH}"
    git -C "${SRC_DIR}" reset --hard "origin/${REPO_BRANCH}"
    git -C "${SRC_DIR}" clean -fdx
  else
    log "Клонирую репозиторий MTProxy..."
    rm -rf "${SRC_DIR}"
    git clone --branch "${REPO_BRANCH}" "${REPO_URL}" "${SRC_DIR}"
  fi
}

patch_makefile_if_needed() {
  local makefile="${SRC_DIR}/Makefile"

  [[ -f "${makefile}" ]] || die "Не найден Makefile: ${makefile}"

  if grep -q -- '-fcommon' "${makefile}"; then
    info "Makefile уже содержит -fcommon"
    return 0
  fi

  warn "Добавляю -fcommon в Makefile как fallback для новых GCC..."
  sed -i \
    -e '/^COMMON_CFLAGS[[:space:]]*=/ s/$/ -fcommon/' \
    -e '/^COMMON_LDFLAGS[[:space:]]*=/ s/$/ -fcommon/' \
    "${makefile}"
}

build_mtproxy() {
  log "Собираю MTProxy..."
  cd "${SRC_DIR}"

  if ! make; then
    warn "Первая сборка не удалась, пробую с patch + clean..."
    patch_makefile_if_needed
    make clean || true
    make
  fi

  [[ -x "${SRC_DIR}/objs/bin/mtproto-proxy" ]] || die "Бинарник не собран"

  install -m 0755 "${SRC_DIR}/objs/bin/mtproto-proxy" "${BIN_PATH}"

  if (( PORT <= 1024 )); then
    info "Порт ${PORT} привилегированный: capability будет выдан через systemd unit"
  fi

  setcap -r "${BIN_PATH}" 2>/dev/null || true
}

ensure_secret() {
  local secret_file="${CONFIG_DIR}/secret"

  if [[ ! -f "${secret_file}" ]]; then
    log "Генерирую secret..."
    head -c 16 /dev/urandom | xxd -ps -c 32 > "${secret_file}"
  fi

  chown root:"${RUN_GROUP}" "${secret_file}"
  chmod 640 "${secret_file}"
}

download_proxy_files() {
  local tmp_secret
  local tmp_conf

  tmp_secret="$(mktemp)"
  tmp_conf="$(mktemp)"

  trap 'rm -f "${tmp_secret}" "${tmp_conf}"' RETURN

  log "Скачиваю proxy-secret..."
  curl -fsSL https://core.telegram.org/getProxySecret -o "${tmp_secret}"

  log "Скачиваю proxy-multi.conf..."
  curl -fsSL https://core.telegram.org/getProxyConfig -o "${tmp_conf}"

  install -o root -g "${RUN_GROUP}" -m 0640 "${tmp_secret}" "${CONFIG_DIR}/proxy-secret"
  install -o root -g "${RUN_GROUP}" -m 0640 "${tmp_conf}" "${CONFIG_DIR}/proxy-multi.conf"

  rm -f "${tmp_secret}" "${tmp_conf}"
  trap - RETURN
}

apply_permissions() {
  log "Применяю права..."
  chown root:"${RUN_GROUP}" "${CONFIG_DIR}"
  chmod 750 "${CONFIG_DIR}"

  chown root:"${RUN_GROUP}" "${CONFIG_DIR}/secret" "${CONFIG_DIR}/proxy-secret" "${CONFIG_DIR}/proxy-multi.conf"
  chmod 640 "${CONFIG_DIR}/secret" "${CONFIG_DIR}/proxy-secret" "${CONFIG_DIR}/proxy-multi.conf"

  chown "${RUN_USER}:${RUN_GROUP}" "${STATE_DIR}"
  chmod 750 "${STATE_DIR}"
}

ensure_pid_workaround() {
  local current_pid_max
  current_pid_max="$(cat /proc/sys/kernel/pid_max)"

  if (( current_pid_max > 65535 )); then
    warn "Текущий kernel.pid_max=${current_pid_max}, выставляю 65535 из-за бага MTProxy..."
    cat > "${SYSCTL_FILE}" <<EOF
kernel.pid_max = 65535
EOF
    sysctl -w kernel.pid_max=65535 >/dev/null
  else
    info "kernel.pid_max уже в безопасном диапазоне: ${current_pid_max}"
  fi

  if [[ -w /proc/sys/kernel/ns_last_pid ]]; then
    echo 30000 > /proc/sys/kernel/ns_last_pid || true
  fi
}

render_service_file() {
  local secret
  secret="$(tr -d '\n\r' < "${CONFIG_DIR}/secret")"

  [[ -n "${secret}" ]] || die "Файл secret пустой"

  cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=Telegram MTProxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
WorkingDirectory=${STATE_DIR}
ExecStartPre=/usr/bin/test -r ${CONFIG_DIR}/proxy-secret
ExecStartPre=/usr/bin/test -r ${CONFIG_DIR}/proxy-multi.conf
ExecStart=${BIN_PATH} -u ${RUN_USER} -p ${INTERNAL_PORT} -H ${PORT} -S ${secret} --aes-pwd ${CONFIG_DIR}/proxy-secret ${CONFIG_DIR}/proxy-multi.conf -M ${WORKERS}
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

[Install]
WantedBy=multi-user.target
EOF
}

reload_and_enable_service() {
  log "Перезагружаю systemd..."
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" >/dev/null
}

start_service() {
  log "Запускаю ${SERVICE_NAME}..."
  systemctl restart "${SERVICE_NAME}"
}

configure_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    info "Открываю порт ${PORT}/tcp в ufw..."
    ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
  fi
}

show_connection_info() {
  local secret
  local host

  secret="$(tr -d '\n\r' < "${CONFIG_DIR}/secret")"
  host="$(curl -4 -fsSL https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"

  echo
  echo "========================================"
  echo "MTProxy установлен"
  echo "Host:   ${host}"
  echo "Port:   ${PORT}"
  echo "Secret: ${secret}"
  echo
  echo "Ссылка:"
  echo "tg://proxy?server=${host}&port=${PORT}&secret=${secret}"
  echo
  echo "Проверка:"
  echo "  systemctl status ${SERVICE_NAME} --no-pager -l"
  echo "  journalctl -u ${SERVICE_NAME} -n 100 --no-pager"
  echo "========================================"
  echo
}

status() {
  systemctl status "${SERVICE_NAME}" --no-pager -l || true
  echo
  journalctl -u "${SERVICE_NAME}" -n 50 --no-pager || true
}

restart_service_command() {
  ensure_pid_workaround
  systemctl restart "${SERVICE_NAME}"
  status
}

update_config() {
  require_root
  download_proxy_files
  apply_permissions
  ensure_pid_workaround
  systemctl restart "${SERVICE_NAME}"
  log "Конфиг обновлен"
  status
}

rotate_secret() {
  require_root

  log "Ротирую client secret..."
  head -c 16 /dev/urandom | xxd -ps -c 32 > "${CONFIG_DIR}/secret"
  chown root:"${RUN_GROUP}" "${CONFIG_DIR}/secret"
  chmod 640 "${CONFIG_DIR}/secret"

  render_service_file
  systemctl daemon-reload
  ensure_pid_workaround
  systemctl restart "${SERVICE_NAME}"

  log "Secret обновлен"
  show_connection_info
}

install_all() {
  require_root
  validate_runtime_settings

  ensure_packages
  ensure_user_and_dirs
  clone_or_update_repo
  build_mtproxy
  ensure_secret
  download_proxy_files
  apply_permissions
  ensure_pid_workaround
  render_service_file
  reload_and_enable_service
  configure_firewall
  start_service
  show_connection_info
}

uninstall_all() {
  require_root

  warn "Останавливаю и удаляю сервис..."
  systemctl disable --now "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "${SERVICE_PATH}"
  systemctl daemon-reload

  warn "Удаляю бинарник и исходники..."
  rm -f "${BIN_PATH}"
  rm -rf "${SRC_DIR}"

  warn "Удаляю sysctl workaround..."
  rm -f "${SYSCTL_FILE}"
  sysctl --system >/dev/null 2>&1 || true

  warn "Удаляю конфиги и state..."
  rm -rf "${CONFIG_DIR}" "${STATE_DIR}"

  if id -u "${RUN_USER}" >/dev/null 2>&1; then
    userdel "${RUN_USER}" 2>/dev/null || true
  fi

  if getent group "${RUN_GROUP}" >/dev/null 2>&1; then
    groupdel "${RUN_GROUP}" 2>/dev/null || true
  fi

  log "MTProxy удален"
}

usage() {
  cat <<EOF
Usage:
  sudo bash $0 install
  sudo bash $0 update-config
  sudo bash $0 rotate-secret
  sudo bash $0 restart
  sudo bash $0 status
  sudo bash $0 uninstall

Environment variables:
  PORT=443
  INTERNAL_PORT=8888
  WORKERS=1
  REPO_URL=https://github.com/TelegramMessenger/MTProxy.git
  REPO_BRANCH=master

Examples:
  sudo PORT=443 WORKERS=2 bash $0 install
  sudo bash $0 update-config
EOF
}

main() {
  local cmd="${1:-}"

  case "${cmd}" in
    install)
      install_all
      ;;
    update-config)
      update_config
      ;;
    rotate-secret)
      rotate_secret
      ;;
    restart)
      require_root
      restart_service_command
      ;;
    status)
      status
      ;;
    uninstall)
      uninstall_all
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
