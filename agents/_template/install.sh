#!/usr/bin/env bash
set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/opt/agent}"

install_agent() {
  mkdir -p "${AGENT_HOME}/bin"

  cat >"${AGENT_HOME}/bin/start" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '[ERROR] replace agents/<agent>/install.sh with the real Linux install flow.\n' >&2
exit 64
EOF

  chmod +x "${AGENT_HOME}/bin/start"
}

main() {
  case "${1:-install}" in
    install)
      install_agent
      ;;
    *)
      printf '[ERROR] unknown install command: %s\n' "$1" >&2
      exit 1
      ;;
  esac
}

main "$@"
