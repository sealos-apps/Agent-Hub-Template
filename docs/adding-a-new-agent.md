# Adding A New Agent

This repository keeps only the runtime and template contract. It does not provide a repository-level scaffold generator. To add an agent, copy `agents/_template` and replace the placeholders.

Model initialization, model switching, and current model inspection must follow `docs/agent-hub-ai-agent-switch.md`. Do not add Agent Hub-specific initialization commands to image builds or default startup scripts.

## Directory Layout

```text
agents/my-agent/
  Dockerfile
  build.env
  install.sh
  entrypoint.sh
  template.yaml
  README.md
  manifests/
    devbox.yaml.tmpl
    service.yaml.tmpl
    ingress.yaml.tmpl
```

Do not add `config.sh`, `config.json`, `bootstrap.sh`, or `healthcheck.sh`.

## File Responsibilities

- `Dockerfile`: builds the final image from the shared `AGENT_BASE_IMAGE`, preserves the `/init` entrypoint, and keeps `CMD ["start"]`
- `build.env`: stores non-sensitive build-time defaults such as upstream source URLs and install paths
- `install.sh`: installs the real upstream agent and creates `/opt/agent/bin/start`
- `entrypoint.sh`: shared by all agents and kept byte-for-byte identical to `agents/_template/entrypoint.sh`
- `README.md`: documents build, runtime, configuration, and testing for this agent
- `template.yaml`: Agent Hub template metadata, access behavior, settings schema, and model presets
- `manifests/*.yaml.tmpl`: Devbox, Service, and Ingress templates rendered by Agent Hub

For real agents, `template.yaml.image` must use:

```text
ghcr.io/<owner>/<agent-id>:latest
```

`<owner>` must match the repository owner used by the release workflow. The release workflow publishes both `latest` and `build-*` tags, while Agent Hub reads `latest` from the template.

## Configuration Principles

- Non-sensitive flags: environment variables
- Secrets and tokens: Kubernetes Secrets
- Large structured configuration: mounted files
- Runtime working directory: `/workspace`
- Agent private data directory: `/root/.<agent-name>`

Do not bake runtime secrets into images. Do not route every agent through a repository-specific configuration script.

## Model Configuration

Agents that support model configuration must declare `modelIntegration` in `template.yaml`.

- Single-model agents declare one `main` slot.
- Multi-model agents declare only slots supported by their `ai-agent-switch` adapter.
- Each slot `label` must be an i18n map.
- Each slot `modelTypes` entry must reference a `regionModelTypes.<region>[].key` value.
- Each slot `defaultModels` map must declare every supported region explicitly.
- Each `defaultModels.<region>` value must exist in that region's selectable model list.
- Missing or invalid defaults are errors. Do not fallback to another region or the first model.
- Do not add `settings.agent.provider`, `settings.agent.model`, or `settings.agent.baseURL` for model selection.

See `docs/agent-hub-ai-agent-switch.md` for the full schema and command contract.

## Steps

1. Copy `agents/_template` to `agents/my-agent`.
2. Replace every `change-me` placeholder.
3. Implement the upstream installation flow in `install.sh`.
4. Generate `/opt/agent/bin/start` from `install.sh`.
5. Update `template.yaml` and `manifests/` in the same directory.
6. Write a clear agent `README.md`.
7. Add the agent to `registry/agents.yaml`.
8. Run local contract, syntax, image build, and runtime checks.

`template.yaml` is both the Agent Hub metadata source and the metadata source for local manifests. Define port, user, working directory, and access path in `template.yaml`, then render them into `manifests/*.yaml.tmpl` through `.Agent.*`. Do not hard-code a second user, working directory, or port directly in manifests for a single agent.

## Local Checks

```bash
bash test/validate-agent-contract.sh agents/my-agent
bash -n agents/my-agent/install.sh
bash -n agents/my-agent/entrypoint.sh
docker build -f agents/my-agent/Dockerfile -t agent-hub/my-agent:local .
```

CI rejects an agent if `entrypoint.sh` differs from the template. Do not change one agent's entrypoint unless the repository-wide runtime contract is also changing.
