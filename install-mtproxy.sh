#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# The MTProto installer entrypoint.  Historically this script was
# distributed standalone and assumed that all of its supporting
# libraries lived in a sibling `lib/` directory.  Recent refactoring
# modularised the codebase into dozens of files under `lib/` and
# auxiliary directories.  Unfortunately, consumers continued to copy
# just this file and execute it from arbitrary locations.  In that
# configuration the original implementation would blindly attempt to
# `source` files from `$SCRIPT_DIR/lib/…` and fail with messages like
# ``./install-mtproxy.sh: line 9: /root/lib/core/constants.sh: No such file or directory``.
#
# To preserve backwards compatibility with the original one‑file usage
# while keeping the new decomposition intact, this version performs
# a discovery phase at startup.  It attempts to locate the `lib/`
# directory relative to the current working directory or, as a last
# resort, downloads the latest installer archive from GitHub.  If none
# of those strategies succeed the script aborts with a clear error.
#
# Consumers who have cloned the repository or unpacked a release
# archive will continue to see deterministic behaviour: the `lib/`
# directory discovered by this script will match the repository
# version.  Users who download only this file can still execute
# installation in a single command provided outbound network access to
# GitHub is available.

set -euo pipefail

# Determine the absolute path of this script.  `$BASH_SOURCE[0]` is
# preferred over `$0` because it resolves symlinks.  Use `realpath` to
# obtain a canonical directory.  If `realpath` is not available, fall
# back to a subshell changing into the directory.
_this="${BASH_SOURCE[0]:-${0}}"
SCRIPT_DIR="$(cd "$(dirname "$_this")" >/dev/null 2>&1 && pwd)"

# Attempt to locate the `lib/` directory.  A valid installation will
# contain `core/constants.sh` inside `lib/`.  We allow three
# strategies in order of preference:
# 1. A sibling `lib/` next to this script (typical for repository
#    clones).
# 2. A `lib/` in the current working directory (for users executing
#    `bash install-mtproxy.sh` from the repo root).
# 3. Download a tarball of the repository and extract the `lib/`
#    contents into a temporary directory.

locate_lib_dir() {
  local candidate
  candidate="$1"
  if [ -d "$candidate" ] && [ -f "$candidate/core/constants.sh" ]; then
    printf '%s' "$candidate"
    return 0
  fi
  return 1
}

resolve_lib_dir() {
  local lib_dir
  # Strategy 1: sibling lib relative to script directory.
  if lib_dir=$(locate_lib_dir "$SCRIPT_DIR/lib"); then
    echo "$lib_dir"
    return
  fi
  # Strategy 2: lib in current working directory.
  if lib_dir=$(locate_lib_dir "$PWD/lib"); then
    echo "$lib_dir"
    return
  fi
  # Strategy 3: fetch from remote repository.  The user may
  # override the repository URL by exporting MT_INSTALLER_REPO_URL.  By
  # default we use the upstream GitHub repository.  We download a
  # tarball of the default branch (usually `master` or `main`).  The
  # network call is performed only if previous strategies have
  # failed.  If curl or tar are unavailable or the network download
  # fails, we abort with a descriptive error.
  local repo_url="${MT_INSTALLER_REPO_URL:-https://github.com/dartdavros/MTProto-Installer}"
  local archive_url="$repo_url/archive/refs/heads/master.tar.gz"
  local tmpdir
  tmpdir=$(mktemp -d)
  printf 'Warning: lib directory not found. Attempting to download installer modules from %s\n' "$archive_url" >&2
  if ! command -v curl >/dev/null 2>&1; then
    printf 'Error: curl is required to download installer modules. Please install curl or run the script from within the repository.\n' >&2
    return 1
  fi
  if ! command -v tar >/dev/null 2>&1; then
    printf 'Error: tar is required to extract installer modules. Please install tar or run the script from within the repository.\n' >&2
    return 1
  fi
  if ! curl -L "$archive_url" 2>/dev/null | tar -xz -C "$tmpdir"; then
    printf 'Error: failed to download or extract installer modules from %s\n' "$archive_url" >&2
    return 1
  fi
  # The extracted archive directory has a name like MTProto-Installer-master or MTProto-Installer-main.
  local extracted
  extracted=$(find "$tmpdir" -mindepth 2 -maxdepth 2 -type d -name 'lib' | head -n1 || true)
  if [ -z "$extracted" ]; then
    printf 'Error: extracted archive does not contain a lib directory.\n' >&2
    return 1
  fi
  echo "$extracted"
}

LIB_DIR="$(resolve_lib_dir)"
if [ -z "$LIB_DIR" ]; then
  printf 'Failed to locate required lib directory. Please run this script from the project root or ensure network access to fetch dependencies.\n' >&2
  exit 1
fi

# Export BASE_DIR so that downstream scripts know where to find their
# modules.  The original code derived `BASE_DIR` from `SCRIPT_DIR`.
export BASE_DIR="$LIB_DIR"

# Source core modules.  These will in turn load additional modules as
# needed.  We use an explicit relative path based on LIB_DIR rather
# than SCRIPT_DIR to avoid inadvertently loading host files when the
# script is executed from an unexpected location.
source "$LIB_DIR/core/constants.sh"
source "$LIB_DIR/core/utils.sh"

## Runtime modules
# The runtime modules contain functions for interacting with the
# underlying proxy engine and supporting daemons.  They are sourced
# here so that the command dispatchers defined below can call
# `cmd_install`, `cmd_uninstall`, `cmd_rotate-link`, etc.  Each of
# these files is expected to define functions beginning with
# `cmd_`.  Additional modules may be added as the codebase evolves.
if [ -f "$LIB_DIR/runtime/rotate.sh" ]; then
  source "$LIB_DIR/runtime/rotate.sh"
fi
if [ -f "$LIB_DIR/runtime/telemt.sh" ]; then
  source "$LIB_DIR/runtime/telemt.sh"
fi

# Entry point function.  It parses the command line and dispatches to
# appropriate subcommands.  When invoked without any arguments, this
# function starts the interactive installer described in the README.
main() {
  if [ $# -eq 0 ]; then
    # No arguments means we should offer interactive mode.  Call into
    # the interactive module if available.  If not, show the usage.
    if declare -f interactive_menu >/dev/null 2>&1; then
      interactive_menu
    else
      usage
    fi
    return
  fi
  # Otherwise dispatch based on the first argument.
  local cmd="$1"
  shift || true
  case "$cmd" in
    install|uninstall|status|enable|disable|rotate-link|rotate-all-links)
      # For well-known commands, defer to subcommand functions.  These
      # functions are expected to be defined in lib scripts.
      if declare -f "cmd_$cmd" >/dev/null 2>&1; then
        "cmd_$cmd" "$@"
      else
        printf 'Error: command "%s" is not implemented.\n' "$cmd" >&2
        usage
        return 1
      fi
      ;;
    *)
      usage
      return 1
      ;;
  esac
}

usage() {
  cat <<'USAGE'
Usage: install-mtproxy.sh <command> [<args>]

Commands:
  install                  Install or update MTProto proxy
  uninstall                Remove MTProto proxy and service
  status                   Show current installation status
  enable                   Enable the MTProto service at boot
  disable                  Disable the MTProto service at boot
  rotate-link              Rotate a single user link without service restart
  rotate-all-links         Rotate all user links without service restart

When invoked without any arguments, the script enters an interactive
mode where you can choose actions from a menu.  To use this script
without cloning the full repository, simply download it and execute
it; it will automatically fetch its supporting modules if they are
missing.  Alternatively, set the environment variable
MT_INSTALLER_REPO_URL to point at an alternative repository.
USAGE
}

# Only run main when this script is executed directly.  If it is
# sourced from another script, the caller can invoke `main` or other
# functions manually.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi