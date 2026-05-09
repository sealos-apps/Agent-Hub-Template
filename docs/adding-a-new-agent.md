# 添加一个新的 Agent

这份文档描述的是第一阶段接入规范：平台统一入口与目录契约，但不统一 agent 自身的配置格式。

## 1. 复制模板

直接复制 `agents/_template` 为新的 agent 目录，例如：

```text
agents/my-agent/
  Dockerfile
  install.sh
  entrypoint.sh
  config.sh
  config.json
  index.json
  deploy.yaml
  README.md
```

然后在 `registry/agents.yaml` 里追加：

```yaml
agents:
  - name: my-agent
    path: agents/my-agent
    enabled: false
```

## 2. 必须遵守的入口契约

### 镜像入口

Dockerfile 里必须保持：

- `ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]`
- `CMD ["start"]`

不要在部署模板里覆盖 `command` 去绕开 `/init`。

### Deployment 默认参数

`deploy.yaml` 里默认只写：

```yaml
args: ["start"]
```

第一阶段不把“任意上游 CLI 参数透传”当成标准能力。

### `entrypoint.sh` 标准命令

每个 agent 都要实现这四个入口：

- `start`
- `config`
- `shell`
- `run`

语义要求：

- `start`
  - `service` 型 agent: 启动前台长驻主进程
  - `tool` 型 agent: 完成 bootstrap 并保持容器可 `exec`
- `config`
  - 转发到 `/opt/agent/config.sh`
- `shell`
  - 进入调试 shell
- `run`
  - 给维护者调试或做原生 CLI 验证，不是默认启动契约

## 3. `runtime.kind`

在 `index.json` 中声明：

```json
{
  "runtime": {
    "kind": "service"
  }
}
```

允许值：

- `service`
- `tool`

平台读取这个字段是为了理解运行语义，不是为了统一 agent 内部实现。

## 4. `config.sh` 只做原生配置

`config.sh` 是前端的统一调用入口，但配置内容必须是该 agent 的原生配置。

正确做法：

- Hermes 直接写它自己的 `config.yaml` / `.env`
- OpenClaw 直接调用它自己的 `openclaw config set/get/unset`，并写 `.env`
- 其他 agent 直接写它们自己的原生配置文件或状态目录

不要做这些事：

- 不要发明仓库统一的 `endpoint/api_key/model` 中间层
- 不要发明统一 `yaml_state`、`providers.list` 之类平台私有格式
- 不要假设所有 agent 都支持同样的 provider / model / key 字段
- 不要把日志写到 stdout；stdout 必须留给前端解析 JSON

`config.sh` 的前端动作必须返回统一 JSON envelope：

```json
{
  "ok": true,
  "resource": "model",
  "action": "set-main",
  "applied": true,
  "data": {}
}
```

失败时也要返回 JSON，并使用非 0 退出码：

```json
{
  "ok": false,
  "resource": "model",
  "action": "set-main",
  "error": {
    "code": "invalid_config",
    "message": "human readable error"
  }
}
```

## 5. `config.json` 是前端 UI manifest

`config.json` 只负责告诉前端：

- 有哪些资源可配置
- 每个资源有哪些动作
- 每个动作需要什么参数
- 每个动作是 `read` / `write` / `delete` 哪一种
- 哪些字段是 `password` / `sensitive`

前端只能按当前 agent 的 `config.json` 渲染，不能假设不同 agent 共用同一套字段。

必须包含：

```json
{
  "schemaVersion": "devbox-agent-config.v1",
  "script": "/opt/agent/config.sh"
}
```

第一阶段要求 manifest 同时提供 `zh.resources` 和 `en.resources`，两种语言都描述同一组 resource/action，只允许展示文案不同。

`config.json` 不存真实配置值，不存密钥。

## 6. Dockerfile 要做什么

每个 agent 的 Dockerfile 需要负责：

- 基于 Devbox base 安装真实上游 agent
- 明确创建或确认运行用户、工作目录、配置目录
- 复制 `entrypoint.sh` / `config.sh` / `config.json` 到 `/opt/agent/`
- 保留 `/init` 启动链路

推荐保留一个可选的 `build.env` 作为构建期实现辅助文件，但它不属于平台强制对外接口。

## 7. 接入完成后的最小验证

新增 agent 后，至少要验证：

```bash
bash -n agents/my-agent/install.sh
bash -n agents/my-agent/entrypoint.sh
bash -n agents/my-agent/config.sh
bash test/validate-agent-contract.sh agents/my-agent

docker build -f agents/my-agent/Dockerfile -t agent-hub/my-agent:local .
docker run --rm agent-hub/my-agent:local
docker run --rm -it agent-hub/my-agent:local shell
```

如果是 `service` 型 agent，还要验证它在 `start` 下能稳定以前台方式运行。
