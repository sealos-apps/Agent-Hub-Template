# Hermes Agent 镜像

这个目录把官方 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent/) 封装成 Sealos Devbox 可接入的标准镜像。

当前实现遵守第一阶段标准：

- 固定入口：`entrypoint.sh start`
- 固定配置入口：`config.sh`
- 前端 manifest：`/opt/agent/config.json`
- `config.sh` stdout 固定返回 JSON envelope
- 不承诺部署时透传任意 Hermes CLI 参数
- 配置直接落到 Hermes 原生 `~/.hermes/config.yaml` 与 `~/.hermes/.env`

## Upstream Pin

- upstream branch: `main`
- pinned ref: `59b56d445c34e1d4bf797f5345b802c7b5986c72`

## 运行方式

### 默认启动

```bash
docker run --rm -p 127.0.0.1:28642:8642 agent-hub/hermes-agent:dev
```

等价于：

```bash
docker run --rm -p 127.0.0.1:28642:8642 agent-hub/hermes-agent:dev start
```

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

## 配置方式

Hermes 这一层不再维护任何仓库私有中间文件，直接使用原生配置：

- `~/.hermes/config.yaml`
- `~/.hermes/.env`

### 设置主 Provider

```bash
docker run --rm agent-hub/hermes-agent:dev config provider set-main openai
```

自定义 OpenAI-compatible endpoint：

```bash
docker run --rm agent-hub/hermes-agent:dev config provider set-main custom http://host.docker.internal:11434/v1
```

命名 provider，例如 ccswitch：

```bash
docker run --rm agent-hub/hermes-agent:dev config provider set-main ccswitch http://host.docker.internal:15721/v1 chat_completions CCSWITCH_API_KEY
```

这个命令会写入 Hermes 当前原生 `providers.ccswitch`，并保留 `model.provider = ccswitch`。

### 设置主模型

```bash
docker run --rm agent-hub/hermes-agent:dev config model set-main gpt-5.4
```

### 设置凭据或 API Server 相关环境变量

```bash
docker run --rm agent-hub/hermes-agent:dev config env set OPENAI_API_KEY sk-xxx
docker run --rm agent-hub/hermes-agent:dev config env set API_SERVER_KEY change-me-local-dev
```

### 查看当前配置

```bash
docker run --rm agent-hub/hermes-agent:dev config provider get-main
docker run --rm agent-hub/hermes-agent:dev config model get-main
docker run --rm agent-hub/hermes-agent:dev config env list
```

所有配置命令的 stdout 都是统一 JSON。读取 `.env` 时只返回是否已配置和掩码，不返回密钥明文。

## 本地持久化测试

```bash
mkdir -p .tmp/hermes-home

docker run -d \
  --name hermes-local \
  -p 127.0.0.1:28642:8642 \
  -v "$PWD/.tmp/hermes-home:/home/agent/.hermes" \
  agent-hub/hermes-agent:dev

docker exec hermes-local /opt/agent/config.sh provider set-main ccswitch http://host.docker.internal:15721/v1 chat_completions CCSWITCH_API_KEY
docker exec hermes-local /opt/agent/config.sh model set-main gpt-5.4
docker exec hermes-local /opt/agent/config.sh env set CCSWITCH_API_KEY sk-local-test
```

Hermes gateway 是长驻进程，上游会在运行期重新读取 `config.yaml` 与 `.env`，所以配置修改围绕当前运行中的 gateway 生效，而不是依赖重新传启动参数。
