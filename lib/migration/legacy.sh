# shellcheck shell=bash

legacy_secret_profile_from_value() {
  local value="$1"

  case "${value}" in
    ee[0-9A-Fa-f][0-9A-Fa-f]*)
      printf 'ee\n'
      ;;
    dd[0-9A-Fa-f][0-9A-Fa-f]*)
      printf 'dd\n'
      ;;
    *)
      printf 'classic\n'
      ;;
  esac
}

link_definitions_contain_name() {
  local name="$1"
  [[ -f "${LINK_DEFINITIONS_PATH}" ]] || return 1
  awk -F $'\t' -v name="${name}" '$1 == name { found = 1 } END { exit(found ? 0 : 1) }' "${LINK_DEFINITIONS_PATH}"
}

managed_slots_contain_raw_secret() {
  local target_raw="$1"
  local secret_file stored_secret raw_secret

  if ! compgen -G "${SECRETS_DIR}/*.secret" >/dev/null; then
    return 1
  fi

  for secret_file in "${SECRETS_DIR}"/*.secret; do
    [[ -f "${secret_file}" ]] || continue
    stored_secret="$(normalize_secret "${secret_file}")"
    raw_secret="$(extract_raw_secret_hex "${stored_secret}")"
    if [[ "${raw_secret}" == "${target_raw}" ]]; then
      return 0
    fi
  done

  return 1
}

next_legacy_import_slot_name() {
  local base="legacy-import"
  local candidate="${base}"
  local index=1

  while link_definitions_contain_name "${candidate}" || [[ -f "$(secret_file_for_name "${candidate}")" ]]; do
    candidate="${base}-${index}"
    index=$((index + 1))
  done

  printf '%s\n' "${candidate}"
}

import_legacy_client_secret_if_present() {
  local legacy_secret_value legacy_raw_secret legacy_profile slot_name slot_secret_file

  [[ -f "${LEGACY_SECRET_PATH}" ]] || return 0

  legacy_secret_value="$(normalize_secret "${LEGACY_SECRET_PATH}")"
  [[ -n "${legacy_secret_value}" ]] || return 0

  legacy_raw_secret="$(extract_raw_secret_hex "${legacy_secret_value}")"
  if managed_slots_contain_raw_secret "${legacy_raw_secret}"; then
    info "Legacy client secret уже представлен в managed slots"
    return 0
  fi

  legacy_profile="$(legacy_secret_profile_from_value "${legacy_secret_value}")"
  slot_name="$(next_legacy_import_slot_name)"
  slot_secret_file="$(secret_file_for_name "${slot_name}")"

  warn "Импортирую legacy client secret в managed slot ${slot_name} (${legacy_profile})..."
  printf '%s\t%s\n' "${slot_name}" "${legacy_profile}" >> "${LINK_DEFINITIONS_PATH}"
  install -o root -g "${RUN_GROUP}" -m 0640 "${LEGACY_SECRET_PATH}" "${slot_secret_file}"
}

parse_legacy_service_exec_flag() {
  local flag="$1"
  [[ -f "${SERVICE_PATH}" ]] || return 1

  awk -v flag="${flag}" '
    /^ExecStart=/ {
      line = $0
      sub(/^ExecStart=/, "", line)
      n = split(line, fields, /[[:space:]]+/)
      for (i = 1; i < n; i++) {
        if (fields[i] == flag) {
          print fields[i + 1]
          exit
        }
      }
    }
  ' "${SERVICE_PATH}"
}

populate_contract_from_legacy_service_if_needed() {
  local legacy_public_port legacy_internal_port legacy_workers

  [[ -f "${MANIFEST_PATH}" ]] && return 0
  [[ -f "${SERVICE_PATH}" ]] || return 0

  read_requested_contract

  legacy_public_port="$(parse_legacy_service_exec_flag '-H' || true)"
  legacy_internal_port="$(parse_legacy_service_exec_flag '-p' || true)"
  legacy_workers="$(parse_legacy_service_exec_flag '-M' || true)"

  if [[ -z "${REQUESTED_PUBLIC_PORT}" && -z "${MANIFEST_PUBLIC_PORT}" && -n "${legacy_public_port}" ]]; then
    info "Найден legacy public port: ${legacy_public_port}"
    PUBLIC_PORT="${legacy_public_port}"
  fi

  if [[ -z "${REQUESTED_INTERNAL_PORT}" && -z "${MANIFEST_INTERNAL_PORT}" && -n "${legacy_internal_port}" ]]; then
    info "Найден legacy internal port: ${legacy_internal_port}"
    INTERNAL_PORT="${legacy_internal_port}"
  fi

  if [[ -z "${REQUESTED_WORKERS}" && -z "${MANIFEST_WORKERS}" && -n "${legacy_workers}" ]]; then
    info "Найден legacy workers count: ${legacy_workers}"
    WORKERS="${legacy_workers}"
  fi
}

migrate_legacy_layout_if_present() {
  [[ -f "${MANIFEST_PATH}" ]] && return 0
  [[ -f "${LINK_DEFINITIONS_PATH}" ]] || return 0

  import_legacy_client_secret_if_present

  if [[ -f "${LEGACY_PROXY_SECRET_PATH}" && ! -f "${PROXY_SECRET_PATH}" ]]; then
    warn "Импортирую legacy proxy-secret..."
    install -o root -g "${RUN_GROUP}" -m 0640 "${LEGACY_PROXY_SECRET_PATH}" "${PROXY_SECRET_PATH}"
  fi

  if [[ -f "${LEGACY_PROXY_MULTI_CONF_PATH}" && ! -f "${PROXY_MULTI_CONF_PATH}" ]]; then
    warn "Импортирую legacy proxy-multi.conf..."
    install -o root -g "${RUN_GROUP}" -m 0640 "${LEGACY_PROXY_MULTI_CONF_PATH}" "${PROXY_MULTI_CONF_PATH}"
  fi
}

migrate_install() {
  require_root

  if has_manifest; then
    warn "Manifest уже существует. Выполняю обычный install для актуализации установки."
    install_all
    return 0
  fi

  if [[ ! -f "${LEGACY_SECRET_PATH}" && ! -f "${LEGACY_PROXY_SECRET_PATH}" && ! -f "${LEGACY_PROXY_MULTI_CONF_PATH}" && ! -f "${SERVICE_PATH}" ]]; then
    die "Legacy installation не найдена: нечего мигрировать"
  fi

  warn "Запускаю migration install: legacy layout будет импортирован в managed artifact model"
  install_all
}
