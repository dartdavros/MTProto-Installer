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

engine_requires_telegram_upstream() {
  [[ "${ENGINE}" == "official" ]]
}

engine_requires_pid_workaround() {
  [[ "${ENGINE}" == "official" ]]
}

build_engine_binary() {
  case "${ENGINE}" in
    official)
      official_build_engine_binary
      ;;
    stealth)
      stealth_build_engine_binary
      ;;
    *)
      die "Неизвестный engine: ${ENGINE}"
      ;;
  esac

  if (( PUBLIC_PORT <= 1024 )); then
    info "Порт ${PUBLIC_PORT} привилегированный: capability будет выдан через systemd unit"
  fi
}

render_engine_runtime_artifacts() {
  case "${ENGINE}" in
    official)
      official_render_runtime_artifacts
      ;;
    stealth)
      stealth_render_runtime_artifacts
      ;;
    *)
      die "Неизвестный engine: ${ENGINE}"
      ;;
  esac
}
