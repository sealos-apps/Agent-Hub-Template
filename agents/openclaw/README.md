# OpenClaw Agent Image

This directory packages the upstream [openclaw/openclaw](https://github.com/openclaw/openclaw) container runtime as a standard Sealos Devbox-compatible image.

The current implementation follows the shared Agent Hub runtime contract:

- fixed entrypoint: `entrypoint.sh start`
- built from `ghcr.io/nightwhite/agent-devbox-base`
- installs the latest `openclaw` through the official Linux install path
- installs the latest standalone `ai-agent-switch` binary through its official curl installer
- does not use `onboard --install-daemon` as the standard container startup path
- standard long-running process is `openclaw gateway run`
- configuration is written to native OpenClaw files: `~/.openclaw/openclaw.json` and `~/.openclaw/.env`

## Upstream Install

- OpenClaw: `npm install -g openclaw@latest`
- ai-agent-switch: `curl -fsSL https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh | sh`

## Runtime Usage

### Default Startup

```bash
docker run --rm \
  -p 127.0.0.1:28789:18789 \
  -e OPENCLAW_GATEWAY_TOKEN=sk-local-openclaw \
  agent-hub/openclaw:dev
```

Equivalent command:

```bash
docker run --rm \
  -p 127.0.0.1:28789:18789 \
  -e OPENCLAW_GATEWAY_TOKEN=sk-local-openclaw \
  agent-hub/openclaw:dev start
```

Default startup requires `OPENCLAW_GATEWAY_TOKEN` from runtime environment variables, Agent Hub template settings, or a Kubernetes Secret. The startup script writes this value to `~/.openclaw/.env` and preserves the full token, including the `sk-` prefix.

The image always starts:

```bash
openclaw gateway run
```

### Debug Shell

```bash
docker run --rm -it agent-hub/openclaw:dev shell
```

### Native CLI Debugging

```bash
docker run --rm agent-hub/openclaw:dev run --help
```

## Configuration

OpenClaw configuration is still written to native configuration files:

- `~/.openclaw/openclaw.json`
- `~/.openclaw/.env`

Image build and default startup do not initialize or switch models. Model and provider configuration is handled by Agent Hub at runtime.

In Agent Hub, access to the same Devbox is controlled by platform authentication and the gateway token. The image writes `gateway.controlUi.allowedOrigins=["*"]` and `gateway.controlUi.dangerouslyDisableDeviceAuth=true` by default, disabling OpenClaw Control UI origin restrictions and device pairing.

### Show ai-agent-switch Status

```bash
docker run --rm agent-hub/openclaw:dev ai-agent-switch status --json
```

## Local Persistence Test

```bash
mkdir -p .tmp/openclaw-home

docker run -d \
  --name openclaw-local \
  -p 127.0.0.1:28789:18789 \
  -v "$PWD/.tmp/openclaw-home:/root/.openclaw" \
  -e OPENCLAW_GATEWAY_TOKEN=sk-local-openclaw \
  agent-hub/openclaw:dev

docker exec -e HOME=/root openclaw-local ai-agent-switch status --json
```

The container pins `gateway.bind` to `lan` by default, so the host can access the published port after `docker run -p ...`. It also sets `OPENCLAW_NO_RESPAWN=1` to prevent configuration changes that require a full process restart from exiting the container in local `docker run` scenarios.

The default native configuration disables the bundled `acpx`, `bonjour`, and `browser` sidecar plugins. This Devbox adapter validates gateway, model provider, hot-reload configuration, and inference paths first; desktop and channel discovery sidecars are not enabled by default to avoid non-core blocking or restart behavior in local Docker and Devbox container networks.
