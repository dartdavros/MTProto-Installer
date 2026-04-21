#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="mtproxy"
RUN_USER="mtproxy"
RUN_GROUP="mtproxy"

REPO_URL="${REPO_URL:-https://github.com/TelegramMessenger/MTProxy.git}"
REPO_BRANCH="${REPO_BRANCH:-master}"

SRC_DIR="/opt/mtproxy-src"
BIN_PATH="/usr/local/bin/mtproto-proxy"

CONFIG_ROOT="/etc/mtproxy"
MANIFEST_DIR="${CONFIG_ROOT}/config"
SECRETS_DIR="${CONFIG_ROOT}/secrets"
LINKS_DIR="${CONFIG_ROOT}/links"
RUNTIME_DIR="${CONFIG_ROOT}/runtime"
STATE_DIR="/var/lib/mtproxy"
LIBEXEC_DIR="/usr/local/libexec"

MANIFEST_PATH="${MANIFEST_DIR}/manifest.env"
PROXY_SECRET_PATH="${MANIFEST_DIR}/proxy-secret"
PROXY_MULTI_CONF_PATH="${MANIFEST_DIR}/proxy-multi.conf"
LINK_DEFINITIONS_PATH="${LINKS_DIR}/definitions.tsv"
LINK_BUNDLE_PATH="${LINKS_DIR}/bundle.tsv"
RUNNER_PATH="${LIBEXEC_DIR}/mtproxy-run"
REFRESH_HELPER_PATH="${LIBEXEC_DIR}/mtproxy-refresh"

SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="mtproxy.service"
SERVICE_PATH="${SYSTEMD_DIR}/${SERVICE_NAME}"
REFRESH_SERVICE_NAME="mtproxy-refresh.service"
REFRESH_SERVICE_PATH="${SYSTEMD_DIR}/${REFRESH_SERVICE_NAME}"
REFRESH_TIMER_NAME="mtproxy-refresh.timer"
REFRESH_TIMER_PATH="${SYSTEMD_DIR}/${REFRESH_TIMER_NAME}"

SYSCTL_FILE="/etc/sysctl.d/90-mtproxy.conf"
LEGACY_SECRET_PATH="${CONFIG_ROOT}/secret"
LEGACY_PROXY_SECRET_PATH="${CONFIG_ROOT}/proxy-secret"
LEGACY_PROXY_MULTI_CONF_PATH="${CONFIG_ROOT}/proxy-multi.conf"

REQUESTED_PUBLIC_DOMAIN="${PUBLIC_DOMAIN:-}"
REQUESTED_PUBLIC_PORT="${PUBLIC_PORT:-${PORT:-}}"
REQUESTED_INTERNAL_PORT="${INTERNAL_PORT:-}"
REQUESTED_WORKERS="${WORKERS:-}"
REQUESTED_ENGINE="${ENGINE:-}"
REQUESTED_PRIMARY_PROFILE="${PRIMARY_PROFILE:-}"
REQUESTED_LINK_STRATEGY="${LINK_STRATEGY:-}"

PUBLIC_DOMAIN=""
PUBLIC_PORT="443"
INTERNAL_PORT="8888"
WORKERS="1"
ENGINE="official"
PRIMARY_PROFILE="dd"
LINK_STRATEGY="bundle"

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

quote_kv() {
  local key="$1"
  local value="$2"
  printf '%s=%q\n' "${key}" "${value}"
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Запусти от root: sudo bash $0 <command>"
}

require_installed() {
  [[ -f "${MANIFEST_PATH}" ]] || die "Установка не найдена: отсутствует ${MANIFEST_PATH}"
  load_manifest
}

validate_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || die "Некорректный порт: ${value}"
  (( value >= 1 && value <= 65535 )) || die "Порт вне диапазона 1..65535: ${value}"
}

validate_domain() {
  local value="$1"
  [[ -n "${value}" ]] || die "PUBLIC_DOMAIN обязателен"
  [[ "${value}" =~ ^[A-Za-z0-9.-]+$ ]] || die "Некорректный домен: ${value}"
  [[ "${value}" != .* && "${value}" != *..* && "${value}" != *-.* && "${value}" != *.-* ]] || die "Некорректный домен: ${value}"
}

validate_runtime_settings() {
  validate_port "${PUBLIC_PORT}"
  validate_port "${INTERNAL_PORT}"

  [[ "${WORKERS}" =~ ^[0-9]+$ ]] || die "WORKERS должен быть числом"
  (( WORKERS >= 1 )) || die "WORKERS должен быть >= 1"
}

validate_install_contract() {
  if [[ -n "${PUBLIC_PORT:-}" && -n "${PORT:-}" && "${PUBLIC_PORT}" != "${PORT}" ]]; then
    die "Заданы конфликтующие PUBLIC_PORT=${PUBLIC_PORT} и PORT=${PORT}"
  fi

  validate_domain "${PUBLIC_DOMAIN}"
  validate_runtime_settings

  case "${ENGINE}" in
    official)
      ;;
    stealth)
      die "ENGINE=stealth еще не реализован в текущей итерации. В этой поставке поддержан только ENGINE=official без фальшивого stealth-обмана."
      ;;
    *)
      die "Поддерживаются только ENGINE=official|stealth"
      ;;
  esac

  case "${LINK_STRATEGY}" in
    bundle)
      ;;
    per-device)
      die "LINK_STRATEGY=per-device еще не реализован в текущей итерации"
      ;;
    *)
      die "Поддерживаются только LINK_STRATEGY=bundle|per-device"
      ;;
  esac

  case "${PRIMARY_PROFILE}" in
    dd|classic)
      ;;
    *)
      die "Для ENGINE=official поддерживаются только PRIMARY_PROFILE=dd|classic"
      ;;
  esac
}

load_manifest() {
  # shellcheck disable=SC1090
  source "${MANIFEST_PATH}"
}

read_manifest_contract() {
  MANIFEST_PUBLIC_DOMAIN=""
  MANIFEST_PUBLIC_PORT=""
  MANIFEST_INTERNAL_PORT=""
  MANIFEST_WORKERS=""
  MANIFEST_ENGINE=""
  MANIFEST_PRIMARY_PROFILE=""
  MANIFEST_LINK_STRATEGY=""

  if [[ -f "${MANIFEST_PATH}" ]]; then
    local PUBLIC_DOMAIN=""
    local PUBLIC_PORT=""
    local INTERNAL_PORT=""
    local WORKERS=""
    local ENGINE=""
    local PRIMARY_PROFILE=""
    local LINK_STRATEGY=""

    # shellcheck disable=SC1090
    source "${MANIFEST_PATH}"

    MANIFEST_PUBLIC_DOMAIN="${PUBLIC_DOMAIN:-}"
    MANIFEST_PUBLIC_PORT="${PUBLIC_PORT:-}"
    MANIFEST_INTERNAL_PORT="${INTERNAL_PORT:-}"
    MANIFEST_WORKERS="${WORKERS:-}"
    MANIFEST_ENGINE="${ENGINE:-}"
    MANIFEST_PRIMARY_PROFILE="${PRIMARY_PROFILE:-}"
    MANIFEST_LINK_STRATEGY="${LINK_STRATEGY:-}"
  fi
}

resolve_install_contract() {
  read_manifest_contract

  PUBLIC_DOMAIN="${REQUESTED_PUBLIC_DOMAIN:-${MANIFEST_PUBLIC_DOMAIN:-}}"
  PUBLIC_PORT="${REQUESTED_PUBLIC_PORT:-${MANIFEST_PUBLIC_PORT:-443}}"
  INTERNAL_PORT="${REQUESTED_INTERNAL_PORT:-${MANIFEST_INTERNAL_PORT:-8888}}"
  WORKERS="${REQUESTED_WORKERS:-${MANIFEST_WORKERS:-1}}"
  ENGINE="${REQUESTED_ENGINE:-${MANIFEST_ENGINE:-official}}"
  PRIMARY_PROFILE="${REQUESTED_PRIMARY_PROFILE:-${MANIFEST_PRIMARY_PROFILE:-dd}}"
  LINK_STRATEGY="${REQUESTED_LINK_STRATEGY:-${MANIFEST_LINK_STRATEGY:-bundle}}"

  PUBLIC_DOMAIN="${PUBLIC_DOMAIN,,}"
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

  mkdir -p \
    "${MANIFEST_DIR}" \
    "${SECRETS_DIR}" \
    "${LINKS_DIR}" \
    "${RUNTIME_DIR}" \
    "${STATE_DIR}" \
    "${LIBEXEC_DIR}"

  chown root:"${RUN_GROUP}" "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}"
  chmod 750 "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}"

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

  if (( PUBLIC_PORT <= 1024 )); then
    info "Порт ${PUBLIC_PORT} привилегированный: capability будет выдан через systemd unit"
  fi

  setcap -r "${BIN_PATH}" 2>/dev/null || true
}

write_default_link_definitions() {
  if [[ -f "${LINK_DEFINITIONS_PATH}" ]]; then
    return 0
  fi

  log "Создаю модель ссылок по умолчанию..."

  case "${PRIMARY_PROFILE}" in
    dd)
      printf 'primary-dd\tdd\nreserve-dd\tdd\nfallback-classic\tclassic\n' > "${LINK_DEFINITIONS_PATH}"
      ;;
    classic)
      printf 'primary-classic\tclassic\nreserve-classic\tclassic\nfallback-dd\tdd\n' > "${LINK_DEFINITIONS_PATH}"
      ;;
  esac
}

secret_file_for_name() {
  local name="$1"
  printf '%s/%s.secret\n' "${SECRETS_DIR}" "${name}"
}

normalize_secret() {
  tr -d '\n\r' < "$1"
}

generate_secret_for_profile() {
  local profile="$1"
  local raw

  raw="$(head -c 16 /dev/urandom | xxd -ps -c 32)"

  case "${profile}" in
    classic)
      printf '%s\n' "${raw}"
      ;;
    dd)
      printf 'dd%s\n' "${raw}"
      ;;
    *)
      die "Неподдерживаемый профиль секрета: ${profile}"
      ;;
  esac
}

migrate_legacy_layout_if_present() {
  local first_name
  local first_secret_file

  [[ -f "${MANIFEST_PATH}" ]] && return 0
  [[ -f "${LINK_DEFINITIONS_PATH}" ]] || return 0

  first_name="$(awk 'NR==1 {print $1}' "${LINK_DEFINITIONS_PATH}")"
  [[ -n "${first_name}" ]] || return 0

  first_secret_file="$(secret_file_for_name "${first_name}")"

  if [[ -f "${LEGACY_SECRET_PATH}" && ! -f "${first_secret_file}" ]]; then
    warn "Импортирую legacy secret в ${first_name}..."
    install -o root -g "${RUN_GROUP}" -m 0640 "${LEGACY_SECRET_PATH}" "${first_secret_file}"
  fi

  if [[ -f "${LEGACY_PROXY_SECRET_PATH}" && ! -f "${PROXY_SECRET_PATH}" ]]; then
    warn "Импортирую legacy proxy-secret..."
    install -o root -g "${RUN_GROUP}" -m 0640 "${LEGACY_PROXY_SECRET_PATH}" "${PROXY_SECRET_PATH}"
  fi

  if [[ -f "${LEGACY_PROXY_MULTI_CONF_PATH}" && ! -f "${PROXY_MULTI_CONF_PATH}" ]]; then
    warn "Импортирую legacy proxy-multi.conf..."
    install -o root -g "${RUN_GROUP}" -m 0640 "${LEGACY_PROXY_MULTI_CONF_PATH}" "${PROXY_MULTI_CONF_PATH}"
  fi
}

ensure_link_secrets() {
  local name
  local profile
  local secret_file

  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue
    secret_file="$(secret_file_for_name "${name}")"

    if [[ ! -f "${secret_file}" ]]; then
      log "Генерирую secret slot ${name} (${profile})..."
      generate_secret_for_profile "${profile}" > "${secret_file}"
    fi
  done < "${LINK_DEFINITIONS_PATH}"
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

  install -o root -g "${RUN_GROUP}" -m 0640 "${tmp_secret}" "${PROXY_SECRET_PATH}"
  install -o root -g "${RUN_GROUP}" -m 0640 "${tmp_conf}" "${PROXY_MULTI_CONF_PATH}"

  rm -f "${tmp_secret}" "${tmp_conf}"
  trap - RETURN
}

persist_manifest() {
  log "Сохраняю deployment manifest..."

  {
    quote_kv APP_NAME "${APP_NAME}"
    quote_kv RUN_USER "${RUN_USER}"
    quote_kv RUN_GROUP "${RUN_GROUP}"
    quote_kv REPO_URL "${REPO_URL}"
    quote_kv REPO_BRANCH "${REPO_BRANCH}"
    quote_kv BIN_PATH "${BIN_PATH}"
    quote_kv SRC_DIR "${SRC_DIR}"
    quote_kv CONFIG_ROOT "${CONFIG_ROOT}"
    quote_kv MANIFEST_DIR "${MANIFEST_DIR}"
    quote_kv SECRETS_DIR "${SECRETS_DIR}"
    quote_kv LINKS_DIR "${LINKS_DIR}"
    quote_kv RUNTIME_DIR "${RUNTIME_DIR}"
    quote_kv STATE_DIR "${STATE_DIR}"
    quote_kv MANIFEST_PATH "${MANIFEST_PATH}"
    quote_kv PROXY_SECRET_PATH "${PROXY_SECRET_PATH}"
    quote_kv PROXY_MULTI_CONF_PATH "${PROXY_MULTI_CONF_PATH}"
    quote_kv LINK_DEFINITIONS_PATH "${LINK_DEFINITIONS_PATH}"
    quote_kv LINK_BUNDLE_PATH "${LINK_BUNDLE_PATH}"
    quote_kv SERVICE_NAME "${SERVICE_NAME}"
    quote_kv PUBLIC_DOMAIN "${PUBLIC_DOMAIN}"
    quote_kv PUBLIC_PORT "${PUBLIC_PORT}"
    quote_kv INTERNAL_PORT "${INTERNAL_PORT}"
    quote_kv WORKERS "${WORKERS}"
    quote_kv ENGINE "${ENGINE}"
    quote_kv PRIMARY_PROFILE "${PRIMARY_PROFILE}"
    quote_kv LINK_STRATEGY "${LINK_STRATEGY}"
  } > "${MANIFEST_PATH}"
}

build_link_bundle() {
  local name
  local profile
  local secret_file
  local secret
  local link

  : > "${LINK_BUNDLE_PATH}"

  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue
    secret_file="$(secret_file_for_name "${name}")"
    [[ -f "${secret_file}" ]] || die "Не найден secret slot: ${secret_file}"
    secret="$(normalize_secret "${secret_file}")"
    [[ -n "${secret}" ]] || die "Пустой secret slot: ${secret_file}"
    link="tg://proxy?server=${PUBLIC_DOMAIN}&port=${PUBLIC_PORT}&secret=${secret}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${name}" "${profile}" "${PUBLIC_DOMAIN}" "${PUBLIC_PORT}" "${secret}" "${link}" >> "${LINK_BUNDLE_PATH}"
  done < "${LINK_DEFINITIONS_PATH}"
}

apply_permissions() {
  log "Применяю права..."

  chown root:"${RUN_GROUP}" "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}"
  chmod 750 "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}"

  [[ -f "${MANIFEST_PATH}" ]] && chown root:"${RUN_GROUP}" "${MANIFEST_PATH}" && chmod 0640 "${MANIFEST_PATH}"
  [[ -f "${PROXY_SECRET_PATH}" ]] && chown root:"${RUN_GROUP}" "${PROXY_SECRET_PATH}" && chmod 0640 "${PROXY_SECRET_PATH}"
  [[ -f "${PROXY_MULTI_CONF_PATH}" ]] && chown root:"${RUN_GROUP}" "${PROXY_MULTI_CONF_PATH}" && chmod 0640 "${PROXY_MULTI_CONF_PATH}"
  [[ -f "${LINK_DEFINITIONS_PATH}" ]] && chown root:"${RUN_GROUP}" "${LINK_DEFINITIONS_PATH}" && chmod 0640 "${LINK_DEFINITIONS_PATH}"
  [[ -f "${LINK_BUNDLE_PATH}" ]] && chown root:"${RUN_GROUP}" "${LINK_BUNDLE_PATH}" && chmod 0640 "${LINK_BUNDLE_PATH}"

  if compgen -G "${SECRETS_DIR}/*.secret" >/dev/null; then
    chown root:"${RUN_GROUP}" "${SECRETS_DIR}"/*.secret
    chmod 0640 "${SECRETS_DIR}"/*.secret
  fi

  [[ -f "${RUNNER_PATH}" ]] && chown root:"${RUN_GROUP}" "${RUNNER_PATH}" && chmod 0750 "${RUNNER_PATH}"
  [[ -f "${REFRESH_HELPER_PATH}" ]] && chown root:"${RUN_GROUP}" "${REFRESH_HELPER_PATH}" && chmod 0750 "${REFRESH_HELPER_PATH}"

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

render_runner_script() {
  cat > "${RUNNER_PATH}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1090
source "${MANIFEST_PATH}"

secret_args=()
while IFS=\$'\\t' read -r name profile; do
  [[ -n "\${name}" ]] || continue
  secret_file="\${SECRETS_DIR}/\${name}.secret"
  [[ -f "\${secret_file}" ]] || { echo "Secret slot not found: \${secret_file}" >&2; exit 1; }
  secret="\$(tr -d '\\n\\r' < "\${secret_file}")"
  [[ -n "\${secret}" ]] || { echo "Secret slot is empty: \${secret_file}" >&2; exit 1; }
  secret_args+=("-S" "\${secret}")
done < "\${LINK_DEFINITIONS_PATH}"

"${BIN_PATH}" -u "${RUN_USER}" -p "\${INTERNAL_PORT}" -H "\${PUBLIC_PORT}" "\${secret_args[@]}" --aes-pwd "\${PROXY_SECRET_PATH}" "\${PROXY_MULTI_CONF_PATH}" -M "\${WORKERS}" &
child=\$!

forward_term() {
  kill -TERM "\${child}" 2>/dev/null || true
}

trap forward_term TERM INT
wait "\${child}"
EOF
}

render_refresh_helper() {
  cat > "${REFRESH_HELPER_PATH}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1090
source "${MANIFEST_PATH}"

tmp_secret="\$(mktemp)"
tmp_conf="\$(mktemp)"
trap 'rm -f "\${tmp_secret}" "\${tmp_conf}"' EXIT

curl -fsSL https://core.telegram.org/getProxySecret -o "\${tmp_secret}"
curl -fsSL https://core.telegram.org/getProxyConfig -o "\${tmp_conf}"

install -o root -g "${RUN_GROUP}" -m 0640 "\${tmp_secret}" "\${PROXY_SECRET_PATH}"
install -o root -g "${RUN_GROUP}" -m 0640 "\${tmp_conf}" "\${PROXY_MULTI_CONF_PATH}"

systemctl restart "${SERVICE_NAME}"
EOF
}

render_service_file() {
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
ExecStartPre=/usr/bin/test -x ${RUNNER_PATH}
ExecStartPre=/usr/bin/test -r ${MANIFEST_PATH}
ExecStartPre=/usr/bin/test -r ${PROXY_SECRET_PATH}
ExecStartPre=/usr/bin/test -r ${PROXY_MULTI_CONF_PATH}
ExecStartPre=/usr/bin/test -r ${LINK_DEFINITIONS_PATH}
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
EOF
}

render_refresh_units() {
  cat > "${REFRESH_SERVICE_PATH}" <<EOF
[Unit]
Description=Refresh Telegram MTProxy upstream configuration
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${REFRESH_HELPER_PATH}
EOF

  cat > "${REFRESH_TIMER_PATH}" <<EOF
[Unit]
Description=Daily refresh for Telegram MTProxy upstream configuration

[Timer]
OnCalendar=daily
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

reload_and_enable_units() {
  log "Перезагружаю systemd..."
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" >/dev/null
  systemctl enable "${REFRESH_TIMER_NAME}" >/dev/null
}

start_service() {
  log "Запускаю ${SERVICE_NAME}..."
  systemctl restart "${SERVICE_NAME}"
  systemctl start "${REFRESH_TIMER_NAME}"
}

configure_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    info "Открываю порт ${PUBLIC_PORT}/tcp в ufw..."
    ufw allow "${PUBLIC_PORT}/tcp" >/dev/null 2>&1 || true
  fi
}

redact_secret() {
  local value="$1"
  local len=${#value}

  if (( len <= 8 )); then
    printf '****\n'
    return 0
  fi

  printf '%s…%s\n' "${value:0:4}" "${value: -4}"
}

print_links_table() {
  local reveal="$1"
  local name
  local profile
  local domain
  local port
  local secret
  local link

  while IFS=$'\t' read -r name profile domain port secret link; do
    [[ -n "${name}" ]] || continue

    if [[ "${reveal}" == "yes" ]]; then
      printf '%-20s %-10s %s\n' "${name}" "${profile}" "${link}"
    else
      printf '%-20s %-10s %-24s %s\n' "${name}" "${profile}" "$(redact_secret "${secret}")" "${domain}:${port}"
    fi
  done < "${LINK_BUNDLE_PATH}"
}

show_post_install_summary() {
  echo
  echo "========================================"
  echo "MTProxy установлен"
  echo "Domain: ${PUBLIC_DOMAIN}"
  echo "Port:   ${PUBLIC_PORT}"
  echo "Engine: ${ENGINE}"
  echo "Links:  $(awk 'END {print NR+0}' "${LINK_BUNDLE_PATH}")"
  echo
  echo "Секреты и tg:// ссылки по умолчанию не печатаются."
  echo "Чтобы намеренно открыть bundle, выполни:"
  echo "  sudo bash $0 share-links"
  echo
  echo "Проверка:"
  echo "  sudo bash $0 status"
  echo "  sudo bash $0 health"
  echo "========================================"
  echo
}

status() {
  require_installed

  echo "Service: $(systemctl is-active "${SERVICE_NAME}" 2>/dev/null || true)"
  echo "Domain:  ${PUBLIC_DOMAIN}"
  echo "Port:    ${PUBLIC_PORT}"
  echo "Engine:  ${ENGINE}"
  echo "Timer:   $(systemctl is-active "${REFRESH_TIMER_NAME}" 2>/dev/null || true)"
  echo
  echo "Links (redacted):"
  print_links_table "no"
  echo
  echo "Recent logs:"
  journalctl -u "${SERVICE_NAME}" -n 20 --no-pager || true
}

health() {
  require_installed

  local failed=0

  echo "Health checks:"
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo "  [ok] service active"
  else
    echo "  [fail] service inactive"
    failed=1
  fi

  if systemctl is-enabled --quiet "${REFRESH_TIMER_NAME}" 2>/dev/null; then
    echo "  [ok] refresh timer enabled"
  else
    echo "  [fail] refresh timer disabled"
    failed=1
  fi

  if ss -ltn "( sport = :${PUBLIC_PORT} )" | tail -n +2 | grep -q .; then
    echo "  [ok] listener present on ${PUBLIC_PORT}/tcp"
  else
    echo "  [fail] listener missing on ${PUBLIC_PORT}/tcp"
    failed=1
  fi

  if [[ -f "${MANIFEST_PATH}" && -f "${LINK_BUNDLE_PATH}" && -f "${PROXY_SECRET_PATH}" && -f "${PROXY_MULTI_CONF_PATH}" ]]; then
    echo "  [ok] manifest and runtime artifacts present"
  else
    echo "  [fail] manifest/runtime artifacts missing"
    failed=1
  fi

  if [[ -n "${PUBLIC_DOMAIN}" ]]; then
    echo "  [ok] public domain recorded (${PUBLIC_DOMAIN})"
  else
    echo "  [fail] public domain missing from manifest"
    failed=1
  fi

  if (( failed == 0 )); then
    echo
    log "Health check passed"
  else
    echo
    die "Health check failed"
  fi
}

share_links() {
  require_root
  require_installed

  echo "Links:"
  print_links_table "yes"
}

list_links() {
  require_installed

  echo "Links (redacted):"
  print_links_table "no"
}

refresh_telegram_config() {
  require_root
  require_installed

  download_proxy_files
  apply_permissions
  ensure_pid_workaround
  systemctl restart "${SERVICE_NAME}"

  log "Конфиг Telegram обновлен"
}

rotate_link() {
  local target_name="${1:-}"
  local name
  local profile
  local secret_file
  local found=0

  require_root
  require_installed

  [[ -n "${target_name}" ]] || die "Укажи имя ссылки: rotate-link <name>"

  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue

    if [[ "${name}" == "${target_name}" ]]; then
      secret_file="$(secret_file_for_name "${name}")"
      log "Ротирую link ${name} (${profile})..."
      generate_secret_for_profile "${profile}" > "${secret_file}"
      found=1
      break
    fi
  done < "${LINK_DEFINITIONS_PATH}"

  (( found == 1 )) || die "Link slot не найден: ${target_name}"

  build_link_bundle
  apply_permissions
  ensure_pid_workaround
  systemctl restart "${SERVICE_NAME}"

  log "Link ${target_name} обновлен"
}

rotate_all_links() {
  local name
  local profile
  local secret_file

  require_root
  require_installed

  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue
    secret_file="$(secret_file_for_name "${name}")"
    log "Ротирую link ${name} (${profile})..."
    generate_secret_for_profile "${profile}" > "${secret_file}"
  done < "${LINK_DEFINITIONS_PATH}"

  build_link_bundle
  apply_permissions
  ensure_pid_workaround
  systemctl restart "${SERVICE_NAME}"

  log "Все link slots обновлены"
}

rotate_secret_legacy_alias() {
  require_installed
  local first_name
  first_name="$(awk 'NR==1 {print $1}' "${LINK_DEFINITIONS_PATH}")"
  [[ -n "${first_name}" ]] || die "Не найден primary link slot"
  rotate_link "${first_name}"
}

restart_service_command() {
  require_root
  require_installed
  ensure_pid_workaround
  systemctl restart "${SERVICE_NAME}"
  status
}

install_all() {
  require_root
  resolve_install_contract
  validate_install_contract

  ensure_packages
  ensure_user_and_dirs
  clone_or_update_repo
  build_mtproxy
  write_default_link_definitions
  migrate_legacy_layout_if_present
  ensure_link_secrets

  if [[ ! -f "${PROXY_SECRET_PATH}" || ! -f "${PROXY_MULTI_CONF_PATH}" ]]; then
    download_proxy_files
  else
    info "Proxy upstream artifacts уже существуют, обновление не требуется"
  fi

  persist_manifest
  build_link_bundle
  render_runner_script
  render_refresh_helper
  render_service_file
  render_refresh_units
  apply_permissions
  ensure_pid_workaround
  reload_and_enable_units
  configure_firewall
  start_service
  show_post_install_summary
}

uninstall_all() {
  require_root

  warn "Останавливаю и удаляю сервисы..."
  systemctl disable --now "${REFRESH_TIMER_NAME}" 2>/dev/null || true
  systemctl disable --now "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "${SERVICE_PATH}" "${REFRESH_SERVICE_PATH}" "${REFRESH_TIMER_PATH}"
  systemctl daemon-reload

  warn "Удаляю бинарник, исходники и helper scripts..."
  rm -f "${BIN_PATH}" "${RUNNER_PATH}" "${REFRESH_HELPER_PATH}"
  rm -rf "${SRC_DIR}"

  warn "Удаляю sysctl workaround..."
  rm -f "${SYSCTL_FILE}"
  sysctl --system >/dev/null 2>&1 || true

  warn "Удаляю конфиги и state..."
  rm -rf "${CONFIG_ROOT}" "${STATE_DIR}"

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
  sudo PUBLIC_DOMAIN=proxy.example.com bash $0 install
  sudo bash $0 status
  sudo bash $0 health
  sudo bash $0 list-links
  sudo bash $0 share-links
  sudo bash $0 rotate-link <name>
  sudo bash $0 rotate-all-links
  sudo bash $0 refresh-telegram-config
  sudo bash $0 restart
  sudo bash $0 uninstall

Compatibility aliases:
  sudo bash $0 update-config
  sudo bash $0 rotate-secret

Environment variables:
  PUBLIC_DOMAIN=<required on first install>
  PUBLIC_PORT=443
  INTERNAL_PORT=8888
  WORKERS=1
  ENGINE=official
  PRIMARY_PROFILE=dd
  LINK_STRATEGY=bundle
  REPO_URL=https://github.com/TelegramMessenger/MTProxy.git
  REPO_BRANCH=master

Examples:
  sudo PUBLIC_DOMAIN=proxy.example.com bash $0 install
  sudo PUBLIC_DOMAIN=proxy.example.com PUBLIC_PORT=443 WORKERS=2 bash $0 install
  sudo bash $0 list-links
EOF
}

main() {
  local cmd="${1:-}"
  local arg="${2:-}"

  case "${cmd}" in
    install)
      install_all
      ;;
    update-config|refresh-telegram-config)
      refresh_telegram_config
      ;;
    rotate-secret)
      rotate_secret_legacy_alias
      ;;
    rotate-link)
      rotate_link "${arg}"
      ;;
    rotate-all-links)
      rotate_all_links
      ;;
    restart)
      restart_service_command
      ;;
    status)
      status
      ;;
    health)
      health
      ;;
    share-links)
      share_links
      ;;
    list-links)
      list_links
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
