#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# This file defines shared constants used throughout the installer.  In
# the original project these constants were defined in depth by
# environment and manifest.  For the purposes of this stub, we only
# define a handful of defaults.  Downstream modules may override these
# definitions or extend them as necessary.

# Name of the systemd service.  Override via SERVICE_NAME.
SERVICE_NAME="${SERVICE_NAME:-mtproto}"

# Path to the telemt configuration file.  This constant can be
# overridden by environment variable to customise the location.
TELEMT_CONFIG_PATH="${TELEMT_CONFIG_PATH:-/etc/mtproto/telemt.toml}"