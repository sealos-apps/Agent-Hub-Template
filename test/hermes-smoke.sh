#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-agent-hub/hermes-agent:local}"
CONTAINER="${CONTAINER:-hermes-smoke-$RANDOM}"
HOST_PORT="${HOST_PORT:-28642}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"

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
  -f agents/hermes-agent/Dockerfile \
  -t "$IMAGE" \
  .

printf '==> starting %s\n' "$CONTAINER"
docker run -d \
  --platform "$DOCKER_PLATFORM" \
  --add-host host.docker.internal:host-gateway \
  --name "$CONTAINER" \
  -p "127.0.0.1:${HOST_PORT}:8642" \
  "${docker_proxy_env[@]+"${docker_proxy_env[@]}"}" \
  "$IMAGE" >/dev/null

printf '==> waiting for Hermes API server\n'
ready=0
for _ in $(seq 1 30); do
  if curl --noproxy '*' -fsS --max-time 2 "http://127.0.0.1:${HOST_PORT}/v1/models" \
    -H 'Authorization: Bearer change-me-local-dev' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
[[ "$ready" -eq 1 ]] || fail "Hermes API server did not become ready"

printf '==> checking runtime manifest and standard entrypoints\n'
docker exec "$CONTAINER" cat /opt/agent/config.json | python3 -m json.tool >/dev/null
docker exec "$CONTAINER" cat /opt/agent/config.json | python3 -c 'import json, sys; assert json.load(sys.stdin)["schemaVersion"] == "devbox-agent-config.v1"'
docker exec "$CONTAINER" /opt/agent/entrypoint.sh run version >/dev/null

printf '==> mutating Hermes native config through JSON protocol\n'
run_config_json provider set-main ccswitch http://host.docker.internal:11434/v1 chat_completions CCSWITCH_API_KEY >/dev/null
run_config_json model set-main gpt-5.4 >/dev/null
secret_output="$(run_config_json env set CCSWITCH_API_KEY sk-local-test)"
[[ "$secret_output" != *sk-local-test* ]] || fail "secret value leaked in env set output"
run_config_json provider get-main >/dev/null
run_config_json model get-main >/dev/null
secret_output="$(run_config_json env get CCSWITCH_API_KEY)"
[[ "$secret_output" != *sk-local-test* ]] || fail "secret value leaked in env get output"
run_config_json env list >/dev/null
expect_config_error model set-main

printf '==> verifying config files\n'
docker exec "$CONTAINER" sh -lc 'grep -q "provider: ccswitch" /home/agent/.hermes/config.yaml'
docker exec "$CONTAINER" sh -lc 'grep -q "providers:" /home/agent/.hermes/config.yaml'
docker exec "$CONTAINER" sh -lc 'grep -q "ccswitch:" /home/agent/.hermes/config.yaml'
docker exec "$CONTAINER" sh -lc 'grep -q "base_url: http://host.docker.internal:11434/v1" /home/agent/.hermes/config.yaml'
docker exec "$CONTAINER" sh -lc 'grep -q "api_mode: chat_completions" /home/agent/.hermes/config.yaml'
docker exec "$CONTAINER" sh -lc 'grep -q "key_env: CCSWITCH_API_KEY" /home/agent/.hermes/config.yaml'
docker exec "$CONTAINER" sh -lc 'grep -q "default: gpt-5.4" /home/agent/.hermes/config.yaml'
docker exec "$CONTAINER" sh -lc 'grep -q "CCSWITCH_API_KEY=sk-local-test" /home/agent/.hermes/.env'
docker exec "$CONTAINER" sh -lc 'test "$(stat -c %a /home/agent/.hermes)" = "700"'
docker exec "$CONTAINER" sh -lc 'test "$(stat -c %a /home/agent/.hermes/.env)" = "600"'

printf '==> checking Hermes API server again\n'
curl --noproxy '*' -fsS --max-time 5 "http://127.0.0.1:${HOST_PORT}/v1/models" \
  -H 'Authorization: Bearer change-me-local-dev' >/dev/null

printf '==> Hermes smoke passed\n'
