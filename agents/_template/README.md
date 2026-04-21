# change-me agent template

First read: `docs/adding-a-new-agent.md`

This directory is the scaffold for a new agent image.

Before you try to build it, update at least:

  - `Dockerfile`
  - `install.sh`
  - `config.sh`
  - `config.json`
  - `entrypoint.sh`
  - `index.json`
  - `index.yaml`
  - `README.md`

Quick checklist:

- Replace placeholder metadata such as `replace-me`
- Keep all agent-specific logic inside this directory
- Leave `enabled: false` in `registry/agents.yaml` until the image really builds and passes smoke tests

Important:

- `Dockerfile` must use `FROM ghcr.io/gitlayzer/ubuntu:22.04-base`
- `config.sh` is responsible for routing commands like `set config ...` and `get config`
- `config.json` is used by the frontend to render configuration actions for `config.sh`
- `index.json` describes the agent for frontend listing and display
- `_template/index.yaml` is the Kubernetes deployment manifest template for this agent
- The template only defines the dispatch shape; each agent should implement its own `set_config`, `get_config`, `delete_config`, and `list_config`
- `entrypoint.sh` is responsible for the startup function and positional argument handling
- `install.sh` is responsible for routing install commands like `install agent`
- The template only defines the install dispatch shape; each agent should implement its own install functions
- Replace the placeholder installation logic with the real upstream agent runtime.
- Do not leave the generated agent enabled until the image builds and the smoke test passes.
- Keep agent-specific logic inside the agent directory.
