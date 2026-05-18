#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-change-me}"
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
  apt-get install -y --no-install-recommends ca-certificates
  rm -rf /var/lib/apt/lists/*
}

install_agent_files() {
  mkdir -p "${AGENT_HOME}/bin" "${AGENT_HOME}/lib" "${AGENT_HOME}/etc"

  cat >"${AGENT_HOME}/bin/start" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'MSG'
change-me agent scaffold is not implemented yet.

Replace agents/<agent>/install.sh with the real upstream install flow,
then make sure it writes the real startup command to /opt/agent/bin/start.
Runtime configuration should come from environment variables, mounted files,
or Kubernetes Secret/ConfigMap references.
MSG
exit 64
EOF

  chmod +x "${AGENT_HOME}/bin/start"
}

install_agent() {
  prepare_install_env
  install_system_packages
  install_agent_files
}

dispatch_install_resource() {
  local resource="${1:?missing install resource}"
  shift || true

  case "$resource" in
    agent)
      install_agent "$@"
      ;;
    *)
      fail "unknown install resource: ${resource}"
      ;;
  esac
}

main() {
  local action="${1:-install}"
  local resource="${2:-agent}"

  shift || true
  shift || true

  case "$action" in
    install)
      dispatch_install_resource "$resource" "$@"
      ;;
    *)
      fail "unknown install action: ${action}"
      ;;
  esac
}

main "$@"
