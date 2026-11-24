# DeepSeek Harness

Preinstalled DeepSeek Harness (`@deepseek-ai/dsh`) web workbench adapter built on Node 24 and `ghcr.io/sealos-apps/agent-devbox-base`.

## Runtime behavior

- Runs `/opt/agent/bin/start` on port `3080` (`AGENT_PORT`).
- Dynamically binds the container's concrete non-loopback IPv4 address (required by `dsh web`, which rejects `0.0.0.0`).
- When `SANDBOX_PUBLIC_HOST` is set, passes `--public-url "https://${SANDBOX_PUBLIC_HOST}" --trusted-host "${SANDBOX_PUBLIC_HOST}"`.
- When `OPENAI_API_KEY` and `OPENAI_BASE_URL` (or `AGENT_MODEL_APIKEY` / `AGENT_MODEL_BASEURL`) are set and `${DSH_HOME}/profiles/web/cordis.patch.yml` does not exist yet, discovers available models from `${OPENAI_BASE_URL}/models` and writes a `sealos-ai-gateway` provider referencing `apiKeyEnv: OPENAI_API_KEY` (no secret written to disk).
