#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-change-me}"
AGENT_RUNTIME_KIND="${AGENT_RUNTIME_KIND:-service}"

log() {
  printf '[%s] [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
  exit 1
}

run_as_agent() {
  exec runuser -u agent -- "$@"
}

ensure_agent_state() {
  mkdir -p /workspace
}

start_service_agent() {
  [[ "$#" -eq 0 ]] || fail "${AGENT_NAME} start does not accept extra arguments in phase 1"
  fail "replace start_service_agent in this agent's entrypoint.sh with the real long-running process"
}

bootstrap_tool_agent() {
  [[ "$#" -eq 0 ]] || fail "${AGENT_NAME} start does not accept extra arguments in phase 1"
  log "replace bootstrap_tool_agent in this agent's entrypoint.sh with real bootstrap logic"
  exec tail -f /dev/null
}

run_agent_cli() {
  [[ "$#" -gt 0 ]] || fail "${AGENT_NAME} run requires native CLI arguments"
  fail "replace run_agent_cli in this agent's entrypoint.sh with the real upstream CLI"
}

start_agent() {
  case "$AGENT_RUNTIME_KIND" in
    service)
      start_service_agent "$@"
      ;;
    tool)
      bootstrap_tool_agent "$@"
      ;;
    *)
      fail "unknown AGENT_RUNTIME_KIND: ${AGENT_RUNTIME_KIND}"
      ;;
  esac
}

main() {
  local command="${1:-start}"
  shift || true

  ensure_agent_state

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
