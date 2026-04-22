#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

BOOTSTRAP_REPO_URL_DEFAULT="https://github.com/dartdavros/MTProto-Installer"
BOOTSTRAP_REPO_REF_DEFAULT="main"
BOOTSTRAP_RUNTIME_ROOT_DEFAULT="/opt/mtproxy-installer"
BOOTSTRAP_RELEASES_DIR_NAME="releases"
BOOTSTRAP_CURRENT_LINK_NAME="current"

bootstrap_script_path="${BASH_SOURCE[0]:-$0}"
bootstrap_script_dir="$(cd "$(dirname "${bootstrap_script_path}")" >/dev/null 2>&1 && pwd)"

bootstrap_err() {
  printf '%s\n' "$*" >&2
}

bootstrap_die() {
  bootstrap_err "$*"
  exit 1
}

bootstrap_runtime_has_layout() {
  local root="$1"
  [[ -n "${root}" ]] || return 1
  [[ -f "${root}/install-mtproxy.sh" ]] || return 1
  [[ -f "${root}/lib/core/constants.sh" ]] || return 1
  [[ -f "${root}/lib/commands/dispatch.sh" ]] || return 1
}

bootstrap_local_runtime_root() {
  if bootstrap_runtime_has_layout "${bootstrap_script_dir}"; then
    printf '%s\n' "${bootstrap_script_dir}"
    return 0
  fi

  if bootstrap_runtime_has_layout "${PWD}"; then
    printf '%s\n' "${PWD}"
    return 0
  fi

  return 1
}

bootstrap_runtime_root_dir() {
  printf '%s\n' "${INSTALLER_RUNTIME_ROOT:-${BOOTSTRAP_RUNTIME_ROOT_DEFAULT}}"
}

bootstrap_current_runtime_link() {
  printf '%s/%s\n' "$(bootstrap_runtime_root_dir)" "${BOOTSTRAP_CURRENT_LINK_NAME}"
}

bootstrap_releases_dir() {
  printf '%s/%s\n' "$(bootstrap_runtime_root_dir)" "${BOOTSTRAP_RELEASES_DIR_NAME}"
}

bootstrap_download_url() {
  local override_url="${INSTALLER_BUNDLE_URL:-}"
  local repo_url="${INSTALLER_REPO_URL:-${BOOTSTRAP_REPO_URL_DEFAULT}}"
  local repo_ref="${INSTALLER_REPO_REF:-${BOOTSTRAP_REPO_REF_DEFAULT}}"

  if [[ -n "${override_url}" ]]; then
    printf '%s\n' "${override_url}"
  else
    printf '%s/archive/refs/heads/%s.tar.gz\n' "${repo_url%/}" "${repo_ref}"
  fi
}

bootstrap_require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || bootstrap_die "Требуется команда ${cmd} для bootstrap-установки"
}

bootstrap_archive_sha256() {
  sha256sum "$1" | awk '{print $1}'
}

bootstrap_verify_archive() {
  local archive_path="$1"
  local expected_sha="${INSTALLER_BUNDLE_SHA256:-}"
  local actual_sha

  bootstrap_require_command sha256sum
  actual_sha="$(bootstrap_archive_sha256 "${archive_path}")"

  if [[ -n "${expected_sha}" && "${actual_sha}" != "${expected_sha}" ]]; then
    bootstrap_die "SHA256 bootstrap bundle не совпал: expected=${expected_sha} actual=${actual_sha}"
  fi

  printf '%s\n' "${actual_sha}"
}

bootstrap_release_id() {
  local archive_sha="$1"
  local explicit_release_id="${INSTALLER_RELEASE_ID:-}"
  local repo_ref="${INSTALLER_REPO_REF:-${BOOTSTRAP_REPO_REF_DEFAULT}}"
  local sanitized_ref

  if [[ -n "${explicit_release_id}" ]]; then
    printf '%s\n' "${explicit_release_id}"
    return 0
  fi

  sanitized_ref="${repo_ref//[^A-Za-z0-9._-]/-}"
  printf 'bootstrap-%s-%s\n' "${sanitized_ref}" "${archive_sha:0:12}"
}

bootstrap_find_extracted_root() {
  local search_root="$1"
  local candidate

  while IFS= read -r -d '' candidate; do
    candidate="$(dirname "${candidate}")"
    if bootstrap_runtime_has_layout "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done < <(find "${search_root}" -type f -name 'install-mtproxy.sh' -print0 | sort -z)

  return 1
}

bootstrap_persist_runtime() {
  local extracted_root="$1"
  local release_id="$2"
  local archive_url="$3"
  local archive_sha="$4"
  local runtime_root releases_dir release_dir current_link

  runtime_root="$(bootstrap_runtime_root_dir)"
  releases_dir="$(bootstrap_releases_dir)"
  current_link="$(bootstrap_current_runtime_link)"
  release_dir="${releases_dir}/${release_id}"

  mkdir -p "${releases_dir}"

  if [[ ! -d "${release_dir}" ]]; then
    local tmp_release_dir
    tmp_release_dir="${release_dir}.tmp.$$"
    rm -rf "${tmp_release_dir}"
    mkdir -p "${tmp_release_dir}"
    cp -a "${extracted_root}/." "${tmp_release_dir}/"
    {
      printf 'SOURCE_URL=%q\n' "${archive_url}"
      printf 'ARCHIVE_SHA256=%q\n' "${archive_sha}"
      printf 'RELEASE_ID=%q\n' "${release_id}"
      printf 'INSTALLED_AT_UTC=%q\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } > "${tmp_release_dir}/.bootstrap-source.env"
    mv "${tmp_release_dir}" "${release_dir}"
  fi

  ln -sfn "${release_dir}" "${current_link}"
  printf '%s\n' "${release_dir}"
}

bootstrap_install_managed_runtime() {
  local archive_url archive_path archive_sha release_id stage_dir extracted_base extracted_root runtime_root

  [[ "${EUID}" -eq 0 ]] || bootstrap_die "Для standalone bootstrap нужен запуск от root: sudo bash ./install-mtproxy.sh"

  bootstrap_require_command curl
  bootstrap_require_command tar
  bootstrap_require_command find
  bootstrap_require_command cp
  bootstrap_require_command mv
  bootstrap_require_command mktemp

  runtime_root="$(bootstrap_runtime_root_dir)"
  stage_dir="$(mktemp -d)"
  trap 'rm -rf "${stage_dir}"' RETURN

  archive_url="$(bootstrap_download_url)"
  archive_path="${stage_dir}/installer-runtime.tar.gz"
  extracted_base="${stage_dir}/extracted"

  bootstrap_err "Bootstrap: загружаю installer runtime из ${archive_url}"
  curl -fsSL "${archive_url}" -o "${archive_path}" || bootstrap_die "Не удалось скачать installer runtime: ${archive_url}"

  archive_sha="$(bootstrap_verify_archive "${archive_path}")"
  release_id="$(bootstrap_release_id "${archive_sha}")"

  if bootstrap_runtime_has_layout "${runtime_root}/${BOOTSTRAP_RELEASES_DIR_NAME}/${release_id}"; then
    ln -sfn "${runtime_root}/${BOOTSTRAP_RELEASES_DIR_NAME}/${release_id}" "$(bootstrap_current_runtime_link)"
    printf '%s\n' "${runtime_root}/${BOOTSTRAP_RELEASES_DIR_NAME}/${release_id}"
    return 0
  fi

  mkdir -p "${extracted_base}"
  tar -xzf "${archive_path}" -C "${extracted_base}" || bootstrap_die "Не удалось распаковать installer runtime"
  extracted_root="$(bootstrap_find_extracted_root "${extracted_base}")" || bootstrap_die "В bootstrap archive не найден корректный installer runtime"
  bootstrap_persist_runtime "${extracted_root}" "${release_id}" "${archive_url}" "${archive_sha}"
}

bootstrap_resolve_runtime_root() {
  local runtime_root

  if runtime_root="$(bootstrap_local_runtime_root 2>/dev/null)"; then
    printf '%s\n' "${runtime_root}"
    return 0
  fi

  runtime_root="$(bootstrap_install_managed_runtime)"
  printf '%s\n' "${runtime_root}"
}

bootstrap_source_runtime() {
  local runtime_root="$1"
  local file

  export BASE_DIR="${runtime_root}"

  while IFS= read -r -d '' file; do
    # shellcheck disable=SC1090
    source "${file}"
  done < <(find "${runtime_root}/lib" -type f -name '*.sh' -print0 | sort -z)
}

bootstrap_entrypoint() {
  local runtime_root

  runtime_root="$(bootstrap_resolve_runtime_root)"
  bootstrap_source_runtime "${runtime_root}"

  if [[ $# -eq 0 ]]; then
    interactive_menu
    set -- "${INTERACTIVE_ARGS[@]}"
  fi

  main "$@"
}

bootstrap_entrypoint "$@"
