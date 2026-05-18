#!/command/with-contenv bash
set -euo pipefail

export AGENT_NAME="${AGENT_NAME:-agent}"
export AGENT_HOME="${AGENT_HOME:-/opt/agent}"
export AGENT_START="${AGENT_START:-${AGENT_HOME}/bin/start}"
export AGENT_DATA_DIR="${AGENT_DATA_DIR:-/home/agent/.${AGENT_NAME}}"
export AGENT_WORKSPACE="${AGENT_WORKSPACE:-/workspace}"
export AGENT_PORT="${AGENT_PORT:-8080}"
export AGENT_LOG_LEVEL="${AGENT_LOG_LEVEL:-info}"
export PATH="${AGENT_HOME}/bin:${PATH}"

mkdir -p "$AGENT_DATA_DIR" "$AGENT_WORKSPACE"
if [[ "$(id -u)" -eq 0 ]] && id -u agent >/dev/null 2>&1; then
  chown agent:agent "$AGENT_DATA_DIR" "$AGENT_WORKSPACE"
fi

run_as_agent() {
  exec runuser --preserve-environment -u agent -- env \
    AGENT_NAME="$AGENT_NAME" \
    AGENT_HOME="$AGENT_HOME" \
    AGENT_START="$AGENT_START" \
    AGENT_DATA_DIR="$AGENT_DATA_DIR" \
    AGENT_WORKSPACE="$AGENT_WORKSPACE" \
    AGENT_PORT="$AGENT_PORT" \
    AGENT_LOG_LEVEL="$AGENT_LOG_LEVEL" \
    HOME=/home/agent \
    PATH="$PATH" \
    "$@"
}

start_agent() {
  if [[ ! -x "$AGENT_START" ]]; then
    printf '[ERROR] missing executable agent start file: %s\n' "$AGENT_START" >&2
    exit 127
  fi

  run_as_agent "$AGENT_START" "$@"
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
