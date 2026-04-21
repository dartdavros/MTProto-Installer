# shellcheck shell=bash

log()  { echo -e "${GREEN}[*]${NC} $*"; }

info() { echo -e "${BLUE}[-]${NC} $*"; }

warn() { echo -e "${YELLOW}[!]${NC} $*"; }

err()  { echo -e "${RED}[x]${NC} $*" >&2; }

die() {
  err "$*"
  exit 1
}

quote_kv() {
  local key="$1"
  local value="$2"
  printf '%s=%q\n' "${key}" "${value}"
}
