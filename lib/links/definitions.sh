# shellcheck shell=bash

fallback_profile_for_primary() {
  case "${ENGINE}:${PRIMARY_PROFILE}" in
    official:dd) printf 'classic\n' ;;
    official:classic) printf 'dd\n' ;;
    stealth:ee) printf 'dd\n' ;;
    stealth:dd) printf 'classic\n' ;;
    stealth:classic) printf 'dd\n' ;;
    *) die "Неизвестная комбинация ENGINE/PRIMARY_PROFILE: ${ENGINE}/${PRIMARY_PROFILE}" ;;
  esac
}

render_managed_link_definitions() {
  local fallback_profile
  local device
  local created=0

  case "${LINK_STRATEGY}" in
    bundle)
      case "${ENGINE}:${PRIMARY_PROFILE}" in
        official:dd)
          printf 'primary-dd\tdd\nreserve-dd\tdd\nfallback-classic\tclassic\n'
          ;;
        official:classic)
          printf 'primary-classic\tclassic\nreserve-classic\tclassic\nfallback-dd\tdd\n'
          ;;
        stealth:ee)
          printf 'primary-ee\tee\nreserve-ee\tee\nfallback-dd\tdd\n'
          ;;
        stealth:dd)
          printf 'primary-dd\tdd\nreserve-dd\tdd\nfallback-classic\tclassic\n'
          ;;
        stealth:classic)
          printf 'primary-classic\tclassic\nreserve-classic\tclassic\nfallback-dd\tdd\n'
          ;;
        *)
          die "Неизвестная комбинация ENGINE/PRIMARY_PROFILE: ${ENGINE}/${PRIMARY_PROFILE}"
          ;;
      esac
      ;;
    per-device)
      fallback_profile="$(fallback_profile_for_primary)"
      IFS=',' read -r -a devices <<< "${DEVICE_NAMES}"
      for device in "${devices[@]}"; do
        [[ -n "${device}" ]] || continue
        printf '%s-%s\t%s\n' "${device}" "${PRIMARY_PROFILE}" "${PRIMARY_PROFILE}"
        created=1
      done

      (( created == 1 )) || die "Не удалось построить per-device definitions: пустой DEVICE_NAMES"
      printf 'shared-fallback-%s\t%s\n' "${fallback_profile}" "${fallback_profile}"
      ;;
    *)
      die "Неизвестная стратегия ссылок: ${LINK_STRATEGY}"
      ;;
  esac
}

write_managed_link_definitions() {
  local tmp_path

  tmp_path="${LINK_DEFINITIONS_PATH}.tmp"
  render_managed_link_definitions > "${tmp_path}"

  if [[ -f "${LINK_DEFINITIONS_PATH}" ]] && cmp -s "${tmp_path}" "${LINK_DEFINITIONS_PATH}"; then
    rm -f "${tmp_path}"
    info "Link definitions уже актуальны"
    return 0
  fi

  if [[ -f "${LINK_DEFINITIONS_PATH}" ]]; then
    log "Обновляю модель ссылок (${LINK_STRATEGY})..."
  else
    log "Создаю модель ссылок (${LINK_STRATEGY})..."
  fi

  mv "${tmp_path}" "${LINK_DEFINITIONS_PATH}"
}
