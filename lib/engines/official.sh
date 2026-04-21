# shellcheck shell=bash

patch_makefile_if_needed() {
  local makefile="${OFFICIAL_SRC_DIR}/Makefile"

  [[ -f "${makefile}" ]] || die "Не найден Makefile: ${makefile}"

  if grep -q -- '-fcommon' "${makefile}"; then
    info "Makefile уже содержит -fcommon"
    return 0
  fi

  warn "Добавляю -fcommon в Makefile как fallback для новых GCC..."
  sed -i \
    -e '/^COMMON_CFLAGS[[:space:]]*=/ s/$/ -fcommon/' \
    -e '/^COMMON_LDFLAGS[[:space:]]*=/ s/$/ -fcommon/' \
    "${makefile}"
}

official_build_engine_binary() {
  log "Собираю official MTProxy..."
  cd "${OFFICIAL_SRC_DIR}"

  if ! make; then
    warn "Первая сборка official MTProxy не удалась, пробую с patch + clean..."
    patch_makefile_if_needed
    make clean || true
    make
  fi

  [[ -x "${OFFICIAL_SRC_DIR}/objs/bin/mtproto-proxy" ]] || die "Бинарник official MTProxy не собран"
  install -m 0755 "${OFFICIAL_SRC_DIR}/objs/bin/mtproto-proxy" "${OFFICIAL_BIN_PATH}"
  setcap -r "${OFFICIAL_BIN_PATH}" 2>/dev/null || true
}

official_render_runtime_artifacts() {
  rm -f "${STEALTH_CONFIG_PATH}"
}
