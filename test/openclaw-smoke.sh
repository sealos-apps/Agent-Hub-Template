#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-agent-hub/openclaw:local}"
CONTAINER="${CONTAINER:-openclaw-smoke-$RANDOM}"
HOST_PORT="${HOST_PORT:-28789}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
CCSWITCH_CONTAINER_BASE_URL="${CCSWITCH_CONTAINER_BASE_URL:-http://host.docker.internal:15721/v1}"
CCSWITCH_API_KEY="${CCSWITCH_API_KEY:-sk-local-smoke}"
CCSWITCH_MODEL="${CCSWITCH_MODEL:-gpt-5.4-mini}"
OPENCLAW_INFER_TIMEOUT_SECONDS="${OPENCLAW_INFER_TIMEOUT_SECONDS:-240}"

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

rewrite_proxy_for_docker() {
  local value="${1:-}"
  value="${value//127.0.0.1/host.docker.internal}"
  value="${value//localhost/host.docker.internal}"
  printf '%s' "$value"
}

append_no_proxy_host() {
  local value="${1:-}"
  if [[ -z "$value" ]]; then
    printf 'host.docker.internal'
    return
  fi

  case ",${value}," in
    *,host.docker.internal,*)
      printf '%s' "$value"
      ;;
    *)
      printf '%s,%s' "$value" "host.docker.internal"
      ;;
  esac
}

assert_success_json() {
  local output="$1"
  printf '%s' "$output" | python3 -c 'import json, sys
payload = json.load(sys.stdin)
assert payload.get("ok") is True, payload
assert payload.get("applied") is True, payload
assert "data" in payload, payload
'
}

assert_error_json() {
  local output="$1"
  printf '%s' "$output" | python3 -c 'import json, sys
payload = json.load(sys.stdin)
assert payload.get("ok") is False, payload
assert isinstance(payload.get("error"), dict), payload
assert payload["error"].get("message"), payload
'
}

assert_runtime_config_applied() {
  local output="$1"
  printf '%s' "$output" | python3 -c 'import json, sys
payload = json.load(sys.stdin)
runtime_apply = payload.get("data", {}).get("runtimeApply", {})
assert runtime_apply.get("applied") is True, payload
assert runtime_apply.get("skipped") is False, payload
'
}

assert_runtime_apply_applied() {
  local output="$1"
  printf '%s' "$output" | python3 -c 'import json, sys
payload = json.load(sys.stdin)
runtime_apply = payload.get("data", {}).get("runtimeApply", {})
assert runtime_apply.get("applied") is True, payload
assert runtime_apply.get("skipped") is False, payload
'
}

assert_openclaw_infer_json() {
  local output_file="$1"
  python3 - "$output_file" "$CCSWITCH_MODEL" <<'PY'
import json
import sys

path, expected_model = sys.argv[1], sys.argv[2]
payload = json.loads(open(path, encoding="utf-8").read())
if payload.get("transport") == "gateway":
    outputs = payload.get("outputs", [])
    provider = payload.get("provider")
    model = payload.get("model")
else:
    result = payload.get("result", {})
    outputs = result.get("payloads", [])
    agent_meta = result.get("meta", {}).get("agentMeta", {})
    provider = agent_meta.get("provider")
    model = agent_meta.get("model")
texts = [
    item.get("text")
    for item in outputs
    if isinstance(item, dict) and item.get("text")
]
text = payload.get("output") or payload.get("text") or payload.get("content") or " ".join(texts)
assert provider == "ccswitch", payload
assert model == expected_model, payload
assert text, payload
PY
}

run_config_json() {
  local output
  output="$(docker exec "$CONTAINER" /opt/agent/config.sh "$@")"
  assert_success_json "$output"
  printf '%s' "$output"
}

expect_config_error() {
  local output
  if output="$(docker exec "$CONTAINER" /opt/agent/config.sh "$@" 2>/dev/null)"; then
    fail "config command unexpectedly succeeded: $*"
  fi
  assert_error_json "$output"
}

run_openclaw_gateway_infer() {
  local output_file="$1"
  python3 - "$CONTAINER" "$output_file" "$OPENCLAW_INFER_TIMEOUT_SECONDS" "$CCSWITCH_MODEL" <<'PY'
import subprocess
import sys
import uuid

container, output_file, timeout_seconds, model = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
params = {
    "agentId": "main",
    "message": "Reply with exactly: pong",
    "provider": "ccswitch",
    "model": model,
    "idempotencyKey": f"openclaw-smoke-{uuid.uuid4().hex}",
}
cmd = [
    "docker",
    "exec",
    container,
    "/opt/agent/entrypoint.sh",
    "run",
    "gateway",
    "call",
    "agent",
    "--expect-final",
    "--timeout",
    str(timeout_seconds * 1000),
    "--json",
    "--params",
    __import__("json").dumps(params),
]
with open(output_file, "wb") as output:
    completed = subprocess.run(cmd, stdout=output, stderr=subprocess.PIPE, timeout=timeout_seconds)
if completed.returncode != 0:
    sys.stderr.write(completed.stderr.decode("utf-8", "replace"))
    raise SystemExit(completed.returncode)
PY
}

docker_proxy_args=()
for key in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY; do
  if [[ -n "${!key:-}" ]]; then
    value="${!key}"
    if [[ "$key" == "no_proxy" || "$key" == "NO_PROXY" ]]; then
      value="$(append_no_proxy_host "$value")"
    else
      value="$(rewrite_proxy_for_docker "$value")"
    fi
    docker_proxy_args+=(--build-arg "${key}=${value}")
  fi
done

docker_proxy_env=()
for key in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY; do
  if [[ -n "${!key:-}" ]]; then
    value="${!key}"
    if [[ "$key" == "no_proxy" || "$key" == "NO_PROXY" ]]; then
      value="$(append_no_proxy_host "$value")"
    else
      value="$(rewrite_proxy_for_docker "$value")"
    fi
    docker_proxy_env+=(-e "${key}=${value}")
  fi
done

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf '==> building %s (%s)\n' "$IMAGE" "$DOCKER_PLATFORM"
docker build \
  --platform "$DOCKER_PLATFORM" \
  --add-host host.docker.internal:host-gateway \
  "${docker_proxy_args[@]+"${docker_proxy_args[@]}"}" \
  -f agents/openclaw/Dockerfile \
  -t "$IMAGE" \
  .

printf '==> starting %s\n' "$CONTAINER"
docker run -d \
  --platform "$DOCKER_PLATFORM" \
  --add-host host.docker.internal:host-gateway \
  --name "$CONTAINER" \
  -p "127.0.0.1:${HOST_PORT}:18789" \
  "${docker_proxy_env[@]+"${docker_proxy_env[@]}"}" \
  "$IMAGE" >/dev/null

printf '==> waiting for OpenClaw readiness endpoint\n'
ready=0
for _ in $(seq 1 90); do
  if curl --noproxy '*' -fsS --max-time 2 "http://127.0.0.1:${HOST_PORT}/readyz" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
[[ "$ready" -eq 1 ]] || fail "OpenClaw readiness endpoint did not become ready"

printf '==> checking runtime manifest and standard entrypoints\n'
docker exec "$CONTAINER" cat /opt/agent/config.json | python3 -m json.tool >/dev/null
docker exec "$CONTAINER" cat /opt/agent/config.json | python3 -c 'import json, sys; assert json.load(sys.stdin)["schemaVersion"] == "devbox-agent-config.v1"'
docker exec "$CONTAINER" /opt/agent/entrypoint.sh run config file >/dev/null

printf '==> mutating OpenClaw native config through JSON protocol\n'
run_config_json gateway get-local >/dev/null
runtime_output="$(run_config_json gateway set-local lan 18789)"
assert_runtime_apply_applied "$runtime_output"
runtime_output="$(run_config_json provider set ccswitch "$CCSWITCH_CONTAINER_BASE_URL" openai-completions)"
assert_runtime_apply_applied "$runtime_output"
runtime_output="$(run_config_json model set-main ccswitch "$CCSWITCH_MODEL")"
assert_runtime_apply_applied "$runtime_output"
secret_output="$(run_config_json provider set-api-key ccswitch "$CCSWITCH_API_KEY")"
[[ "$secret_output" != *"$CCSWITCH_API_KEY"* ]] || fail "secret value leaked in provider set-api-key output"
assert_runtime_config_applied "$secret_output"
secret_output="$(run_config_json env set OPENAI_API_KEY "$CCSWITCH_API_KEY")"
[[ "$secret_output" != *"$CCSWITCH_API_KEY"* ]] || fail "secret value leaked in env set output"
run_config_json provider get ccswitch >/dev/null
run_config_json model get-main >/dev/null
secret_output="$(run_config_json provider get-api-key ccswitch)"
[[ "$secret_output" != *"$CCSWITCH_API_KEY"* ]] || fail "secret value leaked in provider get-api-key output"
secret_output="$(run_config_json env get OPENAI_API_KEY)"
[[ "$secret_output" != *"$CCSWITCH_API_KEY"* ]] || fail "secret value leaked in env get output"
run_config_json env list >/dev/null
expect_config_error model set-main

printf '==> verifying config files\n'
openclaw_config_file="$(mktemp)"
docker exec "$CONTAINER" cat /home/agent/.openclaw/openclaw.json >"$openclaw_config_file"
python3 - "$openclaw_config_file" "$CCSWITCH_MODEL" "$CCSWITCH_CONTAINER_BASE_URL" "$CCSWITCH_API_KEY" <<'PY'
import json
import sys

config_path, expected_model, expected_base_url, expected_api_key = sys.argv[1:]
config = json.load(open(config_path, encoding="utf-8"))
assert config["agents"]["defaults"]["model"]["primary"] == f"ccswitch/{expected_model}", config
provider = config["models"]["providers"]["ccswitch"]
assert provider["baseUrl"] == expected_base_url, provider
assert provider["api"] == "openai-completions", provider
assert provider["apiKey"] == expected_api_key, provider
PY
rm -f "$openclaw_config_file"
docker exec "$CONTAINER" cat /home/agent/.openclaw/.env | grep -F "OPENAI_API_KEY=${CCSWITCH_API_KEY}" >/dev/null
docker exec "$CONTAINER" sh -lc 'test "$(stat -c %a /home/agent/.openclaw)" = "700"'
docker exec "$CONTAINER" sh -lc 'test "$(stat -c %a /home/agent/.openclaw/.env)" = "600"'
docker exec "$CONTAINER" sh -lc 'test "$(stat -c %a /home/agent/.openclaw/openclaw.json)" = "600"'

printf '==> checking OpenClaw gateway inference through ccswitch\n'
infer_output="$(mktemp)"
run_openclaw_gateway_infer "$infer_output"
assert_openclaw_infer_json "$infer_output"
rm -f "$infer_output"

printf '==> checking readiness endpoint again\n'
ready=0
for _ in $(seq 1 15); do
  if curl --noproxy '*' -fsS --max-time 5 "http://127.0.0.1:${HOST_PORT}/readyz" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
[[ "$ready" -eq 1 ]] || fail "OpenClaw readiness endpoint did not stay ready after config changes"

printf '==> OpenClaw smoke passed\n'
