# Hermes Agent 镜像

这个目录把官方 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent/) 封装成 Sealos Devbox 可接入的标准镜像。

当前实现遵守第一阶段标准：

- 固定入口：`entrypoint.sh start`
- 镜像内置 `ai-agent-switch`
- 默认启动会把 Agent Hub 注入的 `AGENT_MODEL_*` 环境变量通过 `ai-agent-switch agent-hub init` 写入模型配置
- 当前模型通过 `ai-agent-switch client show hermes --json` 读取
- 不承诺部署时透传任意 Hermes CLI 参数
- 配置直接落到 Hermes 原生 `~/.hermes/config.yaml` 与 `~/.hermes/.env`

## Upstream Pin

- upstream tag: `v2026.5.16`
- package version: `0.14.0`
- pinned ref: `a91a57fa5a13d516c38b07a141a9ce8a3daabeb0`
- Agent Hub test image: `ghcr.io/gitlayzer/hermes-agent:0.14.0-agenthub-test.2`

## 运行方式

### 默认启动

```bash
docker run --rm \
  -p 127.0.0.1:28642:8642 \
  -e API_SERVER_KEY=sk-local-hermes \
  agent-hub/hermes-agent:dev
```

等价于：

```bash
docker run --rm \
  -p 127.0.0.1:28642:8642 \
  -e API_SERVER_KEY=sk-local-hermes \
  agent-hub/hermes-agent:dev start
```

默认启动必须通过运行时环境变量或 Kubernetes Secret 提供 `API_SERVER_KEY`。

镜像内部固定执行：

```bash
hermes gateway run
```

### 调试 shell

```bash
docker run --rm -it agent-hub/hermes-agent:dev shell
```

### 原生 CLI 调试

```bash
docker run --rm agent-hub/hermes-agent:dev run version
```

## 模型配置方式

Hermes 这一层不再维护仓库私有配置脚本，模型初始化和切换统一交给 `ai-agent-switch`，最终仍然写入 Hermes 原生配置：

- `~/.hermes/config.yaml`
- `~/.hermes/.env`

在 Agent Hub/Devbox 路径下，容器启动时会读取 `AGENT_MODEL_PROVIDER`、`AGENT_MODEL_BASEURL`、`AGENT_MODEL_APIKEY`、`AGENT_MODEL`、`AGENT_MODEL_API_MODE`，自动执行一次 `agent-hub init -y --json`。AI Proxy provider 会使用 `AIPROXY_API_KEY`，普通自定义 provider 使用 `AGENT_MODEL_APIKEY`。

### 初始化或切换模型

```bash
docker run --rm \
  -e CCSWITCH_API_KEY=sk-local-test \
  agent-hub/hermes-agent:dev \
  ai-agent-switch agent-hub init \
    --client hermes \
    --provider-id ccswitch \
    --provider-name CCSwitch \
    --model-type openai-chat-compatible \
    --base-url http://host.docker.internal:15721/v1 \
    --api-key-env CCSWITCH_API_KEY \
    --model gpt-5.4 \
    --available-model gpt-5.4 \
    -y \
    --json
```

这个命令会写入 Hermes 原生 `providers.ccswitch`，并设置 `model.provider = ccswitch`、`model.default = gpt-5.4`。密钥通过环境变量引用，不写入明文 token。

### 查看当前模型

```bash
docker run --rm agent-hub/hermes-agent:dev ai-agent-switch client show hermes --json
```

### Agent Hub 初始化命令自检

```bash
docker run --rm agent-hub/hermes-agent:dev ai-agent-switch agent-hub init --help
```

## 本地持久化测试

```bash
mkdir -p .tmp/hermes-home

docker run -d \
  --name hermes-local \
  -p 127.0.0.1:28642:8642 \
  -v "$PWD/.tmp/hermes-home:/home/agent/.hermes" \
  -e API_SERVER_KEY=sk-local-hermes \
  -e CCSWITCH_API_KEY=sk-local-test \
  agent-hub/hermes-agent:dev \
  bash -lc '
    ai-agent-switch agent-hub init \
      --client hermes \
      --provider-id ccswitch \
      --provider-name CCSwitch \
      --model-type openai-chat-compatible \
      --base-url http://host.docker.internal:15721/v1 \
      --api-key-env CCSWITCH_API_KEY \
      --model gpt-5.4 \
      --available-model gpt-5.4 \
      -y \
      --json
    exec /opt/agent/bin/start
  '

docker exec --user agent -e HOME=/home/agent hermes-local ai-agent-switch client show hermes --json
```

本地持久化测试建议在启动长驻 gateway 前完成 `init`，这和 Agent Hub 初始化容器配置的路径一致。
