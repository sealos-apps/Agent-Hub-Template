#!/usr/bin/env bash
set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/opt/agent}"
OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/root/.openclaw}"
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"
OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-/workspace}"
OPENCLAW_DEFAULTS_DIR="${OPENCLAW_DEFAULTS_DIR:-/opt/agent/defaults/openclaw}"
AI_AGENT_SWITCH_INSTALL_URL="${AI_AGENT_SWITCH_INSTALL_URL:-https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh}"
AI_AGENT_SWITCH_LATEST_RELEASE_URL="${AI_AGENT_SWITCH_LATEST_RELEASE_URL:-https://api.github.com/repos/sealos-apps/ai-agent-switch/releases/latest}"

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

install_openclaw() {
  npm install -g openclaw@latest
  command -v openclaw >/dev/null 2>&1 || fail "openclaw was not installed"
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

write_default_config() {
  mkdir -p "$OPENCLAW_DEFAULTS_DIR" "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE"

  cat >"${OPENCLAW_DEFAULTS_DIR}/openclaw.json" <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "auth": {
      "mode": "token"
    },
    "controlUi": {
      "enabled": true,
      "allowedOrigins": ["*"],
      "dangerouslyDisableDeviceAuth": true
    }
  },
  "agents": {
    "defaults": {
      "workspace": "${OPENCLAW_WORKSPACE}",
      "model": {
        "primary": "openai/gpt-5.4"
      }
    }
  },
  "plugins": {
    "entries": {
      "acpx": {
        "enabled": false
      },
      "bonjour": {
        "enabled": false
      },
      "browser": {
        "enabled": false
      }
    }
  }
}
EOF

  install -m 0644 "${OPENCLAW_DEFAULTS_DIR}/openclaw.json" "$OPENCLAW_CONFIG_PATH"
}

write_start_script() {
  mkdir -p "${AGENT_HOME}/bin"

  cat >"${AGENT_HOME}/bin/start" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-${AGENT_DATA_DIR:-/root/.openclaw}}"
export OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"
export OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-${AGENT_WORKSPACE:-/workspace}}"
export OPENCLAW_DEFAULT_CONFIG_FILE="${OPENCLAW_DEFAULT_CONFIG_FILE:-/opt/agent/defaults/openclaw/openclaw.json}"
export PATH="/usr/local/bin:${PATH}"

mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE"

if [[ ! -f "$OPENCLAW_CONFIG_PATH" ]]; then
  install -m 0644 "$OPENCLAW_DEFAULT_CONFIG_FILE" "$OPENCLAW_CONFIG_PATH"
fi

if [[ "$#" -eq 0 ]]; then
  : "${OPENCLAW_GATEWAY_TOKEN:?OPENCLAW_GATEWAY_TOKEN is required}"
  umask 077
  printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$OPENCLAW_GATEWAY_TOKEN" >"${OPENCLAW_STATE_DIR}/.env"
  node <<'NODE'
const fs = require("fs");

const configPath = process.env.OPENCLAW_CONFIG_PATH;
const token = process.env.OPENCLAW_GATEWAY_TOKEN;
const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
config.gateway = config.gateway && typeof config.gateway === "object" && !Array.isArray(config.gateway)
  ? config.gateway
  : {};
config.gateway.auth = config.gateway.auth && typeof config.gateway.auth === "object" && !Array.isArray(config.gateway.auth)
  ? config.gateway.auth
  : {};
config.gateway.auth.mode = "token";
config.gateway.auth.token = token;
fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
NODE
  exec env OPENCLAW_NO_RESPAWN=1 openclaw gateway run
fi

case "$1" in
  openclaw|ai-agent-switch|node|npm|bash|sh)
    exec "$@"
    ;;
  *)
    exec openclaw "$@"
    ;;
esac
EOF

  chmod +x "${AGENT_HOME}/bin/start"
}

install_agent() {
  install_openclaw
  install_ai_agent_switch
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
