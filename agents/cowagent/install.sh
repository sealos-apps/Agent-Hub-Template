#!/usr/bin/env bash
set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/opt/agent}"
COWAGENT_GIT_URL="${COWAGENT_GIT_URL:-https://github.com/zhayujie/CowAgent.git}"
COWAGENT_SRC="${COWAGENT_SRC:-/opt/cowagent/src}"
COWAGENT_VENV="${COWAGENT_VENV:-/opt/cowagent/venv}"
COWAGENT_HOME="${COWAGENT_HOME:-/root/.cowagent}"
COWAGENT_DEFAULTS_DIR="${COWAGENT_DEFAULTS_DIR:-/opt/agent/defaults/cowagent}"
AI_AGENT_SWITCH_INSTALL_URL="${AI_AGENT_SWITCH_INSTALL_URL:-https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh}"

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

install_system_packages() {
  apt-get update
  apt-get install -y --no-install-recommends espeak ffmpeg libavcodec-extra
  rm -rf /var/lib/apt/lists/*
}

install_ai_agent_switch() {
  local install_dir
  install_dir="/opt/ai-agent-switch/bin"

  curl -fsSL "$AI_AGENT_SWITCH_INSTALL_URL" | INSTALL_DIR="$install_dir" sh
  ln -sf "${install_dir}/ai-agent-switch" /usr/local/bin/ai-agent-switch
  command -v ai-agent-switch >/dev/null 2>&1 || fail "ai-agent-switch was not installed"
}

install_cowagent() {
  rm -rf "$COWAGENT_SRC"
  mkdir -p "$(dirname "$COWAGENT_SRC")" "$COWAGENT_HOME"
  git clone --depth 1 "$COWAGENT_GIT_URL" "$COWAGENT_SRC"

  python3 -m venv "$COWAGENT_VENV"
  "$COWAGENT_VENV/bin/python" -m pip install --no-cache-dir --upgrade pip setuptools wheel
  "$COWAGENT_VENV/bin/pip" install --no-cache-dir -r "${COWAGENT_SRC}/requirements.txt"
  "$COWAGENT_VENV/bin/pip" install --no-cache-dir -r "${COWAGENT_SRC}/requirements-optional.txt"
  "$COWAGENT_VENV/bin/pip" install --no-cache-dir -e "$COWAGENT_SRC"
  [[ -x "${COWAGENT_VENV}/bin/cow" ]] || fail "cow was not installed"
}

write_default_config() {
  mkdir -p "$COWAGENT_DEFAULTS_DIR" "$COWAGENT_HOME"

  "$COWAGENT_VENV/bin/python" - <<'PY'
import json
import os
from pathlib import Path

src = Path(os.environ.get("COWAGENT_SRC", "/opt/cowagent/src"))
target = Path(os.environ.get("COWAGENT_DEFAULTS_DIR", "/opt/agent/defaults/cowagent")) / "config.json"
config = json.loads((src / "config-template.json").read_text(encoding="utf-8"))
config.update(
    {
        "channel_type": "web",
        "web_host": "0.0.0.0",
        "web_port": 9899,
        "agent": True,
        "agent_workspace": "/workspace",
        "appdata_dir": "/root/.cowagent/appdata",
        "speech_recognition": False,
        "group_speech_recognition": False,
    }
)
target.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

  install -m 0644 "${COWAGENT_DEFAULTS_DIR}/config.json" "${COWAGENT_HOME}/config.json"
}

write_start_script() {
  mkdir -p "${AGENT_HOME}/bin"

  cat >"${AGENT_HOME}/bin/start" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export COWAGENT_SRC="${COWAGENT_SRC:-/opt/cowagent/src}"
export COWAGENT_HOME="${COWAGENT_HOME:-${AGENT_DATA_DIR:-/root/.cowagent}}"
export COWAGENT_CONFIG_FILE="${COWAGENT_CONFIG_FILE:-${COWAGENT_HOME}/config.json}"
export COWAGENT_DEFAULT_CONFIG_FILE="${COWAGENT_DEFAULT_CONFIG_FILE:-/opt/agent/defaults/cowagent/config.json}"
export COWAGENT_VENV="${COWAGENT_VENV:-/opt/cowagent/venv}"
export PATH="${COWAGENT_VENV}/bin:${PATH}"

mkdir -p "$COWAGENT_HOME" "${AGENT_WORKSPACE:-/workspace}"

if [[ ! -f "$COWAGENT_CONFIG_FILE" ]]; then
  install -m 0644 "$COWAGENT_DEFAULT_CONFIG_FILE" "$COWAGENT_CONFIG_FILE"
fi

rm -f "${COWAGENT_SRC}/config.json"
ln -s "$COWAGENT_CONFIG_FILE" "${COWAGENT_SRC}/config.json"

export channel_type="${COWAGENT_CHANNEL_TYPE:-web}"
export web_port="${COWAGENT_WEB_PORT:-${AGENT_PORT:-9899}}"
export agent_workspace="${COWAGENT_AGENT_WORKSPACE:-${AGENT_WORKSPACE:-/workspace}}"
export appdata_dir="${COWAGENT_APPDATA_DIR:-${COWAGENT_HOME}/appdata}"
export web_password="${COWAGENT_WEB_PASSWORD:-}"
export agent="${COWAGENT_AGENT:-true}"

cd "$COWAGENT_SRC"

if [[ "$#" -eq 0 ]]; then
  exec python app.py
fi

case "$1" in
  app|serve)
    shift
    exec python app.py "$@"
    ;;
  --*)
    exec python app.py "$@"
    ;;
  cow|ai-agent-switch|python|python3|bash|sh)
    exec "$@"
    ;;
  *)
    exec cow "$@"
    ;;
esac
EOF

  chmod +x "${AGENT_HOME}/bin/start"
}

install_agent() {
  install_system_packages
  install_ai_agent_switch
  install_cowagent
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
