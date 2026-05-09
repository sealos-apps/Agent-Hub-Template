#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-openclaw}"
OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/home/agent/.openclaw}"
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"
OPENCLAW_DOTENV_FILE="${OPENCLAW_DOTENV_FILE:-${OPENCLAW_STATE_DIR}/.env}"
OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-change-me-local-dev}"
OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-/workspace}"
OPENCLAW_PLUGIN_STAGE_DIR="${OPENCLAW_PLUGIN_STAGE_DIR:-/opt/openclaw/plugin-runtime-deps}"
PATH="/usr/local/bin:${PATH}"
CURRENT_RESOURCE=""
CURRENT_ACTION=""

json_quote() {
  node -e 'process.stdout.write(JSON.stringify(process.argv[1] ?? ""))' "${1-}"
}

json_success() {
  local resource="${1:-$CURRENT_RESOURCE}"
  local action="${2:-$CURRENT_ACTION}"
  local applied="${3:-true}"
  local data="${4:-}"

  [[ -n "$data" ]] || data='{}'
  printf '{"ok":true,"resource":%s,"action":%s,"applied":%s,"data":%s}\n' \
    "$(json_quote "$resource")" \
    "$(json_quote "$action")" \
    "$applied" \
    "$data"
}

json_error() {
  local resource="${1:-$CURRENT_RESOURCE}"
  local action="${2:-$CURRENT_ACTION}"
  local code="${3:-error}"
  local message="${4:-unknown error}"

  printf '{"ok":false,"resource":%s,"action":%s,"error":{"code":%s,"message":%s}}\n' \
    "$(json_quote "$resource")" \
    "$(json_quote "$action")" \
    "$(json_quote "$code")" \
    "$(json_quote "$message")"
}

fail() {
  local message="$*"
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$message" >&2
  json_error "$CURRENT_RESOURCE" "$CURRENT_ACTION" "invalid_config" "$message"
  exit 1
}

require_arg() {
  local value="${1-}"
  local name="${2:-argument}"
  [[ -n "$value" ]] || fail "missing ${name}"
}

run_as_agent_script() {
  if [[ "$(id -u)" -eq 0 ]] && [[ "${OPENCLAW_CONFIG_AS_AGENT:-1}" == "1" ]]; then
    ensure_openclaw_state
    ensure_agent_ownership
    exec runuser -u agent -- env \
      OPENCLAW_CONFIG_AS_AGENT=0 \
      AGENT_NAME="$AGENT_NAME" \
      OPENCLAW_STATE_DIR="$OPENCLAW_STATE_DIR" \
      OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG_PATH" \
      OPENCLAW_DOTENV_FILE="$OPENCLAW_DOTENV_FILE" \
      OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
      OPENCLAW_WORKSPACE="$OPENCLAW_WORKSPACE" \
      OPENCLAW_PLUGIN_STAGE_DIR="$OPENCLAW_PLUGIN_STAGE_DIR" \
      HOME=/home/agent \
      PATH="$PATH" \
      /opt/agent/config.sh "$@"
  fi
}

ensure_agent_ownership() {
  if [[ -e "$OPENCLAW_STATE_DIR" ]] && [[ "$(stat -c '%U:%G' "$OPENCLAW_STATE_DIR")" != "agent:agent" ]]; then
    chown agent:agent "$OPENCLAW_STATE_DIR"
  fi
  find "$OPENCLAW_STATE_DIR" -mindepth 1 -maxdepth 1 \( ! -user agent -o ! -group agent \) -exec chown agent:agent {} +
  if [[ -e "$OPENCLAW_WORKSPACE" ]] && [[ "$(stat -c '%U:%G' "$OPENCLAW_WORKSPACE")" != "agent:agent" ]]; then
    chown agent:agent "$OPENCLAW_WORKSPACE"
  fi
}

ensure_openclaw_state() {
  mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE"
  chmod 700 "$OPENCLAW_STATE_DIR"

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

  if [[ ! -f "$OPENCLAW_DOTENV_FILE" ]]; then
    printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$OPENCLAW_GATEWAY_TOKEN" >"$OPENCLAW_DOTENV_FILE"
  fi
  chmod 600 "$OPENCLAW_CONFIG_PATH" "$OPENCLAW_DOTENV_FILE"
}

openclaw_cli() {
  HOME=/home/agent \
  OPENCLAW_STATE_DIR="$OPENCLAW_STATE_DIR" \
  OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG_PATH" \
  OPENCLAW_PLUGIN_STAGE_DIR="$OPENCLAW_PLUGIN_STAGE_DIR" \
  PATH="$PATH" \
  openclaw "$@"
}

openclaw_cli_with_timeout() {
  local seconds="${1:?missing timeout seconds}"
  shift

  command_timeout "$seconds" env \
    HOME=/home/agent \
    OPENCLAW_STATE_DIR="$OPENCLAW_STATE_DIR" \
    OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG_PATH" \
    OPENCLAW_PLUGIN_STAGE_DIR="$OPENCLAW_PLUGIN_STAGE_DIR" \
    PATH="$PATH" \
    openclaw "$@"
}

command_timeout() {
  local seconds="${1:?missing timeout seconds}"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout -k 5s "${seconds}s" "$@"
    return
  fi

  "$@"
}

dotenv_set() {
  local key="${1:?missing key}"
  local value="${2:-}"
  local temp_file
  local found=0

  ensure_openclaw_state
  temp_file="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "${key}="* ]]; then
      printf '%s=%s\n' "$key" "$value" >>"$temp_file"
      found=1
    else
      printf '%s\n' "$line" >>"$temp_file"
    fi
  done <"$OPENCLAW_DOTENV_FILE"

  if [[ "$found" -eq 0 ]]; then
    printf '%s=%s\n' "$key" "$value" >>"$temp_file"
  fi

  mv "$temp_file" "$OPENCLAW_DOTENV_FILE"
}

dotenv_delete() {
  local key="${1:?missing key}"
  local temp_file

  ensure_openclaw_state
  temp_file="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" != "${key}="* ]]; then
      printf '%s\n' "$line" >>"$temp_file"
    fi
  done <"$OPENCLAW_DOTENV_FILE"

  mv "$temp_file" "$OPENCLAW_DOTENV_FILE"
}

dotenv_json() {
  node - "$OPENCLAW_DOTENV_FILE" "$@" <<'NODE'
const fs = require('fs');
const [file, command, key] = process.argv.slice(2);
const values = {};
if (fs.existsSync(file)) {
  for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#') || !line.includes('=')) continue;
    const idx = line.indexOf('=');
    values[line.slice(0, idx)] = line.slice(idx + 1);
  }
}
const status = (currentKey) => {
  const value = values[currentKey];
  const configured = Boolean(value);
  return { key: currentKey, configured, masked: configured ? '********' : null };
};
if (command === 'get') {
  process.stdout.write(JSON.stringify(status(key)));
} else if (command === 'list') {
  process.stdout.write(JSON.stringify({ values: Object.fromEntries(Object.entries(values).map(([k]) => [k, status(k)])) }));
} else {
  throw new Error(`unknown dotenv command: ${command}`);
}
NODE
}

build_provider_payload() {
  local current_json="${1:-}"
  local base_url="${2:-}"
  local api_mode="${3:-}"
  node - "$current_json" "$base_url" "$api_mode" <<'NODE'
const [currentJson, baseUrl, apiMode] = process.argv.slice(2);
const payload = currentJson ? JSON.parse(currentJson) : {};
if (!Array.isArray(payload.models)) payload.models = [];
if (baseUrl) payload.baseUrl = baseUrl;
if (apiMode) payload.api = apiMode;
process.stdout.write(JSON.stringify(payload));
NODE
}

gateway_health_url() {
  node - "$OPENCLAW_CONFIG_PATH" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
let port = 18789;
try {
  const config = JSON.parse(fs.readFileSync(file, 'utf8'));
  const rawPort = config?.gateway?.port;
  if (Number.isInteger(rawPort) && rawPort > 0) {
    port = rawPort;
  }
} catch {
  // Keep the default gateway port when config is not readable yet.
}
	process.stdout.write(`http://127.0.0.1:${port}/readyz`);
NODE
}

wait_for_gateway_ready() {
  local wait_seconds="${OPENCLAW_RUNTIME_APPLY_WAIT_SECONDS:-30}"
  local timeout_ms="${OPENCLAW_GATEWAY_HEALTH_TIMEOUT_MS:-3000}"
  local timeout_seconds=$(( (timeout_ms + 999) / 1000 ))
  local url

  for _ in $(seq 1 "$((wait_seconds + 1))"); do
	    url="$(gateway_health_url 2>/dev/null || printf 'http://127.0.0.1:18789/readyz')"
    if command_timeout "$((timeout_seconds + 1))" curl --noproxy '*' -fsS --max-time "$timeout_seconds" "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

gateway_call_json() {
  local method="${1:?missing gateway method}"
  local params="${2:-}"
  local call_timeout_ms="${OPENCLAW_GATEWAY_CALL_TIMEOUT_MS:-30000}"
  local call_timeout_seconds=$(( (call_timeout_ms + 999) / 1000 + 5 ))
  [[ -n "$params" ]] || params='{}'
  openclaw_cli_with_timeout "$call_timeout_seconds" gateway call "$method" \
    --params "$params" \
    --json \
    --timeout "$call_timeout_ms"
}

gateway_config_patch_json() {
  local raw_patch="${1:?missing config patch}"
  local snapshot
  local params

  snapshot="$(gateway_call_json config.get '{}')" || return 1
  params="$(node - "$raw_patch" "$snapshot" <<'NODE'
const [rawPatch, snapshotRaw] = process.argv.slice(2);
const snapshot = JSON.parse(snapshotRaw);
const baseHash = snapshot.hash || snapshot.configHash || snapshot.persistedHash;
if (!baseHash) {
  throw new Error('config.get did not return a base hash');
}
process.stdout.write(JSON.stringify({
  raw: rawPatch,
  baseHash,
  restartDelayMs: 0,
  note: 'Devbox adapter config update',
}));
NODE
)" || return 1

  gateway_call_json config.patch "$params"
}

patch_result_has_restart() {
  local patch_result="${1:-}"
  node - "$patch_result" <<'NODE'
const raw = process.argv[2] || '{}';
try {
  const payload = JSON.parse(raw);
  process.exit(payload && typeof payload === 'object' && payload.restart ? 0 : 1);
} catch {
  process.exit(1);
}
NODE
}

mark_patch_restart_recovered() {
  local patch_result="${1:-}"
  [[ -n "$patch_result" ]] || patch_result='{}'
  node - "$patch_result" <<'NODE'
const raw = process.argv[2] || '{}';
let payload;
try {
  payload = JSON.parse(raw);
} catch {
  payload = {};
}
if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
  payload = {};
}
const restart = payload.restart && typeof payload.restart === 'object' && !Array.isArray(payload.restart)
  ? payload.restart
  : {};
payload.restart = {
  ...restart,
  recovered: true,
  recovery: 'gateway_ready_after_restart',
};
process.stdout.write(JSON.stringify(payload));
NODE
}

synthetic_recovered_restart_patch_result() {
  local reason="${1:-service_restart}"
  node - "$reason" <<'NODE'
const reason = process.argv[2] || 'service_restart';
process.stdout.write(JSON.stringify({
  ok: true,
  restart: {
    recovered: true,
    reason,
    recovery: 'gateway_ready_after_restart',
  },
}));
NODE
}

gateway_config_patch_json_applied() {
  local raw_patch="${1:?missing config patch}"
  local patch_result
  local error_file
  local error_text

  error_file="$(mktemp)"
  if patch_result="$(gateway_config_patch_json "$raw_patch" 2>"$error_file")"; then
    rm -f "$error_file" >/dev/null 2>&1 || true
    if patch_result_has_restart "$patch_result"; then
      wait_for_gateway_ready || return 1
      mark_patch_restart_recovered "$patch_result"
      return 0
    fi
    printf '%s' "$patch_result"
    return 0
  fi

  error_text="$(cat "$error_file")"
  rm -f "$error_file" >/dev/null 2>&1 || true
  if [[ "$error_text" == *"service restart"* || "$error_text" == *"gateway closed (1012)"* ]]; then
    if wait_for_gateway_ready; then
      printf '%s\n' "$error_text" >&2
      synthetic_recovered_restart_patch_result "service_restart"
      return 0
    fi
  fi

  printf '%s\n' "$error_text" >&2
  return 1
}

build_model_patch() {
  local provider="${1:?missing provider}"
  local model="${2:?missing model}"
  node - "$provider" "$model" <<'NODE'
const [provider, model] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  agents: {
    defaults: {
      model: {
        primary: `${provider}/${model}`,
      },
    },
  },
}));
NODE
}

build_provider_patch() {
  local provider="${1:?missing provider}"
  local payload="${2:?missing provider payload}"
  node - "$provider" "$payload" <<'NODE'
const [provider, payloadRaw] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  models: {
    providers: {
      [provider]: JSON.parse(payloadRaw),
    },
  },
}));
NODE
}

build_provider_delete_patch() {
  local provider="${1:?missing provider}"
  node - "$provider" <<'NODE'
const [provider] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  models: {
    providers: {
      [provider]: null,
    },
  },
}));
NODE
}

build_provider_api_key_patch() {
  local provider="${1:?missing provider}"
  local api_key="${2:?missing api key}"
  node - "$provider" "$api_key" <<'NODE'
const [provider, apiKey] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  models: {
    providers: {
      [provider]: {
        apiKey,
      },
    },
  },
}));
NODE
}

build_provider_api_key_delete_patch() {
  local provider="${1:?missing provider}"
  node - "$provider" <<'NODE'
const [provider] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  models: {
    providers: {
      [provider]: {
        apiKey: null,
      },
    },
  },
}));
NODE
}

provider_api_key_status_json() {
  local provider="${1:?missing provider}"
  local env_key_hint="${2:-}"
  node - "$OPENCLAW_CONFIG_PATH" "$OPENCLAW_DOTENV_FILE" "$provider" "$env_key_hint" <<'NODE'
const fs = require('fs');
const [configPath, envPath, provider, envKeyHint] = process.argv.slice(2);

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return {};
  }
}

function readEnv(file) {
  const values = {};
  try {
    for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
      const line = raw.trim();
      if (!line || line.startsWith('#') || !line.includes('=')) continue;
      const idx = line.indexOf('=');
      values[line.slice(0, idx)] = line.slice(idx + 1);
    }
  } catch {
    // Missing .env means no configured env-backed secret.
  }
  return values;
}

const config = readJson(configPath);
const providerConfig = config?.models?.providers?.[provider] ?? {};
const apiKey = providerConfig?.apiKey;
const envValues = readEnv(envPath);
let envKey = envKeyHint || null;
let native = 'models.providers.apiKey';

if (apiKey && typeof apiKey === 'object' && !Array.isArray(apiKey)) {
  if (apiKey.source === 'env' && typeof apiKey.id === 'string') {
    envKey = apiKey.id;
    native = 'models.providers.apiKey.envRef';
  }
} else if (typeof apiKey === 'string' && apiKey.length > 0) {
  process.stdout.write(JSON.stringify({
    provider,
    configured: true,
    masked: '********',
    native,
  }));
  process.exit(0);
}

const configured = Boolean(envKey && envValues[envKey]);
process.stdout.write(JSON.stringify({
  provider,
  key: envKey,
  configured,
  masked: configured ? '********' : null,
  native,
}));
NODE
}

build_workspace_patch() {
  local workspace="${1:?missing workspace}"
  node - "$workspace" <<'NODE'
const [workspace] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  agents: {
    defaults: {
      workspace,
    },
  },
}));
NODE
}

gateway_local_is_runtime_noop() {
  local current_json="${1:-}"
  local bind="${2:?missing bind}"
  local port="${3:?missing port}"
  [[ -n "$current_json" ]] || current_json='{}'
  node - "$current_json" "$bind" "$port" <<'NODE'
const [currentRaw, desiredBind, desiredPortRaw] = process.argv.slice(2);
const current = currentRaw ? JSON.parse(currentRaw) : {};
const currentMode = current.mode ?? 'local';
const currentBind = current.bind ?? 'lan';
const currentPort = current.port ?? 18789;
const desiredPort = Number(desiredPortRaw);
if (!Number.isInteger(desiredPort) || desiredPort <= 0) {
  process.exit(2);
}
process.exit(currentMode === 'local' && currentBind === desiredBind && Number(currentPort) === desiredPort ? 0 : 1);
NODE
}

validate_gateway_port() {
  local port="${1:-}"
  if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "${#port}" -gt 5 ]]; then
    fail "gateway port must be an integer between 1 and 65535"
  fi

  local numeric_port=$((10#$port))
  if (( numeric_port < 1 || numeric_port > 65535 )); then
    fail "gateway port must be an integer between 1 and 65535"
  fi
}

combine_data_with_runtime_patch() {
  local data="${1:-}"
  local patch_result="${2:-}"
  [[ -n "$data" ]] || data='{}'
  [[ -n "$patch_result" ]] || patch_result='{}'
  node - "$data" "$patch_result" <<'NODE'
const [dataRaw, patchRaw] = process.argv.slice(2);
const parsedData = dataRaw ? JSON.parse(dataRaw) : {};
const patch = patchRaw ? JSON.parse(patchRaw) : {};
const restart = patch && typeof patch === 'object' ? patch.restart : undefined;
const restartRequired = Boolean(restart);
const restartRecovered = Boolean(restart && (restart.recovered === true || restart.applied === true));
const applied = !restartRequired || restartRecovered;
const runtimeApply = {
  applied,
  skipped: false,
  method: 'gateway.config.patch',
  restartRequired,
  restartRecovered,
  noop: Boolean(patch.noop),
  path: patch.path ?? null,
};
if (restartRequired) {
  runtimeApply.restart = {
    coalesced: Boolean(restart.coalesced),
    delayMs: restart.delayMs ?? null,
  };
}
const data = parsedData && typeof parsedData === 'object' && !Array.isArray(parsedData)
  ? { ...parsedData, runtimeApply }
  : { value: parsedData, runtimeApply };
process.stdout.write(`${applied}\t${JSON.stringify(data)}`);
NODE
}

combine_data_with_runtime_skipped() {
  local data="${1:-}"
  local reason="${2:-gateway_unavailable}"
  [[ -n "$data" ]] || data='{}'
  node - "$data" "$reason" <<'NODE'
const [dataRaw, reason] = process.argv.slice(2);
const parsedData = dataRaw ? JSON.parse(dataRaw) : {};
const runtimeApply = {
  applied: false,
  skipped: true,
  reason,
};
const data = parsedData && typeof parsedData === 'object' && !Array.isArray(parsedData)
  ? { ...parsedData, runtimeApply }
  : { value: parsedData, runtimeApply };
process.stdout.write(`false\t${JSON.stringify(data)}`);
NODE
}

emit_runtime_success() {
  local resource="$1"
  local action="$2"
  local combined="$3"
  local applied
  local data

  applied="${combined%%$'\t'*}"
  data="${combined#*$'\t'}"
  json_success "$resource" "$action" "$applied" "$data"
}

usage() {
  json_error "" "" "usage" "usage: config.sh <resource> <action> [args...]"
  exit 1
}

emit_success_from() {
  local resource="$1"
  local action="$2"
  shift 2
  local data

  if ! data="$("$@")"; then
    fail "failed to apply ${resource} ${action}"
  fi

  json_success "$resource" "$action" true "$data"
}

run_or_fail() {
  local message="$1"
  shift

  if ! "$@" >/dev/null; then
    fail "$message"
  fi
}

dispatch_config() {
  local resource="${1:?missing resource}"
  local action="${2:?missing action}"
  shift 2 || true

  case "${resource}:${action}" in
    model:set-main)
      require_arg "${1-}" "provider"
      require_arg "${2-}" "model"
      local patch_result
      local data
      if wait_for_gateway_ready; then
        patch_result="$(gateway_config_patch_json_applied "$(build_model_patch "$1" "$2")")" || fail "failed to apply main model to running gateway"
        data="$(openclaw_cli config get agents.defaults.model --json)" || fail "failed to read main model"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_patch "$data" "$patch_result")"
      else
        run_or_fail "failed to set main model" openclaw_cli config set agents.defaults.model.primary "$1/$2"
        data="$(openclaw_cli config get agents.defaults.model --json)" || fail "failed to read main model"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_skipped "$data")"
      fi
      ;;
    model:get-main)
      emit_success_from "$resource" "$action" openclaw_cli config get agents.defaults.model --json
      ;;
    provider:set)
      local provider="${1-}"
      local base_url="${2:-}"
      local api_mode="${3:-}"
      require_arg "$provider" "provider"
      [[ -n "$base_url" || -n "$api_mode" ]] || fail "provider set requires at least base_url or api_mode"
      local payload
      local current_payload='{}'
      local current_file
      current_file="$(mktemp)"
      if openclaw_cli config get "models.providers.${provider}" --json >"$current_file" 2>/dev/null; then
        current_payload="$(cat "$current_file")"
      fi
      rm -f "$current_file" >/dev/null 2>&1 || true
      if ! payload="$(build_provider_payload "$current_payload" "$base_url" "$api_mode")"; then
        fail "failed to build provider payload"
      fi
      local patch_result
      local data
      if wait_for_gateway_ready; then
        patch_result="$(gateway_config_patch_json_applied "$(build_provider_patch "$provider" "$payload")")" || fail "failed to apply provider to running gateway"
        data="$(openclaw_cli config get "models.providers.${provider}" --json)" || fail "failed to read provider"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_patch "$data" "$patch_result")"
      else
        run_or_fail "failed to set provider" openclaw_cli config set "models.providers.${provider}" "$payload" --strict-json
        data="$(openclaw_cli config get "models.providers.${provider}" --json)" || fail "failed to read provider"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_skipped "$data")"
      fi
      ;;
    provider:get)
      require_arg "${1-}" "provider"
      emit_success_from "$resource" "$action" openclaw_cli config get "models.providers.${1}" --json
      ;;
    provider:delete)
      require_arg "${1-}" "provider"
      local patch_result
      local data='{"deleted":true}'
      if wait_for_gateway_ready; then
        patch_result="$(gateway_config_patch_json_applied "$(build_provider_delete_patch "$1")")" || fail "failed to delete provider from running gateway"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_patch "$data" "$patch_result")"
      else
        run_or_fail "failed to delete provider" openclaw_cli config unset "models.providers.${1}"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_skipped "$data")"
      fi
      ;;
    provider:set-api-key)
      require_arg "${1-}" "provider"
      require_arg "${2-}" "api key"
      local provider="${1}"
      local api_key="${2}"
      local patch_result
      local data
      if wait_for_gateway_ready; then
        patch_result="$(gateway_config_patch_json_applied "$(build_provider_api_key_patch "$provider" "$api_key")")" || fail "failed to apply provider api key to running gateway"
        data="$(provider_api_key_status_json "$provider")" || fail "failed to read provider api key status"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_patch "$data" "$patch_result")"
      else
        run_or_fail "failed to set provider api key" openclaw_cli config set "models.providers.${provider}.apiKey" "$api_key"
        data="$(provider_api_key_status_json "$provider")" || fail "failed to read provider api key status"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_skipped "$data")"
      fi
      ;;
    provider:get-api-key)
      require_arg "${1-}" "provider"
      emit_success_from "$resource" "$action" provider_api_key_status_json "$1" "${2:-}"
      ;;
    provider:delete-api-key)
      require_arg "${1-}" "provider"
      local provider="${1}"
      local patch_result
      local data
      if wait_for_gateway_ready; then
        patch_result="$(gateway_config_patch_json_applied "$(build_provider_api_key_delete_patch "$provider")")" || fail "failed to delete provider api key from running gateway"
        data="$(provider_api_key_status_json "$provider")" || fail "failed to read provider api key status"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_patch "$data" "$patch_result")"
      else
        run_or_fail "failed to delete provider api key ref" openclaw_cli config unset "models.providers.${provider}.apiKey"
        data="$(provider_api_key_status_json "$provider")" || fail "failed to read provider api key status"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_skipped "$data")"
      fi
      ;;
    gateway:set-local)
      local bind="${1:-lan}"
      local port="${2:-18789}"
      local data
      validate_gateway_port "$port"
      data="$(openclaw_cli config get gateway --json)" || fail "failed to read gateway config"
      if wait_for_gateway_ready; then
        if gateway_local_is_runtime_noop "$data" "$bind" "$port"; then
          emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_patch "$data" '{"noop":true,"path":null}')"
        else
          fail "gateway bind/port changes require a gateway restart and are not supported as an immediate runtime config action"
        fi
      else
        run_or_fail "failed to set gateway mode" openclaw_cli config set gateway.mode local
        run_or_fail "failed to set gateway bind" openclaw_cli config set gateway.bind "$bind"
        run_or_fail "failed to set gateway port" openclaw_cli config set gateway.port "$port" --strict-json
        data="$(openclaw_cli config get gateway --json)" || fail "failed to read gateway config"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_skipped "$data")"
      fi
      ;;
    gateway:get-local)
      emit_success_from "$resource" "$action" openclaw_cli config get gateway --json
      ;;
    gateway:set-token)
      require_arg "${1-}" "token"
      run_or_fail "failed to write gateway token" dotenv_set OPENCLAW_GATEWAY_TOKEN "$1"
      run_or_fail "failed to set gateway auth mode" openclaw_cli config set gateway.auth.mode token
      emit_success_from "$resource" "$action" dotenv_json get OPENCLAW_GATEWAY_TOKEN
      ;;
    gateway:get-token)
      emit_success_from "$resource" "$action" dotenv_json get OPENCLAW_GATEWAY_TOKEN
      ;;
    gateway:delete-token)
      run_or_fail "failed to delete gateway token" dotenv_delete OPENCLAW_GATEWAY_TOKEN
      emit_success_from "$resource" "$action" dotenv_json get OPENCLAW_GATEWAY_TOKEN
      ;;
    workspace:set)
      require_arg "${1-}" "workspace path"
      local patch_result
      local data
      if wait_for_gateway_ready; then
        patch_result="$(gateway_config_patch_json_applied "$(build_workspace_patch "$1")")" || fail "failed to apply workspace to running gateway"
        data="$(openclaw_cli config get agents.defaults.workspace --json)" || fail "failed to read workspace"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_patch "$data" "$patch_result")"
      else
        run_or_fail "failed to set workspace" openclaw_cli config set agents.defaults.workspace "$1"
        data="$(openclaw_cli config get agents.defaults.workspace --json)" || fail "failed to read workspace"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_skipped "$data")"
      fi
      ;;
    workspace:get)
      emit_success_from "$resource" "$action" openclaw_cli config get agents.defaults.workspace --json
      ;;
    env:set)
      require_arg "${1-}" "key"
      run_or_fail "failed to write env value" dotenv_set "$1" "${2-}"
      emit_success_from "$resource" "$action" dotenv_json get "$1"
      ;;
    env:get)
      require_arg "${1-}" "key"
      emit_success_from "$resource" "$action" dotenv_json get "$1"
      ;;
    env:delete)
      require_arg "${1-}" "key"
      run_or_fail "failed to delete env value" dotenv_delete "$1"
      emit_success_from "$resource" "$action" dotenv_json get "$1"
      ;;
    env:list)
      emit_success_from "$resource" "$action" dotenv_json list
      ;;
    *)
      fail "unknown config command: ${resource} ${action}"
      ;;
  esac
}

main() {
  CURRENT_RESOURCE="${1:-}"
  CURRENT_ACTION="${2:-}"

  [[ -n "$CURRENT_RESOURCE" && -n "$CURRENT_ACTION" ]] || usage

  run_as_agent_script "$@"
  ensure_openclaw_state
  dispatch_config "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
