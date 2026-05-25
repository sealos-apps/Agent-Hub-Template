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
- `build.env`: pins upstream source and build-time options
- `install.sh`: installs CowAgent from upstream source and writes `/opt/agent/bin/start`
- `entrypoint.sh`: shared Agent Hub command router
- `index.json`: Agent Hub display metadata
- `template.yaml` and `manifests/`: Agent Hub deployment template

The pinned upstream source ref is `2.0.9`.

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

The startup script also maps common OpenAI names:

- `OPENAI_API_KEY` -> `OPEN_AI_API_KEY`
- `OPENAI_BASE_URL` -> `OPEN_AI_API_BASE`

Use a persistent data directory:

```bash
docker run --rm -p 127.0.0.1:9899:9899 \
  -v "$(pwd)/.cowagent:/home/agent/.cowagent" \
  -v "$(pwd)/workspace:/workspace" \
  agent-hub/cowagent:dev
```

On first start, `/home/agent/.cowagent/config.json` is created from the baked
default template. CowAgent still supports overriding config values by
environment variables.

## Build options

`build.env` supports:

- `COWAGENT_REF`: upstream git tag or branch, currently `2.0.9`
- `COWAGENT_INSTALL_OPTIONAL`: install optional parsing/voice packages, default `true`
- `COWAGENT_INSTALL_AGENTMESH`: install `agentmesh-sdk` for CowAgent's agent plugin, default `true`
- `COWAGENT_INSTALL_BROWSER`: install Playwright browser support, default `false`
- `COWAGENT_USE_CN_MIRROR`: use China mirrors for apt and pip, default `false`

Example:

```bash
docker build \
  --build-arg BASE_PLATFORM=linux/amd64 \
  --build-arg AGENT_BASE_IMAGE=ghcr.io/gitlayzer/agent-devbox-base:0.1.0 \
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
