# OpenClaw Agent 镜像

这个目录把官方 [openclaw/openclaw](https://github.com/openclaw/openclaw) 的容器接入方式收敛成 Sealos Devbox 可接入的标准镜像。

当前实现遵守第一阶段标准：

- 固定入口：`entrypoint.sh start`
- 固定配置入口：`config.sh`
- 前端 manifest：`/opt/agent/config.json`
- `config.sh` stdout 固定返回 JSON envelope
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
docker run --rm -p 127.0.0.1:28789:18789 agent-hub/openclaw:dev
```

等价于：

```bash
docker run --rm -p 127.0.0.1:28789:18789 agent-hub/openclaw:dev start
```

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

## 配置方式

OpenClaw 这一层直接使用原生配置：

- `~/.openclaw/openclaw.json`
- `~/.openclaw/.env`
- `/opt/openclaw/plugin-runtime-deps` for OpenClaw bundled plugin runtime deps
- `openclaw config set/get/unset`
- Gateway RPC `config.get` + `config.patch` when a gateway is already running

### 设置主模型

```bash
docker run --rm agent-hub/openclaw:dev config model set-main ccswitch gpt-5.4-mini
```

上面的命令会写入：

```text
agents.defaults.model.primary = "ccswitch/gpt-5.4-mini"
```

### 设置 Provider endpoint 覆盖

```bash
docker run --rm agent-hub/openclaw:dev config provider set ccswitch http://host.docker.internal:15721/v1 openai-completions
```

### 设置 Provider API Key

```bash
docker run --rm agent-hub/openclaw:dev config provider set-api-key ccswitch sk-xxx
```

如果 gateway 已经在运行，这个动作会通过 OpenClaw 原生 Gateway RPC `config.patch` 写入 `models.providers.<id>.apiKey`，等待 gateway 重新 ready 后才返回 `applied=true`。stdout 只返回是否已配置和掩码，不返回密钥明文。

### 设置 Gateway 本地模式

```bash
docker run --rm agent-hub/openclaw:dev config gateway set-local lan 18789
```

### 设置 Gateway token

```bash
docker run --rm agent-hub/openclaw:dev config gateway set-token change-me-local-dev
```

### 设置凭据或其他环境变量

```bash
docker run --rm agent-hub/openclaw:dev config env set OPENAI_API_KEY sk-xxx
docker run --rm agent-hub/openclaw:dev config env set OPENCLAW_GATEWAY_TOKEN change-me-local-dev
```

### 查看当前配置

```bash
docker run --rm agent-hub/openclaw:dev config model get-main
docker run --rm agent-hub/openclaw:dev config provider get ccswitch
docker run --rm agent-hub/openclaw:dev config provider get-api-key ccswitch
docker run --rm agent-hub/openclaw:dev config gateway get-local
docker run --rm agent-hub/openclaw:dev config env list
```

所有配置命令的 stdout 都是统一 JSON。读取 token 或 `.env` 时只返回是否已配置和掩码，不返回密钥明文。

## 本地持久化测试

```bash
mkdir -p .tmp/openclaw-home

docker run -d \
  --name openclaw-local \
  -p 127.0.0.1:28789:18789 \
  -v "$PWD/.tmp/openclaw-home:/home/agent/.openclaw" \
  agent-hub/openclaw:dev

docker exec openclaw-local /opt/agent/config.sh gateway get-local
docker exec openclaw-local /opt/agent/config.sh provider set ccswitch http://host.docker.internal:15721/v1 openai-completions
docker exec openclaw-local /opt/agent/config.sh model set-main ccswitch gpt-5.4-mini
docker exec openclaw-local /opt/agent/config.sh provider set-api-key ccswitch sk-local-test
```

容器默认把 `gateway.bind` 固定为 `lan`，这样 `docker run -p ...` 后宿主机可以直接访问 published port。运行中的 gateway 使用 upstream 原生 `config.patch` 触发配置写入与运行态刷新。这里额外设置 `OPENCLAW_NO_RESPAWN=1`，避免 `docker run` 场景下需要 full-process restart 的配置变更直接让容器退出；默认设置 `OPENCLAW_SKIP_CHANNELS=1`，沿用 upstream dev/live-test 入口，避免容器网络里启动 Telegram 等频道 sidecar；默认设置 `OPENCLAW_DISABLE_BONJOUR=1`，沿用 upstream Docker 建议，避免 Docker bridge 网络里的 mDNS 探测导致 gateway 不稳定。

默认原生配置会禁用 `acpx`、`bonjour`、`browser` 这几个 bundled sidecar 插件。第一阶段 Devbox adapter 只验收 gateway、模型 provider、配置热更新和 inference 链路；不默认打开 OpenClaw 桌面/频道发现能力，避免本地 Docker 与 Devbox 容器网络里出现非核心 sidecar 阻塞或重启。
