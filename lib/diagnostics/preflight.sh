# shellcheck shell=bash

port_has_listener() {
  local port="$1"
  ss -ltnH "( sport = :${port} )" 2>/dev/null | grep -q .
}

port_reserved_by_managed_service() {
  local port="$1"
  local service_name="$2"
  local expected_port="$3"

  [[ -n "${service_name}" && -n "${expected_port}" ]] || return 1
  [[ "${port}" == "${expected_port}" ]] || return 1
  systemctl is-active --quiet "${service_name}" 2>/dev/null
}

require_port_available_or_managed() {
  local port="$1"
  local label="$2"
  local service_name="$3"
  local expected_port="$4"

  if ! port_has_listener "${port}"; then
    info "${label}: порт ${port}/tcp свободен"
    return 0
  fi

  if port_reserved_by_managed_service "${port}" "${service_name}" "${expected_port}"; then
    info "${label}: порт ${port}/tcp уже занят managed service ${service_name}, это допустимо"
    return 0
  fi

  die "${label}: порт ${port}/tcp уже занят другим процессом"
}

validate_runtime_port_relationships() {
  [[ "${PUBLIC_PORT}" != "${INTERNAL_PORT}" ]] || die "PUBLIC_PORT и INTERNAL_PORT должны различаться"

  if [[ "${DECOY_MODE}" == "local-https" ]]; then
    [[ "${PUBLIC_PORT}" != "${DECOY_LOCAL_PORT}" ]] || die "PUBLIC_PORT и DECOY_LOCAL_PORT должны различаться"
    [[ "${INTERNAL_PORT}" != "${DECOY_LOCAL_PORT}" ]] || die "INTERNAL_PORT и DECOY_LOCAL_PORT должны различаться"
  fi
}

validate_domain_preflight() {
  local domain="$1"
  local label="$2"
  local require_local_match="$3"
  local resolved_ips local_ips matched=0 line

  resolved_ips="$(collect_domain_candidates "${domain}" | collect_unique_lines)"
  [[ -n "${resolved_ips}" ]] || die "${label}: DNS не вернул A/AAAA записи для ${domain}"

  if [[ "${require_local_match}" != "yes" ]]; then
    info "${label}: DNS записи найдены для ${domain}"
    return 0
  fi

  local_ips="$(collect_local_global_ips | collect_unique_lines)"
  [[ -n "${local_ips}" ]] || die "${label}: не удалось определить глобальные IP адреса текущего хоста"

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    if line_in_block "${line}" "${local_ips}"; then
      matched=1
      break
    fi
  done <<< "${resolved_ips}"

  (( matched == 1 )) || die "${label}: DNS записи ${domain} не указывают на глобальные IP этого VPS"
  info "${label}: DNS указывает на текущий VPS"
}

run_install_preflight_checks() {
  local current_public_port=""
  local current_decoy_local_port=""

  validate_runtime_port_relationships

  if has_manifest; then
    read_manifest_contract
    current_public_port="${MANIFEST_PUBLIC_PORT:-}"
    current_decoy_local_port="${MANIFEST_DECOY_LOCAL_PORT:-}"
  fi

  validate_domain_preflight "${PUBLIC_DOMAIN}" "PUBLIC_DOMAIN" "yes"

  if [[ -n "${TLS_DOMAIN}" && "${TLS_DOMAIN}" != "${PUBLIC_DOMAIN}" ]]; then
    validate_domain_preflight "${TLS_DOMAIN}" "TLS_DOMAIN" "no"
  fi

  require_port_available_or_managed "${PUBLIC_PORT}" "PUBLIC_PORT" "${SERVICE_NAME}" "${current_public_port}"

  if [[ "${DECOY_MODE}" == "local-https" ]]; then
    require_port_available_or_managed "${DECOY_LOCAL_PORT}" "DECOY_LOCAL_PORT" "${DECOY_SERVICE_NAME}" "${current_decoy_local_port}"
  fi
}
