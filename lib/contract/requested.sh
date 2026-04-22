#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# Functions related to reading user‑requested configuration from the
# environment.  The original implementation of the installer was too
# aggressive when hydrating the requested contract: it would
# unconditionally assign values from global variables using `${VAR:-}`
# which effectively folded default values into the "requested" layer.
# As a result the merging logic in `hydrate_effective_contract()` would
# treat default values as if they were explicitly requested by the
# caller, causing the manifest values to be ignored on subsequent
# installs.  This version only considers an environment variable as
# "requested" if it has been explicitly set.  We use the
# `${var+set}` parameter expansion to distinguish between an unset
# variable and one that happens to be empty.

read_requested_contract() {
  # Clear existing variables to avoid leaking previous values.
  REQUESTED_ENGINE=""
  REQUESTED_PUBLIC_PORT=""
  REQUESTED_INTERNAL_PORT=""
  REQUESTED_LINK_STRATEGY=""
  REQUESTED_DECOY_MODE=""
  REQUESTED_WORKERS=""

  # Only assign when the variable is explicitly set in the environment.
  if [ -n "${ENGINE+set}" ]; then
    REQUESTED_ENGINE="$ENGINE"
  fi
  if [ -n "${PUBLIC_PORT+set}" ]; then
    REQUESTED_PUBLIC_PORT="$PUBLIC_PORT"
  fi
  if [ -n "${PORT+set}" ] && [ -z "$REQUESTED_PUBLIC_PORT" ]; then
    # Backwards compatibility: allow PORT as an alias for PUBLIC_PORT
    REQUESTED_PUBLIC_PORT="$PORT"
  fi
  if [ -n "${INTERNAL_PORT+set}" ]; then
    REQUESTED_INTERNAL_PORT="$INTERNAL_PORT"
  fi
  if [ -n "${LINK_STRATEGY+set}" ]; then
    REQUESTED_LINK_STRATEGY="$LINK_STRATEGY"
  fi
  if [ -n "${DECOY_MODE+set}" ]; then
    REQUESTED_DECOY_MODE="$DECOY_MODE"
  fi
  if [ -n "${WORKERS+set}" ]; then
    REQUESTED_WORKERS="$WORKERS"
  fi
}