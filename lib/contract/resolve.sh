# shellcheck shell=bash

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
  DECOY_DOMAIN="${REQUESTED_DECOY_DOMAIN:-${MANIFEST_DECOY_DOMAIN:-${TLS_DOMAIN}}}"
  DECOY_LOCAL_PORT="${REQUESTED_DECOY_LOCAL_PORT:-${MANIFEST_DECOY_LOCAL_PORT:-10443}}"
  DECOY_CERT_SOURCE_PATH="${REQUESTED_DECOY_CERT_PATH:-${MANIFEST_DECOY_CERT_SOURCE_PATH:-}}"
  DECOY_KEY_SOURCE_PATH="${REQUESTED_DECOY_KEY_PATH:-${MANIFEST_DECOY_KEY_SOURCE_PATH:-}}"

  OFFICIAL_REPO_URL="${REQUESTED_OFFICIAL_REPO_URL:-${MANIFEST_OFFICIAL_REPO_URL:-${OFFICIAL_REPO_URL_DEFAULT}}}"
  OFFICIAL_REPO_BRANCH="${REQUESTED_OFFICIAL_REPO_BRANCH:-${MANIFEST_OFFICIAL_REPO_BRANCH:-${OFFICIAL_REPO_BRANCH_DEFAULT}}}"
  STEALTH_REPO_URL="${REQUESTED_STEALTH_REPO_URL:-${MANIFEST_STEALTH_REPO_URL:-${STEALTH_REPO_URL_DEFAULT}}}"
  STEALTH_REPO_BRANCH="${REQUESTED_STEALTH_REPO_BRANCH:-${MANIFEST_STEALTH_REPO_BRANCH:-${STEALTH_REPO_BRANCH_DEFAULT}}}"

  DEVICE_NAMES="$(normalize_device_names_csv "${DEVICE_NAMES}")"
  PUBLIC_DOMAIN="${PUBLIC_DOMAIN,,}"
  TLS_DOMAIN="${TLS_DOMAIN,,}"
  DECOY_DOMAIN="${DECOY_DOMAIN,,}"

  populate_contract_from_legacy_service_if_needed
}
