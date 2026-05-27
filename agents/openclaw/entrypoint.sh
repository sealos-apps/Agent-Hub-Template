#!/command/with-contenv bash
set -euo pipefail

export AGENT_NAME="${AGENT_NAME:-agent}"
export AGENT_HOME="${AGENT_HOME:-/opt/agent}"
export AGENT_START="${AGENT_START:-${AGENT_HOME}/bin/start}"
export AGENT_DATA_DIR="${AGENT_DATA_DIR:-/root/.${AGENT_NAME}}"
export AGENT_WORKSPACE="${AGENT_WORKSPACE:-/workspace}"
export AGENT_PORT="${AGENT_PORT:-8080}"
export AGENT_LOG_LEVEL="${AGENT_LOG_LEVEL:-info}"
export PATH="${AGENT_HOME}/bin:${PATH}"

mkdir -p "$AGENT_DATA_DIR" "$AGENT_WORKSPACE"

start_agent() {
  if [[ ! -x "$AGENT_START" ]]; then
    printf '[ERROR] missing executable agent start file: %s\n' "$AGENT_START" >&2
    exit 127
  fi

  exec "$AGENT_START" "$@"
}

main() {
  local command="${1:-start}"
  shift || true

  case "$command" in
    shell)
      exec /bin/bash "$@"
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
