# shellcheck shell=bash

validate_runtime_settings() {
  validate_port "${PUBLIC_PORT}"
  validate_port "${INTERNAL_PORT}"
  validate_port "${DECOY_LOCAL_PORT}"

  [[ "${WORKERS}" =~ ^[0-9]+$ ]] || die "WORKERS должен быть числом"
  (( WORKERS >= 1 )) || die "WORKERS должен быть >= 1"
}

validate_install_contract() {
  if [[ -n "${PUBLIC_PORT:-}" && -n "${PORT:-}" && "${PUBLIC_PORT}" != "${PORT}" ]]; then
    die "Заданы конфликтующие PUBLIC_PORT=${PUBLIC_PORT} и PORT=${PORT}"
  fi

  validate_domain "${PUBLIC_DOMAIN}"
  validate_domain "${TLS_DOMAIN}"
  validate_runtime_settings

  case "${ENGINE}" in
    official)
      case "${PRIMARY_PROFILE}" in
        dd|classic)
          ;;
        *)
          die "Для ENGINE=official поддерживаются только PRIMARY_PROFILE=dd|classic"
          ;;
      esac

      case "${DECOY_MODE}" in
        disabled)
          ;;
        *)
          die "Для ENGINE=official decoy не поддержан. Используй DECOY_MODE=disabled"
          ;;
      esac
      ;;
    stealth)
      case "${PRIMARY_PROFILE}" in
        ee|dd|classic)
          ;;
        *)
          die "Для ENGINE=stealth поддерживаются только PRIMARY_PROFILE=ee|dd|classic"
          ;;
      esac

      case "${DECOY_MODE}" in
        disabled)
          ;;
        upstream-forward)
          validate_host_or_ip "${DECOY_TARGET_HOST}"
          validate_port "${DECOY_TARGET_PORT}"
          ;;
        local-https)
          validate_domain "${DECOY_DOMAIN}"
          validate_port "${DECOY_LOCAL_PORT}"
          [[ "${DECOY_LOCAL_PORT}" != "${PUBLIC_PORT}" ]] || die "DECOY_LOCAL_PORT должен отличаться от PUBLIC_PORT"

          if [[ -n "${DECOY_CERT_SOURCE_PATH}" || -n "${DECOY_KEY_SOURCE_PATH}" ]]; then
            [[ -n "${DECOY_CERT_SOURCE_PATH}" && -n "${DECOY_KEY_SOURCE_PATH}" ]] || die "Для DECOY_MODE=local-https нужно задать одновременно DECOY_CERT_PATH и DECOY_KEY_PATH"
            [[ -f "${DECOY_CERT_SOURCE_PATH}" ]] || die "Не найден DECOY_CERT_PATH: ${DECOY_CERT_SOURCE_PATH}"
            [[ -f "${DECOY_KEY_SOURCE_PATH}" ]] || die "Не найден DECOY_KEY_PATH: ${DECOY_KEY_SOURCE_PATH}"
          fi
          ;;
        *)
          die "Поддерживаются только DECOY_MODE=disabled|upstream-forward|local-https"
          ;;
      esac
      ;;
    *)
      die "Поддерживаются только ENGINE=official|stealth"
      ;;
  esac

  case "${LINK_STRATEGY}" in
    bundle)
      ;;
    per-device)
      [[ -n "${DEVICE_NAMES}" ]] || die "Для LINK_STRATEGY=per-device требуется DEVICE_NAMES=phone,desktop,tablet"
      ;;
    *)
      die "Поддерживаются только LINK_STRATEGY=bundle|per-device"
      ;;
  esac
}
