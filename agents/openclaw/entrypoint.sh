#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-openclaw}"
OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/home/agent/.openclaw}"
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"
OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-/workspace}"
OPENCLAW_PLUGIN_STAGE_DIR="${OPENCLAW_PLUGIN_STAGE_DIR:-/opt/openclaw/plugin-runtime-deps}"
PATH="/usr/local/bin:${PATH}"

# shellcheck disable=SC1091
source /opt/agent/config.sh

fail() {
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
  exit 1
}

run_as_agent() {
  exec runuser -u agent -- env \
    HOME=/home/agent \
    OPENCLAW_STATE_DIR="$OPENCLAW_STATE_DIR" \
    OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG_PATH" \
    OPENCLAW_WORKSPACE="$OPENCLAW_WORKSPACE" \
    OPENCLAW_PLUGIN_STAGE_DIR="$OPENCLAW_PLUGIN_STAGE_DIR" \
    PATH="$PATH" \
    "$@"
}

ensure_agent_ownership() {
  if [[ "$(id -u)" -eq 0 ]]; then
    if [[ -e "$OPENCLAW_STATE_DIR" ]] && [[ "$(stat -c '%U:%G' "$OPENCLAW_STATE_DIR")" != "agent:agent" ]]; then
      chown agent:agent "$OPENCLAW_STATE_DIR"
    fi
    find "$OPENCLAW_STATE_DIR" -mindepth 1 -maxdepth 1 \( ! -user agent -o ! -group agent \) -exec chown agent:agent {} +
    if [[ -e "$OPENCLAW_WORKSPACE" ]] && [[ "$(stat -c '%U:%G' "$OPENCLAW_WORKSPACE")" != "agent:agent" ]]; then
      chown agent:agent "$OPENCLAW_WORKSPACE"
    fi
  fi
}

start_agent() {
  [[ "$#" -eq 0 ]] || fail "openclaw start does not accept extra arguments in phase 1"
  run_as_agent env \
    OPENCLAW_NO_RESPAWN=1 \
    OPENCLAW_SKIP_CHANNELS="${OPENCLAW_SKIP_CHANNELS:-1}" \
    OPENCLAW_DISABLE_BONJOUR="${OPENCLAW_DISABLE_BONJOUR:-1}" \
    openclaw gateway run
}

run_agent_cli() {
  [[ "$#" -gt 0 ]] || fail "openclaw run requires native CLI arguments"
  run_as_agent openclaw "$@"
}

main() {
  local command="${1:-start}"
  shift || true

  ensure_openclaw_state
  ensure_agent_ownership

  case "$command" in
    start)
      start_agent "$@"
      ;;
    run)
      run_agent_cli "$@"
      ;;
    config)
      exec /opt/agent/config.sh "$@"
      ;;
    shell)
      exec /bin/bash "$@"
      ;;
    *)
      fail "unknown command: ${command}. expected one of: start, run, config, shell"
      ;;
  esac
}

main "$@"
