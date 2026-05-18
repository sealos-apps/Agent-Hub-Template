# Agent Contract

This is the repository-level contract for every Agent Hub runtime image.

## Required Files

Each agent directory must contain:

- `Dockerfile`
- `build.env`
- `install.sh`
- `entrypoint.sh`
- `index.json`
- `deploy.yaml`
- `README.md`

Each agent directory must not contain:

- `config.sh`
- `config.json`

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

## Kubernetes Contract

`deploy.yaml` should provide at least:

- `Deployment`
- any Secret referenced by required runtime environment variables
- `Service` when the agent exposes a network port
- `args: ["start"]`
- `AGENT_PORT` when a port is exposed
- `/workspace` as the working directory

Do not mount an empty directory over a path that contains required default
configuration unless the mount provides replacement files or `/opt/agent/bin/start`
bootstraps the required files before launching the runtime.
