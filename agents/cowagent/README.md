# CowAgent Agent image

This image packages the upstream `zhayujie/CowAgent` project for Agent Hub.

CowAgent is a Python-based AI assistant and agent framework with a Web console,
skills, memory, tools, and integrations for WeChat, Feishu, DingTalk, WeCom,
QQ, WeChat Official Account, terminal, and Web.

## Contract

This agent follows the shared Agent Hub runtime contract:

- no `config.sh`
- no `config.json`
- shared `/opt/agent/entrypoint.sh`
- runtime-specific startup logic lives in `/opt/agent/bin/start`
- default command is `start`
- runtime configuration is injected through environment variables, Secret,
  ConfigMap, or mounted files

## Build contents

- `Dockerfile`: builds the runtime image from the shared Agent Hub Devbox base
- `build.env`: stores the upstream source URL and install paths
- `install.sh`: installs CowAgent from upstream source and writes `/opt/agent/bin/start`
- `entrypoint.sh`: shared Agent Hub command router
- `template.yaml` and `manifests/`: Agent Hub deployment template

Agent Hub master image: `ghcr.io/sealos-apps/cowagent:master`.

## Startup behavior

- image `ENTRYPOINT` is `["/init", "/opt/agent/entrypoint.sh"]`
- image `CMD` is `["start"]`
- default `start` runs `python app.py`
- default channel is `web`
- default Web port is `9899`
- `shell` opens `/bin/bash`
- other arguments are forwarded to the `cow` CLI unless they look like app
  arguments

## Local usage

Build:

```bash
docker build -f agents/cowagent/Dockerfile -t agent-hub/cowagent:dev .
```

Run Web console:

```bash
docker run --rm -p 127.0.0.1:9899:9899 agent-hub/cowagent:dev
```

Open:

```text
http://127.0.0.1:9899/chat
```

Run with OpenAI-compatible configuration:

```bash
docker run --rm -p 127.0.0.1:9899:9899 \
  -e OPEN_AI_API_KEY=sk-xxxxxxxxxx \
  -e OPEN_AI_API_BASE=https://api.openai.com/v1 \
  -e model=gpt-5.4-mini \
  -e bot_type=openai \
  agent-hub/cowagent:dev
```

Use a persistent data directory:

```bash
docker run --rm -p 127.0.0.1:9899:9899 \
  -v "$(pwd)/.cowagent:/root/.cowagent" \
  -v "$(pwd)/workspace:/workspace" \
  agent-hub/cowagent:dev
```

On first start, `/root/.cowagent/config.json` is created from the baked
default template. CowAgent still supports overriding config values by
environment variables.

## Build Inputs

`build.env` supports:

- `COWAGENT_GIT_URL`: upstream repository URL
- `COWAGENT_SRC`: source checkout path
- `COWAGENT_VENV`: Python virtualenv path
- `COWAGENT_HOME`: runtime data path

Example:

```bash
docker build \
  --build-arg BASE_PLATFORM=linux/amd64 \
  --build-arg AGENT_BASE_IMAGE=ghcr.io/sealos-apps/agent-devbox-base \
  -f agents/cowagent/Dockerfile \
  -t agent-hub/cowagent:dev .
```

## Agent Hub template notes

The manifest templates expose port `9899` and use `args: ["start"]`.

Runtime secrets should be provided by Agent Hub settings or external Kubernetes
Secret/ConfigMap wiring.

Suggested keys:

- `web-password`
- `open-ai-api-key`
- `open-ai-api-base`
- `deepseek-api-key`

Use a persistent volume instead of `emptyDir` for production if you need memory,
skills, uploaded files, and config changes to survive pod restarts.
