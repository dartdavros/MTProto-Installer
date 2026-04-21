# shellcheck shell=bash

path_mode() {
  stat -c '%a' "$1"
}

path_owner_group() {
  stat -c '%U:%G' "$1"
}

check_path_contract() {
  local path="$1"
  local expected_mode="$2"
  local expected_owner_group="$3"
  local label="$4"
  local actual_mode actual_owner_group

  [[ -e "${path}" ]] || return 1

  actual_mode="$(path_mode "${path}")"
  actual_owner_group="$(path_owner_group "${path}")"

  [[ "${actual_mode}" == "${expected_mode}" ]] || return 1
  [[ "${actual_owner_group}" == "${expected_owner_group}" ]] || return 1

  return 0
}

check_optional_path_contract() {
  local path="$1"
  local expected_mode="$2"
  local expected_owner_group="$3"

  [[ -e "${path}" ]] || return 0
  check_path_contract "${path}" "${expected_mode}" "${expected_owner_group}" "${path}"
}

sensitive_artifacts_secure() {
  local secret_file

  check_path_contract "${CONFIG_ROOT}" "750" "root:${RUN_GROUP}" "config root" || return 1
  check_path_contract "${MANIFEST_DIR}" "750" "root:${RUN_GROUP}" "manifest dir" || return 1
  check_path_contract "${SECRETS_DIR}" "750" "root:${RUN_GROUP}" "secrets dir" || return 1
  check_path_contract "${LINKS_DIR}" "750" "root:${RUN_GROUP}" "links dir" || return 1
  check_path_contract "${RUNTIME_DIR}" "750" "root:${RUN_GROUP}" "runtime dir" || return 1
  check_path_contract "${STATE_DIR}" "750" "${RUN_USER}:${RUN_GROUP}" "state dir" || return 1
  check_path_contract "${ROTATION_BACKUPS_DIR}" "750" "root:${RUN_GROUP}" "rotation backups dir" || return 1

  check_path_contract "${MANIFEST_PATH}" "640" "root:${RUN_GROUP}" "manifest" || return 1
  check_path_contract "${LINK_DEFINITIONS_PATH}" "640" "root:${RUN_GROUP}" "link definitions" || return 1
  check_path_contract "${LINK_BUNDLE_PATH}" "640" "root:${RUN_GROUP}" "link bundle" || return 1

  check_optional_path_contract "${PROXY_SECRET_PATH}" "640" "root:${RUN_GROUP}" || return 1
  check_optional_path_contract "${PROXY_MULTI_CONF_PATH}" "640" "root:${RUN_GROUP}" || return 1
  check_optional_path_contract "${STEALTH_CONFIG_PATH}" "640" "root:${RUN_GROUP}" || return 1
  check_optional_path_contract "${REFRESH_STATE_PATH}" "640" "root:${RUN_GROUP}" || return 1
  check_optional_path_contract "${DECOY_MANAGED_CERT_PATH}" "640" "root:${RUN_GROUP}" || return 1
  check_optional_path_contract "${DECOY_MANAGED_KEY_PATH}" "640" "root:${RUN_GROUP}" || return 1
  check_optional_path_contract "${RUNNER_PATH}" "750" "root:${RUN_GROUP}" || return 1
  check_optional_path_contract "${REFRESH_HELPER_PATH}" "750" "root:${RUN_GROUP}" || return 1
  check_optional_path_contract "${DECOY_SERVER_PATH}" "750" "root:${RUN_GROUP}" || return 1
  check_optional_path_contract "${STEALTH_TLS_FRONT_DIR}" "750" "${RUN_USER}:${RUN_GROUP}" || return 1
  check_optional_path_contract "${DECOY_WWW_DIR}" "750" "${RUN_USER}:${RUN_GROUP}" || return 1

  while IFS= read -r -d '' secret_file; do
    check_path_contract "${secret_file}" "640" "root:${RUN_GROUP}" "secret slot" || return 1
  done < <(find "${SECRETS_DIR}" -maxdepth 1 -type f -name '*.secret' -print0 | sort -z)

  while IFS= read -r -d '' secret_file; do
    check_path_contract "${secret_file}" "640" "root:${RUN_GROUP}" "rotation backup secret" || return 1
  done < <(find "${ROTATION_BACKUPS_DIR}" -mindepth 2 -maxdepth 3 -type f -name '*.secret' -print0 2>/dev/null | sort -z)

  while IFS= read -r -d '' metadata_file; do
    check_path_contract "${metadata_file}" "640" "root:${RUN_GROUP}" "rotation backup metadata" || return 1
  done < <(find "${ROTATION_BACKUPS_DIR}" -mindepth 2 -maxdepth 2 -type f -name 'metadata.env' -print0 2>/dev/null | sort -z)

  return 0
}

expected_link_definitions_match() {
  local tmp_path

  tmp_path="$(mktemp)"
  trap 'rm -f "${tmp_path}"' RETURN

  render_managed_link_definitions > "${tmp_path}"
  cmp -s "${tmp_path}" "${LINK_DEFINITIONS_PATH}"
}

bundle_contains_expected_profiles() {
  local name profile

  while IFS=$'\t' read -r name profile; do
    [[ -n "${name}" ]] || continue
    grep -Fq "${name}"$'\t'"${profile}"$'\t' "${LINK_BUNDLE_PATH}" || return 1
  done < "${LINK_DEFINITIONS_PATH}"

  return 0
}

read_bundle_secrets() {
  awk -F'\t' 'NF >= 6 {print $5}' "${LINK_BUNDLE_PATH}"
}

output_leaks_managed_secrets() {
  local output="$1"
  local secret

  while IFS= read -r secret; do
    [[ -n "${secret}" ]] || continue
    grep -Fq -- "${secret}" <<< "${output}" && return 0
  done < <(read_bundle_secrets)

  return 1
}

output_contains_tg_links() {
  local output="$1"
  grep -Fq 'tg://proxy?' <<< "${output}"
}

status_output_redacted() {
  local output

  output="$(status 2>&1)"

  output_contains_tg_links "${output}" && return 1
  output_leaks_managed_secrets "${output}" && return 1

  return 0
}

list_output_redacted() {
  local output

  output="$(list_links 2>&1)"

  output_contains_tg_links "${output}" && return 1
  output_leaks_managed_secrets "${output}" && return 1

  return 0
}

share_links_command_operable() {
  share_links >/dev/null
}

refresh_contract_valid() {
  if ! engine_requires_telegram_upstream; then
    return 0
  fi

  [[ -x "${REFRESH_HELPER_PATH}" ]] || return 1
  systemctl is-enabled --quiet "${REFRESH_TIMER_NAME}" 2>/dev/null || return 1

  return 0
}

refresh_command_operable() {
  if [[ "${ACCEPTANCE_RUN_REFRESH:-0}" == "1" ]] && engine_requires_telegram_upstream; then
    refresh_telegram_config >/dev/null
  else
    refresh_contract_valid
  fi
}

refresh_acceptance_healthy() {
  if ! engine_requires_telegram_upstream; then
    return 0
  fi

  if ! refresh_contract_valid; then
    return 1
  fi

  if refresh_has_recorded_attempt; then
    refresh_last_result_successful || return 1
    refresh_success_is_stale && return 1
  fi

  return 0
}

active_rotation_smoke() {
  local first_name secret_file before_raw after_raw restored_raw

  first_name="$(awk 'NR==1 {print $1}' "${LINK_DEFINITIONS_PATH}")"
  [[ -n "${first_name}" ]] || return 1

  secret_file="$(secret_file_for_name "${first_name}")"
  before_raw="$(extract_raw_secret_hex "$(normalize_secret "${secret_file}")")"

  rotate_link "${first_name}" >/dev/null
  after_raw="$(extract_raw_secret_hex "$(normalize_secret "${secret_file}")")"
  [[ -n "${after_raw}" && "${after_raw}" != "${before_raw}" ]] || return 1

  restore_rotation_backup latest >/dev/null
  restored_raw="$(extract_raw_secret_hex "$(normalize_secret "${secret_file}")")"
  [[ "${restored_raw}" == "${before_raw}" ]] || return 1

  rotation_runtime_healthy
}

acceptance_smoke() {
  require_root
  require_installed

  local failed=0

  echo "Acceptance smoke:"

  if health >/dev/null 2>&1; then
    echo "  [ok] health command passed"
  else
    echo "  [fail] health command failed"
    failed=1
  fi

  if expected_link_definitions_match; then
    echo "  [ok] link definition model matches manifest policy"
  else
    echo "  [fail] link definition model drift detected"
    failed=1
  fi

  if bundle_contains_expected_profiles; then
    echo "  [ok] link bundle contains expected slots and profiles"
  else
    echo "  [fail] link bundle is missing expected slots or profiles"
    failed=1
  fi

  if sensitive_artifacts_secure; then
    echo "  [ok] sensitive artifacts keep expected ownership and modes"
  else
    echo "  [fail] sensitive artifact permissions/ownership drift detected"
    failed=1
  fi

  if status_output_redacted; then
    echo "  [ok] status output is redacted"
  else
    echo "  [fail] status output leaks tg-links or managed secrets"
    failed=1
  fi

  if list_output_redacted; then
    echo "  [ok] list-links output is redacted"
  else
    echo "  [fail] list-links output leaks tg-links or managed secrets"
    failed=1
  fi

  if share_links_command_operable; then
    echo "  [ok] share-links command is operable"
  else
    echo "  [fail] share-links command failed"
    failed=1
  fi

  if [[ "${ACCEPTANCE_RUN_ROTATION:-0}" == "1" ]]; then
    if active_rotation_smoke; then
      echo "  [ok] transactional rotation + rollback smoke passed"
    else
      echo "  [fail] transactional rotation + rollback smoke failed"
      failed=1
    fi
  else
    echo "  [ok] transactional rotation smoke skipped (set ACCEPTANCE_RUN_ROTATION=1 for active check)"
  fi

  if refresh_command_operable; then
    if engine_requires_telegram_upstream; then
      if [[ "${ACCEPTANCE_RUN_REFRESH:-0}" == "1" ]]; then
        echo "  [ok] refresh-telegram-config command executed successfully"
      else
        echo "  [ok] refresh contract is present (set ACCEPTANCE_RUN_REFRESH=1 for active check)"
      fi

      if refresh_acceptance_healthy; then
        if refresh_has_recorded_attempt; then
          echo "  [ok] refresh observability is healthy"
        else
          echo "  [ok] refresh observability pending first successful run"
        fi
      else
        echo "  [fail] refresh observability is unhealthy"
        failed=1
      fi
    else
      echo "  [ok] refresh-telegram-config is not required for this engine"
    fi
  else
    echo "  [fail] refresh contract check failed"
    failed=1
  fi

  if engine_supports_decoy && [[ "${DECOY_MODE}" != "disabled" ]]; then
    if test_decoy_command >/dev/null 2>&1; then
      echo "  [ok] decoy diagnostics passed"
    else
      echo "  [fail] decoy diagnostics failed"
      failed=1
    fi
  fi

  if (( failed == 0 )); then
    echo
    log "Acceptance smoke passed"
  else
    echo
    die "Acceptance smoke failed"
  fi
}
