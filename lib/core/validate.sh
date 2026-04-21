# shellcheck shell=bash

validate_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || die "Некорректный порт: ${value}"
  (( value >= 1 && value <= 65535 )) || die "Порт вне диапазона 1..65535: ${value}"
}

validate_domain() {
  local value="$1"
  [[ -n "${value}" ]] || die "Требуется непустой домен"
  [[ "${value}" =~ ^[A-Za-z0-9.-]+$ ]] || die "Некорректный домен: ${value}"
  [[ "${value}" != .* && "${value}" != *..* && "${value}" != *-.* && "${value}" != *.-* ]] || die "Некорректный домен: ${value}"
}

validate_host_or_ip() {
  local value="$1"
  [[ -n "${value}" ]] || die "Требуется host/ip"
  [[ "${value}" =~ ^[A-Za-z0-9._:-]+$ ]] || die "Некорректный host/ip: ${value}"
}
