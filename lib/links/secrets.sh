# shellcheck shell=bash

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
