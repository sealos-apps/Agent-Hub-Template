# Agent Contract

This is the repository-level contract for every Agent Hub runtime image.

## Required Files

Each agent directory must contain:

- `Dockerfile`
- `build.env`
- `install.sh`
- `entrypoint.sh`
- `index.json`
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

- use `ghcr.io/gitlayzer/ubuntu:22.04-base`
- define `ARG BASE_PLATFORM=linux/amd64`
- preserve `ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]`
- use `CMD ["start"]`
- copy the shared `entrypoint.sh` to `/opt/agent/entrypoint.sh`
- run `install.sh` during image build

## Metadata Contract

Each non-template `index.json` must include:

- `ai_agent_switch_version`: the `ai-agent-switch` version or source-ref
  identifier used when the image was built. Release automation syncs this field
  from the resolved build metadata.

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

The template image must match `agents/<agent>/index.json.image`. Release
automation keeps both files synchronized after version image publishing.

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

The manifest templates are rendered by Agent Hub with Go template data such as
`.Agent.Name`, `.Agent.Namespace`, `.Image`, `.SelectorLabels`, and
`.IngressDomain`. They must create a `Devbox`, `Service`, and `Ingress`.

The Devbox must use `args: ["start"]` so the image goes through the shared
`/opt/agent/entrypoint.sh -> /opt/agent/bin/start` runtime chain.
