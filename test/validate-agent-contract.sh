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

read_expected_image_owner() {
  if [[ -n "${GITHUB_REPOSITORY_OWNER:-}" ]]; then
    printf '%s\n' "${GITHUB_REPOSITORY_OWNER,,}"
    return
  fi

  local origin_url
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  case "$origin_url" in
    https://github.com/*/*)
      origin_url="${origin_url#https://github.com/}"
      printf '%s\n' "${origin_url%%/*}" | tr '[:upper:]' '[:lower:]'
      ;;
    git@github.com:*/*)
      origin_url="${origin_url#git@github.com:}"
      printf '%s\n' "${origin_url%%/*}" | tr '[:upper:]' '[:lower:]'
      ;;
    *)
      fail "GITHUB_REPOSITORY_OWNER or a GitHub origin remote is required to validate template image owners"
      ;;
  esac
}

validate_dockerfile_contract() {
  local agent_dir="$1"
  local file="$agent_dir/Dockerfile"

  grep -F 'ARG BASE_PLATFORM=linux/amd64' "$file" >/dev/null || \
    fail "$file must define ARG BASE_PLATFORM=linux/amd64"
  grep -F 'ARG AGENT_BASE_IMAGE=ghcr.io/nightwhite/agent-devbox-base' "$file" >/dev/null || \
    fail "$file must define ARG AGENT_BASE_IMAGE=ghcr.io/nightwhite/agent-devbox-base"
  grep -F 'FROM --platform=${BASE_PLATFORM} ${AGENT_BASE_IMAGE}' "$file" >/dev/null || \
    fail "$file must use the shared Agent Hub Devbox base image"
  grep -Eq '^[[:space:]]*ENTRYPOINT[[:space:]]+\[[[:space:]]*"/init"[[:space:]]*,[[:space:]]*"/opt/agent/entrypoint.sh"[[:space:]]*\]' "$file" || \
    fail "$file must keep the /init entrypoint"
  grep -Eq '^[[:space:]]*CMD[[:space:]]+\[[[:space:]]*"start"[[:space:]]*\]' "$file" || \
    fail "$file must default CMD to start"
  if grep -F 'AI_AGENT_SWITCH_' "$file" >/dev/null; then
    fail "$file must not accept ai-agent-switch build args"
  fi
  if grep -F 'org.sealos.ai-agent-switch.' "$file" >/dev/null; then
    fail "$file must not label a pinned ai-agent-switch version"
  fi

  if grep -Eq '(COPY|ADD)[[:space:]].*(config\.json|config\.sh)' "$file"; then
    fail "$file must not copy or add config.sh or config.json"
  fi
}

validate_template_metadata() {
  local template_dir="$1"
  local template_json
  local expected_owner

  expected_owner="$(read_expected_image_owner)"

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

  EXPECTED_IMAGE_OWNER="$expected_owner" TEMPLATE_JSON="$template_json" python3 - "$template_dir/template.yaml" <<'PY'
import json
import os
import sys

template_path = sys.argv[1]
template = json.loads(os.environ["TEMPLATE_JSON"])
if not isinstance(template, dict):
    raise SystemExit(f"{template_path}: top-level YAML must be a mapping")

allowed_api_modes = {
    "chat_completions",
    "openai_compatible",
    "codex_responses",
    "anthropic_messages",
    "image_generation",
    "video_generation",
    "audio_transcriptions",
    "audio_speech",
    "embeddings",
}

allowed_model_kinds = {
    "llm",
    "vision",
    "image_generation",
    "video_generation",
    "asr",
    "tts",
    "embedding",
}

api_mode_kinds = {
    "chat_completions": {"llm", "vision"},
    "openai_compatible": {"llm", "vision"},
    "codex_responses": {"llm", "vision"},
    "anthropic_messages": {"llm", "vision"},
    "image_generation": {"image_generation"},
    "video_generation": {"video_generation"},
    "audio_transcriptions": {"asr"},
    "audio_speech": {"tts"},
    "embeddings": {"embedding"},
}

slot_model_kinds = {
    "main": {"llm", "vision"},
    "vision": {"llm", "vision"},
    "image": {"image_generation"},
    "video": {"video_generation"},
    "asr": {"asr"},
    "tts": {"tts"},
    "embedding": {"embedding"},
}

def validate_model_kind(template_path, location, item, api_mode):
    kind = str(item.get("kind") or "").strip()
    if not kind:
        raise SystemExit(f"{template_path}: {location} must include kind")
    if kind not in allowed_model_kinds:
        raise SystemExit(f"{template_path}: {location} kind must be one of {', '.join(sorted(allowed_model_kinds))}")
    allowed_kinds = api_mode_kinds.get(api_mode, set())
    if kind not in allowed_kinds:
        raise SystemExit(f"{template_path}: {location} kind {kind} is incompatible with apiMode {api_mode}")

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

if template.get("defaultArgs") != ["start"]:
    raise SystemExit(f'{template_path}: defaultArgs must be ["start"]')
if template.get("user") != "root":
    raise SystemExit(f'{template_path}: user must be "root"')
agent_id = str(template.get("id") or "").strip()
image = str(template.get("image") or "").strip()
expected_owner = os.environ["EXPECTED_IMAGE_OWNER"]
expected_image = f"ghcr.io/{expected_owner}/{agent_id}:latest"
if image != expected_image:
    raise SystemExit(f"{template_path}: image must be {expected_image}")
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
    if key in agent_field_index:
        raise SystemExit(f"{template_path}: settings.agent.{key} must be declared through modelIntegration, not settings.agent")

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
            api_mode = str(item.get("apiMode") or "").strip()
            if api_mode not in allowed_api_modes:
                raise SystemExit(f"{template_path}: regionModelPresets.{region}.{item.get('value')} apiMode must be one of {', '.join(sorted(allowed_api_modes))}")
            validate_model_kind(template_path, f"regionModelPresets.{region}.{item.get('value')}", item, api_mode)

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
                api_mode = str(item.get("apiMode") or "").strip()
                if api_mode not in allowed_api_modes:
                    raise SystemExit(f"{template_path}: regionModelTypes.{region}.{group.get('key')}.{item.get('value')} apiMode must be one of {', '.join(sorted(allowed_api_modes))}")
                validate_model_kind(template_path, f"regionModelTypes.{region}.{group.get('key')}.{item.get('value')}", item, api_mode)

integration = template.get("modelIntegration")
if not isinstance(integration, dict):
    raise SystemExit(f"{template_path}: modelIntegration is required")
if integration.get("type") != "ai-agent-switch":
    raise SystemExit(f"{template_path}: modelIntegration.type must be ai-agent-switch")
if not str(integration.get("client") or "").strip():
    raise SystemExit(f"{template_path}: modelIntegration.client is required")

provider = integration.get("provider")
if not isinstance(provider, dict):
    raise SystemExit(f"{template_path}: modelIntegration.provider must be a mapping")
for key in ("id", "apiKeyEnv"):
    if not str(provider.get(key) or "").strip():
        raise SystemExit(f"{template_path}: modelIntegration.provider.{key} is required")
provider_id = str(provider.get("id") or "").strip()
provider_name = provider.get("name")
if not isinstance(provider_name, dict) or not str(provider_name.get("zh") or "").strip() or not str(provider_name.get("en") or "").strip():
    raise SystemExit(f"{template_path}: modelIntegration.provider.name must include zh and en")
base_url = provider.get("baseURL")
if not isinstance(base_url, dict) or not str(base_url.get("source") or "").strip():
    raise SystemExit(f"{template_path}: modelIntegration.provider.baseURL.source is required")

if not isinstance(model_types, dict):
    raise SystemExit(f"{template_path}: regionModelTypes is required for modelIntegration")
if presets is not None:
    for region, items in presets.items():
        for item in items:
            model_provider = str(item.get("provider") or "").strip()
            if not model_provider.startswith(f"custom:{provider_id}-"):
                raise SystemExit(f"{template_path}: regionModelPresets.{region} provider {model_provider} must use modelIntegration.provider.id {provider_id}")
region_type_models = {}
region_type_model_kinds = {}
for region, groups in model_types.items():
    if not isinstance(groups, list):
        raise SystemExit(f"{template_path}: regionModelTypes.{region} must be a list")
    region_type_models[region] = {}
    region_type_model_kinds[region] = {}
    for group in groups:
        if not isinstance(group, dict):
            raise SystemExit(f"{template_path}: regionModelTypes.{region} entries must be mappings")
        type_key = str(group.get("key") or "").strip()
        models = group.get("models")
        if not type_key or not isinstance(models, list):
            continue
        for item in models:
            if isinstance(item, dict):
                model_provider = str(item.get("provider") or "").strip()
                if not model_provider.startswith(f"custom:{provider_id}-"):
                    raise SystemExit(f"{template_path}: regionModelTypes.{region} provider {model_provider} must use modelIntegration.provider.id {provider_id}")
        region_type_models[region][type_key] = {
            str(item.get("value") or "").strip()
            for item in models
            if isinstance(item, dict) and str(item.get("value") or "").strip()
        }
        region_type_model_kinds[region][type_key] = {
            str(item.get("value") or "").strip(): str(item.get("kind") or "").strip()
            for item in models
            if isinstance(item, dict) and str(item.get("value") or "").strip()
        }

slots = integration.get("slots")
if not isinstance(slots, list) or not slots:
    raise SystemExit(f"{template_path}: modelIntegration.slots must be a non-empty list")
slot_keys = set()
region_keys = set(region_type_models)
for slot in slots:
    if not isinstance(slot, dict):
        raise SystemExit(f"{template_path}: modelIntegration.slots entries must be mappings")
    slot_key = str(slot.get("key") or "").strip()
    if not slot_key:
        raise SystemExit(f"{template_path}: modelIntegration.slots[].key is required")
    if slot_key in slot_keys:
        raise SystemExit(f"{template_path}: duplicate modelIntegration slot {slot_key}")
    slot_keys.add(slot_key)

    label = slot.get("label")
    if not isinstance(label, dict) or not str(label.get("zh") or "").strip() or not str(label.get("en") or "").strip():
        raise SystemExit(f"{template_path}: modelIntegration.slots.{slot_key}.label must include zh and en")

    slot_model_types = slot.get("modelTypes")
    if not isinstance(slot_model_types, list) or not slot_model_types:
        raise SystemExit(f"{template_path}: modelIntegration.slots.{slot_key}.modelTypes must be non-empty")
    slot_type_keys = [str(item or "").strip() for item in slot_model_types]
    if any(not item for item in slot_type_keys):
        raise SystemExit(f"{template_path}: modelIntegration.slots.{slot_key}.modelTypes must not include empty values")
    for region, type_models in region_type_models.items():
        missing_types = [type_key for type_key in slot_type_keys if type_key not in type_models]
        if missing_types:
            raise SystemExit(f"{template_path}: modelIntegration.slots.{slot_key}.modelTypes reference missing regionModelTypes.{region} keys: {', '.join(missing_types)}")

    if "defaultModel" in slot:
        raise SystemExit(f"{template_path}: modelIntegration.slots.{slot_key} must use defaultModels, not defaultModel")
    default_models = slot.get("defaultModels")
    if not isinstance(default_models, dict):
        raise SystemExit(f"{template_path}: modelIntegration.slots.{slot_key}.defaultModels must be a mapping")
    default_regions = set(default_models)
    missing_regions = sorted(region_keys - default_regions)
    if missing_regions:
        raise SystemExit(f"{template_path}: modelIntegration.slots.{slot_key}.defaultModels missing regions: {', '.join(missing_regions)}")
    unknown_regions = sorted(default_regions - region_keys)
    if unknown_regions:
        raise SystemExit(f"{template_path}: modelIntegration.slots.{slot_key}.defaultModels has unknown regions: {', '.join(unknown_regions)}")
    for region, default_model in default_models.items():
        model_value = str(default_model or "").strip()
        if not model_value:
            raise SystemExit(f"{template_path}: modelIntegration.slots.{slot_key}.defaultModels.{region} is required")
        allowed_models = set()
        model_kinds = {}
        for type_key in slot_type_keys:
            allowed_models.update(region_type_models[region][type_key])
            model_kinds.update(region_type_model_kinds[region][type_key])
        if model_value not in allowed_models:
            raise SystemExit(f"{template_path}: modelIntegration.slots.{slot_key}.defaultModels.{region} must reference a model in the slot modelTypes")
        allowed_kinds = slot_model_kinds.get(slot_key)
        if allowed_kinds is not None and model_kinds.get(model_value) not in allowed_kinds:
            raise SystemExit(f"{template_path}: modelIntegration.slots.{slot_key}.defaultModels.{region} kind must be one of {', '.join(sorted(allowed_kinds))}")

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
    validate_template_metadata "$template_dir"
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
  grep -F 'echo "latest"' .github/workflows/release.yml >/dev/null || \
    fail ".github/workflows/release.yml must publish the latest agent image tag"
  grep -F 'trace_tag="build-$(date -u +%Y%m%d)-${short_sha}"' .github/workflows/release.yml >/dev/null || \
    fail ".github/workflows/release.yml must publish traceable build image tags"
  grep -F 'image = f"ghcr.io/{owner}/{name}:latest"' .github/workflows/release.yml >/dev/null || \
    fail ".github/workflows/release.yml sync step must keep template images on latest"
  grep -F 'sync-latest-templates:' .github/workflows/release.yml >/dev/null || \
    fail ".github/workflows/release.yml must name the template sync job after latest images"
  if grep -R --line-number -i -E '\[(skip ci|ci skip|skip actions|actions skip)\]' .github/workflows >/dev/null; then
    fail "workflow-generated commits must not include skip-ci directives"
  fi
}

required_files=(Dockerfile build.env install.sh entrypoint.sh template.yaml README.md)
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

  validate_dockerfile_contract "$agent_dir"
  validate_agent_hub_template_contract "$agent_dir"

  grep -F 'bin/start' "$agent_dir/install.sh" >/dev/null || \
    fail "$agent_dir/install.sh must create /opt/agent/bin/start"
  if [[ "$agent_dir" != "agents/_template" ]]; then
    grep -F 'raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must install ai-agent-switch through the official curl installer"
    grep -F 'AI_AGENT_SWITCH_LATEST_RELEASE_URL' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must resolve the latest ai-agent-switch release"
    grep -F 'install_dir="/opt/ai-agent-switch/bin"' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must install ai-agent-switch into /opt/ai-agent-switch/bin"
    grep -F 'ln -sf "${install_dir}/ai-agent-switch" /usr/local/bin/ai-agent-switch' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must expose only the ai-agent-switch command globally"
    if grep -F -- '--install-dir /usr/local/bin' "$agent_dir/install.sh" >/dev/null; then
      fail "$agent_dir/install.sh must not install ai-agent-switch shortcuts directly into /usr/local/bin"
    fi
    if grep -E '(^|[[:space:]])as[|)]' "$agent_dir/install.sh" >/dev/null; then
      fail "$agent_dir/install.sh must not expose the ai-agent-switch as shortcut"
    fi
    if grep -F 'AI_AGENT_SWITCH_VERSION' "$agent_dir/install.sh" >/dev/null; then
      fail "$agent_dir/install.sh must not pin ai-agent-switch through AI_AGENT_SWITCH_VERSION"
    fi
    if grep -F 'install_ai_agent_switch_from_source' "$agent_dir/install.sh" >/dev/null; then
      fail "$agent_dir/install.sh must not build ai-agent-switch from source"
    fi
    if grep -F 'agent-hub init' "$agent_dir/install.sh" >/dev/null; then
      fail "$agent_dir/install.sh must not run ai-agent-switch agent-hub init during build or startup"
    fi
  fi
  if [[ "$agent_dir" == "agents/openclaw" ]]; then
    grep -F 'openclaw@latest' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must install the latest OpenClaw package"
    grep -F 'config.gateway.auth.token = token' "$agent_dir/install.sh" >/dev/null || \
      fail "$agent_dir/install.sh must write OPENCLAW_GATEWAY_TOKEN into openclaw.json"
  fi
done

validate_workflow_contracts

old_contract_refs="$(mktemp)"
if grep -R --line-number -E 'agent-hub[[:space:]]+(init|sync|init-model)|--provider-type|--request-format' \
  .github agents test README.md docs \
  --exclude=validate-agent-contract.sh \
  --exclude-dir=superpowers >"$old_contract_refs"; then
  cat "$old_contract_refs" >&2
  rm -f "$old_contract_refs"
  fail "old ai-agent-switch agent-hub contract must not be used"
fi
rm -f "$old_contract_refs"

printf '==> agent contract validation passed\n'
