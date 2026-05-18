# Agent Hub Template

面向 Sealos Devbox / Agent Hub 的 agent 镜像接入仓库。

这个仓库维护一套统一的 agent 镜像目录契约：每个 agent 可以保留自己的上游运行方式和配置方式，但镜像构建、容器入口、部署模板和元数据必须稳定一致。

## 仓库布局

```text
agents/
  _template/
    template.yaml
    manifests/
  hermes-agent/
    template.yaml
    manifests/
  openclaw/
    template.yaml
    manifests/
  cowagent/
    template.yaml
    manifests/
registry/
  agents.yaml
docs/
test/
```

## Agent 目录契约

每个 agent 目录必须提供：

- `Dockerfile`
- `build.env`
- `install.sh`
- `entrypoint.sh`
- `index.json`
- `template.yaml`
- `manifests/devbox.yaml.tmpl`
- `manifests/service.yaml.tmpl`
- `manifests/ingress.yaml.tmpl`
- `README.md`

每个 agent 目录不能再提供：

- `config.sh`
- `config.json`
- `bootstrap.sh`
- `healthcheck.sh`

运行期配置应来自环境变量、Kubernetes Secret、ConfigMap 或挂载文件，不再通过仓库统一配置脚本中转。

## 运行契约

所有 agent 使用同一条启动链路：

```text
/init
  -> /opt/agent/entrypoint.sh
    -> /opt/agent/bin/start
      -> real upstream agent runtime
```

关键规则：

- `ENTRYPOINT` 固定为 `["/init", "/opt/agent/entrypoint.sh"]`
- `CMD` 固定为 `["start"]`
- `entrypoint.sh` 必须和 `agents/_template/entrypoint.sh` 保持一致
- agent 自己的启动逻辑只写在 `/opt/agent/bin/start`
- `/opt/agent/bin/start` 由 `install.sh` 在镜像构建时生成
- `manifests/devbox.yaml.tmpl` 中实例默认使用 `args: ["start"]`

共享入口会导出这些标准变量：

- `AGENT_NAME`
- `AGENT_HOME=/opt/agent`
- `AGENT_START=/opt/agent/bin/start`
- `AGENT_DATA_DIR`
- `AGENT_WORKSPACE=/workspace`
- `AGENT_PORT`
- `AGENT_LOG_LEVEL`

## 当前 Agent

- `agents/hermes-agent`: Hermes Agent gateway adapter
- `agents/openclaw`: OpenClaw gateway adapter
- `agents/cowagent`: CowAgent Web console adapter

## 镜像版本规则

GitHub Actions 会根据 `registry/agents.yaml` 生成构建矩阵。

- 分支 push、tag 和手动发布都会构建版本镜像：
  - `ghcr.io/<owner>/<agent>:<index.json.version>`

发布成功后，Actions 会把 enabled agents 的 `index.json.image` 和 `agents/<agent>/template.yaml` 镜像引用同步为版本镜像。

## Agent Hub 模板

每个 agent 目录内部自带 Agent Hub 模板：

- `template.yaml`: 模板目录元数据、访问能力、运行设置和模型预设
- `manifests/devbox.yaml.tmpl`: Devbox Go template
- `manifests/service.yaml.tmpl`: Service Go template
- `manifests/ingress.yaml.tmpl`: Ingress Go template

`template.yaml` 中的 `port`、`workingDir`、`user`、`defaultArgs`、`access` 和
`manifestDir` 必须和 `manifests/` 渲染出的资源保持一致；本仓库不使用
`bootstrap.sh` 或 `healthcheck.sh`。

当前已提供 `agents/hermes-agent`、`agents/openclaw`、`agents/cowagent` 的本地模板。仓库不再维护顶层 `template/` 目录，也不再要求 `bootstrap.sh` 或 `healthcheck.sh`。

## 本地验证

```bash
bash test/validate-agent-contract.sh
bash test/hermes-smoke.sh
bash test/openclaw-smoke.sh
docker build -f agents/cowagent/Dockerfile -t agent-hub/cowagent:local .
```

参考：

- `docs/agent-contract.md`
- `docs/adding-a-new-agent.md`
- `docs/testing-hermes.md`
- `test/README.md`
