# shellcheck shell=bash

domain_resolved_ips() {
  local domain="$1"
  collect_domain_candidates "${domain}" | collect_unique_lines
}

domain_local_global_ips() {
  collect_local_global_ips | collect_unique_lines
}

domain_matches_local_host() {
  local domain="$1"
  local resolved_ips local_ips line

  resolved_ips="$(domain_resolved_ips "${domain}")"
  local_ips="$(domain_local_global_ips)"

  [[ -n "${resolved_ips}" && -n "${local_ips}" ]] || return 1

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    if line_in_block "${line}" "${local_ips}"; then
      return 0
    fi
  done <<< "${resolved_ips}"

  return 1
}

print_domain_diagnostics() {
  local domain="$1"
  local label="$2"
  local resolved_ips local_ips line matched=0

  validate_domain "${domain}"

  resolved_ips="$(domain_resolved_ips "${domain}")"
  local_ips="$(domain_local_global_ips)"

  echo "${label}: ${domain}"

  if [[ -n "${resolved_ips}" ]]; then
    echo "  resolved IPs:"
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      printf '    - %s
' "${line}"
      if [[ -n "${local_ips}" ]] && line_in_block "${line}" "${local_ips}"; then
        matched=1
      fi
    done <<< "${resolved_ips}"
  else
    echo "  [warn] DNS lookup returned no A/AAAA records"
  fi

  if [[ -n "${local_ips}" ]]; then
    echo "  local global IPs:"
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      printf '    - %s
' "${line}"
    done <<< "${local_ips}"
  else
    echo "  [warn] no global IPs detected on this host"
  fi

  if [[ -n "${resolved_ips}" && -n "${local_ips}" ]]; then
    if (( matched == 1 )); then
      echo "  [ok] at least one DNS record matches a local global IP"
    else
      echo "  [warn] DNS records do not match local global IPs"
    fi
  fi
}
