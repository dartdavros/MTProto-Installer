# shellcheck shell=bash

usage() {
  cat <<EOF_USAGE
Usage:
  sudo PUBLIC_DOMAIN=proxy.example.com bash $0 install
  sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth bash $0 install
  sudo bash $0 status
  sudo bash $0 acceptance-smoke
  sudo bash $0 health
  sudo bash $0 acceptance-smoke
  sudo bash $0 list-links
  sudo bash $0 share-links
  sudo bash $0 rotate-link <name>
  sudo bash $0 rotate-all-links
  sudo bash $0 list-rotation-backups
  sudo bash $0 restore-rotation-backup <backup-id|latest>
  sudo bash $0 list-install-backups
  sudo bash $0 restore-install-backup <backup-id|latest>
  sudo bash $0 refresh-telegram-config
  sudo bash $0 check-domain
  sudo bash $0 test-decoy
  sudo PUBLIC_DOMAIN=proxy.example.com bash $0 migrate-install
  sudo bash $0 restart
  sudo bash $0 uninstall

Compatibility aliases:
  sudo bash $0 update-config
  sudo bash $0 rotate-secret

Environment variables:
  PUBLIC_DOMAIN=<required on first install>
  PUBLIC_PORT=443
  INTERNAL_PORT=8888
  WORKERS=1
  ENGINE=official|stealth
  PRIMARY_PROFILE=dd|classic (official), ee|dd|classic (stealth)
  LINK_STRATEGY=bundle|per-device
  DEVICE_NAMES=phone,desktop,tablet
  TLS_DOMAIN=<defaults to PUBLIC_DOMAIN>
  DECOY_MODE=disabled|upstream-forward|local-https
  DECOY_TARGET_HOST=<required for DECOY_MODE=upstream-forward>
  DECOY_TARGET_PORT=443
  DECOY_DOMAIN=<defaults to TLS_DOMAIN for local-https>
  DECOY_LOCAL_PORT=10443
  DECOY_CERT_PATH=<optional provided certificate for local-https>
  DECOY_KEY_PATH=<optional provided private key for local-https>
  OFFICIAL_REPO_URL=${OFFICIAL_REPO_URL_DEFAULT}
  OFFICIAL_REPO_BRANCH=${OFFICIAL_REPO_BRANCH_DEFAULT}
  STEALTH_REPO_URL=${STEALTH_REPO_URL_DEFAULT}
  STEALTH_REPO_BRANCH=${STEALTH_REPO_BRANCH_DEFAULT}

Examples:
  sudo PUBLIC_DOMAIN=proxy.example.com bash $0 install
  sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth bash $0 install
  sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth LINK_STRATEGY=per-device DEVICE_NAMES=phone,desktop,tablet bash $0 install
  sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth TLS_DOMAIN=cdn.example.com DECOY_MODE=upstream-forward DECOY_TARGET_HOST=site.example.com DECOY_TARGET_PORT=443 bash $0 install
  sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth DECOY_MODE=local-https DECOY_DOMAIN=www.example.com bash $0 install
  sudo PUBLIC_DOMAIN=proxy.example.com bash $0 check-domain
  sudo PUBLIC_DOMAIN=proxy.example.com bash $0 migrate-install
EOF_USAGE
}
