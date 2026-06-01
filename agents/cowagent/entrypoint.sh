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
AI_AGENT_SWITCH_INSTALL_URL="${AI_AGENT_SWITCH_INSTALL_URL:-https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh}"

mkdir -p "$AGENT_DATA_DIR" "$AGENT_WORKSPACE"

refresh_ai_agent_switch() {
  local install_dir="/opt/ai-agent-switch/bin"
  local tmp_script

  if ! tmp_script="$(mktemp)"; then
    printf '[WARN] ai-agent-switch refresh failed; using bundled version: ' >&2
    ai-agent-switch --version >&2 || true
    return 0
  fi
  if curl --connect-timeout 5 --max-time 30 --retry 2 --retry-delay 1 -fsSL "$AI_AGENT_SWITCH_INSTALL_URL" -o "$tmp_script" && sh "$tmp_script" --install-dir "$install_dir"; then
    ln -sf "${install_dir}/ai-agent-switch" /usr/local/bin/ai-agent-switch || true
    printf '[INFO] ai-agent-switch refreshed: '
    ai-agent-switch --version || true
  else
    printf '[WARN] ai-agent-switch refresh failed; using bundled version: ' >&2
    ai-agent-switch --version >&2 || true
  fi
  rm -f "$tmp_script" || true
}

start_agent() {
  if [[ ! -x "$AGENT_START" ]]; then
    printf '[ERROR] missing executable agent start file: %s\n' "$AGENT_START" >&2
    exit 127
  fi

  refresh_ai_agent_switch
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
