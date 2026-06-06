# Agent Contract

This is the repository-level contract for every Agent Hub runtime image.

Model initialization and switching are defined in
`docs/agent-hub-ai-agent-switch.md`. Do not introduce agent-specific Agent Hub
initialization commands in image build scripts or default startup scripts.

## Required Files

Each agent directory must contain:

- `Dockerfile`
- `build.env`
- `install.sh`
- `entrypoint.sh`
- `template.yaml`
- `README.md`
- `manifests/devbox.yaml.tmpl`
- `manifests/service.yaml.tmpl`
- `manifests/ingress.yaml.tmpl`

Each agent keeps its Agent Hub runtime template inside its own directory:

```text
agents/<agent-id>/
  template.yaml
  manifests/
    devbox.yaml.tmpl
    service.yaml.tmpl
    ingress.yaml.tmpl
```

Each agent directory must not contain:

- `config.sh`
- `config.json`
- `bootstrap.sh`
- `healthcheck.sh`

## Build Contract

The Dockerfile must:

- define `ARG BASE_PLATFORM=linux/amd64`
- define `ARG AGENT_BASE_IMAGE=ghcr.io/sealos-apps/agent-devbox-base`
- use `FROM --platform=${BASE_PLATFORM} ${AGENT_BASE_IMAGE}`
- preserve `ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]`
- use `CMD ["start"]`
- copy the shared `entrypoint.sh` to `/opt/agent/entrypoint.sh`
- run `install.sh` during image build

The shared base image is built from `base/` and carries the Devbox runtime
contract: `/init`, s6 services, SSH support, the `devbox` user,
`/workspace`, Node.js 22, Python tooling, `uv`, and common agent utilities.

## Runtime Contract

All agents use the same startup chain:

```text
/init
  -> /opt/agent/entrypoint.sh
    -> /opt/agent/bin/start
      -> real upstream agent runtime
```

`entrypoint.sh` must stay byte-for-byte identical to
`agents/_template/entrypoint.sh`.

`install.sh` must create an executable:

```text
/opt/agent/bin/start
```

The shared entrypoint handles only:

- `shell`: open `/bin/bash`
- `start`: run `/opt/agent/bin/start`
- any other command: forward it to `/opt/agent/bin/start`

## Standard Runtime Environment

The shared entrypoint exports:

- `AGENT_NAME`
- `AGENT_HOME`
- `AGENT_START`
- `AGENT_DATA_DIR`
- `AGENT_WORKSPACE`
- `AGENT_PORT`
- `AGENT_LOG_LEVEL`

Agent-specific secrets and provider settings must be injected externally through
environment variables, Kubernetes Secret, ConfigMap, or mounted files.

## Agent Hub Template Contract

`agents/<agent-id>/template.yaml` follows the schema used by
`sealos-apps/agent-hub`, not the generic `app.sealos.io/v1 Template` CR.

Required metadata includes:

- `id`
- `name`
- `shortName`
- `description`
- `image`
- `port`
- `defaultArgs: ["start"]`
- `backendSupported`
- `workingDir`
- `manifestDir: manifests`
- `user`
- `presentation`
- `workspaces`
- `access`
- `actions`
- `settings`
- `regionModelPresets`

Templates that support model configuration must also include `modelIntegration`.
That field is the entry point for Agent Hub model integration and is specified
in `docs/agent-hub-ai-agent-switch.md`.

`template.yaml` is the single metadata source consumed by Agent Hub. Release
automation keeps real agent image refs on the repository owner used by the
release workflow:

```text
ghcr.io/<owner>/<agent-id>:latest
```

Release builds also push traceable images in the form
`ghcr.io/<owner>/<agent>:build-YYYYMMDD-<12-char-sha>`. Those `build-*` tags are
for audit and rollback investigations; Agent Hub deploys the `latest` ref from
`template.yaml`.

`template.yaml` is the metadata source for local manifests:

- `port` must match the Devbox exposed port, Service port, and Ingress backend port.
- `workingDir` must match `access.files.rootPath` and is rendered into Devbox
  `spec.config.workingDir`, `AGENT_WORKSPACE`, and `AGENT_WORKDIR`.
- `user` is rendered into Devbox `spec.config.user`.
- `defaultArgs` must stay `["start"]`.
- `backendSupported` must be `true` and `manifestDir` must be `manifests`.
- `bootstrap` and `healthcheck` are not part of this repository contract.
- `deploy.yaml` is not part of this repository contract; Agent Hub deployment
  resources live under `manifests/`.

Model field ownership:

- `modelIntegration`: declares the integration type, `ai-agent-switch` client,
  provider metadata, model slots, i18n labels, mutability, defaults, and allowed
  model type keys.
- `modelIntegration.slots[].defaultModels`: declares each region default
  explicitly. Every value must exist in the matching `regionModelTypes.<region>`
  model list; missing or invalid region defaults are errors and must not fall
  back to another region or list order.
- `regionModelTypes`: owns region-specific model type keys and the model lists
  referenced by `modelIntegration.slots[].modelTypes`.
- `regionModelPresets`: owns flattened provider/model presets consumed by Agent
  Hub compatibility code and UI options.
- `runtimeProvider`: for CowAgent model presets, declares the native provider
  that CowAgent should receive after Agent Hub syncs through `ai-agent-switch`.
  Current values are `openai`, `gemini`, and `dashscope`.
- `settings`: owns non-model runtime settings; do not add new
  `settings.agent.provider`, `settings.agent.model`, or
  `settings.agent.baseURL` fields for model selection.

Agent Hub renders and validates model configuration from template data, then
executes `ai-agent-switch provider init` and
`ai-agent-switch client configure` inside the running Devbox. Templates must not
define shell commands for model initialization or model switching.

The manifest templates are rendered by Agent Hub with Go template data such as
`.Agent.Name`, `.Agent.Namespace`, `.Image`, `.SelectorLabels`, and
`.IngressDomain`. They must create a `Devbox`, `Service`, and `Ingress`.

The Devbox must use `args: ["start"]` so the image goes through the shared
`/opt/agent/entrypoint.sh -> /opt/agent/bin/start` runtime chain.
