# Hermes Agent 镜像

这个目录把官方 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent/) 封装成 Sealos Devbox 可接入的标准镜像。

当前实现遵守第一阶段标准：

- 固定入口：`entrypoint.sh start`
- 镜像内置 `ai-agent-switch`
- 镜像构建和默认启动不执行模型初始化命令
- 当前模型通过 `ai-agent-switch client show hermes --json` 读取
- 不承诺部署时透传任意 Hermes CLI 参数
- 配置直接落到 Hermes 原生 `~/.hermes/config.yaml` 与 `~/.hermes/.env`

## Upstream Install

- Hermes: clone `https://github.com/NousResearch/hermes-agent.git`, then install `.[all]` with `uv`
- ai-agent-switch: `curl -fsSL https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh | sh`

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

Agent Hub 注入的模型变量由平台后续流程处理；镜像本身只提供 Hermes 和 `ai-agent-switch` 二进制。

### 初始化或切换模型

```bash
docker run --rm \
  -e CCSWITCH_API_KEY=sk-local-test \
  agent-hub/hermes-agent:dev \
  bash -lc '
    ai-agent-switch provider init \
      --id ccswitch \
      --name CCSwitch \
      --base-url http://host.docker.internal:15721/v1 \
      --api-key-env CCSWITCH_API_KEY \
      --model gpt-5.4:chat_completions \
      --default-model gpt-5.4 \
      --json
    ai-agent-switch client configure \
      --client hermes \
      --slot main=ccswitch/gpt-5.4 \
      -y \
      --json
  '
```

这个命令会写入 Hermes 原生 `providers.ccswitch`，并设置 `model.provider = ccswitch`、`model.default = gpt-5.4`。密钥通过环境变量引用，不写入明文 token。

### 查看当前模型

```bash
docker run --rm agent-hub/hermes-agent:dev ai-agent-switch client show hermes --json
```

## 本地持久化测试

```bash
mkdir -p .tmp/hermes-home

docker run -d \
  --name hermes-local \
  -p 127.0.0.1:28642:8642 \
  -v "$PWD/.tmp/hermes-home:/root/.hermes" \
  -e API_SERVER_KEY=sk-local-hermes \
  -e CCSWITCH_API_KEY=sk-local-test \
  agent-hub/hermes-agent:dev \
  bash -lc '
    ai-agent-switch provider init \
      --id ccswitch \
      --name CCSwitch \
      --base-url http://host.docker.internal:15721/v1 \
      --api-key-env CCSWITCH_API_KEY \
      --model gpt-5.4:chat_completions \
      --default-model gpt-5.4 \
      --json
    ai-agent-switch client configure --client hermes --slot main=ccswitch/gpt-5.4 -y --json
    exec /opt/agent/bin/start
  '

docker exec -e HOME=/root hermes-local ai-agent-switch client show hermes --json
```

本地持久化测试建议在启动长驻 gateway 前完成 `init`。
