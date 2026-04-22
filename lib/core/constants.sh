# shellcheck shell=bash

APP_NAME="MTProxy Installer"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

RUN_USER="mtproxy"
RUN_GROUP="mtproxy"

CONFIG_ROOT="/etc/mtproxy"
MANIFEST_DIR="${CONFIG_ROOT}/config"
SECRETS_DIR="${CONFIG_ROOT}/secrets"
LINKS_DIR="${CONFIG_ROOT}/links"
RUNTIME_DIR="${CONFIG_ROOT}/runtime"
DECOY_CONFIG_DIR="${CONFIG_ROOT}/decoy"
DECOY_CERT_DIR="${CONFIG_ROOT}/certs"

MANIFEST_PATH="${MANIFEST_DIR}/manifest.env"
PROXY_SECRET_PATH="${RUNTIME_DIR}/proxy-secret"
PROXY_MULTI_CONF_PATH="${RUNTIME_DIR}/proxy-multi.conf"
STEALTH_CONFIG_PATH="${RUNTIME_DIR}/telemt.toml"
LINK_DEFINITIONS_PATH="${LINKS_DIR}/definitions.tsv"
LINK_BUNDLE_PATH="${LINKS_DIR}/bundle.tsv"
REFRESH_STATE_PATH="${RUNTIME_DIR}/refresh-state.env"
DECOY_MANAGED_CERT_PATH="${DECOY_CERT_DIR}/decoy.crt"
DECOY_MANAGED_KEY_PATH="${DECOY_CERT_DIR}/decoy.key"

STATE_DIR="/var/lib/mtproxy"
ROTATION_BACKUPS_DIR="${STATE_DIR}/rotation-backups"
ROTATION_BACKUP_LATEST_LINK="${ROTATION_BACKUPS_DIR}/latest"
INSTALL_BACKUPS_DIR="${STATE_DIR}/install-backups"
INSTALL_BACKUP_LATEST_LINK="${INSTALL_BACKUPS_DIR}/latest"
STEALTH_TLS_FRONT_DIR="${STATE_DIR}/tls-front"
DECOY_WWW_DIR="${STATE_DIR}/decoy-www"

LIBEXEC_DIR="/usr/local/libexec/mtproxy"
RUNNER_PATH="${LIBEXEC_DIR}/mtproxy-runner.sh"
REFRESH_HELPER_PATH="${LIBEXEC_DIR}/mtproxy-refresh.sh"
DECOY_SERVER_PATH="${LIBEXEC_DIR}/mtproxy-decoy-server.py"

OFFICIAL_SRC_DIR="/usr/local/src/mtproxy-official"
STEALTH_SRC_DIR="/usr/local/src/mtproxy-stealth"
OFFICIAL_BIN_PATH="/usr/local/bin/mtproto-proxy"
STEALTH_BIN_PATH="/usr/local/bin/telemt"

SERVICE_NAME="mtproxy.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
REFRESH_SERVICE_NAME="mtproxy-refresh.service"
REFRESH_SERVICE_PATH="/etc/systemd/system/${REFRESH_SERVICE_NAME}"
REFRESH_TIMER_NAME="mtproxy-refresh.timer"
REFRESH_TIMER_PATH="/etc/systemd/system/${REFRESH_TIMER_NAME}"
DECOY_SERVICE_NAME="mtproxy-decoy.service"
DECOY_SERVICE_PATH="/etc/systemd/system/${DECOY_SERVICE_NAME}"

SYSCTL_FILE="/etc/sysctl.d/99-mtproxy-installer.conf"

LEGACY_SECRET_PATH="${CONFIG_ROOT}/secret"
LEGACY_PROXY_SECRET_PATH="${CONFIG_ROOT}/proxy-secret"
LEGACY_PROXY_MULTI_CONF_PATH="${CONFIG_ROOT}/proxy-multi.conf"

OFFICIAL_REPO_URL_DEFAULT="https://github.com/TelegramMessenger/MTProxy.git"
OFFICIAL_REPO_BRANCH_DEFAULT="master"
STEALTH_REPO_URL_DEFAULT="https://github.com/telemt/telemt.git"
STEALTH_REPO_BRANCH_DEFAULT="main"
