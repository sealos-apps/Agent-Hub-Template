# OpenClaw Agent 镜像

这个目录把官方 [openclaw/openclaw](https://github.com/openclaw/openclaw) 的容器接入方式收敛成 Sealos Devbox 可接入的标准镜像。

当前实现遵守第一阶段标准：

- 固定入口：`entrypoint.sh start`
- 基于 `ghcr.io/nightwhite/agent-devbox-base` 构建
- 通过官方 Linux 安装方式安装最新 `openclaw`
- 通过官方 curl 安装脚本安装最新 `ai-agent-switch` standalone binary
- 不把 `onboard --install-daemon` 当成容器标准启动方式
- 容器里的标准长驻进程固定为 `openclaw gateway run`
- 配置直接落到 OpenClaw 原生 `~/.openclaw/openclaw.json` 与 `~/.openclaw/.env`

## Upstream Install

- OpenClaw: `npm install -g openclaw@latest`
- ai-agent-switch: `curl -fsSL https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh | sh -s -- <latest-release-tag>`

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

默认启动必须通过运行时环境变量、Agent Hub 模板设置或 Kubernetes Secret 提供 `OPENCLAW_GATEWAY_TOKEN`。启动脚本会把这个值写入 `~/.openclaw/.env`，包括 `sk-` 前缀在内的完整 token 会被保留。

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

OpenClaw 配置仍然写入原生配置文件：

- `~/.openclaw/openclaw.json`
- `~/.openclaw/.env`

镜像构建和默认启动都不执行 Agent Hub 初始化命令。模型/provider 配置由运行时或 Agent Hub 后续流程负责。

Agent Hub 场景下同一个 Devbox 会通过平台鉴权和网关 token 控制访问，镜像默认写入 `gateway.controlUi.allowedOrigins=["*"]` 和 `gateway.controlUi.dangerouslyDisableDeviceAuth=true`，关闭 OpenClaw Control UI 的来源限制和设备配对流程。

### 查看 ai-agent-switch 状态

```bash
docker run --rm agent-hub/openclaw:dev ai-agent-switch status --json
```

## 本地持久化测试

```bash
mkdir -p .tmp/openclaw-home

docker run -d \
  --name openclaw-local \
  -p 127.0.0.1:28789:18789 \
  -v "$PWD/.tmp/openclaw-home:/root/.openclaw" \
  -e OPENCLAW_GATEWAY_TOKEN=sk-local-openclaw \
  agent-hub/openclaw:dev

docker exec -e HOME=/root openclaw-local ai-agent-switch status --json
```

容器默认把 `gateway.bind` 固定为 `lan`，这样 `docker run -p ...` 后宿主机可以直接访问 published port。这里额外设置 `OPENCLAW_NO_RESPAWN=1`，避免 `docker run` 场景下需要 full-process restart 的配置变更直接让容器退出。

默认原生配置会禁用 `acpx`、`bonjour`、`browser` 这几个 bundled sidecar 插件。第一阶段 Devbox adapter 只验收 gateway、模型 provider、配置热更新和 inference 链路；不默认打开 OpenClaw 桌面/频道发现能力，避免本地 Docker 与 Devbox 容器网络里出现非核心 sidecar 阻塞或重启。
