# shellcheck shell=bash

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
