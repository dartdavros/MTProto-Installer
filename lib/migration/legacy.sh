# shellcheck shell=bash

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
