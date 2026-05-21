#!/usr/bin/env bash
set -euo pipefail

HERMES_IMAGE="${HERMES_IMAGE:-agent-hub/hermes-agent:local}"
OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-agent-hub/openclaw:local}"
HERMES_CONTAINER="${HERMES_CONTAINER:-hermes-ccswitch-smoke-$RANDOM}"
OPENCLAW_CONTAINER="${OPENCLAW_CONTAINER:-openclaw-ccswitch-smoke-$RANDOM}"
HERMES_HOST_PORT="${HERMES_HOST_PORT:-$((28600 + RANDOM % 500))}"
OPENCLAW_HOST_PORT="${OPENCLAW_HOST_PORT:-$((28700 + RANDOM % 500))}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
BUILD_IMAGES="${BUILD_IMAGES:-1}"
AGENT_BASE_IMAGE="${AGENT_BASE_IMAGE:-ghcr.io/gitlayzer/agent-devbox-base:0.1.0}"
AI_AGENT_SWITCH_SOURCE_URL="${AI_AGENT_SWITCH_SOURCE_URL:-https://github.com/sealos-apps/ai-agent-switch.git}"
AI_AGENT_SWITCH_SOURCE_REF="${AI_AGENT_SWITCH_SOURCE_REF:-9d78561ecbd35ce775f7acfe70e3bdb6617b9b51}"
CCSWITCH_DIRECT_BASE_URL="${CCSWITCH_DIRECT_BASE_URL:-http://127.0.0.1:15721/v1}"
CCSWITCH_CONTAINER_BASE_URL="${CCSWITCH_CONTAINER_BASE_URL:-http://host.docker.internal:15721/v1}"
CCSWITCH_API_KEY="${CCSWITCH_API_KEY:-sk-local-smoke}"
CCSWITCH_MODEL="${CCSWITCH_MODEL:-gpt-5.4-mini}"
OPENCLAW_INFER_TIMEOUT_SECONDS="${OPENCLAW_INFER_TIMEOUT_SECONDS:-240}"
HERMES_API_SERVER_KEY="${HERMES_API_SERVER_KEY:-hermes-ccswitch-smoke-token}"
OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-openclaw-ccswitch-smoke-token}"

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

resolve_ai_agent_switch_version() {
  if [[ -n "${AI_AGENT_SWITCH_VERSION:-}" ]]; then
    printf '%s' "$AI_AGENT_SWITCH_VERSION"
    return
  fi

  command -v npm >/dev/null 2>&1 || \
    fail "AI_AGENT_SWITCH_VERSION is required when npm is not available"

  npm view ai-agent-switch version || \
    fail "failed to resolve AI_AGENT_SWITCH_VERSION from npm"
}

AI_AGENT_SWITCH_VERSION="$(resolve_ai_agent_switch_version)"
if [[ -z "${AI_AGENT_SWITCH_METADATA:-}" ]]; then
  AI_AGENT_SWITCH_METADATA="$AI_AGENT_SWITCH_VERSION"
  if [[ -n "$AI_AGENT_SWITCH_SOURCE_REF" ]]; then
    AI_AGENT_SWITCH_METADATA="${AI_AGENT_SWITCH_VERSION}+source.${AI_AGENT_SWITCH_SOURCE_REF}"
  fi
fi

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

assert_chat_completion_text() {
  local output_file="$1"
  local label="$2"
  python3 - "$output_file" "$label" "$CCSWITCH_MODEL" <<'PY'
import json
import sys

path, label, expected_model = sys.argv[1], sys.argv[2], sys.argv[3]
payload = json.load(open(path, encoding="utf-8"))
text = payload.get("choices", [{}])[0].get("message", {}).get("content")
assert text, payload
model = payload.get("model")
if model is not None:
    assert model == expected_model, payload
print(f"{label}=ok model={model} text={text[:120]}")
PY
}

assert_openclaw_gateway_text() {
  local output_file="$1"
  python3 - "$output_file" "$CCSWITCH_MODEL" <<'PY'
import json
import sys

path, expected_model = sys.argv[1], sys.argv[2]
payload = json.load(open(path, encoding="utf-8"))
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
print(f"openclaw_gateway=ok model={model} text={text[:120]}")
PY
}

wait_for_hermes() {
  local ready=0
  for _ in $(seq 1 45); do
    if curl --noproxy '*' -fsS --max-time 2 "http://127.0.0.1:${HERMES_HOST_PORT}/v1/models" \
      -H "Authorization: Bearer ${HERMES_API_SERVER_KEY}" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 2
  done
  [[ "$ready" -eq 1 ]] || fail "Hermes API server did not become ready"
}

wait_for_openclaw() {
  local ready=0
  for _ in $(seq 1 90); do
    if curl --noproxy '*' -fsS --max-time 2 "http://127.0.0.1:${OPENCLAW_HOST_PORT}/readyz" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 2
  done
  [[ "$ready" -eq 1 ]] || fail "OpenClaw health endpoint did not become ready"
}

run_openclaw_gateway_infer() {
  local output_file="$1"
  python3 - "$OPENCLAW_CONTAINER" "$output_file" "$OPENCLAW_INFER_TIMEOUT_SECONDS" "$CCSWITCH_MODEL" <<'PY'
import subprocess
import sys
import uuid

container, output_file, timeout_seconds, model = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
params = {
    "agentId": "main",
    "message": "Reply with exactly: pong",
    "provider": "ccswitch",
    "model": model,
    "idempotencyKey": f"openclaw-ccswitch-smoke-{uuid.uuid4().hex}",
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

verify_ai_agent_switch_image() {
  local image="$1"
  local client="$2"
  local output
  output="$(
    docker run --rm --platform "$DOCKER_PLATFORM" -e "VERIFY_CLIENT=${client}" "$image" bash -lc '
      set -euo pipefail
      verify_home="$(mktemp -d)"
      trap "rm -rf \"$verify_home\"" EXIT
      HOME="$verify_home" ai-agent-switch agent-hub init \
        --client "$VERIFY_CLIENT" \
        --provider-id verify-aiproxy \
        --provider-name Verify \
        --model-type openai-chat-compatible \
        --base-url http://127.0.0.1:1/v1 \
        --api-key-env AIPROXY_API_KEY \
        --model verify-model \
        --available-model verify-model \
        --json
    '
  )"
  printf '%s' "$output" | grep -F '"requiresConfirmation": true' >/dev/null
  docker image inspect "$image" --format '{{ index .Config.Labels "org.sealos.ai-agent-switch.version" }}' | grep -Fx "$AI_AGENT_SWITCH_VERSION" >/dev/null
  docker image inspect "$image" --format '{{ index .Config.Labels "org.sealos.ai-agent-switch.metadata" }}' | grep -Fx "$AI_AGENT_SWITCH_METADATA" >/dev/null
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
  docker rm -f "$HERMES_CONTAINER" "$OPENCLAW_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ "$BUILD_IMAGES" == "1" ]]; then
  printf '==> building Hermes and OpenClaw images (%s, ai-agent-switch %s)\n' "$DOCKER_PLATFORM" "$AI_AGENT_SWITCH_VERSION"
  docker build \
    --platform "$DOCKER_PLATFORM" \
    --add-host host.docker.internal:host-gateway \
    --build-arg "AGENT_BASE_IMAGE=${AGENT_BASE_IMAGE}" \
    --build-arg "AI_AGENT_SWITCH_VERSION=${AI_AGENT_SWITCH_VERSION}" \
    --build-arg "AI_AGENT_SWITCH_METADATA=${AI_AGENT_SWITCH_METADATA}" \
    --build-arg "AI_AGENT_SWITCH_SOURCE_URL=${AI_AGENT_SWITCH_SOURCE_URL}" \
    --build-arg "AI_AGENT_SWITCH_SOURCE_REF=${AI_AGENT_SWITCH_SOURCE_REF}" \
    "${docker_proxy_args[@]+"${docker_proxy_args[@]}"}" \
    -f agents/hermes-agent/Dockerfile \
    -t "$HERMES_IMAGE" \
    .
  docker build \
    --platform "$DOCKER_PLATFORM" \
    --add-host host.docker.internal:host-gateway \
    --build-arg "AGENT_BASE_IMAGE=${AGENT_BASE_IMAGE}" \
    --build-arg "AI_AGENT_SWITCH_VERSION=${AI_AGENT_SWITCH_VERSION}" \
    --build-arg "AI_AGENT_SWITCH_METADATA=${AI_AGENT_SWITCH_METADATA}" \
    --build-arg "AI_AGENT_SWITCH_SOURCE_URL=${AI_AGENT_SWITCH_SOURCE_URL}" \
    --build-arg "AI_AGENT_SWITCH_SOURCE_REF=${AI_AGENT_SWITCH_SOURCE_REF}" \
    "${docker_proxy_args[@]+"${docker_proxy_args[@]}"}" \
    -f agents/openclaw/Dockerfile \
    -t "$OPENCLAW_IMAGE" \
    .
fi

verify_ai_agent_switch_image "$HERMES_IMAGE" hermes
verify_ai_agent_switch_image "$OPENCLAW_IMAGE" openclaw

printf '==> checking direct ccswitch chat completion\n'
direct_output="$(mktemp)"
curl --noproxy '*' -fsS --max-time 30 "${CCSWITCH_DIRECT_BASE_URL}/chat/completions" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${CCSWITCH_API_KEY}" \
  -d '{"model":"'"${CCSWITCH_MODEL}"'","messages":[{"role":"user","content":"Reply with exactly: pong"}],"max_tokens":16}' \
  >"$direct_output"
assert_chat_completion_text "$direct_output" "direct_ccswitch"
rm -f "$direct_output"

printf '==> starting Hermes ccswitch smoke container\n'
docker run -d \
  --platform "$DOCKER_PLATFORM" \
  --add-host host.docker.internal:host-gateway \
  --name "$HERMES_CONTAINER" \
  -p "127.0.0.1:${HERMES_HOST_PORT}:8642" \
  -e "CCSWITCH_API_KEY=${CCSWITCH_API_KEY}" \
  -e "CCSWITCH_CONTAINER_BASE_URL=${CCSWITCH_CONTAINER_BASE_URL}" \
  -e "CCSWITCH_MODEL=${CCSWITCH_MODEL}" \
  -e "API_SERVER_KEY=${HERMES_API_SERVER_KEY}" \
  "${docker_proxy_env[@]+"${docker_proxy_env[@]}"}" \
  "$HERMES_IMAGE" \
  bash -lc '
    set -euo pipefail
    ai-agent-switch agent-hub init \
      --client hermes \
      --provider-id ccswitch \
      --provider-name CCSwitch \
      --model-type openai-chat-compatible \
      --base-url "$CCSWITCH_CONTAINER_BASE_URL" \
      --api-key-env CCSWITCH_API_KEY \
      --model "$CCSWITCH_MODEL" \
      --available-model "$CCSWITCH_MODEL" \
      -y \
      --json
    exec /opt/agent/bin/start
  ' >/dev/null
wait_for_hermes

docker exec --user agent -e HOME=/home/agent "$HERMES_CONTAINER" ai-agent-switch client show hermes --json | python3 -c 'import json, sys; expected=sys.argv[1]; payload=json.load(sys.stdin); assert payload["providerId"] == "ccswitch", payload; assert payload["modelId"] == expected, payload' "$CCSWITCH_MODEL"
hermes_output="$(mktemp)"
curl --noproxy '*' -fsS --max-time 90 "http://127.0.0.1:${HERMES_HOST_PORT}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${HERMES_API_SERVER_KEY}" \
  -d '{"model":"'"${CCSWITCH_MODEL}"'","messages":[{"role":"user","content":"Reply with exactly: pong"}],"max_tokens":16}' \
  >"$hermes_output"
assert_chat_completion_text "$hermes_output" "hermes_gateway"
rm -f "$hermes_output"

printf '==> starting OpenClaw ccswitch smoke container\n'
docker run -d \
  --platform "$DOCKER_PLATFORM" \
  --add-host host.docker.internal:host-gateway \
  --name "$OPENCLAW_CONTAINER" \
  -p "127.0.0.1:${OPENCLAW_HOST_PORT}:18789" \
  -e "CCSWITCH_API_KEY=${CCSWITCH_API_KEY}" \
  -e "CCSWITCH_CONTAINER_BASE_URL=${CCSWITCH_CONTAINER_BASE_URL}" \
  -e "CCSWITCH_MODEL=${CCSWITCH_MODEL}" \
  -e "OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}" \
  "${docker_proxy_env[@]+"${docker_proxy_env[@]}"}" \
  "$OPENCLAW_IMAGE" \
  bash -lc '
    set -euo pipefail
    ai-agent-switch agent-hub init \
      --client openclaw \
      --provider-id ccswitch \
      --provider-name CCSwitch \
      --model-type openai-chat-compatible \
      --base-url "$CCSWITCH_CONTAINER_BASE_URL" \
      --api-key-env CCSWITCH_API_KEY \
      --model "$CCSWITCH_MODEL" \
      --available-model "$CCSWITCH_MODEL" \
      -y \
      --json
    exec /opt/agent/bin/start
  ' >/dev/null
wait_for_openclaw

docker exec --user agent -e HOME=/home/agent "$OPENCLAW_CONTAINER" ai-agent-switch client show openclaw --json | python3 -c 'import json, sys; expected=sys.argv[1]; payload=json.load(sys.stdin); assert payload["providerId"] == "ccswitch", payload; assert payload["modelId"] == expected, payload' "$CCSWITCH_MODEL"
openclaw_output="$(mktemp)"
run_openclaw_gateway_infer "$openclaw_output"
assert_openclaw_gateway_text "$openclaw_output"
rm -f "$openclaw_output"

curl --noproxy '*' -fsS --max-time 5 "http://127.0.0.1:${OPENCLAW_HOST_PORT}/readyz" >/dev/null

printf '==> ccswitch smoke passed\n'
