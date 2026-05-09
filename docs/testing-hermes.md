# Hermes 本地测试

这份文档对应当前仓库里的 `agents/hermes-agent` 第一阶段接入实现。

目标是验证五件事：

- 镜像能构建
- 默认启动就是标准 `start`
- 运行中的容器可以通过 `config.sh` 修改 Hermes 原生配置
- `config.sh` stdout 返回统一 JSON envelope
- 修改后能从容器内看到 `~/.hermes/config.yaml` 与 `~/.hermes/.env` 的实际变化

## 1. 语法检查

```bash
bash -n agents/hermes-agent/install.sh
bash -n agents/hermes-agent/entrypoint.sh
bash -n agents/hermes-agent/config.sh
bash test/validate-agent-contract.sh agents/hermes-agent
```

预期：无输出，退出码为 `0`。

## 2. 构建镜像

```bash
docker build -f agents/hermes-agent/Dockerfile -t agent-hub/hermes-agent:local .
```

## 3. 以前台 gateway 方式启动

```bash
docker rm -f hermes-local 2>/dev/null || true

docker run -d \
  --name hermes-local \
  -p 127.0.0.1:28642:8642 \
  agent-hub/hermes-agent:local
```

这里不再传 `gateway` 参数。默认 `CMD` 已经固定为 `start`，容器内部会执行：

```bash
hermes gateway run
```

检查状态：

```bash
docker ps --filter name=hermes-local
```

查看日志：

```bash
docker logs --tail 120 hermes-local
```

## 4. 验证标准入口

### `shell`

```bash
docker run --rm -it agent-hub/hermes-agent:local shell
```

### `run`

```bash
docker run --rm agent-hub/hermes-agent:local run version
```

## 5. 运行中配置 Hermes

### 设置主 Provider

```bash
docker exec hermes-local /opt/agent/config.sh provider set-main ccswitch http://host.docker.internal:15721/v1 chat_completions CCSWITCH_API_KEY
```

预期 stdout 是 JSON：

```json
{
  "ok": true,
  "resource": "provider",
  "action": "set-main",
  "applied": true,
  "data": {}
}
```

### 设置主模型

```bash
docker exec hermes-local /opt/agent/config.sh model set-main gpt-5.4
```

### 设置凭据

```bash
docker exec hermes-local /opt/agent/config.sh env set CCSWITCH_API_KEY sk-local-test
```

### 读取配置

```bash
docker exec hermes-local /opt/agent/config.sh provider get-main
docker exec hermes-local /opt/agent/config.sh model get-main
docker exec hermes-local /opt/agent/config.sh env list
```

凭据读取只返回 `configured` / `masked`，不会返回 API key 明文。

## 6. 验证原生文件已被修改

```bash
docker exec hermes-local cat /home/agent/.hermes/config.yaml
docker exec hermes-local cat /home/agent/.hermes/.env
```

这里应该能直接看到：

- `config.yaml` 中的 `model.provider` / `providers` / `model.default`
- `.env` 中的 `CCSWITCH_API_KEY`

## 7. 验证 API Server 监听

```bash
curl -sv --max-time 5 \
  http://127.0.0.1:28642/v1/models \
  -H 'Authorization: Bearer change-me-local-dev'
```

这个检查的重点不是模型调用成功，而是容器已经按固定 `start` 语义把 gateway 拉起来。

## 8. 一键 smoke 测试

如果想直接跑自动化 smoke：

```bash
bash test/hermes-smoke.sh
```
