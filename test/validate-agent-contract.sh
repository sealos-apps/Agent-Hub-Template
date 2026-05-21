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
    version = str(data["version"])
    image_tag = str(data.get("image_tag") or version)
    image = str(data["image"])
    if not image.endswith(f":{image_tag}"):
        raise SystemExit(f"{path}: image tag must match image_tag {image_tag}")
    if data.get("image_tag") is not None and not str(data["image_tag"]).startswith(f"{version}-"):
        raise SystemExit(f"{path}: image_tag must be derived from version {version}")
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
  grep -F 'ARG AGENT_BASE_IMAGE=ghcr.io/gitlayzer/agent-devbox-base:0.1.0' "$file" >/dev/null || \
    fail "$file must define ARG AGENT_BASE_IMAGE=ghcr.io/gitlayzer/agent-devbox-base:0.1.0"
  grep -F 'FROM --platform=${BASE_PLATFORM} ${AGENT_BASE_IMAGE}' "$file" >/dev/null || \
    fail "$file must use the shared Agent Hub Devbox base image"
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

validate_template_metadata() {
  local agent_dir="$1"
  local template_dir="$2"
  local index_json
  local template_json

  index_json="$(python3 - "$agent_dir/index.json" <<'PY'
import json
import sys
from pathlib import Path

print(json.dumps(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))))
PY
)"

  if python3 -c 'import yaml' >/dev/null 2>&1; then
    template_json="$(python3 - "$template_dir/template.yaml" <<'PY'
import json
import yaml
import sys
from pathlib import Path

print(json.dumps(yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))))
PY
)"
  elif command -v ruby >/dev/null 2>&1; then
    template_json="$(ruby -rjson -ryaml -e 'puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), permitted_classes: [], permitted_symbols: [], aliases: true))' "$template_dir/template.yaml")"
  else
    fail "python3 with PyYAML or ruby is required to validate Agent Hub template metadata"
  fi

  INDEX_JSON="$index_json" TEMPLATE_JSON="$template_json" python3 - "$agent_dir/index.json" "$template_dir/template.yaml" <<'PY'
import json
import os
import sys

index_path = sys.argv[1]
template_path = sys.argv[2]
index = json.loads(os.environ["INDEX_JSON"])
template = json.loads(os.environ["TEMPLATE_JSON"])
if not isinstance(template, dict):
    raise SystemExit(f"{template_path}: top-level YAML must be a mapping")

required = [
    "id",
    "name",
    "shortName",
    "description",
    "image",
    "port",
    "defaultArgs",
    "backendSupported",
    "workingDir",
    "user",
    "presentation",
    "workspaces",
    "access",
    "actions",
    "settings",
]
for key in required:
    if key not in template or template[key] in ("", None):
        raise SystemExit(f"{template_path}: missing required key {key}")

if template["id"] != index["id"]:
    raise SystemExit(f"{template_path}: id must match {index_path}")
if template["image"] != index["image"]:
    raise SystemExit(f"{template_path}: image must match {index_path}")
if template.get("defaultArgs") != ["start"]:
    raise SystemExit(f'{template_path}: defaultArgs must be ["start"]')
if not isinstance(template.get("port"), int) or template["port"] <= 0:
    raise SystemExit(f"{template_path}: port must be a positive integer")
for legacy in ("bootstrap", "healthcheck"):
    if legacy in template:
        raise SystemExit(f"{template_path}: {legacy} is not supported in this template repository")

presentation = template.get("presentation")
if not isinstance(presentation, dict):
    raise SystemExit(f"{template_path}: presentation must be a mapping")
for key in ("logoKey", "brandColor", "docsLabel"):
    if not presentation.get(key):
        raise SystemExit(f"{template_path}: presentation.{key} is required")

settings = template.get("settings")
if not isinstance(settings, dict):
    raise SystemExit(f"{template_path}: settings must be a mapping")
if not isinstance(settings.get("runtime"), list):
    raise SystemExit(f"{template_path}: settings.runtime must be a list")
if not isinstance(settings.get("agent"), list):
    raise SystemExit(f"{template_path}: settings.agent must be a list")
runtime_keys = {field.get("key") for field in settings["runtime"] if isinstance(field, dict)}
for key in ("cpu", "memory", "storage"):
    if key not in runtime_keys:
        raise SystemExit(f"{template_path}: settings.runtime must include {key}")
agent_fields = [field for field in settings["agent"] if isinstance(field, dict)]
agent_field_index = {field.get("key"): field for field in agent_fields}
for key in ("provider", "model", "baseURL"):
    field = agent_field_index.get(key)
    if not isinstance(field, dict):
        raise SystemExit(f"{template_path}: settings.agent must include {key}")
    if field.get("required") is not True:
        raise SystemExit(f"{template_path}: settings.agent.{key} must be required")
    if field.get("rebootstrap") is not True:
        raise SystemExit(f"{template_path}: settings.agent.{key} must set rebootstrap: true")

provider_options = {
    str(option.get("value")).strip()
    for option in agent_field_index["provider"].get("options", [])
    if isinstance(option, dict) and str(option.get("value", "")).strip()
}
if not provider_options:
    raise SystemExit(f"{template_path}: settings.agent.provider must define options")

presets = template.get("regionModelPresets")
model_types = template.get("regionModelTypes")
if presets is None and model_types is None:
    raise SystemExit(f"{template_path}: regionModelPresets or regionModelTypes is required")

if presets is not None:
    if not isinstance(presets, dict):
        raise SystemExit(f"{template_path}: regionModelPresets must be a mapping")
    for region in ("us", "cn"):
        if region not in presets or not isinstance(presets[region], list):
            raise SystemExit(f"{template_path}: regionModelPresets.{region} must be a list")
        if not presets[region]:
            raise SystemExit(f"{template_path}: regionModelPresets.{region} must not be empty")
        for item in presets[region]:
            if not isinstance(item, dict):
                raise SystemExit(f"{template_path}: regionModelPresets.{region} entries must be mappings")
            for key in ("value", "label", "provider", "apiMode"):
                if not item.get(key):
                    raise SystemExit(f"{template_path}: regionModelPresets.{region} entries must include {key}")
            if str(item["provider"]).strip() not in provider_options:
                raise SystemExit(f"{template_path}: model preset provider {item['provider']} is missing from provider options")

if model_types is not None:
    if not isinstance(model_types, dict):
        raise SystemExit(f"{template_path}: regionModelTypes must be a mapping")
    for region in ("us", "cn"):
        if region not in model_types or not isinstance(model_types[region], list):
            raise SystemExit(f"{template_path}: regionModelTypes.{region} must be a list")
        if not model_types[region]:
            raise SystemExit(f"{template_path}: regionModelTypes.{region} must not be empty")
        for group in model_types[region]:
            if not isinstance(group, dict):
                raise SystemExit(f"{template_path}: regionModelTypes.{region} entries must be mappings")
            for key in ("key", "label", "models"):
                if not group.get(key):
                    raise SystemExit(f"{template_path}: regionModelTypes.{region} entries must include {key}")
            models = group.get("models")
            if not isinstance(models, list) or not models:
                raise SystemExit(f"{template_path}: regionModelTypes.{region}.{group.get('key')} models must be a non-empty list")
            for item in models:
                if not isinstance(item, dict):
                    raise SystemExit(f"{template_path}: regionModelTypes.{region}.{group.get('key')} models must be mappings")
                for key in ("value", "label", "provider", "apiMode"):
                    if not item.get(key):
                        raise SystemExit(f"{template_path}: regionModelTypes.{region}.{group.get('key')} models must include {key}")
                if str(item["provider"]).strip() not in provider_options:
                    raise SystemExit(f"{template_path}: model provider {item['provider']} is missing from provider options")

if template.get("backendSupported") is True:
    if template.get("manifestDir") != "manifests":
        raise SystemExit(f"{template_path}: backendSupported templates must set manifestDir: manifests")
else:
    raise SystemExit(f"{template_path}: backendSupported must be true for local manifests")

access = template.get("access")
if not isinstance(access, list):
    raise SystemExit(f"{template_path}: access must be a list")
access_index = {item.get("key"): item for item in access if isinstance(item, dict)}
if not any(key in access_index for key in ("api", "web-ui")):
    raise SystemExit(f"{template_path}: access must include api or web-ui")
for key in ("api", "web-ui"):
    if key in access_index and not str(access_index[key].get("path", "")).startswith("/"):
        raise SystemExit(f"{template_path}: access.{key}.path must start with /")
files = access_index.get("files")
if isinstance(files, dict) and files.get("rootPath") != template.get("workingDir"):
    raise SystemExit(f"{template_path}: access.files.rootPath must match workingDir")
PY
}

validate_manifest_templates() {
  local template_dir="$1"
  local port="$2"

  for file in devbox.yaml.tmpl service.yaml.tmpl ingress.yaml.tmpl; do
    [[ -f "$template_dir/manifests/$file" ]] || fail "$template_dir is missing manifests/$file"
  done

  grep -F 'kind: Devbox' "$template_dir/manifests/devbox.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/devbox.yaml.tmpl must define a Devbox"
  grep -F 'type: "SSHGate"' "$template_dir/manifests/devbox.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/devbox.yaml.tmpl must use SSHGate networking"
  grep -F 'args:' "$template_dir/manifests/devbox.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/devbox.yaml.tmpl must define args"
  grep -F '      - start' "$template_dir/manifests/devbox.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/devbox.yaml.tmpl must start with the shared start command"
  grep -F "containerPort: $port" "$template_dir/manifests/devbox.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/devbox.yaml.tmpl must expose container port $port"
  grep -F 'user: {{ quote .Agent.User }}' "$template_dir/manifests/devbox.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/devbox.yaml.tmpl must derive user from template.yaml"
  grep -F 'workingDir: {{ quote .Agent.WorkingDir }}' "$template_dir/manifests/devbox.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/devbox.yaml.tmpl must derive workingDir from template.yaml"
  grep -F 'value: {{ quote .Agent.WorkingDir }}' "$template_dir/manifests/devbox.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/devbox.yaml.tmpl must expose AGENT_WORKSPACE/AGENT_WORKDIR from template.yaml"

  grep -F 'kind: Service' "$template_dir/manifests/service.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/service.yaml.tmpl must define a Service"
  grep -F "port: $port" "$template_dir/manifests/service.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/service.yaml.tmpl must expose service port $port"
  grep -F "targetPort: $port" "$template_dir/manifests/service.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/service.yaml.tmpl must target port $port"

  grep -F 'kind: Ingress' "$template_dir/manifests/ingress.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/ingress.yaml.tmpl must define an Ingress"
  grep -F 'cloud.sealos.io/app-deploy-manager:' "$template_dir/manifests/ingress.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/ingress.yaml.tmpl must set cloud.sealos.io/app-deploy-manager"
  grep -F 'cloud.sealos.io/app-deploy-manager-domain:' "$template_dir/manifests/ingress.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/ingress.yaml.tmpl must set cloud.sealos.io/app-deploy-manager-domain"
  grep -F 'kubernetes.io/ingress.class: "nginx"' "$template_dir/manifests/ingress.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/ingress.yaml.tmpl must set kubernetes.io/ingress.class"
  grep -F 'nginx.ingress.kubernetes.io/proxy-body-size: "32m"' "$template_dir/manifests/ingress.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/ingress.yaml.tmpl must set nginx proxy-body-size"
  grep -F 'nginx.ingress.kubernetes.io/ssl-redirect: "false"' "$template_dir/manifests/ingress.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/ingress.yaml.tmpl must disable nginx ssl redirect"
  grep -F 'nginx.ingress.kubernetes.io/backend-protocol: "HTTP"' "$template_dir/manifests/ingress.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/ingress.yaml.tmpl must set nginx backend protocol"
  grep -F 'nginx.ingress.kubernetes.io/server-snippet: |' "$template_dir/manifests/ingress.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/ingress.yaml.tmpl must set nginx server-snippet"
  grep -F 'host: {{ quote .IngressDomain }}' "$template_dir/manifests/ingress.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/ingress.yaml.tmpl must use .IngressDomain"
  grep -F "number: $port" "$template_dir/manifests/ingress.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/ingress.yaml.tmpl must route to port $port"
  grep -F 'secretName: "wildcard-cert"' "$template_dir/manifests/ingress.yaml.tmpl" >/dev/null || \
    fail "$template_dir/manifests/ingress.yaml.tmpl must use wildcard-cert TLS"
}

read_template_port() {
  local file="$1"

  if python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$file" <<'PY'
from pathlib import Path
import sys
import yaml

print(yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))["port"])
PY
    return
  elif command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -e 'puts YAML.safe_load(File.read(ARGV[0]), permitted_classes: [], permitted_symbols: [], aliases: true)["port"]' "$file"
    return
  else
    fail "python3 with PyYAML or ruby is required to read $file"
  fi
}

validate_agent_hub_template_contract() {
  local agent_dir="$1"
  local template_dir="$agent_dir"
  local port

  [[ -f "$template_dir/template.yaml" ]] || fail "$agent_dir is missing template.yaml"

  validate_yaml_file "$template_dir/template.yaml"
  port="$(read_template_port "$template_dir/template.yaml")"
  validate_manifest_templates "$template_dir" "$port"

  if [[ "$agent_dir" != "agents/_template" ]]; then
    validate_template_metadata "$agent_dir" "$template_dir"
  fi
}

validate_workflow_contracts() {
  [[ -f .gitmodules ]] || fail ".gitmodules is required so Actions can fetch devbox-runtime"
  grep -F '[submodule "devbox-runtime"]' .gitmodules >/dev/null || \
    fail ".gitmodules must define devbox-runtime"
  grep -F 'url = https://github.com/gitlayzer/devbox-runtime.git' .gitmodules >/dev/null || \
    fail ".gitmodules must pin the devbox-runtime source repository"
  grep -F 'submodules: recursive' .github/workflows/build.yml >/dev/null || \
    fail ".github/workflows/build.yml must checkout devbox-runtime submodule before base builds"
  grep -F 'submodules: recursive' .github/workflows/release.yml >/dev/null || \
    fail ".github/workflows/release.yml must checkout devbox-runtime submodule before base builds"
  grep -F 'or ".gitmodules" in changed_files' .github/workflows/build.yml >/dev/null || \
    fail ".github/workflows/build.yml must rebuild agents when .gitmodules changes"
  grep -F 'path == "devbox-runtime" or path.startswith("devbox-runtime/")' .github/workflows/build.yml >/dev/null || \
    fail ".github/workflows/build.yml must rebuild agents when devbox-runtime changes"
  grep -F 'COPY devbox-runtime/tooling/scripts' base/Dockerfile >/dev/null || \
    fail "base/Dockerfile must copy devbox-runtime tooling scripts"
  grep -F 'COPY devbox-runtime/tooling/docs' base/Dockerfile >/dev/null || \
    fail "base/Dockerfile must copy devbox-runtime tooling docs"
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
  grep -F '"image_tag": index.get("image_tag")' .github/workflows/release.yml >/dev/null || \
    fail ".github/workflows/release.yml must carry optional per-agent image_tag"
  grep -F 'AGENT_IMAGE_TAG: ${{ matrix.image_tag' .github/workflows/release.yml >/dev/null || \
    fail ".github/workflows/release.yml must prefer image_tag over version when tagging images"
  grep -F 'tag = str(item.get("image_tag") or item["version"])' .github/workflows/release.yml >/dev/null || \
    fail ".github/workflows/release.yml sync step must preserve image_tag in templates"
  if grep -R --line-number -i -E '\[(skip ci|ci skip|skip actions|actions skip)\]' .github/workflows >/dev/null; then
    fail "workflow-generated commits must not include skip-ci directives"
  fi
}

required_files=(Dockerfile build.env install.sh entrypoint.sh index.json template.yaml README.md)
forbidden_files=(config.sh config.json deploy.yaml bootstrap.sh healthcheck.sh)
[[ ! -d template ]] || fail "templates must live in each agents/<agent>/ directory; remove top-level template/"
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
  validate_index "$agent_dir"
  validate_dockerfile_contract "$agent_dir"
  validate_agent_hub_template_contract "$agent_dir"

  grep -F 'bin/start' "$agent_dir/install.sh" >/dev/null || \
    fail "$agent_dir/install.sh must create /opt/agent/bin/start"
  if [[ "$agent_dir" != "agents/_template" ]]; then
    grep -F 'AI_AGENT_SWITCH_VERSION is required' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must require AI_AGENT_SWITCH_VERSION"
    grep -F 'install_ai_agent_switch_from_npm' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must install ai-agent-switch from AI_AGENT_SWITCH_VERSION"
    grep -F 'npm install -g --prefix "$prefix" "ai-agent-switch@${AI_AGENT_SWITCH_VERSION}"' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must install ai-agent-switch into an isolated prefix"
    grep -F 'ln -sf "${prefix}/bin/ai-agent-switch" /usr/local/bin/ai-agent-switch' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must expose only the ai-agent-switch command globally"
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
