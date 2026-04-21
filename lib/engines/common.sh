# shellcheck shell=bash

engine_source_dir() {
  case "${ENGINE}" in
    official) printf '%s\n' "${OFFICIAL_SRC_DIR}" ;;
    stealth)  printf '%s\n' "${STEALTH_SRC_DIR}" ;;
    *) die "Неизвестный engine: ${ENGINE}" ;;
  esac
}

engine_binary_path() {
  case "${ENGINE}" in
    official) printf '%s\n' "${OFFICIAL_BIN_PATH}" ;;
    stealth)  printf '%s\n' "${STEALTH_BIN_PATH}" ;;
    *) die "Неизвестный engine: ${ENGINE}" ;;
  esac
}

engine_repo_url() {
  case "${ENGINE}" in
    official) printf '%s\n' "${OFFICIAL_REPO_URL}" ;;
    stealth)  printf '%s\n' "${STEALTH_REPO_URL}" ;;
    *) die "Неизвестный engine: ${ENGINE}" ;;
  esac
}

engine_repo_branch() {
  case "${ENGINE}" in
    official) printf '%s\n' "${OFFICIAL_REPO_BRANCH}" ;;
    stealth)  printf '%s\n' "${STEALTH_REPO_BRANCH}" ;;
    *) die "Неизвестный engine: ${ENGINE}" ;;
  esac
}

ensure_packages() {
  local -a packages

  log "Устанавливаю зависимости..."
  apt-get update -y

  packages=(
    git
    curl
    ca-certificates
    build-essential
    libssl-dev
    zlib1g-dev
    xxd
    ufw
    libcap2-bin
    pkg-config
    openssl
    python3
  )

  if [[ "${ENGINE}" == "stealth" ]]; then
    packages+=(cargo rustc)
  fi

  DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

ensure_user_and_dirs() {
  if ! getent group "${RUN_GROUP}" >/dev/null 2>&1; then
    log "Создаю группу ${RUN_GROUP}..."
    groupadd --system "${RUN_GROUP}"
  fi

  if ! id -u "${RUN_USER}" >/dev/null 2>&1; then
    log "Создаю пользователя ${RUN_USER}..."
    useradd \
      --system \
      --home-dir "${STATE_DIR}" \
      --shell /usr/sbin/nologin \
      --gid "${RUN_GROUP}" \
      "${RUN_USER}"
  fi

  mkdir -p \
    "${MANIFEST_DIR}" \
    "${SECRETS_DIR}" \
    "${LINKS_DIR}" \
    "${RUNTIME_DIR}" \
    "${STATE_DIR}" \
    "${LIBEXEC_DIR}" \
    "${STEALTH_TLS_FRONT_DIR}" \
    "${DECOY_CONFIG_DIR}" \
    "${DECOY_CERT_DIR}" \
    "${DECOY_WWW_DIR}"

  chown root:"${RUN_GROUP}" "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}" "${DECOY_CONFIG_DIR}" "${DECOY_CERT_DIR}"
  chmod 750 "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}" "${DECOY_CONFIG_DIR}" "${DECOY_CERT_DIR}"

  chown -R "${RUN_USER}:${RUN_GROUP}" "${STATE_DIR}"
  chmod 750 "${STATE_DIR}" "${STEALTH_TLS_FRONT_DIR}" "${DECOY_WWW_DIR}"
}

clone_or_update_engine_repo() {
  local src_dir repo_url repo_branch

  src_dir="$(engine_source_dir)"
  repo_url="$(engine_repo_url)"
  repo_branch="$(engine_repo_branch)"

  if [[ -d "${src_dir}/.git" ]]; then
    log "Обновляю исходники engine=${ENGINE}..."
    git -C "${src_dir}" fetch --all --tags
    git -C "${src_dir}" checkout "${repo_branch}"
    git -C "${src_dir}" reset --hard "origin/${repo_branch}"
    git -C "${src_dir}" clean -fdx
  else
    log "Клонирую репозиторий engine=${ENGINE}..."
    rm -rf "${src_dir}"
    git clone --branch "${repo_branch}" "${repo_url}" "${src_dir}"
  fi
}

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

build_engine_binary() {
  case "${ENGINE}" in
    official)
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
      ;;
    stealth)
      log "Собираю telemt..."
      cd "${STEALTH_SRC_DIR}"
      cargo build --release
      [[ -x "${STEALTH_SRC_DIR}/target/release/telemt" ]] || die "Бинарник telemt не собран"
      install -m 0755 "${STEALTH_SRC_DIR}/target/release/telemt" "${STEALTH_BIN_PATH}"
      setcap -r "${STEALTH_BIN_PATH}" 2>/dev/null || true
      ;;
  esac

  if (( PUBLIC_PORT <= 1024 )); then
    info "Порт ${PUBLIC_PORT} привилегированный: capability будет выдан через systemd unit"
  fi
}
