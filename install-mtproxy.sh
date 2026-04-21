#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="mtproxy"
RUN_USER="mtproxy"
RUN_GROUP="mtproxy"

OFFICIAL_REPO_URL_DEFAULT="https://github.com/TelegramMessenger/MTProxy.git"
OFFICIAL_REPO_BRANCH_DEFAULT="master"
STEALTH_REPO_URL_DEFAULT="https://github.com/telemt/telemt.git"
STEALTH_REPO_BRANCH_DEFAULT="main"

REQUESTED_OFFICIAL_REPO_URL="${OFFICIAL_REPO_URL:-${REPO_URL:-}}"
REQUESTED_OFFICIAL_REPO_BRANCH="${OFFICIAL_REPO_BRANCH:-${REPO_BRANCH:-}}"
REQUESTED_STEALTH_REPO_URL="${STEALTH_REPO_URL:-}"
REQUESTED_STEALTH_REPO_BRANCH="${STEALTH_REPO_BRANCH:-}"

OFFICIAL_REPO_URL="${OFFICIAL_REPO_URL_DEFAULT}"
OFFICIAL_REPO_BRANCH="${OFFICIAL_REPO_BRANCH_DEFAULT}"
STEALTH_REPO_URL="${STEALTH_REPO_URL_DEFAULT}"
STEALTH_REPO_BRANCH="${STEALTH_REPO_BRANCH_DEFAULT}"

OFFICIAL_SRC_DIR="/opt/mtproxy-src"
STEALTH_SRC_DIR="/opt/telemt-src"
OFFICIAL_BIN_PATH="/usr/local/bin/mtproto-proxy"
STEALTH_BIN_PATH="/usr/local/bin/telemt"

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
STEALTH_CONFIG_PATH="${RUNTIME_DIR}/telemt.toml"
LINK_DEFINITIONS_PATH="${LINKS_DIR}/definitions.tsv"
LINK_BUNDLE_PATH="${LINKS_DIR}/bundle.tsv"
RUNNER_PATH="${LIBEXEC_DIR}/mtproxy-run"
REFRESH_HELPER_PATH="${LIBEXEC_DIR}/mtproxy-refresh"
STEALTH_TLS_FRONT_DIR="${STATE_DIR}/tlsfront"

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
REQUESTED_DEVICE_NAMES="${DEVICE_NAMES:-}"
REQUESTED_TLS_DOMAIN="${TLS_DOMAIN:-}"
REQUESTED_DECOY_MODE="${DECOY_MODE:-}"
REQUESTED_DECOY_TARGET_HOST="${DECOY_TARGET_HOST:-}"
REQUESTED_DECOY_TARGET_PORT="${DECOY_TARGET_PORT:-}"

PUBLIC_DOMAIN=""
PUBLIC_PORT="443"
INTERNAL_PORT="8888"
WORKERS="1"
ENGINE="official"
PRIMARY_PROFILE=""
LINK_STRATEGY="bundle"
DEVICE_NAMES=""
TLS_DOMAIN=""
DECOY_MODE="disabled"
DECOY_TARGET_HOST=""
DECOY_TARGET_PORT="443"

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
  [[ -n "${value}" ]] || die "Требуется непустой домен"
  [[ "${value}" =~ ^[A-Za-z0-9.-]+$ ]] || die "Некорректный домен: ${value}"
  [[ "${value}" != .* && "${value}" != *..* && "${value}" != *-.* && "${value}" != *.-* ]] || die "Некорректный домен: ${value}"
}

validate_host_or_ip() {
  local value="$1"
  [[ -n "${value}" ]] || die "Требуется host/ip"
  [[ "${value}" =~ ^[A-Za-z0-9._:-]+$ ]] || die "Некорректный host/ip: ${value}"
}

normalize_device_names_csv() {
  local raw="$1"
  local normalized=""
  local seen=" "
  local item token

  raw="${raw//;/,}"
  raw="${raw// /,}"
  raw="${raw//$'\n'/,}"
  raw="${raw//$'\t'/,}"

  IFS=',' read -r -a items <<< "${raw}"
  for item in "${items[@]}"; do
    token="${item,,}"
    token="${token//_/-}"
    [[ -n "${token}" ]] || continue
    [[ "${token}" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] || die "Некорректное имя устройства: ${token}"
    [[ "${token}" != *- ]] || die "Имя устройства не должно заканчиваться '-': ${token}"

    if [[ "${seen}" != *" ${token} "* ]]; then
      normalized="${normalized:+${normalized},}${token}"
      seen+="${token} "
    fi
  done

  printf '%s\n' "${normalized}"
}

default_primary_profile_for_engine() {
  local engine="$1"
  case "${engine}" in
    official)
      printf 'dd\n'
      ;;
    stealth)
      printf 'ee\n'
      ;;
    *)
      die "Неизвестный engine для выбора профиля по умолчанию: ${engine}"
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
  MANIFEST_DEVICE_NAMES=""
  MANIFEST_TLS_DOMAIN=""
  MANIFEST_DECOY_MODE=""
  MANIFEST_DECOY_TARGET_HOST=""
  MANIFEST_DECOY_TARGET_PORT=""
  MANIFEST_OFFICIAL_REPO_URL=""
  MANIFEST_OFFICIAL_REPO_BRANCH=""
  MANIFEST_STEALTH_REPO_URL=""
  MANIFEST_STEALTH_REPO_BRANCH=""

  if [[ -f "${MANIFEST_PATH}" ]]; then
    local PUBLIC_DOMAIN=""
    local PUBLIC_PORT=""
    local INTERNAL_PORT=""
    local WORKERS=""
    local ENGINE=""
    local PRIMARY_PROFILE=""
    local LINK_STRATEGY=""
    local DEVICE_NAMES=""
    local TLS_DOMAIN=""
    local DECOY_MODE=""
    local DECOY_TARGET_HOST=""
    local DECOY_TARGET_PORT=""
    local OFFICIAL_REPO_URL=""
    local OFFICIAL_REPO_BRANCH=""
    local STEALTH_REPO_URL=""
    local STEALTH_REPO_BRANCH=""

    # shellcheck disable=SC1090
    source "${MANIFEST_PATH}"

    MANIFEST_PUBLIC_DOMAIN="${PUBLIC_DOMAIN:-}"
    MANIFEST_PUBLIC_PORT="${PUBLIC_PORT:-}"
    MANIFEST_INTERNAL_PORT="${INTERNAL_PORT:-}"
    MANIFEST_WORKERS="${WORKERS:-}"
    MANIFEST_ENGINE="${ENGINE:-}"
    MANIFEST_PRIMARY_PROFILE="${PRIMARY_PROFILE:-}"
    MANIFEST_LINK_STRATEGY="${LINK_STRATEGY:-}"
    MANIFEST_DEVICE_NAMES="${DEVICE_NAMES:-}"
    MANIFEST_TLS_DOMAIN="${TLS_DOMAIN:-}"
    MANIFEST_DECOY_MODE="${DECOY_MODE:-}"
    MANIFEST_DECOY_TARGET_HOST="${DECOY_TARGET_HOST:-}"
    MANIFEST_DECOY_TARGET_PORT="${DECOY_TARGET_PORT:-}"
    MANIFEST_OFFICIAL_REPO_URL="${OFFICIAL_REPO_URL:-}"
    MANIFEST_OFFICIAL_REPO_BRANCH="${OFFICIAL_REPO_BRANCH:-}"
    MANIFEST_STEALTH_REPO_URL="${STEALTH_REPO_URL:-}"
    MANIFEST_STEALTH_REPO_BRANCH="${STEALTH_REPO_BRANCH:-}"
  fi
}

resolve_install_contract() {
  local default_profile

  read_manifest_contract

  ENGINE="${REQUESTED_ENGINE:-${MANIFEST_ENGINE:-official}}"
  default_profile="$(default_primary_profile_for_engine "${ENGINE}")"

  PUBLIC_DOMAIN="${REQUESTED_PUBLIC_DOMAIN:-${MANIFEST_PUBLIC_DOMAIN:-}}"
  PUBLIC_PORT="${REQUESTED_PUBLIC_PORT:-${MANIFEST_PUBLIC_PORT:-443}}"
  INTERNAL_PORT="${REQUESTED_INTERNAL_PORT:-${MANIFEST_INTERNAL_PORT:-8888}}"
  WORKERS="${REQUESTED_WORKERS:-${MANIFEST_WORKERS:-1}}"
  PRIMARY_PROFILE="${REQUESTED_PRIMARY_PROFILE:-${MANIFEST_PRIMARY_PROFILE:-${default_profile}}}"
  LINK_STRATEGY="${REQUESTED_LINK_STRATEGY:-${MANIFEST_LINK_STRATEGY:-bundle}}"
  DEVICE_NAMES="${REQUESTED_DEVICE_NAMES:-${MANIFEST_DEVICE_NAMES:-}}"
  TLS_DOMAIN="${REQUESTED_TLS_DOMAIN:-${MANIFEST_TLS_DOMAIN:-${PUBLIC_DOMAIN}}}"
  DECOY_MODE="${REQUESTED_DECOY_MODE:-${MANIFEST_DECOY_MODE:-disabled}}"
  DECOY_TARGET_HOST="${REQUESTED_DECOY_TARGET_HOST:-${MANIFEST_DECOY_TARGET_HOST:-}}"
  DECOY_TARGET_PORT="${REQUESTED_DECOY_TARGET_PORT:-${MANIFEST_DECOY_TARGET_PORT:-443}}"

  OFFICIAL_REPO_URL="${REQUESTED_OFFICIAL_REPO_URL:-${MANIFEST_OFFICIAL_REPO_URL:-${OFFICIAL_REPO_URL_DEFAULT}}}"
  OFFICIAL_REPO_BRANCH="${REQUESTED_OFFICIAL_REPO_BRANCH:-${MANIFEST_OFFICIAL_REPO_BRANCH:-${OFFICIAL_REPO_BRANCH_DEFAULT}}}"
  STEALTH_REPO_URL="${REQUESTED_STEALTH_REPO_URL:-${MANIFEST_STEALTH_REPO_URL:-${STEALTH_REPO_URL_DEFAULT}}}"
  STEALTH_REPO_BRANCH="${REQUESTED_STEALTH_REPO_BRANCH:-${MANIFEST_STEALTH_REPO_BRANCH:-${STEALTH_REPO_BRANCH_DEFAULT}}}"

  DEVICE_NAMES="$(normalize_device_names_csv "${DEVICE_NAMES}")"
  PUBLIC_DOMAIN="${PUBLIC_DOMAIN,,}"
  TLS_DOMAIN="${TLS_DOMAIN,,}"
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
  validate_domain "${TLS_DOMAIN}"
  validate_runtime_settings

  case "${ENGINE}" in
    official)
      case "${PRIMARY_PROFILE}" in
        dd|classic)
          ;;
        *)
          die "Для ENGINE=official поддерживаются только PRIMARY_PROFILE=dd|classic"
          ;;
      esac

      case "${DECOY_MODE}" in
        disabled)
          ;;
        *)
          die "Для ENGINE=official decoy не поддержан. Используй DECOY_MODE=disabled"
          ;;
      esac
      ;;
    stealth)
      case "${PRIMARY_PROFILE}" in
        ee|dd|classic)
          ;;
        *)
          die "Для ENGINE=stealth поддерживаются только PRIMARY_PROFILE=ee|dd|classic"
          ;;
      esac

      case "${DECOY_MODE}" in
        disabled)
          ;;
        upstream-forward)
          validate_host_or_ip "${DECOY_TARGET_HOST}"
          validate_port "${DECOY_TARGET_PORT}"
          ;;
        local-https)
          die "DECOY_MODE=local-https еще не реализован в этой итерации"
          ;;
        *)
          die "Поддерживаются только DECOY_MODE=disabled|upstream-forward|local-https"
          ;;
      esac
      ;;
    *)
      die "Поддерживаются только ENGINE=official|stealth"
      ;;
  esac

  case "${LINK_STRATEGY}" in
    bundle)
      ;;
    per-device)
      [[ -n "${DEVICE_NAMES}" ]] || die "Для LINK_STRATEGY=per-device требуется DEVICE_NAMES=phone,desktop,tablet"
      ;;
    *)
      die "Поддерживаются только LINK_STRATEGY=bundle|per-device"
      ;;
  esac
}

engine_source_dir() {
  case "${ENGINE}" in
    official) printf '%s\n' "${OFFICIAL_SRC_DIR}" ;;
    stealth)  printf '%s\n' "${STEALTH_SRC_DIR}" ;;
    *) die "Неизвестный engine: ${ENGINE}" ;;
  esac
}

engine_binary_path() {
  case "${ENGINE}" in
    official) printf '%s\n' "${OFFICIAL_BIN_PATH}" ;;
    stealth)  printf '%s\n' "${STEALTH_BIN_PATH}" ;;
    *) die "Неизвестный engine: ${ENGINE}" ;;
  esac
}

engine_repo_url() {
  case "${ENGINE}" in
    official) printf '%s\n' "${OFFICIAL_REPO_URL}" ;;
    stealth)  printf '%s\n' "${STEALTH_REPO_URL}" ;;
    *) die "Неизвестный engine: ${ENGINE}" ;;
  esac
}

engine_repo_branch() {
  case "${ENGINE}" in
    official) printf '%s\n' "${OFFICIAL_REPO_BRANCH}" ;;
    stealth)  printf '%s\n' "${STEALTH_REPO_BRANCH}" ;;
    *) die "Неизвестный engine: ${ENGINE}" ;;
  esac
}

ensure_packages() {
  local -a packages

  log "Устанавливаю зависимости..."
  apt-get update -y

  packages=(
    git
    curl
    ca-certificates
    build-essential
    libssl-dev
    zlib1g-dev
    xxd
    ufw
    libcap2-bin
    pkg-config
  )

  if [[ "${ENGINE}" == "stealth" ]]; then
    packages+=(cargo rustc)
  fi

  DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
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
    "${LIBEXEC_DIR}" \
    "${STEALTH_TLS_FRONT_DIR}"

  chown root:"${RUN_GROUP}" "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}"
  chmod 750 "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}"

  chown -R "${RUN_USER}:${RUN_GROUP}" "${STATE_DIR}"
  chmod 750 "${STATE_DIR}" "${STEALTH_TLS_FRONT_DIR}"
}

clone_or_update_engine_repo() {
  local src_dir repo_url repo_branch

  src_dir="$(engine_source_dir)"
  repo_url="$(engine_repo_url)"
  repo_branch="$(engine_repo_branch)"

  if [[ -d "${src_dir}/.git" ]]; then
    log "Обновляю исходники engine=${ENGINE}..."
    git -C "${src_dir}" fetch --all --tags
    git -C "${src_dir}" checkout "${repo_branch}"
    git -C "${src_dir}" reset --hard "origin/${repo_branch}"
    git -C "${src_dir}" clean -fdx
  else
    log "Клонирую репозиторий engine=${ENGINE}..."
    rm -rf "${src_dir}"
    git clone --branch "${repo_branch}" "${repo_url}" "${src_dir}"
  fi
}

patch_makefile_if_needed() {
  local makefile="${OFFICIAL_SRC_DIR}/Makefile"

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

build_engine_binary() {
  case "${ENGINE}" in
    official)
      log "Собираю official MTProxy..."
      cd "${OFFICIAL_SRC_DIR}"

      if ! make; then
        warn "Первая сборка official MTProxy не удалась, пробую с patch + clean..."
        patch_makefile_if_needed
        make clean || true
        make
      fi

      [[ -x "${OFFICIAL_SRC_DIR}/objs/bin/mtproto-proxy" ]] || die "Бинарник official MTProxy не собран"
      install -m 0755 "${OFFICIAL_SRC_DIR}/objs/bin/mtproto-proxy" "${OFFICIAL_BIN_PATH}"
      setcap -r "${OFFICIAL_BIN_PATH}" 2>/dev/null || true
      ;;
    stealth)
      log "Собираю telemt..."
      cd "${STEALTH_SRC_DIR}"
      cargo build --release
      [[ -x "${STEALTH_SRC_DIR}/target/release/telemt" ]] || die "Бинарник telemt не собран"
      install -m 0755 "${STEALTH_SRC_DIR}/target/release/telemt" "${STEALTH_BIN_PATH}"
      setcap -r "${STEALTH_BIN_PATH}" 2>/dev/null || true
      ;;
  esac

  if (( PUBLIC_PORT <= 1024 )); then
    info "Порт ${PUBLIC_PORT} привилегированный: capability будет выдан через systemd unit"
  fi
}

fallback_profile_for_primary() {
  case "${ENGINE}:${PRIMARY_PROFILE}" in
    official:dd) printf 'classic\n' ;;
    official:classic) printf 'dd\n' ;;
    stealth:ee) printf 'dd\n' ;;
    stealth:dd) printf 'classic\n' ;;
    stealth:classic) printf 'dd\n' ;;
    *) die "Неизвестная комбинация ENGINE/PRIMARY_PROFILE: ${ENGINE}/${PRIMARY_PROFILE}" ;;
  esac
}

write_managed_link_definitions() {
  local tmp_path
  local fallback_profile
  local device
  local created=0

  tmp_path="${LINK_DEFINITIONS_PATH}.tmp"
  : > "${tmp_path}"

  case "${LINK_STRATEGY}" in
    bundle)
      case "${ENGINE}:${PRIMARY_PROFILE}" in
        official:dd)
          printf 'primary-dd\tdd\nreserve-dd\tdd\nfallback-classic\tclassic\n' > "${tmp_path}"
          ;;
        official:classic)
          printf 'primary-classic\tclassic\nreserve-classic\tclassic\nfallback-dd\tdd\n' > "${tmp_path}"
          ;;
        stealth:ee)
          printf 'primary-ee\tee\nreserve-ee\tee\nfallback-dd\tdd\n' > "${tmp_path}"
          ;;
        stealth:dd)
          printf 'primary-dd\tdd\nreserve-dd\tdd\nfallback-classic\tclassic\n' > "${tmp_path}"
          ;;
        stealth:classic)
          printf 'primary-classic\tclassic\nreserve-classic\tclassic\nfallback-dd\tdd\n' > "${tmp_path}"
          ;;
        *)
          rm -f "${tmp_path}"
          die "Неизвестная комбинация ENGINE/PRIMARY_PROFILE: ${ENGINE}/${PRIMARY_PROFILE}"
          ;;
      esac
      ;;
    per-device)
      fallback_profile="$(fallback_profile_for_primary)"
      IFS=',' read -r -a devices <<< "${DEVICE_NAMES}"
      for device in "${devices[@]}"; do
        [[ -n "${device}" ]] || continue
        printf '%s-%s\t%s\n' "${device}" "${PRIMARY_PROFILE}" "${PRIMARY_PROFILE}" >> "${tmp_path}"
        created=1
      done

      (( created == 1 )) || { rm -f "${tmp_path}"; die "Не удалось построить per-device definitions: пустой DEVICE_NAMES"; }
      printf 'shared-fallback-%s\t%s\n' "${fallback_profile}" "${fallback_profile}" >> "${tmp_path}"
      ;;
    *)
      rm -f "${tmp_path}"
      die "Неизвестная стратегия ссылок: ${LINK_STRATEGY}"
      ;;
  esac

  if [[ -f "${LINK_DEFINITIONS_PATH}" ]] && cmp -s "${tmp_path}" "${LINK_DEFINITIONS_PATH}"; then
    rm -f "${tmp_path}"
    info "Link definitions уже актуальны"
    return 0
  fi

  if [[ -f "${LINK_DEFINITIONS_PATH}" ]]; then
    log "Обновляю модель ссылок (${LINK_STRATEGY})..."
  else
    log "Создаю модель ссылок (${LINK_STRATEGY})..."
  fi

  mv "${tmp_path}" "${LINK_DEFINITIONS_PATH}"
}

secret_file_for_name() {
  local name="$1"
  printf '%s/%s.secret\n' "${SECRETS_DIR}" "${name}"
}

normalize_secret() {
  tr -d '\n\r' < "$1"
}

generate_raw_secret_hex() {
  head -c 16 /dev/urandom | xxd -ps -c 32 | tr 'A-F' 'a-f'
}

extract_raw_secret_hex() {
  local value="$1"

  if [[ "${value}" =~ ^(dd|ee)?([0-9A-Fa-f]{32})([0-9A-Fa-f]*)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[2],,}"
    return 0
  fi

  die "Не удалось выделить raw secret из значения"
}

format_slot_secret_for_engine_profile() {
  local engine="$1"
  local profile="$2"
  local raw="$3"

  case "${engine}:${profile}" in
    official:classic)
      printf '%s\n' "${raw}"
      ;;
    official:dd)
      printf 'dd%s\n' "${raw}"
      ;;
    stealth:classic|stealth:dd|stealth:ee)
      printf '%s\n' "${raw}"
      ;;
    *)
      die "Неподдерживаемое сочетание engine/profile для slot secret: ${engine}/${profile}"
      ;;
  esac
}

hex_encode_ascii() {
  local value="$1"
  printf '%s' "${value}" | xxd -p -c 9999 | tr -d '\n'
}

format_client_secret_for_bundle() {
  local engine="$1"
  local profile="$2"
  local raw="$3"
  local tls_domain="$4"
  local encoded_domain

  case "${engine}:${profile}" in
    official:classic)
      printf '%s\n' "${raw}"
      ;;
    official:dd)
      printf 'dd%s\n' "${raw}"
      ;;
    stealth:classic)
      printf '%s\n' "${raw}"
      ;;
    stealth:dd)
      printf 'dd%s\n' "${raw}"
      ;;
    stealth:ee)
      encoded_domain="$(hex_encode_ascii "${tls_domain}")"
      printf 'ee%s%s\n' "${raw}" "${encoded_domain}"
      ;;
    *)
      die "Неподдерживаемое сочетание engine/profile для client secret: ${engine}/${profile}"
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
  local raw_secret
  local current_value
  local desired_value

  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue
    secret_file="$(secret_file_for_name "${name}")"

    if [[ -f "${secret_file}" ]]; then
      current_value="$(normalize_secret "${secret_file}")"
      raw_secret="$(extract_raw_secret_hex "${current_value}")"
      desired_value="$(format_slot_secret_for_engine_profile "${ENGINE}" "${profile}" "${raw_secret}")"

      if [[ "${current_value}" != "${desired_value}" ]]; then
        info "Нормализую secret slot ${name} под engine=${ENGINE} profile=${profile}..."
        printf '%s\n' "${desired_value}" > "${secret_file}"
      fi
    else
      log "Генерирую secret slot ${name} (${profile})..."
      raw_secret="$(generate_raw_secret_hex)"
      desired_value="$(format_slot_secret_for_engine_profile "${ENGINE}" "${profile}" "${raw_secret}")"
      printf '%s\n' "${desired_value}" > "${secret_file}"
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
    quote_kv OFFICIAL_REPO_URL "${OFFICIAL_REPO_URL}"
    quote_kv OFFICIAL_REPO_BRANCH "${OFFICIAL_REPO_BRANCH}"
    quote_kv STEALTH_REPO_URL "${STEALTH_REPO_URL}"
    quote_kv STEALTH_REPO_BRANCH "${STEALTH_REPO_BRANCH}"
    quote_kv OFFICIAL_SRC_DIR "${OFFICIAL_SRC_DIR}"
    quote_kv STEALTH_SRC_DIR "${STEALTH_SRC_DIR}"
    quote_kv OFFICIAL_BIN_PATH "${OFFICIAL_BIN_PATH}"
    quote_kv STEALTH_BIN_PATH "${STEALTH_BIN_PATH}"
    quote_kv CONFIG_ROOT "${CONFIG_ROOT}"
    quote_kv MANIFEST_DIR "${MANIFEST_DIR}"
    quote_kv SECRETS_DIR "${SECRETS_DIR}"
    quote_kv LINKS_DIR "${LINKS_DIR}"
    quote_kv RUNTIME_DIR "${RUNTIME_DIR}"
    quote_kv STATE_DIR "${STATE_DIR}"
    quote_kv STEALTH_TLS_FRONT_DIR "${STEALTH_TLS_FRONT_DIR}"
    quote_kv MANIFEST_PATH "${MANIFEST_PATH}"
    quote_kv PROXY_SECRET_PATH "${PROXY_SECRET_PATH}"
    quote_kv PROXY_MULTI_CONF_PATH "${PROXY_MULTI_CONF_PATH}"
    quote_kv STEALTH_CONFIG_PATH "${STEALTH_CONFIG_PATH}"
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
    quote_kv DEVICE_NAMES "${DEVICE_NAMES}"
    quote_kv TLS_DOMAIN "${TLS_DOMAIN}"
    quote_kv DECOY_MODE "${DECOY_MODE}"
    quote_kv DECOY_TARGET_HOST "${DECOY_TARGET_HOST}"
    quote_kv DECOY_TARGET_PORT "${DECOY_TARGET_PORT}"
  } > "${MANIFEST_PATH}"
}

build_link_bundle() {
  local name
  local profile
  local secret_file
  local stored_secret
  local raw_secret
  local client_secret
  local link

  : > "${LINK_BUNDLE_PATH}"

  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue
    secret_file="$(secret_file_for_name "${name}")"
    [[ -f "${secret_file}" ]] || die "Не найден secret slot: ${secret_file}"
    stored_secret="$(normalize_secret "${secret_file}")"
    raw_secret="$(extract_raw_secret_hex "${stored_secret}")"
    client_secret="$(format_client_secret_for_bundle "${ENGINE}" "${profile}" "${raw_secret}" "${TLS_DOMAIN}")"
    link="tg://proxy?server=${PUBLIC_DOMAIN}&port=${PUBLIC_PORT}&secret=${client_secret}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${name}" "${profile}" "${PUBLIC_DOMAIN}" "${PUBLIC_PORT}" "${client_secret}" "${link}" >> "${LINK_BUNDLE_PATH}"
  done < "${LINK_DEFINITIONS_PATH}"
}

compute_link_mode_flags() {
  HAS_CLASSIC="false"
  HAS_SECURE="false"
  HAS_TLS="false"

  local name profile
  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue
    case "${profile}" in
      classic) HAS_CLASSIC="true" ;;
      dd) HAS_SECURE="true" ;;
      ee) HAS_TLS="true" ;;
      *) die "Неизвестный профиль в definitions: ${profile}" ;;
    esac
  done < "${LINK_DEFINITIONS_PATH}"
}

render_stealth_config() {
  local mask_enabled="false"
  local unknown_sni_action="reject_handshake"
  local name profile secret_file stored_secret raw_secret

  compute_link_mode_flags

  if [[ "${DECOY_MODE}" == "upstream-forward" ]]; then
    mask_enabled="true"
    unknown_sni_action="mask"
  fi

  cat > "${STEALTH_CONFIG_PATH}" <<EOF_CFG
### Generated by ${APP_NAME}
[general]
use_middle_proxy = true
log_level = "normal"

[general.modes]
classic = ${HAS_CLASSIC}
secure = ${HAS_SECURE}
tls = ${HAS_TLS}

[general.links]
show = "*"
public_host = "${PUBLIC_DOMAIN}"
public_port = ${PUBLIC_PORT}

[server]
port = ${PUBLIC_PORT}

[server.api]
enabled = false
listen = "127.0.0.1:9091"
whitelist = ["127.0.0.1/32", "::1/128"]
minimal_runtime_enabled = false
minimal_runtime_cache_ttl_ms = 1000

[[server.listeners]]
ip = "0.0.0.0"

[censorship]
tls_domain = "${TLS_DOMAIN}"
mask = ${mask_enabled}
tls_emulation = true
tls_front_dir = "${STEALTH_TLS_FRONT_DIR}"
unknown_sni_action = "${unknown_sni_action}"
EOF_CFG

  if [[ "${DECOY_MODE}" == "upstream-forward" ]]; then
    cat >> "${STEALTH_CONFIG_PATH}" <<EOF_CFG
mask_host = "${DECOY_TARGET_HOST}"
mask_port = ${DECOY_TARGET_PORT}
EOF_CFG
  fi

  printf '\n[access.users]\n' >> "${STEALTH_CONFIG_PATH}"
  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue
    secret_file="$(secret_file_for_name "${name}")"
    stored_secret="$(normalize_secret "${secret_file}")"
    raw_secret="$(extract_raw_secret_hex "${stored_secret}")"
    printf '%s = "%s"\n' "${name}" "${raw_secret}" >> "${STEALTH_CONFIG_PATH}"
  done < "${LINK_DEFINITIONS_PATH}"
}

render_engine_runtime_artifacts() {
  case "${ENGINE}" in
    official)
      rm -f "${STEALTH_CONFIG_PATH}"
      ;;
    stealth)
      render_stealth_config
      ;;
  esac
}

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

  if compgen -G "${SECRETS_DIR}/*.secret" >/dev/null; then
    chown root:"${RUN_GROUP}" "${SECRETS_DIR}"/*.secret
    chmod 0640 "${SECRETS_DIR}"/*.secret
  fi

  [[ -f "${RUNNER_PATH}" ]] && chown root:"${RUN_GROUP}" "${RUNNER_PATH}" && chmod 0750 "${RUNNER_PATH}"
  [[ -f "${REFRESH_HELPER_PATH}" ]] && chown root:"${RUN_GROUP}" "${REFRESH_HELPER_PATH}" && chmod 0750 "${REFRESH_HELPER_PATH}"

  chown -R "${RUN_USER}:${RUN_GROUP}" "${STATE_DIR}"
  chmod 750 "${STATE_DIR}" "${STEALTH_TLS_FRONT_DIR}"
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
}

start_service() {
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
  local name profile domain port secret link

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
  echo "Domain:     ${PUBLIC_DOMAIN}"
  echo "Port:       ${PUBLIC_PORT}"
  echo "Engine:     ${ENGINE}"
  echo "Strategy:   ${LINK_STRATEGY}"
  if [[ "${LINK_STRATEGY}" == "per-device" ]]; then
    echo "Devices:    ${DEVICE_NAMES}"
  fi
  echo "TLS domain: ${TLS_DOMAIN}"
  echo "Decoy:      ${DECOY_MODE}"
  echo "Links:      $(awk 'END {print NR+0}' "${LINK_BUNDLE_PATH}")"
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

  echo "Service:    $(systemctl is-active "${SERVICE_NAME}" 2>/dev/null || true)"
  echo "Domain:     ${PUBLIC_DOMAIN}"
  echo "Port:       ${PUBLIC_PORT}"
  echo "Engine:     ${ENGINE}"
  echo "Strategy:   ${LINK_STRATEGY}"
  if [[ "${LINK_STRATEGY}" == "per-device" ]]; then
    echo "Devices:    ${DEVICE_NAMES}"
  fi
  echo "TLS domain: ${TLS_DOMAIN}"
  echo "Decoy:      ${DECOY_MODE}"

  if [[ "${ENGINE}" == "official" ]]; then
    echo "Timer:      $(systemctl is-active "${REFRESH_TIMER_NAME}" 2>/dev/null || true)"
  else
    echo "Timer:      n/a"
  fi

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

  if ss -ltn "( sport = :${PUBLIC_PORT} )" | tail -n +2 | grep -q .; then
    echo "  [ok] listener present on ${PUBLIC_PORT}/tcp"
  else
    echo "  [fail] listener missing on ${PUBLIC_PORT}/tcp"
    failed=1
  fi

  if [[ -f "${MANIFEST_PATH}" && -f "${LINK_BUNDLE_PATH}" && -f "${LINK_DEFINITIONS_PATH}" ]]; then
    echo "  [ok] manifest/link artifacts present"
  else
    echo "  [fail] manifest/link artifacts missing"
    failed=1
  fi

  if [[ -n "${PUBLIC_DOMAIN}" ]]; then
    echo "  [ok] public domain recorded (${PUBLIC_DOMAIN})"
  else
    echo "  [fail] public domain missing from manifest"
    failed=1
  fi

  case "${ENGINE}" in
    official)
      if systemctl is-enabled --quiet "${REFRESH_TIMER_NAME}" 2>/dev/null; then
        echo "  [ok] refresh timer enabled"
      else
        echo "  [fail] refresh timer disabled"
        failed=1
      fi

      if [[ -f "${PROXY_SECRET_PATH}" && -f "${PROXY_MULTI_CONF_PATH}" && -x "${OFFICIAL_BIN_PATH}" ]]; then
        echo "  [ok] official runtime artifacts present"
      else
        echo "  [fail] official runtime artifacts missing"
        failed=1
      fi
      ;;
    stealth)
      if [[ -f "${STEALTH_CONFIG_PATH}" && -x "${STEALTH_BIN_PATH}" ]]; then
        echo "  [ok] stealth runtime artifacts present"
      else
        echo "  [fail] stealth runtime artifacts missing"
        failed=1
      fi

      if [[ "${DECOY_MODE}" == "upstream-forward" ]]; then
        if [[ -n "${DECOY_TARGET_HOST}" ]]; then
          echo "  [ok] decoy target recorded (${DECOY_TARGET_HOST}:${DECOY_TARGET_PORT})"
        else
          echo "  [fail] decoy target missing"
          failed=1
        fi
      else
        echo "  [ok] decoy mode ${DECOY_MODE}"
      fi
      ;;
  esac

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

  case "${ENGINE}" in
    official)
      download_proxy_files
      apply_permissions
      apply_engine_runtime_tuning
      systemctl restart "${SERVICE_NAME}"
      log "Конфиг Telegram обновлен"
      ;;
    stealth)
      warn "refresh-telegram-config не требуется для ENGINE=stealth"
      ;;
  esac
}

rotate_link() {
  local target_name="${1:-}"
  local name profile secret_file raw_secret desired_value found=0

  require_root
  require_installed

  [[ -n "${target_name}" ]] || die "Укажи имя ссылки: rotate-link <name>"

  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue

    if [[ "${name}" == "${target_name}" ]]; then
      secret_file="$(secret_file_for_name "${name}")"
      raw_secret="$(generate_raw_secret_hex)"
      desired_value="$(format_slot_secret_for_engine_profile "${ENGINE}" "${profile}" "${raw_secret}")"
      log "Ротирую link ${name} (${profile})..."
      printf '%s\n' "${desired_value}" > "${secret_file}"
      found=1
      break
    fi
  done < "${LINK_DEFINITIONS_PATH}"

  (( found == 1 )) || die "Link slot не найден: ${target_name}"

  render_engine_runtime_artifacts
  build_link_bundle
  apply_permissions
  apply_engine_runtime_tuning
  systemctl restart "${SERVICE_NAME}"

  log "Link ${target_name} обновлен"
}

rotate_all_links() {
  local name profile secret_file raw_secret desired_value

  require_root
  require_installed

  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue
    secret_file="$(secret_file_for_name "${name}")"
    raw_secret="$(generate_raw_secret_hex)"
    desired_value="$(format_slot_secret_for_engine_profile "${ENGINE}" "${profile}" "${raw_secret}")"
    log "Ротирую link ${name} (${profile})..."
    printf '%s\n' "${desired_value}" > "${secret_file}"
  done < "${LINK_DEFINITIONS_PATH}"

  render_engine_runtime_artifacts
  build_link_bundle
  apply_permissions
  apply_engine_runtime_tuning
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
  apply_engine_runtime_tuning
  systemctl restart "${SERVICE_NAME}"
  status
}

install_all() {
  require_root
  resolve_install_contract
  validate_install_contract

  ensure_packages
  ensure_user_and_dirs
  clone_or_update_engine_repo
  build_engine_binary
  write_managed_link_definitions
  migrate_legacy_layout_if_present
  ensure_link_secrets

  if [[ "${ENGINE}" == "official" ]]; then
    if [[ ! -f "${PROXY_SECRET_PATH}" || ! -f "${PROXY_MULTI_CONF_PATH}" ]]; then
      download_proxy_files
    else
      info "Proxy upstream artifacts уже существуют, обновление не требуется"
    fi
  fi

  persist_manifest
  render_engine_runtime_artifacts
  build_link_bundle
  render_runner_script
  render_refresh_helper
  render_service_file
  render_refresh_units
  apply_permissions
  apply_engine_runtime_tuning
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

  warn "Удаляю бинарники, исходники и helper scripts..."
  rm -f "${OFFICIAL_BIN_PATH}" "${STEALTH_BIN_PATH}" "${RUNNER_PATH}" "${REFRESH_HELPER_PATH}"
  rm -rf "${OFFICIAL_SRC_DIR}" "${STEALTH_SRC_DIR}"

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
  cat <<EOF_USAGE
Usage:
  sudo PUBLIC_DOMAIN=proxy.example.com bash $0 install
  sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth bash $0 install
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
  ENGINE=official|stealth
  PRIMARY_PROFILE=dd|classic (official), ee|dd|classic (stealth)
  LINK_STRATEGY=bundle|per-device
  DEVICE_NAMES=phone,desktop,tablet
  TLS_DOMAIN=<defaults to PUBLIC_DOMAIN>
  DECOY_MODE=disabled|upstream-forward
  DECOY_TARGET_HOST=<required for DECOY_MODE=upstream-forward>
  DECOY_TARGET_PORT=443
  OFFICIAL_REPO_URL=${OFFICIAL_REPO_URL_DEFAULT}
  OFFICIAL_REPO_BRANCH=${OFFICIAL_REPO_BRANCH_DEFAULT}
  STEALTH_REPO_URL=${STEALTH_REPO_URL_DEFAULT}
  STEALTH_REPO_BRANCH=${STEALTH_REPO_BRANCH_DEFAULT}

Examples:
  sudo PUBLIC_DOMAIN=proxy.example.com bash $0 install
  sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth bash $0 install
  sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth LINK_STRATEGY=per-device DEVICE_NAMES=phone,desktop,tablet bash $0 install
  sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth TLS_DOMAIN=cdn.example.com DECOY_MODE=upstream-forward DECOY_TARGET_HOST=site.example.com DECOY_TARGET_PORT=443 bash $0 install
EOF_USAGE
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
