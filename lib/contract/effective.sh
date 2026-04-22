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

pick_effective_value() {
  local requested="$1"
  local manifest="$2"
  local fallback="$3"

  if [[ -n "${requested}" ]]; then
    printf '%s\n' "${requested}"
  elif [[ -n "${manifest}" ]]; then
    printf '%s\n' "${manifest}"
  else
    printf '%s\n' "${fallback}"
  fi
}

hydrate_effective_contract() {
  local requested_enabled="$1"
  local requested_engine=""
  local requested_public_domain=""
  local requested_public_port=""
  local requested_internal_port=""
  local requested_workers=""
  local requested_primary_profile=""
  local requested_link_strategy=""
  local requested_device_names=""
  local requested_tls_domain=""
  local requested_decoy_mode=""
  local requested_decoy_target_host=""
  local requested_decoy_target_port=""
  local requested_decoy_domain=""
  local requested_decoy_local_port=""
  local requested_decoy_cert_path=""
  local requested_decoy_key_path=""
  local requested_official_repo_url=""
  local requested_official_repo_branch=""
  local requested_stealth_repo_url=""
  local requested_stealth_repo_branch=""
  local default_profile

  read_manifest_contract

  case "${requested_enabled}" in
    yes)
      read_requested_contract
      requested_engine="${REQUESTED_ENGINE:-}"
      requested_public_domain="${REQUESTED_PUBLIC_DOMAIN:-}"
      requested_public_port="${REQUESTED_PUBLIC_PORT:-}"
      requested_internal_port="${REQUESTED_INTERNAL_PORT:-}"
      requested_workers="${REQUESTED_WORKERS:-}"
      requested_primary_profile="${REQUESTED_PRIMARY_PROFILE:-}"
      requested_link_strategy="${REQUESTED_LINK_STRATEGY:-}"
      requested_device_names="${REQUESTED_DEVICE_NAMES:-}"
      requested_tls_domain="${REQUESTED_TLS_DOMAIN:-}"
      requested_decoy_mode="${REQUESTED_DECOY_MODE:-}"
      requested_decoy_target_host="${REQUESTED_DECOY_TARGET_HOST:-}"
      requested_decoy_target_port="${REQUESTED_DECOY_TARGET_PORT:-}"
      requested_decoy_domain="${REQUESTED_DECOY_DOMAIN:-}"
      requested_decoy_local_port="${REQUESTED_DECOY_LOCAL_PORT:-}"
      requested_decoy_cert_path="${REQUESTED_DECOY_CERT_PATH:-}"
      requested_decoy_key_path="${REQUESTED_DECOY_KEY_PATH:-}"
      requested_official_repo_url="${REQUESTED_OFFICIAL_REPO_URL:-}"
      requested_official_repo_branch="${REQUESTED_OFFICIAL_REPO_BRANCH:-}"
      requested_stealth_repo_url="${REQUESTED_STEALTH_REPO_URL:-}"
      requested_stealth_repo_branch="${REQUESTED_STEALTH_REPO_BRANCH:-}"
      ;;
    no)
      ;;
    *)
      die "Неизвестный режим гидрации контракта: ${requested_enabled}"
      ;;
  esac

  ENGINE="$(pick_effective_value "${requested_engine}" "${MANIFEST_ENGINE:-}" "stealth")"
  default_profile="$(default_primary_profile_for_engine "${ENGINE}")"

  PUBLIC_DOMAIN="$(pick_effective_value "${requested_public_domain}" "${MANIFEST_PUBLIC_DOMAIN:-}" "")"
  PUBLIC_PORT="$(pick_effective_value "${requested_public_port}" "${MANIFEST_PUBLIC_PORT:-}" "443")"
  INTERNAL_PORT="$(pick_effective_value "${requested_internal_port}" "${MANIFEST_INTERNAL_PORT:-}" "8888")"
  WORKERS="$(pick_effective_value "${requested_workers}" "${MANIFEST_WORKERS:-}" "1")"
  PRIMARY_PROFILE="$(pick_effective_value "${requested_primary_profile}" "${MANIFEST_PRIMARY_PROFILE:-}" "${default_profile}")"
  LINK_STRATEGY="$(pick_effective_value "${requested_link_strategy}" "${MANIFEST_LINK_STRATEGY:-}" "bundle")"
  DEVICE_NAMES="$(pick_effective_value "${requested_device_names}" "${MANIFEST_DEVICE_NAMES:-}" "")"
  TLS_DOMAIN="$(pick_effective_value "${requested_tls_domain}" "${MANIFEST_TLS_DOMAIN:-}" "${PUBLIC_DOMAIN}")"
  DECOY_MODE="$(pick_effective_value "${requested_decoy_mode}" "${MANIFEST_DECOY_MODE:-}" "disabled")"
  DECOY_TARGET_HOST="$(pick_effective_value "${requested_decoy_target_host}" "${MANIFEST_DECOY_TARGET_HOST:-}" "")"
  DECOY_TARGET_PORT="$(pick_effective_value "${requested_decoy_target_port}" "${MANIFEST_DECOY_TARGET_PORT:-}" "443")"
  DECOY_DOMAIN="$(pick_effective_value "${requested_decoy_domain}" "${MANIFEST_DECOY_DOMAIN:-}" "${TLS_DOMAIN}")"
  DECOY_LOCAL_PORT="$(pick_effective_value "${requested_decoy_local_port}" "${MANIFEST_DECOY_LOCAL_PORT:-}" "10443")"
  DECOY_CERT_SOURCE_PATH="$(pick_effective_value "${requested_decoy_cert_path}" "${MANIFEST_DECOY_CERT_SOURCE_PATH:-}" "")"
  DECOY_KEY_SOURCE_PATH="$(pick_effective_value "${requested_decoy_key_path}" "${MANIFEST_DECOY_KEY_SOURCE_PATH:-}" "")"

  OFFICIAL_REPO_URL="$(pick_effective_value "${requested_official_repo_url}" "${MANIFEST_OFFICIAL_REPO_URL:-}" "${OFFICIAL_REPO_URL_DEFAULT}")"
  OFFICIAL_REPO_BRANCH="$(pick_effective_value "${requested_official_repo_branch}" "${MANIFEST_OFFICIAL_REPO_BRANCH:-}" "${OFFICIAL_REPO_BRANCH_DEFAULT}")"
  STEALTH_REPO_URL="$(pick_effective_value "${requested_stealth_repo_url}" "${MANIFEST_STEALTH_REPO_URL:-}" "${STEALTH_REPO_URL_DEFAULT}")"
  STEALTH_REPO_BRANCH="$(pick_effective_value "${requested_stealth_repo_branch}" "${MANIFEST_STEALTH_REPO_BRANCH:-}" "${STEALTH_REPO_BRANCH_DEFAULT}")"

  DEVICE_NAMES="$(normalize_device_names_csv "${DEVICE_NAMES}")"
  PUBLIC_DOMAIN="${PUBLIC_DOMAIN,,}"
  TLS_DOMAIN="${TLS_DOMAIN,,}"
  DECOY_DOMAIN="${DECOY_DOMAIN,,}"
}
