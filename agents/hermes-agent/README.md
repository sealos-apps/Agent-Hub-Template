# Hermes Agent Image

This directory packages the upstream [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent/) project as a standard Sealos Devbox-compatible image.

The current implementation follows the shared Agent Hub runtime contract:

- fixed entrypoint: `entrypoint.sh start`
- bundled `ai-agent-switch`
- no model initialization during image build or default startup
- current model state is read with `ai-agent-switch client show hermes --json`
- no promise to pass arbitrary Hermes CLI arguments through deployment settings
- configuration is written to native Hermes files: `~/.hermes/config.yaml` and `~/.hermes/.env`

## Upstream Install

- Hermes: clone `https://github.com/NousResearch/hermes-agent.git`, then install `.[all]` with `uv`
- ai-agent-switch: `curl -fsSL https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh | sh`

## Runtime Usage

### Default Startup

```bash
docker run --rm \
  -p 127.0.0.1:28642:8642 \
  -e API_SERVER_KEY=sk-local-hermes \
  agent-hub/hermes-agent:dev
```

Equivalent command:

```bash
docker run --rm \
  -p 127.0.0.1:28642:8642 \
  -e API_SERVER_KEY=sk-local-hermes \
  agent-hub/hermes-agent:dev start
```

Default startup requires `API_SERVER_KEY` from runtime environment variables or a Kubernetes Secret.

The image always starts:

```bash
hermes gateway run
```

### Debug Shell

```bash
docker run --rm -it agent-hub/hermes-agent:dev shell
```

### Native CLI Debugging

```bash
docker run --rm agent-hub/hermes-agent:dev run version
```

## Model Configuration

This image does not keep repository-specific model configuration scripts. Model initialization and switching are handled by `ai-agent-switch`, which writes the final state back to native Hermes configuration:

- `~/.hermes/config.yaml`
- `~/.hermes/.env`

Model values injected by Agent Hub are handled by the platform runtime flow. The image only provides Hermes and the `ai-agent-switch` binary.

### Initialize Or Switch Models

```bash
docker run --rm \
  -e CCSWITCH_API_KEY=sk-local-test \
  agent-hub/hermes-agent:dev \
  bash -lc '
    ai-agent-switch provider init \
      --id ccswitch \
      --name CCSwitch \
      --base-url http://host.docker.internal:15721/v1 \
      --api-key-env CCSWITCH_API_KEY \
      --model gpt-5.4:chat_completions:llm \
      --default-model gpt-5.4 \
      --json
    ai-agent-switch client configure \
      --client hermes \
      --slot main=ccswitch/gpt-5.4 \
      -y \
      --json
  '
```

This command writes the native Hermes `providers.ccswitch` entry and sets `model.provider = ccswitch` and `model.default = gpt-5.4`. The API key is referenced through an environment variable and is not written as a plaintext token.

### Show Current Model

```bash
docker run --rm agent-hub/hermes-agent:dev ai-agent-switch client show hermes --json
```

## Local Persistence Test

```bash
mkdir -p .tmp/hermes-home

docker run -d \
  --name hermes-local \
  -p 127.0.0.1:28642:8642 \
  -v "$PWD/.tmp/hermes-home:/root/.hermes" \
  -e API_SERVER_KEY=sk-local-hermes \
  -e CCSWITCH_API_KEY=sk-local-test \
  agent-hub/hermes-agent:dev \
  bash -lc '
    ai-agent-switch provider init \
      --id ccswitch \
      --name CCSwitch \
      --base-url http://host.docker.internal:15721/v1 \
      --api-key-env CCSWITCH_API_KEY \
      --model gpt-5.4:chat_completions:llm \
      --default-model gpt-5.4 \
      --json
    ai-agent-switch client configure --client hermes --slot main=ccswitch/gpt-5.4 -y --json
    exec /opt/agent/bin/start
  '

docker exec -e HOME=/root hermes-local ai-agent-switch client show hermes --json
```

For local persistence tests, run `init` before starting the long-running gateway process.
