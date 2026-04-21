#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

source_lib() {
  local rel_path="$1"
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/${rel_path}"
}

source_lib "lib/core/constants.sh"
source_lib "lib/core/log.sh"
source_lib "lib/core/shell.sh"
source_lib "lib/core/validate.sh"
source_lib "lib/core/network.sh"
source_lib "lib/contract/manifest.sh"
source_lib "lib/migration/legacy.sh"
source_lib "lib/contract/resolve.sh"
source_lib "lib/contract/validate.sh"
source_lib "lib/engines/common.sh"
source_lib "lib/links/definitions.sh"
source_lib "lib/links/secrets.sh"
source_lib "lib/telegram/upstream.sh"
source_lib "lib/runtime/engine_artifacts.sh"
source_lib "lib/decoy/runtime.sh"
source_lib "lib/runtime/systemd.sh"
source_lib "lib/links/bundle.sh"
source_lib "lib/diagnostics/domain.sh"
source_lib "lib/commands/install.sh"
source_lib "lib/commands/status.sh"
source_lib "lib/commands/links.sh"
source_lib "lib/commands/help.sh"
source_lib "lib/commands/dispatch.sh"

main "$@"
