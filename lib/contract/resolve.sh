# shellcheck shell=bash

resolve_install_contract() {
  hydrate_effective_contract "yes"
  populate_contract_from_legacy_service_if_needed
}
