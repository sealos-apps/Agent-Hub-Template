#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-change-me}"

log() {
  printf '[%s] [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
  exit 1
}

set_config() {
  fail "set_config is not implemented for ${AGENT_NAME}; received args: $*"
}

get_config() {
  fail "get_config is not implemented for ${AGENT_NAME}; received args: $*"
}

delete_config() {
  fail "delete_config is not implemented for ${AGENT_NAME}; received args: $*"
}

list_config() {
  fail "list_config is not implemented for ${AGENT_NAME}; received args: $*"
}

dispatch_config_action() {
  local action="${1:?missing action}"
  shift || true

  case "$action" in
    set)
      set_config "$@"
      ;;
    get)
      get_config "$@"
      ;;
    delete)
      delete_config "$@"
      ;;
    list)
      list_config "$@"
      ;;
    *)
      fail "unknown config action: ${action}"
      ;;
  esac
}

main() {
  local action="${1:-list}"
  local resource="${2:-config}"

  shift || true
  shift || true

  case "$resource" in
    config)
      dispatch_config_action "$action" "$@"
      ;;
    *)
      fail "unknown config resource: ${resource}"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
