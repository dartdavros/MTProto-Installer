# shellcheck shell=bash

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Запусти от root: sudo bash $0 <command>"
}

require_installed() {
  [[ -f "${MANIFEST_PATH}" ]] || die "Установка не найдена: отсутствует ${MANIFEST_PATH}"
  load_manifest
}
