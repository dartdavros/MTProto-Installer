# shellcheck shell=bash

INTERACTIVE_ARGS=()

manifest_default_value() {
  local key="$1"
  local value=""

  [[ -f "${MANIFEST_PATH}" ]] || return 1

  value="$({
    # shellcheck disable=SC1090
    source "${MANIFEST_PATH}"
    printf '%s' "${!key-}"
  } 2>/dev/null)" || return 1

  [[ -n "${value}" ]] || return 1
  printf '%s\n' "${value}"
}

prompt_with_default() {
  local prompt="$1"
  local default_value="${2-}"
  local answer=""

  if [[ -n "${default_value}" ]]; then
    read -r -p "${prompt} [${default_value}]: " answer
    printf '%s\n' "${answer:-${default_value}}"
  else
    read -r -p "${prompt}: " answer
    printf '%s\n' "${answer}"
  fi
}

interactive_prompt_install_contract() {
  local current_domain current_engine current_public_port current_link_strategy current_tls_domain
  local current_decoy_mode current_decoy_target_host current_decoy_target_port current_decoy_domain current_decoy_local_port

  current_domain="${PUBLIC_DOMAIN:-$(manifest_default_value PUBLIC_DOMAIN 2>/dev/null || true)}"
  current_engine="${ENGINE:-$(manifest_default_value ENGINE 2>/dev/null || true)}"
  current_public_port="${PUBLIC_PORT:-$(manifest_default_value PUBLIC_PORT 2>/dev/null || true)}"
  current_link_strategy="${LINK_STRATEGY:-$(manifest_default_value LINK_STRATEGY 2>/dev/null || true)}"
  current_tls_domain="${TLS_DOMAIN:-$(manifest_default_value TLS_DOMAIN 2>/dev/null || true)}"
  current_decoy_mode="${DECOY_MODE:-$(manifest_default_value DECOY_MODE 2>/dev/null || true)}"
  current_decoy_target_host="${DECOY_TARGET_HOST:-$(manifest_default_value DECOY_TARGET_HOST 2>/dev/null || true)}"
  current_decoy_target_port="${DECOY_TARGET_PORT:-$(manifest_default_value DECOY_TARGET_PORT 2>/dev/null || true)}"
  current_decoy_domain="${DECOY_DOMAIN:-$(manifest_default_value DECOY_DOMAIN 2>/dev/null || true)}"
  current_decoy_local_port="${DECOY_LOCAL_PORT:-$(manifest_default_value DECOY_LOCAL_PORT 2>/dev/null || true)}"

  export PUBLIC_DOMAIN="$(prompt_with_default 'Основной домен PUBLIC_DOMAIN' "${current_domain}")"
  export ENGINE="$(prompt_with_default 'ENGINE (official|stealth)' "${current_engine:-stealth}")"
  export PUBLIC_PORT="$(prompt_with_default 'Публичный порт PUBLIC_PORT' "${current_public_port:-443}")"
  export LINK_STRATEGY="$(prompt_with_default 'Стратегия ссылок LINK_STRATEGY (bundle|per-device)' "${current_link_strategy:-bundle}")"

  if [[ "${LINK_STRATEGY}" == "per-device" ]]; then
    export DEVICE_NAMES="$(prompt_with_default 'DEVICE_NAMES через запятую' "${DEVICE_NAMES:-$(manifest_default_value DEVICE_NAMES 2>/dev/null || true)}")"
  else
    unset DEVICE_NAMES || true
  fi

  if [[ "${ENGINE}" == "stealth" ]]; then
    export TLS_DOMAIN="$(prompt_with_default 'TLS_DOMAIN для ee-профиля' "${current_tls_domain:-${PUBLIC_DOMAIN}}")"
    export DECOY_MODE="$(prompt_with_default 'DECOY_MODE (disabled|upstream-forward|local-https)' "${current_decoy_mode:-disabled}")"

    case "${DECOY_MODE}" in
      upstream-forward)
        export DECOY_TARGET_HOST="$(prompt_with_default 'DECOY_TARGET_HOST' "${current_decoy_target_host}")"
        export DECOY_TARGET_PORT="$(prompt_with_default 'DECOY_TARGET_PORT' "${current_decoy_target_port:-443}")"
        unset DECOY_DOMAIN DECOY_LOCAL_PORT || true
        ;;
      local-https)
        export DECOY_DOMAIN="$(prompt_with_default 'DECOY_DOMAIN' "${current_decoy_domain:-${TLS_DOMAIN}}")"
        export DECOY_LOCAL_PORT="$(prompt_with_default 'DECOY_LOCAL_PORT' "${current_decoy_local_port:-10443}")"
        unset DECOY_TARGET_HOST DECOY_TARGET_PORT || true
        ;;
      disabled)
        export DECOY_MODE=disabled
        unset DECOY_TARGET_HOST DECOY_TARGET_PORT DECOY_DOMAIN DECOY_LOCAL_PORT || true
        ;;
      *)
        die "Поддерживаются только DECOY_MODE=disabled|upstream-forward|local-https"
        ;;
    esac
  else
    export DECOY_MODE=disabled
    unset TLS_DOMAIN DECOY_TARGET_HOST DECOY_TARGET_PORT DECOY_DOMAIN DECOY_LOCAL_PORT || true
  fi
}

interactive_menu() {
  local choice command_name argument=""

  cat <<'EOF_MENU'
MTProxy Installer

1) install
2) status
3) health
4) share-links
5) list-links
6) rotate-link
7) rotate-all-links
8) refresh-telegram-config
9) restart
10) check-domain
11) test-decoy
12) migrate-install
13) uninstall
0) exit
EOF_MENU

  read -r -p 'Выбор [1]: ' choice
  choice="${choice:-1}"

  case "${choice}" in
    1|install)
      command_name="install"
      interactive_prompt_install_contract
      ;;
    2|status)
      command_name="status"
      ;;
    3|health)
      command_name="health"
      ;;
    4|share-links)
      command_name="share-links"
      ;;
    5|list-links)
      command_name="list-links"
      ;;
    6|rotate-link)
      command_name="rotate-link"
      argument="$(prompt_with_default 'Имя ссылки для ротации' '')"
      [[ -n "${argument}" ]] || die 'Нужно указать имя ссылки для rotate-link'
      ;;
    7|rotate-all-links)
      command_name="rotate-all-links"
      ;;
    8|refresh-telegram-config)
      command_name="refresh-telegram-config"
      ;;
    9|restart)
      command_name="restart"
      ;;
    10|check-domain)
      command_name="check-domain"
      export PUBLIC_DOMAIN="$(prompt_with_default 'Основной домен PUBLIC_DOMAIN' "${PUBLIC_DOMAIN:-$(manifest_default_value PUBLIC_DOMAIN 2>/dev/null || true)}")"
      ;;
    11|test-decoy)
      command_name="test-decoy"
      ;;
    12|migrate-install)
      command_name="migrate-install"
      interactive_prompt_install_contract
      ;;
    13|uninstall)
      command_name="uninstall"
      ;;
    0|exit|quit|q)
      exit 0
      ;;
    *)
      die "Неизвестный выбор: ${choice}"
      ;;
  esac

  INTERACTIVE_ARGS=("${command_name}")
  if [[ -n "${argument}" ]]; then
    INTERACTIVE_ARGS+=("${argument}")
  fi
}
