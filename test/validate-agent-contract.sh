#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

load_agent_dirs() {
  if [[ "$#" -gt 0 ]]; then
    printf '%s\n' "$@"
    return
  fi

  if python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - <<'PY'
from pathlib import Path
import yaml

registry_path = Path("registry/agents.yaml")
data = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
if not isinstance(data, dict):
    raise SystemExit(f"{registry_path}: top-level YAML must be a mapping")
items = data.get("agents")
if not isinstance(items, list):
    raise SystemExit(f"{registry_path}: agents must be a list")

paths = ["agents/_template"]
for index, item in enumerate(items):
    if not isinstance(item, dict):
        raise SystemExit(f"{registry_path}: agents[{index}] must be a mapping")
    path = item.get("path")
    if path:
        paths.append(str(path))

seen = set()
for path in paths:
    if path not in seen:
        seen.add(path)
        print(path)
PY
    return
  fi

  if command -v ruby >/dev/null 2>&1; then
    ruby <<'RB'
require "yaml"

registry_path = "registry/agents.yaml"
data = YAML.safe_load(File.read(registry_path), permitted_classes: [], permitted_symbols: [], aliases: true)
abort("#{registry_path}: top-level YAML must be a mapping") unless data.is_a?(Hash)
items = data["agents"]
abort("#{registry_path}: agents must be a list") unless items.is_a?(Array)

paths = ["agents/_template"]
items.each_with_index do |item, index|
  abort("#{registry_path}: agents[#{index}] must be a mapping") unless item.is_a?(Hash)
  path = item["path"]
  paths << path.to_s if path && !path.to_s.empty?
end

seen = {}
paths.each do |path|
  next if seen[path]
  seen[path] = true
  puts path
end
RB
    return
  fi

  fail "python3 with PyYAML or ruby is required to read registry/agents.yaml"
}

validate_json_file() {
  local file="$1"
  python3 -m json.tool "$file" >/dev/null
}

validate_yaml_file() {
  local file="$1"
  if python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$file" <<'PY'
from pathlib import Path
import sys
import yaml

docs = list(yaml.safe_load_all(Path(sys.argv[1]).read_text(encoding="utf-8")))
if not docs or not any(isinstance(doc, dict) for doc in docs):
    raise SystemExit(f"{sys.argv[1]}: YAML must contain at least one mapping document")
PY
    return
  fi

  if command -v ruby >/dev/null 2>&1; then
    ruby -e 'require "yaml"; stream = Psych.parse_stream(File.read(ARGV[0])); abort("#{ARGV[0]}: YAML must contain at least one mapping document") unless stream.children.any? { |doc| doc.root.is_a?(Psych::Nodes::Mapping) }' "$file" >/dev/null
    return
  fi

  fail "python3 with PyYAML or ruby is required to validate YAML: $file"
}

validate_index() {
  local agent_dir="$1"
  python3 - "$agent_dir/index.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
kind = data.get("runtime", {}).get("kind")
if kind not in {"service", "tool"}:
    raise SystemExit(f"{path}: runtime.kind must be service or tool")
for key in ("id", "name", "version", "image", "repo_path", "readme"):
    if not data.get(key):
        raise SystemExit(f"{path}: missing required key {key}")
if data.get("id") != "_template":
    switch_version = data.get("ai_agent_switch_version")
    if not switch_version:
        raise SystemExit(f"{path}: missing required key ai_agent_switch_version")
    if switch_version == "actions-resolved":
        raise SystemExit(f"{path}: ai_agent_switch_version must be concrete")
PY
}

validate_dockerfile_contract() {
  local agent_dir="$1"
  local file="$agent_dir/Dockerfile"

  grep -F 'ARG BASE_PLATFORM=linux/amd64' "$file" >/dev/null || \
    fail "$file must define ARG BASE_PLATFORM=linux/amd64"
  grep -F 'ghcr.io/gitlayzer/ubuntu:22.04-base' "$file" >/dev/null || \
    fail "$file must use ghcr.io/gitlayzer/ubuntu:22.04-base"
  grep -Eq '^[[:space:]]*ENTRYPOINT[[:space:]]+\[[[:space:]]*"/init"[[:space:]]*,[[:space:]]*"/opt/agent/entrypoint.sh"[[:space:]]*\]' "$file" || \
    fail "$file must keep the /init entrypoint"
  grep -Eq '^[[:space:]]*CMD[[:space:]]+\[[[:space:]]*"start"[[:space:]]*\]' "$file" || \
    fail "$file must default CMD to start"
  if [[ "$agent_dir" != "agents/_template" ]]; then
    grep -F 'ARG AI_AGENT_SWITCH_VERSION' "$file" >/dev/null || \
      fail "$file must define ARG AI_AGENT_SWITCH_VERSION"
    grep -F 'ARG AI_AGENT_SWITCH_METADATA' "$file" >/dev/null || \
      fail "$file must define ARG AI_AGENT_SWITCH_METADATA"
    grep -F 'org.sealos.ai-agent-switch.version' "$file" >/dev/null || \
      fail "$file must label org.sealos.ai-agent-switch.version"
    grep -F 'org.sealos.ai-agent-switch.metadata' "$file" >/dev/null || \
      fail "$file must label org.sealos.ai-agent-switch.metadata"
  fi

  if grep -Eq '(COPY|ADD)[[:space:]].*(config\.json|config\.sh)' "$file"; then
    fail "$file must not copy or add config.sh or config.json"
  fi
}

validate_deploy_contract() {
  local file="$1"
  if python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$file" <<'PY'
import sys
from pathlib import Path
import yaml

path = Path(sys.argv[1])
docs = [doc for doc in yaml.safe_load_all(path.read_text(encoding="utf-8")) if isinstance(doc, dict)]
deployments = [doc for doc in docs if doc.get("kind") == "Deployment"]
if not deployments:
    raise SystemExit(f"{path}: deploy YAML must include a Deployment")
for deployment in deployments:
    containers = (
        deployment.get("spec", {})
        .get("template", {})
        .get("spec", {})
        .get("containers", [])
    )
    if not isinstance(containers, list):
        raise SystemExit(f"{path}: Deployment containers must be a list")
    if not any(container.get("args") == ["start"] for container in containers if isinstance(container, dict)):
        raise SystemExit(f'{path}: Deployment container args must be ["start"]')
PY
    return
  fi

  grep -F 'kind: Deployment' "$file" >/dev/null || fail "$file must include a Deployment"
  grep -F 'args: ["start"]' "$file" >/dev/null || fail "$file must set args: [\"start\"]"
}

validate_workflow_contracts() {
  grep -F 'source_ref="9d78561ecbd35ce775f7acfe70e3bdb6617b9b51"' .github/workflows/build.yml >/dev/null || \
    fail ".github/workflows/build.yml must build ai-agent-switch from the Agent Hub init source ref"
  grep -F 'source_ref="9d78561ecbd35ce775f7acfe70e3bdb6617b9b51"' .github/workflows/release.yml >/dev/null || \
    fail ".github/workflows/release.yml must build ai-agent-switch from the Agent Hub init source ref"
  grep -F 'AI_AGENT_SWITCH_SOURCE_URL=${{ needs.prepare.outputs' .github/workflows/build.yml >/dev/null || \
    fail ".github/workflows/build.yml must pass AI_AGENT_SWITCH_SOURCE_URL into docker build"
  grep -F 'AI_AGENT_SWITCH_SOURCE_URL=${{ needs.prepare.outputs' .github/workflows/release.yml >/dev/null || \
    fail ".github/workflows/release.yml must pass AI_AGENT_SWITCH_SOURCE_URL into docker build"
  grep -F 'AI_AGENT_SWITCH_METADATA=${{ needs.prepare.outputs' .github/workflows/build.yml >/dev/null || \
    fail ".github/workflows/build.yml must pass AI_AGENT_SWITCH_METADATA into docker build"
  grep -F 'AI_AGENT_SWITCH_METADATA=${{ needs.prepare.outputs' .github/workflows/release.yml >/dev/null || \
    fail ".github/workflows/release.yml must pass AI_AGENT_SWITCH_METADATA into docker build"
  if grep -R --line-number -i -E '\[(skip ci|ci skip|skip actions|actions skip)\]' .github/workflows >/dev/null; then
    fail "workflow-generated commits must not include skip-ci directives"
  fi
}

required_files=(Dockerfile build.env install.sh entrypoint.sh index.json deploy.yaml README.md)
forbidden_files=(config.sh config.json)
entrypoint_ref="$(mktemp)"
trap 'rm -f "$entrypoint_ref"' EXIT
cat agents/_template/entrypoint.sh >"$entrypoint_ref"

agents=()
while IFS= read -r agent_dir; do
  [[ -n "$agent_dir" ]] && agents+=("$agent_dir")
done < <(load_agent_dirs "$@")

for agent_dir in "${agents[@]}"; do
  [[ -d "$agent_dir" ]] || fail "agent directory not found: $agent_dir"
  printf '==> validating %s\n' "$agent_dir"

  for required in "${required_files[@]}"; do
    [[ -f "$agent_dir/$required" ]] || fail "$agent_dir is missing $required"
  done

  for forbidden in "${forbidden_files[@]}"; do
    [[ ! -e "$agent_dir/$forbidden" ]] || fail "$agent_dir must not contain $forbidden"
  done

  bash -n "$agent_dir/install.sh"
  bash -n "$agent_dir/entrypoint.sh"
  cmp -s "$entrypoint_ref" "$agent_dir/entrypoint.sh" || \
    fail "$agent_dir/entrypoint.sh must match agents/_template/entrypoint.sh"

  validate_json_file "$agent_dir/index.json"
  validate_yaml_file "$agent_dir/deploy.yaml"
  validate_index "$agent_dir"
  validate_dockerfile_contract "$agent_dir"
  validate_deploy_contract "$agent_dir/deploy.yaml"

  grep -F 'bin/start' "$agent_dir/install.sh" >/dev/null || \
    fail "$agent_dir/install.sh must create /opt/agent/bin/start"
  if [[ "$agent_dir" != "agents/_template" ]]; then
    grep -F 'AI_AGENT_SWITCH_VERSION is required' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must require AI_AGENT_SWITCH_VERSION"
    grep -F 'npm install -g "ai-agent-switch@${AI_AGENT_SWITCH_VERSION}"' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must install ai-agent-switch from AI_AGENT_SWITCH_VERSION"
    grep -F 'AI_AGENT_SWITCH_SOURCE_URL' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must support explicit ai-agent-switch source builds"
    grep -F 'install_ai_agent_switch_from_source' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must build ai-agent-switch from explicit source when requested"
    grep -F 'target="linux-$(uname -m' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must detect ai-agent-switch source build target"
    grep -F 'bun run npm:build-package -- --platform "$target"' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must build ai-agent-switch from source for the detected target"
    grep -F 'verify_ai_agent_switch_agent_hub' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must verify ai-agent-switch agent-hub init with a dry-run command"
    grep -F '"requiresConfirmation": true' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must assert ai-agent-switch agent-hub dry-run JSON"
    grep -F 'ai-agent-switch|' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must allow direct ai-agent-switch execution from the image entrypoint"
  fi
done

validate_workflow_contracts

old_contract_refs="$(mktemp)"
if grep -R --line-number -E 'agent-hub[[:space:]]+init-model|--provider-type|--request-format' \
  .github agents test README.md docs \
  --exclude=validate-agent-contract.sh \
  --exclude-dir=superpowers >"$old_contract_refs"; then
  cat "$old_contract_refs" >&2
  rm -f "$old_contract_refs"
  fail "old ai-agent-switch agent-hub init-model contract must not be used"
fi
rm -f "$old_contract_refs"

printf '==> agent contract validation passed\n'
