# Local Smoke Tests

## Local Dependencies

- `python3`: JSON validation and selected smoke assertions.
- `python3` + `PyYAML` or `ruby`: YAML syntax validation.
- `docker`: building and running Hermes/OpenClaw smoke images.
- `curl`: gateway and ccswitch HTTP checks.
- `ccswitch-smoke.sh`: also requires a local ccswitch server listening on `127.0.0.1:15721`.

If PyYAML is not available, scripts fall back to Ruby. If neither dependency exists, contract validation fails with an explicit error.

## Usage

Run static contract validation first:

```bash
bash test/validate-agent-contract.sh
```

Then run real image smoke tests as needed:

```bash
bash test/hermes-smoke.sh
bash test/openclaw-smoke.sh
```

If a local ccswitch server is listening on `127.0.0.1:15721`, run the full model path smoke test:

```bash
bash test/ccswitch-smoke.sh
```

These scripts:

- build images
- start containers with the default `start` command
- initialize smoke-test model configuration through `ai-agent-switch provider init` and `ai-agent-switch client configure`
- read current model state through `ai-agent-switch client show <client> --json`
- verify API keys are referenced through environment variables instead of plaintext tokens
- verify configuration files are written
- verify the running gateway stays healthy
- additionally validate direct ccswitch, Hermes gateway, and OpenClaw gateway model call paths in `ccswitch-smoke.sh`
