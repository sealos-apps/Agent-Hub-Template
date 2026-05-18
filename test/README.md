# 本地 Smoke 测试

## 本地依赖

- `python3`: 用于 JSON 校验和部分 smoke 断言。
- `python3` + `PyYAML` 或 `ruby`: 用于 `deploy.yaml` 语法校验。
- `docker`: 用于构建和运行 Hermes/OpenClaw smoke 镜像。
- `curl`: 用于 gateway 和 ccswitch HTTP 检查。
- `npm`: smoke 脚本默认用它解析最新 `ai-agent-switch` 版本；也可以显式传入 `AI_AGENT_SWITCH_VERSION`。
- `ccswitch-smoke.sh` 还需要本机 ccswitch 监听 `127.0.0.1:15721`。

如果本机没有 PyYAML，脚本会自动回退到 Ruby；两者都没有时，契约校验会明确失败。

## 运行方式

先跑静态契约校验：

```bash
bash test/validate-agent-contract.sh
```

再按需跑真实镜像 smoke：

```bash
bash test/hermes-smoke.sh
bash test/openclaw-smoke.sh
```

如果本机有 ccswitch 监听 `127.0.0.1:15721`，可以跑完整模型链路：

```bash
bash test/ccswitch-smoke.sh
```

这些脚本会：

- 构建镜像
- 按默认 `start` 启动容器
- 通过 `ai-agent-switch agent-hub init` 校验并初始化原生模型配置
- 通过 `ai-agent-switch client show <client> --json` 读取当前模型
- 校验密钥通过环境变量引用，不写入明文 token
- 校验配置文件已经被写入
- 校验运行中的 gateway 仍然健康
- `ccswitch-smoke.sh` 会额外验证 direct ccswitch、Hermes gateway、OpenClaw gateway 三条真实模型调用链路
