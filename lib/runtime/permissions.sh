# shellcheck shell=bash

apply_permissions() {
  log "Применяю права..."

  chown root:"${RUN_GROUP}" "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}"
  chmod 750 "${CONFIG_ROOT}" "${MANIFEST_DIR}" "${SECRETS_DIR}" "${LINKS_DIR}" "${RUNTIME_DIR}"

  [[ -f "${MANIFEST_PATH}" ]] && chown root:"${RUN_GROUP}" "${MANIFEST_PATH}" && chmod 0640 "${MANIFEST_PATH}"
  [[ -f "${PROXY_SECRET_PATH}" ]] && chown root:"${RUN_GROUP}" "${PROXY_SECRET_PATH}" && chmod 0640 "${PROXY_SECRET_PATH}"
  [[ -f "${PROXY_MULTI_CONF_PATH}" ]] && chown root:"${RUN_GROUP}" "${PROXY_MULTI_CONF_PATH}" && chmod 0640 "${PROXY_MULTI_CONF_PATH}"
  [[ -f "${STEALTH_CONFIG_PATH}" ]] && chown root:"${RUN_GROUP}" "${STEALTH_CONFIG_PATH}" && chmod 0640 "${STEALTH_CONFIG_PATH}"
  [[ -f "${LINK_DEFINITIONS_PATH}" ]] && chown root:"${RUN_GROUP}" "${LINK_DEFINITIONS_PATH}" && chmod 0640 "${LINK_DEFINITIONS_PATH}"
  [[ -f "${LINK_BUNDLE_PATH}" ]] && chown root:"${RUN_GROUP}" "${LINK_BUNDLE_PATH}" && chmod 0640 "${LINK_BUNDLE_PATH}"
  [[ -f "${REFRESH_STATE_PATH}" ]] && chown root:"${RUN_GROUP}" "${REFRESH_STATE_PATH}" && chmod 0640 "${REFRESH_STATE_PATH}"
  [[ -f "${DECOY_MANAGED_CERT_PATH}" ]] && chown root:"${RUN_GROUP}" "${DECOY_MANAGED_CERT_PATH}" && chmod 0640 "${DECOY_MANAGED_CERT_PATH}"
  [[ -f "${DECOY_MANAGED_KEY_PATH}" ]] && chown root:"${RUN_GROUP}" "${DECOY_MANAGED_KEY_PATH}" && chmod 0640 "${DECOY_MANAGED_KEY_PATH}"

  if compgen -G "${SECRETS_DIR}/*.secret" >/dev/null; then
    chown root:"${RUN_GROUP}" "${SECRETS_DIR}"/*.secret
    chmod 0640 "${SECRETS_DIR}"/*.secret
  fi

  [[ -f "${RUNNER_PATH}" ]] && chown root:"${RUN_GROUP}" "${RUNNER_PATH}" && chmod 0750 "${RUNNER_PATH}"
  [[ -f "${REFRESH_HELPER_PATH}" ]] && chown root:"${RUN_GROUP}" "${REFRESH_HELPER_PATH}" && chmod 0750 "${REFRESH_HELPER_PATH}"
  [[ -f "${DECOY_SERVER_PATH}" ]] && chown root:"${RUN_GROUP}" "${DECOY_SERVER_PATH}" && chmod 0750 "${DECOY_SERVER_PATH}"

  chown -R "${RUN_USER}:${RUN_GROUP}" "${STATE_DIR}"
  chown root:"${RUN_GROUP}" "${ROTATION_BACKUPS_DIR}" "${INSTALL_BACKUPS_DIR}"
  chmod 750 "${STATE_DIR}" "${ROTATION_BACKUPS_DIR}" "${INSTALL_BACKUPS_DIR}" "${STEALTH_TLS_FRONT_DIR}" "${DECOY_WWW_DIR}"

  if [[ -d "${ROTATION_BACKUPS_DIR}" ]]; then
    find "${ROTATION_BACKUPS_DIR}" -mindepth 1 -type d -exec chown root:"${RUN_GROUP}" {} +
    find "${ROTATION_BACKUPS_DIR}" -mindepth 1 -type d -exec chmod 750 {} +
  fi

  if compgen -G "${ROTATION_BACKUPS_DIR}/*/metadata.env" >/dev/null; then
    chown root:"${RUN_GROUP}" "${ROTATION_BACKUPS_DIR}"/*/metadata.env
    chmod 0640 "${ROTATION_BACKUPS_DIR}"/*/metadata.env
  fi

  if compgen -G "${ROTATION_BACKUPS_DIR}/*/links/*" >/dev/null; then
    chown root:"${RUN_GROUP}" "${ROTATION_BACKUPS_DIR}"/*/links/*
    chmod 0640 "${ROTATION_BACKUPS_DIR}"/*/links/*
  fi

  if compgen -G "${ROTATION_BACKUPS_DIR}/*/secrets/*.secret" >/dev/null; then
    chown root:"${RUN_GROUP}" "${ROTATION_BACKUPS_DIR}"/*/secrets/*.secret
    chmod 0640 "${ROTATION_BACKUPS_DIR}"/*/secrets/*.secret
  fi

  if [[ -d "${INSTALL_BACKUPS_DIR}" ]]; then
    find "${INSTALL_BACKUPS_DIR}" -mindepth 1 -type d -exec chown root:"${RUN_GROUP}" {} +
    find "${INSTALL_BACKUPS_DIR}" -mindepth 1 -type d -exec chmod 750 {} +
  fi

  if compgen -G "${INSTALL_BACKUPS_DIR}/*/metadata.env" >/dev/null; then
    chown root:"${RUN_GROUP}" "${INSTALL_BACKUPS_DIR}"/*/metadata.env
    chmod 0640 "${INSTALL_BACKUPS_DIR}"/*/metadata.env
  fi

  if [[ -d "${INSTALL_BACKUPS_DIR}" ]]; then
    find "${INSTALL_BACKUPS_DIR}" -mindepth 2 -type d -path '*/config-root*' -exec chown root:"${RUN_GROUP}" {} +
    find "${INSTALL_BACKUPS_DIR}" -mindepth 2 -type d -path '*/config-root*' -exec chmod 750 {} +
  fi

  if compgen -G "${INSTALL_BACKUPS_DIR}/*/config-root/*" >/dev/null; then
    find "${INSTALL_BACKUPS_DIR}" -mindepth 3 -type f -path '*/config-root/*' -exec chown root:"${RUN_GROUP}" {} +
    find "${INSTALL_BACKUPS_DIR}" -mindepth 3 -type f -path '*/config-root/*' -exec chmod 0640 {} +
  fi

  if compgen -G "${INSTALL_BACKUPS_DIR}/*/systemd/*" >/dev/null; then
    chown root:"${RUN_GROUP}" "${INSTALL_BACKUPS_DIR}"/*/systemd/*
    chmod 0640 "${INSTALL_BACKUPS_DIR}"/*/systemd/*
  fi

  if compgen -G "${INSTALL_BACKUPS_DIR}/*/libexec/*" >/dev/null; then
    chown root:"${RUN_GROUP}" "${INSTALL_BACKUPS_DIR}"/*/libexec/*
    chmod 0750 "${INSTALL_BACKUPS_DIR}"/*/libexec/*
  fi

  if compgen -G "${INSTALL_BACKUPS_DIR}/*/bin/*" >/dev/null; then
    chown root:"${RUN_GROUP}" "${INSTALL_BACKUPS_DIR}"/*/bin/*
    chmod 0750 "${INSTALL_BACKUPS_DIR}"/*/bin/*
  fi

  if compgen -G "${INSTALL_BACKUPS_DIR}/*/sysctl/*" >/dev/null; then
    chown root:"${RUN_GROUP}" "${INSTALL_BACKUPS_DIR}"/*/sysctl/*
    chmod 0640 "${INSTALL_BACKUPS_DIR}"/*/sysctl/*
  fi

  if [[ -L "${INSTALL_BACKUP_LATEST_LINK}" ]]; then
    chown -h root:"${RUN_GROUP}" "${INSTALL_BACKUP_LATEST_LINK}"
  fi
}
