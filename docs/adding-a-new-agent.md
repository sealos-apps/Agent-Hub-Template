# 添加一个新的 Agent

当前仓库只保留目录契约，不再提供仓库级脚手架或自动化脚本。

## 新增方式

直接复制 `agents/_template` 为新的 agent 目录，然后修改里面的文件。

例如：

```text
agents/my-agent/
  Dockerfile
  install.sh
  config.sh
  config.json
  entrypoint.sh
  index.json
  _template/index.yaml
  README.md
```

然后在 `registry/agents.yaml` 中追加新条目：

```yaml
agents:
  - name: my-agent
    path: agents/my-agent
    enabled: false
```

## 文件职责

- `Dockerfile`
  - 定义最终镜像如何组装
  - 必须使用 `FROM ghcr.io/gitlayzer/ubuntu:22.04-base`
- `install.sh`
  - 提供 `install_agent` 函数
  - 在构建镜像时执行安装逻辑
- `config.sh`
  - 提供配置命令分发
  - 负责接收像 `set config ...`、`get config` 这样的参数
- `config.json`
  - 提供前端渲染配置页面所需的字段定义
- `entrypoint.sh`
  - 提供 `start_agent` 函数
  - 从位置参数读取启动参数
- `index.json`
  - 提供 agent 展示信息
- `_template/index.yaml`
  - 提供部署该 agent 的 Kubernetes YAML
- `README.md`
  - 记录这个 agent 的说明和用法

## 原则

- agent 的安装逻辑放在自己的 `install.sh`
- agent 的配置命令入口放在自己的 `config.sh`
- `registry/agents.yaml` 只负责名字、路径、启用状态
