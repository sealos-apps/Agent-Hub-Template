# Hermes Local Testing

This document covers `agents/hermes-agent`. The current template has removed `config.sh` and `config.json`; tests focus on image build, the shared entrypoint, gateway startup, and API health.

## Syntax And Contract

```bash
bash test/validate-agent-contract.sh agents/hermes-agent
bash -n agents/hermes-agent/install.sh
bash -n agents/hermes-agent/entrypoint.sh
cmp -s agents/_template/entrypoint.sh agents/hermes-agent/entrypoint.sh
```

## Build Image

```bash
docker build -f agents/hermes-agent/Dockerfile -t agent-hub/hermes-agent:local .
```

## Start Gateway

```bash
docker rm -f hermes-local 2>/dev/null || true
export API_SERVER_KEY=sk-local-hermes
docker run -d \
  --name hermes-local \
  -p 127.0.0.1:28642:8642 \
  -e API_SERVER_KEY="$API_SERVER_KEY" \
  agent-hub/hermes-agent:local
```

Default `CMD ["start"]` enters:

```text
/init -> /opt/agent/entrypoint.sh -> /opt/agent/bin/start -> hermes gateway run
```

## Verify API

```bash
curl -sv --max-time 5 \
  http://127.0.0.1:28642/v1/models \
  -H "Authorization: Bearer ${API_SERVER_KEY}"
```

This check verifies that the container starts the gateway through the fixed `start` path. It does not require a real model call to succeed.

## Cleanup

```bash
docker rm -f hermes-local
```
