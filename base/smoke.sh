#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-agent-hub/agent-devbox-base:local}"
CONTAINER="${CONTAINER:-agent-devbox-base-smoke-$RANDOM}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf '==> verifying %s\n' "$IMAGE"
docker run --rm --platform "$DOCKER_PLATFORM" --entrypoint /bin/bash "$IMAGE" -lc '
  set -euo pipefail
  test -x /init
  id devbox >/dev/null
  test -d /home/devbox/project
  test -d /workspace
  test -w /workspace
  command -v node >/dev/null
  command -v npm >/dev/null
  command -v python3 >/dev/null
  command -v pip3 >/dev/null
  python3 -m venv /tmp/base-venv-check
  rm -rf /tmp/base-venv-check
  command -v uv >/dev/null
  command -v rg >/dev/null
  for tool in bash busybox curl wget git file less openssl tar gzip xz zip unzip rsync ssh sshd locale logrotate ps ip ping lsof getent find grep sed gawk; do
    if ! command -v "$tool" >/dev/null; then
      echo "required tool is missing: $tool" >&2
      exit 1
    fi
  done
  test -x /usr/sbin/devbox-sdk-server
  test -f /etc/s6-overlay/s6-rc.d/startup/run
  test -x /etc/s6-overlay/s6-rc.d/startup/up
  head -n 1 /etc/s6-overlay/s6-rc.d/startup/up | grep -Eq "^#!"
  test -f /etc/s6-overlay/s6-rc.d/sshd/run
  test -x /etc/s6-overlay/s6-rc.d/sshd-log-prepare/up
  head -n 1 /etc/s6-overlay/s6-rc.d/sshd-log-prepare/up | grep -F "#!/command/execlineb -P"
  test -x /etc/s6-overlay/s6-rc.d/crond-log-prepare/up
  head -n 1 /etc/s6-overlay/s6-rc.d/crond-log-prepare/up | grep -F "#!/command/execlineb -P"
  test -f /etc/s6-overlay/s6-rc.d/sdk-server/run
  test -f /etc/s6-overlay-hook/pre-rc-init.d/pre-rc-init.sh
  node -e "process.exit(process.versions.node.split(\".\")[0] === \"22\" ? 0 : 1)"
  touch /workspace/.root-write && rm /workspace/.root-write
  runuser -u devbox -- bash -lc "test -w /home/devbox/project && touch /home/devbox/project/.devbox-write && rm /home/devbox/project/.devbox-write"
'

printf '==> starting /init for s6 smoke\n'
docker run -d \
  --platform "$DOCKER_PLATFORM" \
  --name "$CONTAINER" \
  -e DEVBOX_ENV=development \
  -e DEVBOX_JWT_SECRET=base-smoke-secret \
  "$IMAGE" >/dev/null

ready=0
for _ in $(seq 1 20); do
  if docker exec "$CONTAINER" sh -lc 'test -d /run/service/sshd && test -d /run/service/crond && test -d /run/service/sdk-server' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
[[ "$ready" -eq 1 ]] || {
  docker logs "$CONTAINER" >&2 || true
  fail "s6 services did not become ready"
}

docker exec "$CONTAINER" sh -lc 'test -f /usr/start/pod_id || true; test -f /run/utmp; pgrep -f "sshd -D" >/dev/null; pgrep -f "devbox-sdk-server" >/dev/null'

printf '==> base smoke passed\n'
