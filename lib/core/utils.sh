#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# Utility helpers and command stubs for the MTProto installer.  The
# original implementation of the installer provided a rich set of
# functions covering installation, removal, status inspection and
# configuration.  This stub defines minimal versions of those
# functions so that the entrypoint script can be exercised in a
# self‑contained environment.  Real deployments should replace this
# file with the fully‑fledged implementation from the upstream
# repository.

# Show the interactive menu.  In the real installer this would
# present a TUI or series of prompts; here it simply calls usage.
interactive_menu() {
  printf 'Interactive mode is not implemented in this stub.\n' >&2
  usage
}

# Command stubs.  They print messages indicating that the real
# functionality is not available in this environment.  Replace these
# with real implementations as necessary.
cmd_install() {
  echo "[stub] install command invoked with args: $*"
}

cmd_uninstall() {
  echo "[stub] uninstall command invoked with args: $*"
}

cmd_status() {
  echo "[stub] status command invoked with args: $*"
}

cmd_enable() {
  echo "[stub] enable command invoked with args: $*"
}

cmd_disable() {
  echo "[stub] disable command invoked with args: $*"
}

# Note: rotate-link and rotate-all-links are implemented in
# runtime/rotate.sh and sourced by install-mtproxy.sh.
