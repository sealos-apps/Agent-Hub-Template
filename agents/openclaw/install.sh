#!/usr/bin/env bash
set -euo pipefail

NODE_MAJOR="${NODE_MAJOR:-22}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.5.19}"
AI_AGENT_SWITCH_VERSION="${AI_AGENT_SWITCH_VERSION:-}"
AI_AGENT_SWITCH_SOURCE_URL="${AI_AGENT_SWITCH_SOURCE_URL:-}"
AI_AGENT_SWITCH_SOURCE_REF="${AI_AGENT_SWITCH_SOURCE_REF:-}"
OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/home/agent/.openclaw}"
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"
OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-/workspace}"
OPENCLAW_PLUGIN_STAGE_DIR="${OPENCLAW_PLUGIN_STAGE_DIR:-/opt/openclaw/plugin-runtime-deps}"
OPENCLAW_DEFAULTS_DIR="${OPENCLAW_DEFAULTS_DIR:-/opt/agent/defaults/openclaw}"
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
  if command -v npm >/dev/null 2>&1; then
    return
  fi

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
    install_ai_agent_switch_from_npm
  fi
  verify_ai_agent_switch_agent_hub
}

install_ai_agent_switch_from_npm() {
  local prefix="/opt/ai-agent-switch"
  mkdir -p "$prefix"
  npm install -g --prefix "$prefix" "ai-agent-switch@${AI_AGENT_SWITCH_VERSION}"
  ln -sf "${prefix}/bin/ai-agent-switch" /usr/local/bin/ai-agent-switch
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

write_openclaw_default_config() {
  local target="$1"

  mkdir -p "$(dirname "$target")"
  cat >"$target" <<EOF_JSON
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
      "allowedOrigins": [],
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
EOF_JSON
}

write_default_state() {
  mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE" "$OPENCLAW_PLUGIN_STAGE_DIR" "$OPENCLAW_DEFAULTS_DIR"

  write_openclaw_default_config "${OPENCLAW_DEFAULTS_DIR}/openclaw.json"

  if [[ ! -f "$OPENCLAW_CONFIG_PATH" ]]; then
    cp "${OPENCLAW_DEFAULTS_DIR}/openclaw.json" "$OPENCLAW_CONFIG_PATH"
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
export OPENCLAW_DEFAULT_CONFIG_FILE="${OPENCLAW_DEFAULT_CONFIG_FILE:-/opt/agent/defaults/openclaw/openclaw.json}"
export PATH="/usr/local/bin:${PATH}"

mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE" "$OPENCLAW_PLUGIN_STAGE_DIR"

log() {
  printf '[%s] [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

warn() {
  printf '[%s] [WARN] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

restore_openclaw_config() {
  if [[ -L "$OPENCLAW_CONFIG_PATH" && ! -e "$OPENCLAW_CONFIG_PATH" ]]; then
    rm -f "$OPENCLAW_CONFIG_PATH"
  fi

  if [[ -f "$OPENCLAW_CONFIG_PATH" ]]; then
    return 0
  fi

  if [[ ! -f "$OPENCLAW_DEFAULT_CONFIG_FILE" ]]; then
    printf '[ERROR] missing OpenClaw default config: %s\n' "$OPENCLAW_DEFAULT_CONFIG_FILE" >&2
    exit 1
  fi

  install -m 0644 "$OPENCLAW_DEFAULT_CONFIG_FILE" "$OPENCLAW_CONFIG_PATH"
}

agent_hub_model_type() {
  local api_mode="${AGENT_MODEL_API_MODE:-}"
  case "$api_mode" in
    codex_responses|openai-responses|responses)
      printf 'openai-responses'
      ;;
    anthropic_messages|anthropic)
      printf 'anthropic'
      ;;
    chat_completions|openai_chat|openai-chat-compatible|"")
      case "${AGENT_MODEL_PROVIDER:-}" in
        custom:aiproxy-responses)
          printf 'openai-responses'
          ;;
        custom:aiproxy-anthropic)
          printf 'anthropic'
          ;;
        *)
          printf 'openai-chat-compatible'
          ;;
      esac
      ;;
    image_generation)
      printf 'openai-responses'
      ;;
    *)
      printf 'openai-chat-compatible'
      ;;
  esac
}

agent_hub_provider_id() {
  case "${AGENT_MODEL_PROVIDER:-}" in
    custom:aiproxy-chat)
      printf 'aiproxy-chat'
      ;;
    custom:aiproxy-responses)
      printf 'aiproxy-responses'
      ;;
    custom:aiproxy-anthropic)
      printf 'aiproxy-anthropic'
      ;;
    *)
      printf '%s' "${AGENT_MODEL_PROVIDER:-agent-hub}" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/^custom://; s/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//' \
        | sed -E 's/^$/agent-hub/'
      ;;
  esac
}

agent_hub_provider_name() {
  case "${AGENT_MODEL_PROVIDER:-}" in
    custom:aiproxy-chat)
      printf 'AI Proxy Chat Completions'
      ;;
    custom:aiproxy-responses)
      printf 'AI Proxy Responses'
      ;;
    custom:aiproxy-anthropic)
      printf 'AI Proxy Anthropic Messages'
      ;;
    *)
      printf '%s' "$(agent_hub_provider_id)"
      ;;
  esac
}

ensure_openclaw_gateway_config() {
  node <<'NODE'
const fs = require("fs");
const path = require("path");

const configPath = process.env.OPENCLAW_CONFIG_PATH || path.join(process.env.OPENCLAW_STATE_DIR || "/home/agent/.openclaw", "openclaw.json");
const workspace = process.env.OPENCLAW_WORKSPACE || process.env.AGENT_WORKSPACE || "/workspace";
const gatewayPort = Number(process.env.AGENT_PORT || process.env.OPENCLAW_GATEWAY_PORT || 18789);

function readConfig(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    if (error && error.code === "ENOENT") return {};
    throw error;
  }
}

function originVariants(value) {
  const raw = String(value || "").trim();
  if (!raw) return [];
  const candidates = /^https?:\/\//i.test(raw) ? [raw] : [`https://${raw}`, `http://${raw}`];
  return candidates
    .map((candidate) => {
      try {
        return new URL(candidate).origin;
      } catch {
        return undefined;
      }
    })
    .filter(Boolean);
}

function envOrigins(name) {
  return String(process.env[name] || "")
    .split(",")
    .flatMap(originVariants);
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

const config = readConfig(configPath);
config.gateway = config.gateway && typeof config.gateway === "object" && !Array.isArray(config.gateway)
  ? config.gateway
  : {};
config.gateway.mode = config.gateway.mode || "local";
config.gateway.bind = config.gateway.bind || "lan";
config.gateway.port = Number.isFinite(gatewayPort) && gatewayPort > 0 ? gatewayPort : 18789;
config.gateway.auth = config.gateway.auth && typeof config.gateway.auth === "object" && !Array.isArray(config.gateway.auth)
  ? config.gateway.auth
  : {};
config.gateway.auth.mode = config.gateway.auth.mode || "token";
config.gateway.auth.token = process.env.OPENCLAW_GATEWAY_TOKEN || config.gateway.auth.token || "";

const controlUi = config.gateway.controlUi && typeof config.gateway.controlUi === "object" && !Array.isArray(config.gateway.controlUi)
  ? config.gateway.controlUi
  : {};
const configuredOrigins = Array.isArray(controlUi.allowedOrigins)
  ? controlUi.allowedOrigins.flatMap(originVariants)
  : [];
controlUi.enabled = controlUi.enabled ?? true;
controlUi.allowedOrigins = unique([
  ...configuredOrigins,
  ...envOrigins("OPENCLAW_PUBLIC_ORIGIN"),
  ...envOrigins("OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS"),
]);
controlUi.dangerouslyDisableDeviceAuth = process.env.OPENCLAW_CONTROL_UI_DISABLE_DEVICE_AUTH === "false"
  ? false
  : true;
if (process.env.OPENCLAW_CONTROL_UI_ALLOW_HOST_HEADER_ORIGIN_FALLBACK) {
  controlUi.dangerouslyAllowHostHeaderOriginFallback = process.env.OPENCLAW_CONTROL_UI_ALLOW_HOST_HEADER_ORIGIN_FALLBACK === "true";
}
config.gateway.controlUi = controlUi;

config.agents = config.agents && typeof config.agents === "object" && !Array.isArray(config.agents)
  ? config.agents
  : {};
config.agents.defaults = config.agents.defaults && typeof config.agents.defaults === "object" && !Array.isArray(config.agents.defaults)
  ? config.agents.defaults
  : {};
config.agents.defaults.workspace = config.agents.defaults.workspace || workspace;
config.agents.defaults.model = config.agents.defaults.model && typeof config.agents.defaults.model === "object" && !Array.isArray(config.agents.defaults.model)
  ? config.agents.defaults.model
  : {};
config.agents.defaults.model.primary = config.agents.defaults.model.primary || "openai/gpt-5.4";

config.plugins = config.plugins && typeof config.plugins === "object" && !Array.isArray(config.plugins)
  ? config.plugins
  : {};
config.plugins.entries = config.plugins.entries && typeof config.plugins.entries === "object" && !Array.isArray(config.plugins.entries)
  ? config.plugins.entries
  : {};
for (const name of ["acpx", "bonjour", "browser"]) {
  config.plugins.entries[name] = config.plugins.entries[name] && typeof config.plugins.entries[name] === "object" && !Array.isArray(config.plugins.entries[name])
    ? config.plugins.entries[name]
    : {};
  config.plugins.entries[name].enabled = config.plugins.entries[name].enabled ?? false;
}

fs.mkdirSync(path.dirname(configPath), { recursive: true });
fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
NODE
}

sync_agent_hub_model_config() {
  local provider="${AGENT_MODEL_PROVIDER:-}"
  local base_url="${AGENT_MODEL_BASEURL:-}"
  local model="${AGENT_MODEL:-}"
  local api_key_env
  local model_type
  local provider_id
  local provider_name
  local output

  if [[ -z "$provider" || -z "$base_url" || -z "$model" ]]; then
    warn "skipping Agent Hub model sync because provider, base URL, or model is empty"
    return 0
  fi

  if [[ "$provider" == custom:aiproxy-* ]]; then
    export AIPROXY_API_KEY="${AIPROXY_API_KEY:-${AGENT_MODEL_APIKEY:-}}"
    api_key_env="AIPROXY_API_KEY"
  else
    api_key_env="AGENT_MODEL_APIKEY"
  fi

  if [[ -z "${!api_key_env:-}" ]]; then
    warn "skipping Agent Hub model sync because ${api_key_env} is empty"
    return 0
  fi

  if ! command -v ai-agent-switch >/dev/null 2>&1; then
    warn "skipping Agent Hub model sync because ai-agent-switch is not available"
    return 0
  fi

  model_type="$(agent_hub_model_type)"
  provider_id="$(agent_hub_provider_id)"
  provider_name="$(agent_hub_provider_name)"

  if output="$(
    HOME="${HOME:-/home/agent}" ai-agent-switch agent-hub init \
      --client openclaw \
      --provider-id "$provider_id" \
      --provider-name "$provider_name" \
      --model-type "$model_type" \
      --base-url "$base_url" \
      --api-key-env "$api_key_env" \
      --model "$model" \
      --available-model "${model}:${model_type}" \
      -y \
      --json 2>&1
  )"; then
    log "synced Agent Hub model config for OpenClaw: ${provider_id}/${model} (${model_type})"
  else
    warn "Agent Hub model sync failed: ${output}"
  fi
}

if [[ "$#" -eq 0 ]]; then
  : "${OPENCLAW_GATEWAY_TOKEN:?OPENCLAW_GATEWAY_TOKEN is required}"

  restore_openclaw_config

  umask 077
  printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$OPENCLAW_GATEWAY_TOKEN" >"${OPENCLAW_STATE_DIR}/.env"

  ensure_openclaw_gateway_config
  sync_agent_hub_model_config

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
