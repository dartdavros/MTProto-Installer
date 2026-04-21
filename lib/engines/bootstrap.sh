# shellcheck shell=bash

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
    "${ROTATION_BACKUPS_DIR}" \
    "${LIBEXEC_DIR}" \
    "${STEALTH_TLS_FRONT_DIR}" \
    "${DECOY_CONFIG_DIR}" \
    "${DECOY_CERT_DIR}" \
    "${DECOY_WWW_DIR}"

  chown root:"${RUN_GROUP}" "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}" "${DECOY_CONFIG_DIR}" "${DECOY_CERT_DIR}"
  chmod 750 "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}" "${DECOY_CONFIG_DIR}" "${DECOY_CERT_DIR}"

  chown -R "${RUN_USER}:${RUN_GROUP}" "${STATE_DIR}"
  chown root:"${RUN_GROUP}" "${ROTATION_BACKUPS_DIR}"
  chmod 750 "${STATE_DIR}" "${ROTATION_BACKUPS_DIR}" "${STEALTH_TLS_FRONT_DIR}" "${DECOY_WWW_DIR}"
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
