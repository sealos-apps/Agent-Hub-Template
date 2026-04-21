# Agent Hub Template

Minimal agent image repository layout.

This repository now keeps only the directory contract and agent source files. There are no repository-level build, test, scaffold, or validation scripts.

## Layout

```text
agents/
  _template/
  hermes/
registry/
  agents.yaml
docs/
```

## Agent Contract

Each agent directory is expected to contain:

- `Dockerfile`
- `install.sh`
- `config.sh`
- `config.json`
- `entrypoint.sh`
- `index.json`
- `_template/index.yaml`
- `README.md`

## Notes

- The repository no longer includes `scripts/`.
- The repository no longer includes a root `Makefile`.
- All agent Dockerfiles use `ghcr.io/gitlayzer/ubuntu:22.04-base`.
- `config.sh` is used for config command routing.
- `config.json` is used by the frontend to render config operations.
- `entrypoint.sh` is used for startup handling.
- `install.sh` is used for installation during image build.
