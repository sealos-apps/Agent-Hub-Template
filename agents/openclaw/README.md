# OpenClaw Agent 镜像

这个目录把官方 [openclaw/openclaw](https://github.com/openclaw/openclaw) 的容器接入方式收敛成 Sealos Devbox 可接入的标准镜像。

当前实现遵守第一阶段标准：

- 固定入口：`entrypoint.sh start`
- 镜像内置 `ai-agent-switch`
- Agent Hub 通过 `ai-agent-switch agent-hub init` 写入模型配置
- 当前模型通过 `ai-agent-switch client show openclaw --json` 读取
- 不把 `onboard --install-daemon` 当成容器标准启动方式
- 容器里的标准长驻进程固定为 `openclaw gateway run`
- 配置直接落到 OpenClaw 原生 `~/.openclaw/openclaw.json` 与 `~/.openclaw/.env`

## Upstream Pin

- npm package: `openclaw@2026.4.24`
- reference repo head used for study: `3b5463591be93c676a074134c5e384f8024a6945`
- reference repo package version: `2026.4.26` (not published to npm at the time of this adapter update)

## 运行方式

### 默认启动

```bash
docker run --rm \
  -p 127.0.0.1:28789:18789 \
  -e OPENCLAW_GATEWAY_TOKEN=sk-local-openclaw \
  agent-hub/openclaw:dev
```

等价于：

```bash
docker run --rm \
  -p 127.0.0.1:28789:18789 \
  -e OPENCLAW_GATEWAY_TOKEN=sk-local-openclaw \
  agent-hub/openclaw:dev start
```

默认启动必须通过运行时环境变量或 Kubernetes Secret 提供 `OPENCLAW_GATEWAY_TOKEN`。

镜像内部固定执行：

```bash
openclaw gateway run
```

### 调试 shell

```bash
docker run --rm -it agent-hub/openclaw:dev shell
```

### 原生 CLI 调试

```bash
docker run --rm agent-hub/openclaw:dev run --help
```

## 模型配置方式

OpenClaw 这一层不再维护仓库私有配置脚本，模型初始化和切换统一交给 `ai-agent-switch`，最终仍然写入 OpenClaw 原生配置：

- `~/.openclaw/openclaw.json`
- `~/.openclaw/.env`
- `/opt/openclaw/plugin-runtime-deps` for OpenClaw bundled plugin runtime deps

### 初始化或切换模型

```bash
docker run --rm \
  -e CCSWITCH_API_KEY=sk-local-test \
  agent-hub/openclaw:dev \
  ai-agent-switch agent-hub init \
    --client openclaw \
    --provider-id ccswitch \
    --provider-name CCSwitch \
    --model-type openai-chat-compatible \
    --base-url http://host.docker.internal:15721/v1 \
    --api-key-env CCSWITCH_API_KEY \
    --model gpt-5.4-mini \
    --available-model gpt-5.4-mini \
    -y \
    --json
```

上面的命令会写入：

```text
agents.defaults.model.primary = "ccswitch/gpt-5.4-mini"
models.providers.ccswitch.api = "openai-completions"
```

密钥通过环境变量引用，不写入明文 token。

### 查看当前模型

```bash
docker run --rm agent-hub/openclaw:dev ai-agent-switch client show openclaw --json
```

### Agent Hub 初始化命令自检

```bash
docker run --rm agent-hub/openclaw:dev ai-agent-switch agent-hub init --help
```

## 本地持久化测试

```bash
mkdir -p .tmp/openclaw-home

docker run -d \
  --name openclaw-local \
  -p 127.0.0.1:28789:18789 \
  -v "$PWD/.tmp/openclaw-home:/home/agent/.openclaw" \
  -e OPENCLAW_GATEWAY_TOKEN=sk-local-openclaw \
  -e CCSWITCH_API_KEY=sk-local-test \
  agent-hub/openclaw:dev \
  bash -lc '
    ai-agent-switch agent-hub init \
      --client openclaw \
      --provider-id ccswitch \
      --provider-name CCSwitch \
      --model-type openai-chat-compatible \
      --base-url http://host.docker.internal:15721/v1 \
      --api-key-env CCSWITCH_API_KEY \
      --model gpt-5.4-mini \
      --available-model gpt-5.4-mini \
      -y \
      --json
    exec /opt/agent/bin/start
  '

docker exec --user agent -e HOME=/home/agent openclaw-local ai-agent-switch client show openclaw --json
```

容器默认把 `gateway.bind` 固定为 `lan`，这样 `docker run -p ...` 后宿主机可以直接访问 published port。这里额外设置 `OPENCLAW_NO_RESPAWN=1`，避免 `docker run` 场景下需要 full-process restart 的配置变更直接让容器退出；默认设置 `OPENCLAW_SKIP_CHANNELS=1`，沿用 upstream dev/live-test 入口，避免容器网络里启动 Telegram 等频道 sidecar；默认设置 `OPENCLAW_DISABLE_BONJOUR=1`，沿用 upstream Docker 建议，避免 Docker bridge 网络里的 mDNS 探测导致 gateway 不稳定。

默认原生配置会禁用 `acpx`、`bonjour`、`browser` 这几个 bundled sidecar 插件。第一阶段 Devbox adapter 只验收 gateway、模型 provider、配置热更新和 inference 链路；不默认打开 OpenClaw 桌面/频道发现能力，避免本地 Docker 与 Devbox 容器网络里出现非核心 sidecar 阻塞或重启。
