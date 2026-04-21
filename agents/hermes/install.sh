#!/usr/bin/env bash
set -euo pipefail

install_agent() {
  local hermes_git_url="https://github.com/NousResearch/hermes-agent.git"
  local hermes_ref="v2026.4.13"
  local hermes_extras="cron,cli,pty,mcp,acp,web"

  export DEBIAN_FRONTEND=noninteractive

  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    python3 \
    python3-pip \
    python3-venv
  rm -rf /var/lib/apt/lists/*

  mkdir -p /opt/agent/lib /opt/hermes /workspace /home/agent/.hermes

  python3 -m venv /opt/hermes/venv
  source /opt/hermes/venv/bin/activate

  python -m pip install --upgrade pip setuptools wheel

  git clone --depth 1 --branch "$hermes_ref" "$hermes_git_url" /opt/hermes/src
  cd /opt/hermes/src

  python -m pip install --no-cache-dir ".[${hermes_extras}]"

  mkdir -p /home/agent/.hermes
  if [[ ! -f /home/agent/.hermes/config.yaml ]]; then
    cat >/home/agent/.hermes/config.yaml <<'EOF'
model: gpt-5.4
provider: custom
display:
  skin: default
terminal:
  backend: local
EOF
  fi

  if [[ ! -f /home/agent/.hermes/.env ]]; then
    cat >/home/agent/.hermes/.env <<'EOF'
# Populate provider credentials or endpoint configuration before first real use.
# Example custom endpoint values:
# OPENAI_API_KEY=
# OPENAI_BASE_URL=
EOF
  fi
}

main() {
  local command="${1:-install}"
  shift || true

  case "$command" in
    install)
      install_agent "$@"
      ;;
    *)
      printf 'unknown install command: %s\n' "$command" >&2
      exit 1
      ;;
  esac
}

main "$@"
