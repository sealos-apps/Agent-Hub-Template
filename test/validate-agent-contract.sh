#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

if [[ "$#" -gt 0 ]]; then
  agents=("$@")
else
  agent_list="$(
    if python3 -c 'import yaml' >/dev/null 2>&1; then
      python3 - <<'PY'
import sys
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
    elif command -v ruby >/dev/null 2>&1; then
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
    else
      exit 1
    fi
  )" || fail "python3 with PyYAML or ruby is required to read registry/agents.yaml"
  agents=()
  while IFS= read -r agent_dir; do
    [[ -n "$agent_dir" ]] && agents+=("$agent_dir")
  done <<<"$agent_list"
fi
required_files=(Dockerfile install.sh entrypoint.sh config.sh config.json index.json deploy.yaml README.md)

validate_json_file() {
  local file="$1"
  python3 -m json.tool "$file" >/dev/null
}

validate_yaml_file() {
  local file="$1"
  if python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$file" <<'PY'
import sys
from pathlib import Path
import yaml

yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))
PY
    return
  fi

  if command -v ruby >/dev/null 2>&1; then
    ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV[0]), permitted_classes: [], permitted_symbols: [], aliases: true)' "$file" >/dev/null
    return
  fi

  fail "python3 with PyYAML or ruby is required to validate YAML: $file"
}

validate_manifest() {
  local agent_dir="$1"
  python3 - "$agent_dir/config.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
if data.get("schemaVersion") != "devbox-agent-config.v1":
    raise SystemExit(f"{path}: missing schemaVersion devbox-agent-config.v1")
if data.get("script") != "/opt/agent/config.sh":
    raise SystemExit(f"{path}: script must be /opt/agent/config.sh")
allowed_kinds = {"read", "write", "delete"}
allowed_types = {"text", "password", "number", "select"}
for locale in ("zh", "en"):
    resources = data.get(locale, {}).get("resources")
    if not isinstance(resources, list) or not resources:
        raise SystemExit(f"{path}: {locale}.resources must be a non-empty list")
    for resource in resources:
        if not resource.get("resource"):
            raise SystemExit(f"{path}: resource id is required")
        actions = resource.get("actions")
        if not isinstance(actions, list) or not actions:
            raise SystemExit(f"{path}: resource {resource.get('resource')} needs actions")
        for action in actions:
            kind = action.get("kind")
            if kind not in allowed_kinds:
                raise SystemExit(f"{path}: action {action.get('action')} has invalid kind {kind!r}")
            args = action.get("args")
            if not isinstance(args, list):
                raise SystemExit(f"{path}: action {action.get('action')} args must be a list")
            for arg in args:
                arg_type = arg.get("type")
                if arg_type not in allowed_types:
                    raise SystemExit(f"{path}: arg {arg.get('name')} has invalid type {arg_type!r}")
                if arg_type == "password" and arg.get("sensitive") is not True:
                    raise SystemExit(f"{path}: password arg {arg.get('name')} must set sensitive=true")
PY
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
PY
}

validate_dockerfile_contract() {
  local file="$1"

  grep -Eq '^[[:space:]]*ENTRYPOINT[[:space:]]+\[[[:space:]]*"/init"[[:space:]]*,[[:space:]]*"/opt/agent/entrypoint.sh"[[:space:]]*\]' "$file" || \
    fail "$file must keep the /init entrypoint"
  grep -Eq '^[[:space:]]*CMD[[:space:]]+\[[[:space:]]*"start"[[:space:]]*\]' "$file" || \
    fail "$file must default CMD to start"
  grep -Eq '^[[:space:]]*COPY([[:space:]]+--[^[:space:]]+)*[[:space:]]+.*config\.json[[:space:]]+/opt/agent/config\.json([[:space:]]|$)' "$file" || \
    fail "$file must copy config.json to /opt/agent/config.json"
}

validate_deploy_contract() {
  local file="$1"
  if python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$file" <<'PY'
import sys
from pathlib import Path
import yaml

path = Path(sys.argv[1])
data = yaml.safe_load(path.read_text(encoding="utf-8"))
if not isinstance(data, dict):
    raise SystemExit(f"{path}: deploy YAML must be a mapping")
containers = (
    data.get("spec", {})
    .get("template", {})
    .get("spec", {})
    .get("containers", [])
)
if not isinstance(containers, list):
    raise SystemExit(f"{path}: deploy spec.template.spec.containers must be a list")
if not any(container.get("args") == ["start"] for container in containers if isinstance(container, dict)):
    raise SystemExit(f'{path}: deploy container args must be ["start"]')
PY
    return
  fi

  if command -v ruby >/dev/null 2>&1; then
    ruby -e '
      require "yaml"
      path = ARGV[0]
      data = YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: true)
      abort("#{path}: deploy YAML must be a mapping") unless data.is_a?(Hash)
      containers = data.dig("spec", "template", "spec", "containers") || []
      abort("#{path}: deploy spec.template.spec.containers must be a list") unless containers.is_a?(Array)
      ok = containers.any? { |container| container.is_a?(Hash) && container["args"] == ["start"] }
      abort("#{path}: deploy container args must be [\"start\"]") unless ok
    ' "$file"
    return
  fi

  fail "python3 with PyYAML or ruby is required to validate deploy contract: $file"
}

for agent_dir in "${agents[@]}"; do
  [[ -d "$agent_dir" ]] || fail "agent directory not found: $agent_dir"
  printf '==> validating %s\n' "$agent_dir"

  for required in "${required_files[@]}"; do
    [[ -f "$agent_dir/$required" ]] || fail "$agent_dir is missing $required"
  done

  bash -n "$agent_dir/install.sh"
  bash -n "$agent_dir/entrypoint.sh"
  bash -n "$agent_dir/config.sh"
  validate_json_file "$agent_dir/config.json"
  validate_json_file "$agent_dir/index.json"
  validate_yaml_file "$agent_dir/deploy.yaml"
  validate_manifest "$agent_dir"
  validate_index "$agent_dir"
  validate_dockerfile_contract "$agent_dir/Dockerfile"
  validate_deploy_contract "$agent_dir/deploy.yaml"

  grep -F 'json_success' "$agent_dir/config.sh" >/dev/null || \
    fail "$agent_dir/config.sh must emit JSON success envelopes"
  grep -F 'json_error' "$agent_dir/config.sh" >/dev/null || \
    fail "$agent_dir/config.sh must emit JSON error envelopes"
done

printf '==> agent contract validation passed\n'
