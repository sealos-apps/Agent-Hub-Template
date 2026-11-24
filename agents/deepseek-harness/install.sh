#!/usr/bin/env bash
set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/opt/agent}"
DSH_HOME="${DSH_HOME:-/root/.dsh}"
AGENT_WORKSPACE="${AGENT_WORKSPACE:-/workspace}"
NODE_MAJOR="${NODE_MAJOR:-24}"
DSH_PACKAGE="${DSH_PACKAGE:-@deepseek-ai/dsh}"
DSH_VERSION="${DSH_VERSION:-latest}"

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

install_node_24() {
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y --no-install-recommends nodejs
  rm -rf /var/lib/apt/lists/*
  local version
  version="$(node -v)"
  [[ "$version" == v24.* ]] || fail "expected Node 24.x, got ${version}"
}

install_dsh() {
  npm install -g "${DSH_PACKAGE}@${DSH_VERSION}"
  npm cache clean --force
  command -v dsh >/dev/null 2>&1 || fail "dsh was not installed"
  dsh --version >/dev/null 2>&1 || fail "dsh --version failed"
}

install_ai_agent_switch() {
  local install_dir tmp_dir archive_path asset_url platform
  install_dir="/opt/ai-agent-switch/bin"
  tmp_dir="$(mktemp -d)"
  archive_path="${tmp_dir}/ai-agent-switch-linux-x64.tar.gz"
  asset_url="https://github.com/sealos-apps/ai-agent-switch/releases/latest/download/ai-agent-switch-linux-x64.tar.gz"
  platform="linux-x64"

  [[ "$(uname -m)" == "x86_64" ]] || fail "ai-agent-switch linux-x64 release requires x86_64"

  (
    set -euo pipefail
    trap 'rm -rf "$tmp_dir"' EXIT
    curl --connect-timeout 10 --max-time 120 --retry 2 --retry-delay 1 -fsSL "$asset_url" -o "$archive_path"
    mkdir -p "$install_dir"
    tar -xzf "$archive_path" -C "$tmp_dir"
    cp "${tmp_dir}/ai-agent-switch-${platform}/ai-agent-switch" "${install_dir}/ai-agent-switch"
    cp "${tmp_dir}/ai-agent-switch-${platform}/as" "${install_dir}/as"
    chmod 0755 "${install_dir}/ai-agent-switch" "${install_dir}/as"
    ln -sf "${install_dir}/ai-agent-switch" /usr/local/bin/ai-agent-switch
    ai-agent-switch --version >/dev/null 2>&1
  ) || fail "ai-agent-switch was not installed"
}

write_start_script() {
  mkdir -p "${AGENT_HOME}/bin" "$DSH_HOME" "$AGENT_WORKSPACE"

  cat >"${AGENT_HOME}/bin/start" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export DSH_HOME="${DSH_HOME:-${AGENT_DATA_DIR:-/root/.dsh}}"
export AGENT_WORKSPACE="${AGENT_WORKSPACE:-/workspace}"
export AGENT_PORT="${AGENT_PORT:-3080}"
export PATH="/opt/agent/bin:/usr/local/bin:${PATH}"

mkdir -p "$DSH_HOME" "$AGENT_WORKSPACE"

# Bridge Agent Hub env vars into standard OpenAI gateway env vars if not already set.
if [[ -z "${OPENAI_API_KEY:-}" && -n "${AGENT_MODEL_APIKEY:-}" ]]; then
  export OPENAI_API_KEY="$AGENT_MODEL_APIKEY"
fi
if [[ -z "${OPENAI_BASE_URL:-}" && -n "${AGENT_MODEL_BASEURL:-}" ]]; then
  export OPENAI_BASE_URL="$AGENT_MODEL_BASEURL"
fi

configure_gateway_provider() {
  local patch_file="${DSH_HOME}/profiles/web/cordis.patch.yml"
  if [[ -f "$patch_file" ]]; then
    return 0
  fi
  if [[ -z "${OPENAI_API_KEY:-}" || -z "${OPENAI_BASE_URL:-}" ]]; then
    return 0
  fi

  node <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const dshHome = process.env.DSH_HOME || "/root/.dsh";
const baseURL = (process.env.OPENAI_BASE_URL || "").trim().replace(/\/+$/, "");
const apiKey = (process.env.OPENAI_API_KEY || "").trim();
const explicitDefault = (process.env.DSH_DEFAULT_MODEL || process.env.AGENT_MODEL || "").trim();
const patchPath = path.join(dshHome, "profiles", "web", "cordis.patch.yml");

if (!baseURL || !apiKey) process.exit(0);

const preferredOrder = [
  "deepseek-v4-pro",
  "deepseek-v4-flash",
  "deepseek-v4.1-flash",
  "deepseek-v3.2",
  "deepseek-chat",
  "deepseek-reasoner",
];

(async () => {
  try {
    const res = await fetch(`${baseURL}/models`, {
      headers: { Authorization: `Bearer ${apiKey}` },
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) {
      console.error(`[WARN] AI Gateway /models returned HTTP ${res.status}; skipping auto provider config`);
      return;
    }
    const body = await res.json();
    const seen = new Set();
    const models = [];
    for (const item of Array.isArray(body?.data) ? body.data : []) {
      const id = typeof item?.id === "string" ? item.id.trim() : "";
      if (!id || seen.has(id)) continue;
      seen.add(id);
      models.push(id);
    }
    if (models.length === 0) {
      console.error("[WARN] AI Gateway /models returned no models; skipping auto provider config");
      return;
    }

    let defaultModel = "";
    if (explicitDefault && seen.has(explicitDefault)) {
      defaultModel = explicitDefault;
    } else {
      for (const candidate of preferredOrder) {
        if (seen.has(candidate)) {
          defaultModel = candidate;
          break;
        }
      }
    }
    if (!defaultModel) {
      defaultModel = models.find((id) => id.toLowerCase().includes("deepseek")) || models[0];
    }

    const lines = [
      "- id: llm-pi-ai",
      "  config:",
      "    providers:",
      "      sealos-ai-gateway:",
      "        displayName: Sealos AI Gateway",
      "        apiKeyEnv: OPENAI_API_KEY",
      "        api: openai-completions",
      `        baseURL: ${JSON.stringify(baseURL)}`,
      "        models:",
      ...models.map((id) => `          - id: ${JSON.stringify(id)}`),
      "- id: agent-default-model",
      "  config:",
      "    provider: sealos-ai-gateway",
      `    model: ${JSON.stringify(defaultModel)}`,
      "",
    ];

    fs.mkdirSync(path.dirname(patchPath), { recursive: true });
    fs.writeFileSync(patchPath, lines.join("\n"), { mode: 0o644 });
    console.log(
      `[INFO] Configured Sealos AI Gateway provider (${models.length} models, default=${defaultModel})`,
    );
  } catch (err) {
    const msg = err && err.message ? err.message : String(err);
    console.error(`[WARN] Failed to configure AI Gateway provider: ${msg}`);
  }
})();
NODE
}

resolve_bind_host() {
  if [[ -n "${DSH_WEB_HOST:-}" ]]; then
    printf '%s\n' "$DSH_WEB_HOST"
    return 0
  fi
  local host_ip
  host_ip="$(hostname -i 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $i != "127.0.0.1") { print $i; exit }}')"
  if [[ -n "$host_ip" ]]; then
    printf '%s\n' "$host_ip"
    return 0
  fi
  printf '127.0.0.1\n'
}

if [[ "$#" -eq 0 ]]; then
  configure_gateway_provider
  bind_host="$(resolve_bind_host)"
  args=(web --no-open --host "$bind_host" --port "$AGENT_PORT")
  if [[ -n "${SANDBOX_PUBLIC_HOST:-}" ]]; then
    args+=(--public-url "https://${SANDBOX_PUBLIC_HOST}" --trusted-host "${SANDBOX_PUBLIC_HOST}")
  fi
  exec dsh "${args[@]}"
fi

case "$1" in
  dsh|ai-agent-switch|node|npm|bash|sh)
    exec "$@"
    ;;
  *)
    exec dsh "$@"
    ;;
esac
EOF

  chmod +x "${AGENT_HOME}/bin/start"
}

install_agent() {
  install_node_24
  install_dsh
  install_ai_agent_switch
  write_start_script
}

main() {
  case "${1:-install}" in
    install)
      install_agent
      ;;
    *)
      fail "unknown install command: $1"
      ;;
  esac
}

main "$@"
