# `change-me` Agent 模板

先阅读 [docs/adding-a-new-agent.md](../../docs/adding-a-new-agent.md)。

这个目录只提供第一阶段接入骨架，不提供统一配置 schema。

## 模板强调的只有五件事

- 镜像必须基于 Devbox base，并保留 `/init`
- `entrypoint.sh` 统一暴露 `start/config/shell/run`
- `config.sh` 必须直接面对该 agent 的原生配置
- `config.sh` stdout 必须返回统一 JSON envelope，日志只能写 stderr
- `config.json` 是前端 UI manifest，只描述这个 agent 自己的配置动作，不能偷懒做平台统一字段

## 文件说明

- `Dockerfile`
  - 保留 `ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]`
  - 默认 `CMD ["start"]`
- `install.sh`
  - 构建时安装真实 upstream agent
- `entrypoint.sh`
  - 统一标准入口分发
- `config.sh`
  - 原生配置入口，输出 `{ ok, resource, action, applied, data }` 或 `{ ok, error }`
- `config.json`
  - 前端配置表单描述，必须包含 `schemaVersion: "devbox-agent-config.v1"`、`zh.resources` 和 `en.resources`
- `index.json`
  - 展示信息和 `runtime.kind`
- `deploy.yaml`
  - 默认部署模板，只放 `args: ["start"]`
- `README.md`
  - 当前 agent 自己的维护文档

## 使用时必须替换

- `change-me`
- `replace-me-resource`
- `replace-me-action`
- 占位错误提示
- 假的安装逻辑与假命令

## 不要照抄的错误做法

- 不要把模板里的占位资源名当成真实平台 schema
- 不要把 `run` 当成默认启动方式
- 不要在 Deployment 里覆盖 `command` 绕过镜像 `ENTRYPOINT`
- 不要发明统一的 provider/model/api_key 中间配置层
- 不要在 `config.json` 写真实配置值或密钥
- 不要让 `config.sh` 成功退出但没有真正写入或生效
