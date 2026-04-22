#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# Functions to rotate proxy links without restarting the telemt
# service.  The original implementation triggered a full service
# reconfiguration and restart, causing unnecessary connection drops.
# According to the `telemt` documentation, updating the `[access.users]`
# table in the configuration file does not require a restart; a
# `SIGHUP` signal prompts telemt to reload its configuration on the
# fly.

# Generate a new random secret for a user.  A valid secret is a
# hex‑encoded 32‑byte string (64 characters).  We fallback to openssl
# if available; otherwise use /dev/urandom and hexdump.  This function
# returns the secret on stdout.
generate_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    hexdump -n 32 -v -e '/1 "%02x"' /dev/urandom
  fi
}

update_user_secret_in_config() {
  local config_file="$1"
  local user_id="$2"
  local new_secret="$3"
  # Use awk to update the secret for the given user id.  This script
  # assumes that the config file is TOML formatted and that each
  # [[access.users]] table contains an `id` and `secret` entry.  If the
  # user id is not found, it appends a new users table.  The result
  # overwrites the original file atomically via a temporary file.
  local tmp
  tmp=$(mktemp)
  awk -v uid="$user_id" -v sec="$new_secret" '
    BEGIN {in_user=0; found=0}
    /^\[\[access\.users\]\]/ {
      if (in_user && found) {
        print "secret = \"" updated_secret "\""
        found = 0
      }
      in_user = 1
      print $0
      next
    }
    in_user && /^id\s*=\s*"[^"]+"/ {
      user=$0
      match($0, /"([^"]+)"/, m)
      if (m[1] == uid) {
        found=1
        print $0
        getline # read next line; should be secret
        next
      }
    }
    in_user && /^secret\s*=\s*"[^"]+"/ {
      if (found) {
        # replace existing secret
        print "secret = \"" sec "\""
        next
      }
    }
    {print}
    END {
      if (!found) {
        print "[[access.users]]"
        print "id = \"" uid "\""
        print "secret = \"" sec "\""
      }
    }
  ' "$config_file" > "$tmp"
  mv "$tmp" "$config_file"
}

reload_telemt() {
  # Attempt to reload telemt gracefully.  Prefer systemctl if running
  # under systemd; otherwise fall back to sending SIGHUP to the
  # telemt process directly.
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet telemt; then
    systemctl reload telemt
  else
    # Find telemt PID(s) and send HUP
    local pids
    pids=$(pgrep -f '^.*\btelemt\b') || true
    if [ -n "$pids" ]; then
      kill -HUP $pids
    fi
  fi
}

cmd_rotate-link() {
  local user_id="$1"
  if [ -z "$user_id" ]; then
    printf 'Usage: rotate-link <user-id>\n' >&2
    return 1
  fi
  local config="${TELEMT_CONFIG_PATH:-/etc/mtproto/telemt.toml}"
  if [ ! -w "$config" ]; then
    printf 'Error: cannot write telemt config at %s\n' "$config" >&2
    return 1
  fi
  local new_secret
  new_secret=$(generate_secret)
  update_user_secret_in_config "$config" "$user_id" "$new_secret"
  reload_telemt
  printf 'Rotated secret for user "%s"\n' "$user_id"
}

cmd_rotate-all-links() {
  local config="${TELEMT_CONFIG_PATH:-/etc/mtproto/telemt.toml}"
  if [ ! -w "$config" ]; then
    printf 'Error: cannot write telemt config at %s\n' "$config" >&2
    return 1
  fi
  # Extract all user ids and rotate each in turn
  local ids
  ids=$(grep -E '^id\s*=\s*"' "$config" | sed 's/.*"\([^\"]\+\)".*/\1/')
  local id
  for id in $ids; do
    local secret
    secret=$(generate_secret)
    update_user_secret_in_config "$config" "$id" "$secret"
  done
  reload_telemt
  printf 'Rotated secrets for %d users\n' $(echo "$ids" | wc -w)
}