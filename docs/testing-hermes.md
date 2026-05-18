# Hermes 本地测试

这份文档对应 `agents/hermes-agent`。当前模板已经移除 `config.sh` 和 `config.json`，测试重点是镜像构建、统一入口、Gateway 启动和 API 健康检查。

## 语法与契约

```bash
bash test/validate-agent-contract.sh agents/hermes-agent
bash -n agents/hermes-agent/install.sh
bash -n agents/hermes-agent/entrypoint.sh
cmp -s agents/_template/entrypoint.sh agents/hermes-agent/entrypoint.sh
```

## 构建镜像

```bash
docker build -f agents/hermes-agent/Dockerfile -t agent-hub/hermes-agent:local .
```

## 启动 Gateway

```bash
docker rm -f hermes-local 2>/dev/null || true
export API_SERVER_KEY=sk-local-hermes
docker run -d \
  --name hermes-local \
  -p 127.0.0.1:28642:8642 \
  -e API_SERVER_KEY="$API_SERVER_KEY" \
  agent-hub/hermes-agent:local
```

默认 `CMD ["start"]` 会进入：

```text
/init -> /opt/agent/entrypoint.sh -> /opt/agent/bin/start -> hermes gateway run
```

## 验证 API

```bash
curl -sv --max-time 5 \
  http://127.0.0.1:28642/v1/models \
  -H "Authorization: Bearer ${API_SERVER_KEY}"
```

这个检查的重点不是模型调用成功，而是容器已经按固定 `start` 语义把 gateway 拉起来。

## 清理

```bash
docker rm -f hermes-local
```
