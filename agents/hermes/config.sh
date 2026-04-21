#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-hermes}"
HERMES_CONFIG_HOME="${HERMES_CONFIG_HOME:-/home/agent/.hermes}"
HERMES_CONFIG_FILE="${HERMES_CONFIG_FILE:-${HERMES_CONFIG_HOME}/config.runtime.env}"

log() {
  printf '[%s] [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
  exit 1
}

ensure_config_store() {
  mkdir -p "$HERMES_CONFIG_HOME"
  touch "$HERMES_CONFIG_FILE"
}

write_config_value() {
  local key="${1:?missing key}"
  local value="${2:-}"
  local temp_file=""
  local found=0

  ensure_config_store
  temp_file="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "${key}="* ]]; then
      printf '%s=%s\n' "$key" "$value" >>"$temp_file"
      found=1
    else
      printf '%s\n' "$line" >>"$temp_file"
    fi
  done <"$HERMES_CONFIG_FILE"

  if [[ "$found" -eq 0 ]]; then
    printf '%s=%s\n' "$key" "$value" >>"$temp_file"
  fi

  mv "$temp_file" "$HERMES_CONFIG_FILE"
}

set_config() {
  local endpoint="${1:?missing endpoint}"
  local api_key="${2:?missing api key}"
  local model="${3:-gpt-5.4}"

  write_config_value HERMES_BASE_URL "$endpoint"
  write_config_value HERMES_API_KEY "$api_key"
  write_config_value HERMES_MODEL "$model"
  log "updated Hermes runtime config"
}

get_config() {
  ensure_config_store
  cat "$HERMES_CONFIG_FILE"
}

delete_config() {
  rm -f "$HERMES_CONFIG_FILE"
  log "deleted Hermes runtime config"
}

list_config() {
  get_config "$@"
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
