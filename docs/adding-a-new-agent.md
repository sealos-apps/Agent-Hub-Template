# 添加一个新的 Agent

当前仓库只保留目录契约，不提供仓库级脚手架或自动生成脚本。新增 agent 时直接复制 `agents/_template`，然后替换占位内容。

## 目录结构

```text
agents/my-agent/
  Dockerfile
  build.env
  install.sh
  entrypoint.sh
  template.yaml
  README.md
  manifests/
    devbox.yaml.tmpl
    service.yaml.tmpl
    ingress.yaml.tmpl
```

不要新增 `config.sh`、`config.json`、`bootstrap.sh` 或 `healthcheck.sh`。

## 文件职责

- `Dockerfile`: 基于共享 `AGENT_BASE_IMAGE` 组装最终镜像，保留 `/init` 入口和 `CMD ["start"]`
- `build.env`: 构建期非敏感默认值，例如 upstream 仓库和安装路径
- `install.sh`: 安装真实上游 agent，并生成 `/opt/agent/bin/start`
- `entrypoint.sh`: 所有 agent 共用，保持和 `agents/_template/entrypoint.sh` 完全一致
- `README.md`: 当前 agent 的构建、运行、配置和测试说明
- `template.yaml`: Agent Hub 模板目录元数据、访问能力、设置 schema 和模型预设
- `manifests/*.yaml.tmpl`: Agent Hub 渲染的 Devbox、Service、Ingress 模板

真实 agent 的 `template.yaml.image` 必须写成
`ghcr.io/<owner>/<agent-id>:latest`，其中 `<owner>` 必须和 release workflow
使用的仓库 owner 一致。Release workflow 会推送 `latest` 和 `build-*`，
Agent Hub 只从模板读取 `latest`。

## 配置原则

- 非敏感开关：环境变量
- 密钥和 token：Kubernetes Secret
- 大段结构化配置：挂载文件
- 运行时工作目录：`/workspace`
- agent 私有数据目录：`/root/.<agent-name>`

不要把运行期密钥写进镜像，也不要让每个 agent 通过仓库统一配置脚本中转。

## 接入步骤

1. 复制 `agents/_template` 为 `agents/my-agent`
2. 替换所有 `change-me`
3. 在 `install.sh` 中实现上游安装逻辑
4. 在 `install.sh` 中生成 `/opt/agent/bin/start`
5. 更新同目录的 `template.yaml` 和 `manifests/`
6. 写清楚 `README.md`
7. 在 `registry/agents.yaml` 中追加 agent
8. 本地完成契约、语法、镜像构建和运行测试

`template.yaml` 是 Agent Hub 读取的模板元数据源，也是 manifests 的元数据源：端口、用户、工作目录和访问路径要在
`template.yaml` 中定义，再由 `manifests/*.yaml.tmpl` 通过 `.Agent.*` 渲染。不要在
manifests 里为单个 agent 硬编码另一套 `user`、`workingDir` 或端口。

## 本地基础检查

```bash
bash test/validate-agent-contract.sh agents/my-agent
bash -n agents/my-agent/install.sh
bash -n agents/my-agent/entrypoint.sh
docker build -f agents/my-agent/Dockerfile -t agent-hub/my-agent:local .
```

如果 `entrypoint.sh` 和模板不一致，CI 会拒绝。除非要调整全仓库运行契约，不要为单个 agent 单独改入口脚本。
