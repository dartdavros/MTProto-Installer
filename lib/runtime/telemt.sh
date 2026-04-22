#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# Helper functions for interacting with the telemt runtime.  The
# upstream `telemt` daemon supports a TOML configuration file.  One of
# the `[general.links]` options, `show`, controls whether `telemt`
# prints pre‑configured `tg://` proxy links at startup.  In the
# previous implementation the installer set `show = "*"`, which
# instructs `telemt` to display all proxy links to any observer of the
# system journal.  This behaviour leaks sensitive information and
# contradicts the ADR prohibiting the exposure of secrets through
# standard logging.
#
# This module provides a single function, `render_telemt_config`, that
# assembles the TOML configuration with a safe default: the list of
# displayed links is empty.  Operators can still inspect or share
# links via the management commands without leaking them in logs.

render_telemt_config() {
  local users_table="$1"
  cat <<EOF
[general]
  # Silence link display at startup to avoid leaking secrets
  [general.links]
  show = []

${users_table}
EOF
}

# Example usage:
#   users_cfg="[[access.users]]\nid = \"user1\"\nsecret = \"abcd\""
#   render_telemt_config "$users_cfg" > /etc/mtproto/telemt.toml