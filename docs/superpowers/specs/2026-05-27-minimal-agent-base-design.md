# 极简 Agent Base 镜像设计

## 背景

Agent Hub 模板仓库负责把 CLI、二进制程序、Python 项目或 Node.js 项目包装成可部署的 Devbox agent。当前仓库的 base 镜像已经承担了 Devbox runtime、用户、工作目录、Node.js、Python、uv 和一些 agent 依赖，但边界偏宽，容易把具体 agent 的依赖提前塞进 base。

本次重构先从 base 镜像边界开始：base 只提供最高通用性的运行底座和安装能力。具体 agent 的安装逻辑、重型依赖和 `ai-agent-switch` 都下沉到各自 agent 镜像。

## 目标

构建一个轻量、稳定、通用的 `agent-devbox-base` 镜像，使后续 agent 镜像可以像在 Linux 本地环境一样安装和运行：

- CLI agent；
- 单文件或多文件二进制 agent；
- Python 项目；
- Node.js 项目；
- 需要 `ai-agent-switch` 管理模型切换的 Agent Hub agent。

## 非目标

- base 镜像不安装任何具体 agent。
- base 镜像不安装 `ai-agent-switch`。
- base 镜像不写入模型配置。
- base 镜像不包含 `AGENT_MODEL_*` 或 `AI_AGENT_SWITCH_*` 语义。
- base 镜像不承诺提供所有编译工具、媒体库或浏览器依赖。
- base 镜像不 pin 具体 agent 版本。

## Base 镜像职责

base 镜像只包含 3 类能力。

### Devbox runtime

参考 `reference/devbox-runtime/tooling` 的脚本，base 镜像需要提供：

- `/init`；
- s6-overlay；
- sshd；
- crond / supercronic；
- devbox-sdk-server；
- `devbox` 用户；
- `/workspace`，且 root 运行时可写；
- Devbox 运行所需的 service 配置、登录配置、logrotate 配置和 locale 配置。

### 语言与搜索工具

这些工具在大多数 agent 安装或运行路径中都足够常见，放入 base：

- Node.js；
- npm；
- Python 3；
- pip；
- venv；
- uv；
- ripgrep。

### 最小系统工具

base 镜像提供最小 Linux 工具集，满足下载、解压、Git 拉取、SSH、进程检查、网络排查和基础脚本执行：

- `bash`；
- `busybox`；
- `ca-certificates`；
- `curl`；
- `wget`；
- `sudo`；
- `git`；
- `file`；
- `less`；
- `openssl`；
- `tar`；
- `gzip`；
- `xz-utils`；
- `zip`；
- `unzip`；
- `rsync`；
- `openssh-client`；
- `openssh-server`；
- `locales`；
- `tzdata`；
- `logrotate`；
- `procps`；
- `iproute2`；
- `iputils-ping`；
- `lsof`；
- `netbase`；
- `findutils`；
- `grep`；
- `sed`；
- `gawk`。

## Base 镜像明确不包含

以下内容不进入 base，避免镜像变成大而全：

- `ai-agent-switch`；
- `yarn`；
- `pnpm`；
- TypeScript；
- `build-essential`；
- gcc / g++ / make；
- `ffmpeg`；
- `espeak`；
- `libavcodec-extra`；
- 浏览器和 Playwright 依赖；
- OpenClaw、Hermes、CowAgent 或任何其他 agent runtime；
- agent 默认配置；
- 模型 provider 配置；
- 模型切换命令。

如果某个 agent 需要这些依赖，由该 agent 的 `Dockerfile` 或 `install.sh` 显式安装。

## Agent 镜像职责

每个 agent 镜像基于 `agent-devbox-base` 构建，并负责：

- 安装当前 agent 需要的额外系统依赖；
- 按该 agent 在 Linux 本地环境中的常规方式安装 latest；
- 安装 latest `ai-agent-switch`；
- 创建 `/opt/agent/bin/start`；
- 复制统一的 `entrypoint.sh`；
- 保证容器启动路径为 `/init -> /opt/agent/entrypoint.sh -> /opt/agent/bin/start`。

Agent 镜像安装失败时应直接构建失败，不添加未确认的 fallback 逻辑。

## 目录边界

重构后的每个 agent 目录应只保留两类文件。

部署模板：

- `template.yaml`；
- `manifests/devbox.yaml.tmpl`；
- `manifests/service.yaml.tmpl`；
- `manifests/ingress.yaml.tmpl`。

镜像构建与运行：

- `Dockerfile`；
- `build.env`；
- `install.sh`；
- `entrypoint.sh`；
- `README.md`。

`index.json` 不再作为 agent 目录契约的一部分。Agent Hub 读取的 catalog 元数据和镜像引用统一放在 `template.yaml`。`build.env` 本轮仍保留，用于承载非敏感构建常量。

## 验证标准

base 镜像 smoke 测试需要验证：

- `/init` 可执行；
- `devbox` 用户存在；
- `/workspace` 存在且 root 运行时可写；
- `sshd` 可用；
- devbox-sdk-server 可用；
- s6 service 配置存在；
- `node` 可用；
- `npm` 可用；
- `python3` 可用；
- `pip3` 可用；
- `python3 -m venv` 可用；
- `uv` 可用；
- `rg` 可用；
- 最小系统工具可用。

agent 镜像 smoke 测试需要验证：

- 继承 base runtime；
- agent 自身命令可用；
- `ai-agent-switch` 可用；
- `/opt/agent/bin/start` 可执行；
- 默认启动路径进入真实 agent runtime。

## 后续实现顺序

1. 调整 base 镜像包清单和 smoke 测试。
2. 删除 agent 目录中的 `index.json` 契约，让 `template.yaml` 成为唯一 Agent Hub 元数据来源。
3. 简化 agent Dockerfile，只保留 base、agent 安装、`ai-agent-switch` 安装和入口复制。
4. 更新 CI，使其不再读取或回写 `index.json`。
5. 更新文档和契约测试。
