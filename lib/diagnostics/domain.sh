# shellcheck shell=bash

print_domain_diagnostics() {
  local domain="$1"
  local label="$2"
  local resolved_ips local_ips line matched=0

  validate_domain "${domain}"

  resolved_ips="$(collect_domain_candidates "${domain}" | collect_unique_lines)"
  local_ips="$(collect_local_global_ips | collect_unique_lines)"

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
