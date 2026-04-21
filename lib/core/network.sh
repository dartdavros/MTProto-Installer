# shellcheck shell=bash

collect_domain_candidates() {
  local value="$1"
  getent ahosts "${value}" 2>/dev/null | awk '{print $1}' || true
}

collect_unique_lines() {
  awk 'NF && !seen[$0]++ { print $0 }'
}

collect_local_global_ips() {
  ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -v '^127\.' || true
  ip -o -6 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -vi '^::1$' || true
}

line_in_block() {
  local needle="$1"
  local haystack="$2"
  grep -Fqx -- "${needle}" <<< "${haystack}"
}
