#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-change-me}"
AGENT_CONFIG_HOME="${AGENT_CONFIG_HOME:-/home/agent/.config/${AGENT_NAME}}"
CURRENT_RESOURCE=""
CURRENT_ACTION=""

log() {
  printf '[%s] [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

json_quote() {
  # Template helper only. Swap this for the agent's native runtime if Python is not installed.
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "${1-}"
}

json_success() {
  local resource="${1:-$CURRENT_RESOURCE}"
  local action="${2:-$CURRENT_ACTION}"
  local applied="${3:-true}"
  local data="${4:-}"
  [[ -n "$data" ]] || data='{}'

  printf '{"ok":true,"resource":%s,"action":%s,"applied":%s,"data":%s}\n' \
    "$(json_quote "$resource")" \
    "$(json_quote "$action")" \
    "$applied" \
    "$data"
}

json_error() {
  local resource="${1:-$CURRENT_RESOURCE}"
  local action="${2:-$CURRENT_ACTION}"
  local code="${3:-error}"
  local message="${4:-unknown error}"

  printf '{"ok":false,"resource":%s,"action":%s,"error":{"code":%s,"message":%s}}\n' \
    "$(json_quote "$resource")" \
    "$(json_quote "$action")" \
    "$(json_quote "$code")" \
    "$(json_quote "$message")"
}

fail() {
  local message="$*"
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$message" >&2
  json_error "$CURRENT_RESOURCE" "$CURRENT_ACTION" "invalid_config" "$message"
  exit 1
}

ensure_agent_config_home() {
  mkdir -p "$AGENT_CONFIG_HOME"
}

ensure_agent_state() {
  ensure_agent_config_home
}

run_as_agent_script() {
  if [[ "$(id -u)" -eq 0 ]] && [[ "${AGENT_CONFIG_AS_AGENT:-1}" == "1" ]]; then
    exec runuser -u agent -- env \
      AGENT_CONFIG_AS_AGENT=0 \
      AGENT_NAME="$AGENT_NAME" \
      AGENT_CONFIG_HOME="$AGENT_CONFIG_HOME" \
      /opt/agent/config.sh "$@"
  fi
}

usage() {
  json_error "" "" "usage" "usage: config.sh <resource> <action> [args...]"
  exit 1
}

dispatch_config() {
  local resource="${1:?missing resource}"
  local action="${2:?missing action}"
  shift 2 || true

  case "${resource}:${action}" in
    replace-me-resource:replace-me-action)
      fail "replace this action with the target agent's native config operation"
      ;;
    replace-me-resource:replace-me-read)
      json_success "$resource" "$action" true '{}'
      ;;
    *)
      fail "unknown config command: ${resource} ${action}"
      ;;
  esac
}

main() {
  CURRENT_RESOURCE="${1:-}"
  CURRENT_ACTION="${2:-}"

  [[ -n "$CURRENT_RESOURCE" && -n "$CURRENT_ACTION" ]] || usage

  run_as_agent_script "$@"
  ensure_agent_state
  dispatch_config "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
