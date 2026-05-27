#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-agent-hub/hermes-agent:local}"
CONTAINER="${CONTAINER:-hermes-smoke-$RANDOM}"
HOST_PORT="${HOST_PORT:-28642}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
HERMES_API_SERVER_KEY="${HERMES_API_SERVER_KEY:-hermes-smoke-local-token}"
AGENT_BASE_IMAGE="${AGENT_BASE_IMAGE:-ghcr.io/nightwhite/agent-devbox-base}"

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

printf '==> building %s (%s)\n' "$IMAGE" "$DOCKER_PLATFORM"
docker build \
  --platform "$DOCKER_PLATFORM" \
  --add-host host.docker.internal:host-gateway \
  --build-arg "AGENT_BASE_IMAGE=${AGENT_BASE_IMAGE}" \
  "${docker_proxy_args[@]+"${docker_proxy_args[@]}"}" \
  -f agents/hermes-agent/Dockerfile \
  -t "$IMAGE" \
  .

printf '==> starting %s\n' "$CONTAINER"
docker run -d \
  --platform "$DOCKER_PLATFORM" \
  --add-host host.docker.internal:host-gateway \
  --name "$CONTAINER" \
  -p "127.0.0.1:${HOST_PORT}:8642" \
  -e "API_SERVER_KEY=${HERMES_API_SERVER_KEY}" \
  "${docker_proxy_env[@]+"${docker_proxy_env[@]}"}" \
  "$IMAGE" >/dev/null

printf '==> waiting for Hermes API server\n'
ready=0
for _ in $(seq 1 30); do
  if curl --noproxy '*' -fsS --max-time 2 "http://127.0.0.1:${HOST_PORT}/v1/models" \
    -H "Authorization: Bearer ${HERMES_API_SERVER_KEY}" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
[[ "$ready" -eq 1 ]] || fail "Hermes API server did not become ready"

printf '==> applying Agent Hub model through ai-agent-switch\n'
docker exec -e HOME=/root "$CONTAINER" ai-agent-switch agent-hub init \
  --client hermes \
  --provider-id aiproxy \
  --provider-name "AI Proxy" \
  --model-type openai-chat-compatible \
  --base-url http://host.docker.internal:15721/v1 \
  --api-key-env AIPROXY_API_KEY \
  --model glm-4.6 \
  --available-model glm-4.6 \
  -y \
  --json | python3 -c 'import json, sys; payload=json.load(sys.stdin); assert payload["applied"] is True, payload'

docker exec -e HOME=/root "$CONTAINER" ai-agent-switch client show hermes --json | python3 -c 'import json, sys; payload=json.load(sys.stdin); assert payload["providerId"] == "aiproxy", payload; assert payload["modelId"] == "glm-4.6", payload'
docker exec "$CONTAINER" sh -lc 'grep -q "provider: aiproxy" /root/.hermes/config.yaml'
docker exec "$CONTAINER" sh -lc 'grep -q "default: glm-4.6" /root/.hermes/config.yaml'

printf '==> Hermes smoke passed\n'
