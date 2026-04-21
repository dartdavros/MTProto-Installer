# shellcheck shell=bash

check_domain_command() {
  local domain tls_domain

  if requested_domain_inputs_present; then
    read_manifest_contract
    domain="${REQUESTED_PUBLIC_DOMAIN:-${MANIFEST_PUBLIC_DOMAIN:-}}"
    tls_domain="${REQUESTED_TLS_DOMAIN:-${MANIFEST_TLS_DOMAIN:-}}"
  elif has_manifest; then
    load_runtime_context
    domain="${PUBLIC_DOMAIN}"
    tls_domain="${TLS_DOMAIN}"
  else
    read_manifest_contract
    domain="${MANIFEST_PUBLIC_DOMAIN:-}"
    tls_domain="${MANIFEST_TLS_DOMAIN:-}"
  fi

  [[ -n "${domain}" ]] || die "Укажи PUBLIC_DOMAIN либо выполни команду на установленной системе"

  print_domain_diagnostics "${domain,,}" "Public domain"

  if [[ -n "${tls_domain}" && "${tls_domain,,}" != "${domain,,}" ]]; then
    echo
    print_domain_diagnostics "${tls_domain,,}" "TLS domain"
  fi
}
