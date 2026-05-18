#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-agent-hub/openclaw:local}"
CONTAINER="${CONTAINER:-openclaw-smoke-$RANDOM}"
HOST_PORT="${HOST_PORT:-28789}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-openclaw-smoke-local-token}"

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

docker_proxy_args=()
docker_proxy_env=()
for key in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY; do
  if [[ -n "${!key:-}" ]]; then
    value="${!key}"
    if [[ "$key" == "no_proxy" || "$key" == "NO_PROXY" ]]; then
      value="$(append_no_proxy_host "$value")"
    else
      value="$(rewrite_proxy_for_docker "$value")"
    fi
    docker_proxy_args+=(--build-arg "${key}=${value}")
    docker_proxy_env+=(-e "${key}=${value}")
  fi
done

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

verify_ai_agent_switch_agent_hub() {
  local output
  output="$(
    docker run --rm --platform "$DOCKER_PLATFORM" "$IMAGE" bash -lc '
      set -euo pipefail
      verify_home="$(mktemp -d)"
      trap "rm -rf \"$verify_home\"" EXIT
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
    '
  )"
  printf '%s' "$output" | grep -F '"requiresConfirmation": true' >/dev/null
}

printf '==> building %s (%s, ai-agent-switch %s)\n' "$IMAGE" "$DOCKER_PLATFORM" "$AI_AGENT_SWITCH_VERSION"
docker build \
  --platform "$DOCKER_PLATFORM" \
  --add-host host.docker.internal:host-gateway \
  --build-arg "AI_AGENT_SWITCH_VERSION=${AI_AGENT_SWITCH_VERSION}" \
  "${docker_proxy_args[@]+"${docker_proxy_args[@]}"}" \
  -f agents/openclaw/Dockerfile \
  -t "$IMAGE" \
  .

verify_ai_agent_switch_agent_hub

printf '==> starting %s\n' "$CONTAINER"
docker run -d \
  --platform "$DOCKER_PLATFORM" \
  --add-host host.docker.internal:host-gateway \
  --name "$CONTAINER" \
  -p "127.0.0.1:${HOST_PORT}:18789" \
  -e "OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}" \
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

printf '==> applying Agent Hub model through ai-agent-switch\n'
docker exec --user agent -e HOME=/home/agent "$CONTAINER" ai-agent-switch agent-hub init \
  --client openclaw \
  --provider-id aiproxy \
  --provider-name "AI Proxy" \
  --model-type openai-chat-compatible \
  --base-url http://host.docker.internal:15721/v1 \
  --api-key-env AIPROXY_API_KEY \
  --model glm-4.6 \
  --available-model glm-4.6 \
  -y \
  --json | python3 -c 'import json, sys; payload=json.load(sys.stdin); assert payload["applied"] is True, payload'

docker exec --user agent -e HOME=/home/agent "$CONTAINER" ai-agent-switch client show openclaw --json | python3 -c 'import json, sys; payload=json.load(sys.stdin); assert payload["providerId"] == "aiproxy", payload; assert payload["modelId"] == "glm-4.6", payload'
docker exec "$CONTAINER" sh -lc 'grep -q "\"primary\": \"aiproxy/glm-4.6\"" /home/agent/.openclaw/openclaw.json'

printf '==> OpenClaw smoke passed\n'
