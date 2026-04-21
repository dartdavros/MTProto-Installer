# shellcheck shell=bash

restart_service_command() {
  require_root
  require_installed
  restart_managed_runtime
  status
}

main() {
  local cmd="${1:-}"
  local arg="${2:-}"

  case "${cmd}" in
    install)
      install_all
      ;;
    update-config|refresh-telegram-config)
      refresh_telegram_config
      ;;
    rotate-secret)
      rotate_secret_legacy_alias
      ;;
    rotate-link)
      rotate_link "${arg}"
      ;;
    rotate-all-links)
      rotate_all_links
      ;;
    list-rotation-backups)
      list_rotation_backups
      ;;
    restore-rotation-backup)
      restore_rotation_backup "${arg}"
      ;;
    list-install-backups)
      list_install_backups
      ;;
    restore-install-backup)
      restore_install_backup "${arg}"
      ;;
    check-domain)
      check_domain_command
      ;;
    test-decoy)
      test_decoy_command
      ;;
    migrate-install)
      migrate_install
      ;;
    restart)
      restart_service_command
      ;;
    status)
      status
      ;;
    health)
      health
      ;;
    acceptance-smoke)
      acceptance_smoke
      ;;
    share-links)
      share_links
      ;;
    list-links)
      list_links
      ;;
    uninstall)
      uninstall_all
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}
