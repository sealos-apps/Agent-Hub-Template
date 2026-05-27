#!/usr/bin/env bash
set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/opt/agent}"
HERMES_GIT_URL="${HERMES_GIT_URL:-https://github.com/NousResearch/hermes-agent.git}"
HERMES_SRC="${HERMES_SRC:-/opt/hermes/src}"
HERMES_VENV="${HERMES_VENV:-/opt/hermes/venv}"
HERMES_HOME="${HERMES_HOME:-/root/.hermes}"
HERMES_DEFAULTS_DIR="${HERMES_DEFAULTS_DIR:-/opt/agent/defaults/hermes}"
UV_BIN="${UV_BIN:-/usr/local/bin/uv}"
AI_AGENT_SWITCH_INSTALL_URL="${AI_AGENT_SWITCH_INSTALL_URL:-https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh}"
AI_AGENT_SWITCH_LATEST_RELEASE_URL="${AI_AGENT_SWITCH_LATEST_RELEASE_URL:-https://api.github.com/repos/sealos-apps/ai-agent-switch/releases/latest}"

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

install_system_packages() {
  apt-get update
  apt-get install -y --no-install-recommends ffmpeg
  rm -rf /var/lib/apt/lists/*
}

install_ai_agent_switch() {
  local version
  local install_dir
  install_dir="/opt/ai-agent-switch/bin"
  version="$(
    curl -fsSL "$AI_AGENT_SWITCH_LATEST_RELEASE_URL" \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n 1
  )"
  [[ -n "$version" ]] || fail "failed to resolve latest ai-agent-switch release"

  curl -fsSL "$AI_AGENT_SWITCH_INSTALL_URL" | sh -s -- "$version" --install-dir "$install_dir"
  ln -sf "${install_dir}/ai-agent-switch" /usr/local/bin/ai-agent-switch
  command -v ai-agent-switch >/dev/null 2>&1 || fail "ai-agent-switch was not installed"
}

install_hermes() {
  rm -rf "$HERMES_SRC"
  mkdir -p "$(dirname "$HERMES_SRC")" "$HERMES_HOME"
  git clone --depth 1 "$HERMES_GIT_URL" "$HERMES_SRC"

  cd "$HERMES_SRC"
  "$UV_BIN" venv "$HERMES_VENV" --python 3.11
  "$UV_BIN" pip install --python "${HERMES_VENV}/bin/python" -e ".[all]"
  [[ -x "${HERMES_VENV}/bin/hermes" ]] || fail "hermes was not installed"
}

write_default_config() {
  mkdir -p "$HERMES_DEFAULTS_DIR" "$HERMES_HOME"

  cat >"${HERMES_DEFAULTS_DIR}/config.yaml" <<'EOF'
model:
  default: gpt-5.4
  provider: auto
display:
  skin: default
terminal:
  backend: local
EOF

  cat >"${HERMES_DEFAULTS_DIR}/.env" <<'EOF'
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
EOF

  install -m 0644 "${HERMES_DEFAULTS_DIR}/config.yaml" "${HERMES_HOME}/config.yaml"
  install -m 0600 "${HERMES_DEFAULTS_DIR}/.env" "${HERMES_HOME}/.env"
}

write_start_script() {
  mkdir -p "${AGENT_HOME}/bin"

  cat >"${AGENT_HOME}/bin/start" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export HERMES_HOME="${HERMES_HOME:-${AGENT_DATA_DIR:-/root/.hermes}}"
export HERMES_VENV="${HERMES_VENV:-/opt/hermes/venv}"
export HERMES_DEFAULT_CONFIG_FILE="${HERMES_DEFAULT_CONFIG_FILE:-/opt/agent/defaults/hermes/config.yaml}"
export HERMES_DEFAULT_ENV_FILE="${HERMES_DEFAULT_ENV_FILE:-/opt/agent/defaults/hermes/.env}"
export PATH="${HERMES_VENV}/bin:${PATH}"
export API_SERVER_ENABLED="${API_SERVER_ENABLED:-true}"
export API_SERVER_HOST="${API_SERVER_HOST:-0.0.0.0}"
export API_SERVER_PORT="${API_SERVER_PORT:-${AGENT_PORT:-8642}}"

mkdir -p "$HERMES_HOME" "${AGENT_WORKSPACE:-/workspace}"

if [[ ! -f "${HERMES_HOME}/config.yaml" ]]; then
  install -m 0644 "$HERMES_DEFAULT_CONFIG_FILE" "${HERMES_HOME}/config.yaml"
fi

if [[ ! -f "${HERMES_HOME}/.env" ]]; then
  install -m 0600 "$HERMES_DEFAULT_ENV_FILE" "${HERMES_HOME}/.env"
fi

if [[ "$#" -eq 0 ]]; then
  : "${API_SERVER_KEY:?API_SERVER_KEY is required}"
  exec hermes gateway run
fi

case "$1" in
  hermes|ai-agent-switch|python|python3|bash|sh)
    exec "$@"
    ;;
  *)
    exec hermes "$@"
    ;;
esac
EOF

  chmod +x "${AGENT_HOME}/bin/start"
}

install_agent() {
  install_system_packages
  install_ai_agent_switch
  install_hermes
  write_default_config
  write_start_script
}

main() {
  case "${1:-install}" in
    install)
      install_agent
      ;;
    *)
      fail "unknown install command: $1"
      ;;
  esac
}

main "$@"
