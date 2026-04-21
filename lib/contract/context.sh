# shellcheck shell=bash

load_runtime_context() {
  hydrate_effective_contract "no"
  validate_runtime_settings
}
