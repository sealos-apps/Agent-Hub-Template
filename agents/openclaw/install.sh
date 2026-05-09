#!/usr/bin/env bash
set -euo pipefail

NODE_MAJOR="${NODE_MAJOR:-22}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.4.24}"
OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/home/agent/.openclaw}"
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"
OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-/workspace}"
OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-change-me-local-dev}"

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

write_default_state() {
  mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE"

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

  if [[ ! -f "${OPENCLAW_STATE_DIR}/.env" ]]; then
    cat >"${OPENCLAW_STATE_DIR}/.env" <<EOF_ENV
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
EOF_ENV
  fi
}

install_agent() {
  prepare_install_env
  install_system_packages
  install_node
  install_openclaw_runtime
  write_default_state
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
