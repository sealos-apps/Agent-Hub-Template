#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-hermes-agent}"
HERMES_HOME="${HERMES_HOME:-/home/agent/.hermes}"
HERMES_CONFIG_FILE="${HERMES_CONFIG_FILE:-${HERMES_HOME}/config.yaml}"
HERMES_DOTENV_FILE="${HERMES_DOTENV_FILE:-${HERMES_HOME}/.env}"
HERMES_VENV="${HERMES_VENV:-/opt/hermes/venv}"
HERMES_PYTHON="${HERMES_PYTHON:-${HERMES_VENV}/bin/python}"
CURRENT_RESOURCE=""
CURRENT_ACTION=""

log() {
  printf '[%s] [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

json_quote() {
  if [[ -x "$HERMES_PYTHON" ]]; then
    "$HERMES_PYTHON" -c 'import json, sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "${1-}"
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "${1-}"
    return
  fi

  local value="${1-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s"\n' "$value"
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
  if [[ "$(id -u)" -eq 0 ]] && [[ "${HERMES_CONFIG_AS_AGENT:-1}" == "1" ]]; then
    ensure_hermes_state
    ensure_agent_ownership
    exec runuser -u agent -- env \
      HERMES_CONFIG_AS_AGENT=0 \
      AGENT_NAME="$AGENT_NAME" \
      HERMES_HOME="$HERMES_HOME" \
      HERMES_CONFIG_FILE="$HERMES_CONFIG_FILE" \
      HERMES_DOTENV_FILE="$HERMES_DOTENV_FILE" \
      HERMES_VENV="$HERMES_VENV" \
      HERMES_PYTHON="$HERMES_PYTHON" \
      HOME=/home/agent \
      /opt/agent/config.sh "$@"
  fi
}

ensure_agent_ownership() {
  if [[ -e "$HERMES_HOME" ]] && [[ "$(stat -c '%U:%G' "$HERMES_HOME")" != "agent:agent" ]]; then
    chown agent:agent "$HERMES_HOME"
  fi
  find "$HERMES_HOME" -mindepth 1 -maxdepth 1 \( ! -user agent -o ! -group agent \) -exec chown agent:agent {} +
}

ensure_hermes_state() {
  mkdir -p "$HERMES_HOME"
  chmod 700 "$HERMES_HOME"

  if [[ ! -f "$HERMES_CONFIG_FILE" ]]; then
    cat >"$HERMES_CONFIG_FILE" <<'CFG'
model:
  default: gpt-5.4
  provider: auto
display:
  skin: default
terminal:
  backend: local
CFG
  fi

  if [[ ! -f "$HERMES_DOTENV_FILE" ]]; then
    cat >"$HERMES_DOTENV_FILE" <<'ENVFILE'
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
API_SERVER_KEY=change-me-local-dev
ENVFILE
  fi
  chmod 600 "$HERMES_DOTENV_FILE"
}

require_hermes_python() {
  [[ -x "$HERMES_PYTHON" ]] || fail "Hermes python runtime not found: ${HERMES_PYTHON}"
}

dotenv_set() {
  local key="${1:?missing key}"
  local value="${2:-}"
  local temp_file
  local found=0

  ensure_hermes_state
  temp_file="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "${key}="* ]]; then
      printf '%s=%s\n' "$key" "$value" >>"$temp_file"
      found=1
    else
      printf '%s\n' "$line" >>"$temp_file"
    fi
  done <"$HERMES_DOTENV_FILE"

  if [[ "$found" -eq 0 ]]; then
    printf '%s=%s\n' "$key" "$value" >>"$temp_file"
  fi

  mv "$temp_file" "$HERMES_DOTENV_FILE"
}

dotenv_delete() {
  local key="${1:?missing key}"
  local temp_file

  ensure_hermes_state
  temp_file="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" != "${key}="* ]]; then
      printf '%s\n' "$line" >>"$temp_file"
    fi
  done <"$HERMES_DOTENV_FILE"

  mv "$temp_file" "$HERMES_DOTENV_FILE"
}

hermes_yaml() {
  require_hermes_python
  "$HERMES_PYTHON" - "$HERMES_CONFIG_FILE" "$@" <<'PY'
import json
import pathlib
import sys
import yaml

config_path = pathlib.Path(sys.argv[1])
command = sys.argv[2]
args = sys.argv[3:]
if config_path.exists():
    config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
else:
    config = {}
if not isinstance(config, dict):
    config = {}

model = config.setdefault("model", {})
if not isinstance(model, dict):
    model = {}
    config["model"] = model

BUILTIN_PROVIDERS = {
    "auto",
    "openrouter",
    "nous",
    "openai-codex",
    "copilot-acp",
    "copilot",
    "anthropic",
    "gemini",
    "xai",
    "ollama-cloud",
    "huggingface",
    "zai",
    "kimi-coding",
    "kimi-coding-cn",
    "stepfun",
    "minimax",
    "minimax-cn",
    "kilocode",
    "xiaomi",
    "arcee",
    "nvidia",
    "custom",
}

def save() -> None:
    config_path.write_text(yaml.safe_dump(config, allow_unicode=True, sort_keys=False), encoding="utf-8")

def current_provider_entry(provider: str) -> tuple[dict | None, str | None]:
    normalized = provider.strip().lower()
    providers = config.get("providers")
    if isinstance(providers, dict):
        for key, entry in providers.items():
            if not isinstance(entry, dict):
                continue
            names = {
                str(key).strip().lower(),
                str(entry.get("name") or "").strip().lower(),
            }
            if normalized in names:
                return entry, "providers"

    legacy = config.get("custom_providers")
    if isinstance(legacy, list):
        for entry in legacy:
            if not isinstance(entry, dict):
                continue
            names = {
                str(entry.get("name") or "").strip().lower(),
                str(entry.get("provider_key") or "").strip().lower(),
            }
            if normalized in names:
                return entry, "custom_providers"
    return None, None

def upsert_provider(provider: str, base_url: str, api_mode: str | None, key_env: str | None) -> dict:
    providers = config.get("providers")
    if not isinstance(providers, dict):
        providers = {}
    config["providers"] = providers

    entry = providers.get(provider)
    if not isinstance(entry, dict):
        entry = {"name": provider}
        providers[provider] = entry

    entry["base_url"] = base_url
    if model.get("default"):
        entry["default_model"] = model.get("default")
    if api_mode:
        entry["api_mode"] = api_mode
    elif provider.strip().lower() == "ccswitch":
        entry["api_mode"] = "chat_completions"
    if key_env:
        entry["key_env"] = key_env
    return entry

def read_env(env_path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if env_path.exists():
        for raw in env_path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            current_key, current_value = line.split("=", 1)
            values[current_key] = current_value
    return values

def secret_status(key: str, value: str | None) -> dict[str, object]:
    configured = bool(value)
    return {
        "key": key,
        "configured": configured,
        "masked": "********" if configured else None,
    }

if command == "set-provider":
    provider = args[0]
    base_url = args[1] if len(args) > 1 else ""
    api_mode = args[2] if len(args) > 2 else ""
    key_env = args[3] if len(args) > 3 else ""
    normalized_provider = provider.strip().lower()
    if normalized_provider not in BUILTIN_PROVIDERS and not base_url:
        raise SystemExit(f"provider {provider!r} requires base_url because Hermes treats it as a named custom provider")
    model["provider"] = provider
    if base_url:
        if normalized_provider in BUILTIN_PROVIDERS:
            model["base_url"] = base_url
        else:
            model.pop("base_url", None)
            upsert_provider(provider, base_url, api_mode or None, key_env or None)
    else:
        model.pop("base_url", None)
    if api_mode and normalized_provider in {"custom"}:
        model["api_mode"] = api_mode
    elif normalized_provider not in {"custom"}:
        model.pop("api_mode", None)
    save()
    provider_entry, provider_native = current_provider_entry(provider)
    print(json.dumps({
        "provider": model.get("provider"),
        "base_url": model.get("base_url") or (provider_entry or {}).get("base_url") or (provider_entry or {}).get("api"),
        "api_mode": model.get("api_mode") or (provider_entry or {}).get("api_mode"),
        "key_env": (provider_entry or {}).get("key_env"),
        "native": provider_native if provider_entry else "model",
    }, ensure_ascii=False))
elif command == "get-provider":
    provider = model.get("provider", "auto")
    provider_entry, provider_native = current_provider_entry(provider) if isinstance(provider, str) else (None, None)
    print(json.dumps({
        "provider": provider,
        "base_url": model.get("base_url") or (provider_entry or {}).get("base_url") or (provider_entry or {}).get("api"),
        "api_mode": model.get("api_mode") or (provider_entry or {}).get("api_mode"),
        "key_env": (provider_entry or {}).get("key_env"),
        "native": provider_native if provider_entry else "model",
    }, ensure_ascii=False))
elif command == "delete-provider":
    model["provider"] = "auto"
    model.pop("base_url", None)
    model.pop("api_mode", None)
    save()
    print(json.dumps({"provider": model.get("provider"), "base_url": model.get("base_url")}, ensure_ascii=False))
elif command == "set-model":
    model_name = args[0]
    model["default"] = model_name
    provider = model.get("provider")
    if isinstance(provider, str):
        provider_entry, provider_native = current_provider_entry(provider)
        if provider_entry is not None:
            if provider_native == "providers":
                provider_entry["default_model"] = model_name
            else:
                provider_entry["model"] = model_name
    save()
    print(json.dumps({"model": model.get("default")}, ensure_ascii=False))
elif command == "get-model":
    print(json.dumps({"model": model.get("default")}, ensure_ascii=False))
elif command == "delete-model":
    model.pop("default", None)
    save()
    print(json.dumps({"model": model.get("default")}, ensure_ascii=False))
elif command == "env-get":
    env_path = pathlib.Path(args[0])
    key = args[1]
    values = read_env(env_path)
    print(json.dumps(secret_status(key, values.get(key)), ensure_ascii=False))
elif command == "env-list":
    env_path = pathlib.Path(args[0])
    values = read_env(env_path)
    print(json.dumps({"values": {key: secret_status(key, value) for key, value in values.items()}}, ensure_ascii=False))
else:
    raise SystemExit(f"unknown hermes yaml command: {command}")
PY
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
    provider:set-main)
      require_arg "${1-}" "provider"
      emit_success_from "$resource" "$action" hermes_yaml set-provider "$1" "${2:-}" "${3:-}" "${4:-}"
      ;;
    provider:get-main)
      emit_success_from "$resource" "$action" hermes_yaml get-provider
      ;;
    provider:delete-main)
      emit_success_from "$resource" "$action" hermes_yaml delete-provider
      ;;
    model:set-main)
      require_arg "${1-}" "model"
      emit_success_from "$resource" "$action" hermes_yaml set-model "$1"
      ;;
    model:get-main)
      emit_success_from "$resource" "$action" hermes_yaml get-model
      ;;
    model:delete-main)
      emit_success_from "$resource" "$action" hermes_yaml delete-model
      ;;
    env:set)
      require_arg "${1-}" "key"
      run_or_fail "failed to write env value" dotenv_set "$1" "${2-}"
      emit_success_from "$resource" "$action" hermes_yaml env-get "$HERMES_DOTENV_FILE" "$1"
      ;;
    env:get)
      require_arg "${1-}" "key"
      emit_success_from "$resource" "$action" hermes_yaml env-get "$HERMES_DOTENV_FILE" "$1"
      ;;
    env:delete)
      require_arg "${1-}" "key"
      run_or_fail "failed to delete env value" dotenv_delete "$1"
      emit_success_from "$resource" "$action" hermes_yaml env-get "$HERMES_DOTENV_FILE" "$1"
      ;;
    env:list)
      emit_success_from "$resource" "$action" hermes_yaml env-list "$HERMES_DOTENV_FILE"
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
  ensure_hermes_state
  dispatch_config "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
