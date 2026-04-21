#!/usr/bin/env bash
set -euo pipefail

export AGENT_NAME="${AGENT_NAME:-hermes}"
source /opt/agent/config.sh

export HERMES_HOME="${HERMES_HOME:-/home/agent/.hermes}"
export PATH="/opt/hermes/venv/bin:${PATH}"

start_agent() {
  exec hermes "$@"
}

main() {
  local command="${1:-start}"
  shift || true

  case "$command" in
    shell)
      exec /bin/bash "$@"
      ;;
    config)
      exec /opt/agent/config.sh "$@"
      ;;
    start)
      start_agent "$@"
      ;;
    *)
      start_agent "$command" "$@"
      ;;
  esac
}

main "$@"
