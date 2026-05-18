#!/usr/bin/env bash
set -euo pipefail

NODE_MAJOR="${NODE_MAJOR:-22}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.4.24}"
AI_AGENT_SWITCH_VERSION="${AI_AGENT_SWITCH_VERSION:-}"
AI_AGENT_SWITCH_SOURCE_URL="${AI_AGENT_SWITCH_SOURCE_URL:-}"
AI_AGENT_SWITCH_SOURCE_REF="${AI_AGENT_SWITCH_SOURCE_REF:-}"
OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/home/agent/.openclaw}"
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"
OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-/workspace}"
OPENCLAW_PLUGIN_STAGE_DIR="${OPENCLAW_PLUGIN_STAGE_DIR:-/opt/openclaw/plugin-runtime-deps}"
AGENT_HOME="${AGENT_HOME:-/opt/agent}"

log() {
  printf '[%s] [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
  exit 1
}

prepare_install_env() {
  export DEBIAN_FRONTEND=noninteractive
}

install_system_packages() {
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg
  rm -rf /var/lib/apt/lists/*
}

install_node() {
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y --no-install-recommends nodejs
  npm --version >/dev/null 2>&1 || fail "npm was not installed successfully"
}

install_openclaw_runtime() {
  npm install -g "openclaw@${OPENCLAW_VERSION}"
  command -v openclaw >/dev/null 2>&1 || fail "openclaw binary was not installed"
}

install_ai_agent_switch() {
  [[ -n "$AI_AGENT_SWITCH_VERSION" ]] || fail "AI_AGENT_SWITCH_VERSION is required"
  if [[ -n "$AI_AGENT_SWITCH_SOURCE_URL" ]]; then
    install_ai_agent_switch_from_source
  else
    npm install -g "ai-agent-switch@${AI_AGENT_SWITCH_VERSION}"
  fi
  verify_ai_agent_switch_agent_hub
}

install_ai_agent_switch_from_source() {
  local src_dir
  local package_dir
  local target
  target="linux-$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')"
  src_dir="$(mktemp -d)"
  git init "$src_dir"
  (
    cd "$src_dir"
    git remote add origin "$AI_AGENT_SWITCH_SOURCE_URL"
    git fetch --depth 1 origin "${AI_AGENT_SWITCH_SOURCE_REF:-HEAD}"
    git checkout --detach FETCH_HEAD
    npm install -g bun
    bun install --frozen-lockfile
    bun run npm:build-package -- --platform "$target" --out-dir dist/npm-packages --version "$AI_AGENT_SWITCH_VERSION"
  )
  package_dir="$src_dir/dist/npm-packages/ai-agent-switch-$target"
  [[ -x "$package_dir/ai-agent-switch" ]] || fail "ai-agent-switch source binary was not built"
  install -m 0755 "$package_dir/ai-agent-switch" /usr/local/bin/ai-agent-switch
  rm -rf "$src_dir"
}

verify_ai_agent_switch_agent_hub() {
  local verify_home
  local output
  verify_home="$(mktemp -d)"
  output="$(
    HOME="$verify_home" ai-agent-switch agent-hub init \
      --client openclaw \
      --provider-id verify-aiproxy \
      --provider-name Verify \
      --model-type openai-chat-compatible \
      --base-url http://127.0.0.1:1/v1 \
      --api-key-env AIPROXY_API_KEY \
      --model verify-model \
      --available-model verify-model \
      --json
  )" || {
    rm -rf "$verify_home"
    fail "ai-agent-switch agent-hub init verification failed"
  }
  rm -rf "$verify_home"
  printf '%s' "$output" | grep -F '"requiresConfirmation": true' >/dev/null || \
    fail "ai-agent-switch agent-hub init did not return the expected dry-run JSON"
}

write_default_state() {
  mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE" "$OPENCLAW_PLUGIN_STAGE_DIR"

  if [[ ! -f "$OPENCLAW_CONFIG_PATH" ]]; then
    cat >"$OPENCLAW_CONFIG_PATH" <<EOF_JSON
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "auth": {
      "mode": "token"
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
EOF_JSON
  fi
}

install_agent_start() {
  mkdir -p "${AGENT_HOME}/bin"

  cat >"${AGENT_HOME}/bin/start" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-${AGENT_DATA_DIR:-/home/agent/.openclaw}}"
export OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"
export OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-${AGENT_WORKSPACE:-/workspace}}"
export OPENCLAW_PLUGIN_STAGE_DIR="${OPENCLAW_PLUGIN_STAGE_DIR:-/opt/openclaw/plugin-runtime-deps}"
export PATH="/usr/local/bin:${PATH}"

mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE" "$OPENCLAW_PLUGIN_STAGE_DIR"

if [[ "$#" -eq 0 ]]; then
  : "${OPENCLAW_GATEWAY_TOKEN:?OPENCLAW_GATEWAY_TOKEN is required}"

  if [[ ! -f "${OPENCLAW_STATE_DIR}/.env" ]]; then
    umask 077
    printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$OPENCLAW_GATEWAY_TOKEN" >"${OPENCLAW_STATE_DIR}/.env"
  fi

  if [[ ! -f "$OPENCLAW_CONFIG_PATH" ]]; then
    cat >"$OPENCLAW_CONFIG_PATH" <<EOF_JSON
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "auth": {
      "mode": "token"
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
EOF_JSON
  fi

  exec env \
    OPENCLAW_NO_RESPAWN=1 \
    OPENCLAW_SKIP_CHANNELS="${OPENCLAW_SKIP_CHANNELS:-1}" \
    OPENCLAW_DISABLE_BONJOUR="${OPENCLAW_DISABLE_BONJOUR:-1}" \
    openclaw gateway run
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
  prepare_install_env
  install_system_packages
  install_node
  install_openclaw_runtime
  install_ai_agent_switch
  write_default_state
  install_agent_start

  if [[ ! -x "${AGENT_HOME}/bin/start" ]]; then
    fail "agent start file was not installed"
  fi
}

main() {
  local command="${1:-install}"
  shift || true

  case "$command" in
    install|install-agent|agent)
      install_agent "$@"
      ;;
    *)
      fail "unknown install command: ${command}"
      ;;
  esac
}

main "$@"
