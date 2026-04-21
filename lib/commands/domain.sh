# shellcheck shell=bash

check_domain_command() {
  read_manifest_contract

  local domain="${REQUESTED_PUBLIC_DOMAIN:-${MANIFEST_PUBLIC_DOMAIN:-}}"
  local tls_domain="${REQUESTED_TLS_DOMAIN:-${MANIFEST_TLS_DOMAIN:-}}"

  [[ -n "${domain}" ]] || die "Укажи PUBLIC_DOMAIN либо выполни команду на установленной системе"

  print_domain_diagnostics "${domain,,}" "Public domain"

  if [[ -n "${tls_domain}" && "${tls_domain,,}" != "${domain,,}" ]]; then
    echo
    print_domain_diagnostics "${tls_domain,,}" "TLS domain"
  fi
}
