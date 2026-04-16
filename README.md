# Agent Hub Template

<p align="center">
  <img alt="Agent Hub" src="https://img.shields.io/badge/Agent%20Hub-Real%20Runtime%20Images-111111?style=for-the-badge" />
  <img alt="Registry Driven" src="https://img.shields.io/badge/Registry-Driven-2f6feb?style=for-the-badge" />
  <img alt="CI Ready" src="https://img.shields.io/badge/CI-Ready-16a34a?style=for-the-badge" />
</p>

<p align="center">
  <strong>A clean, registry-driven home for real agent container images.</strong>
</p>

<p align="center">
  Build, test, and scale multiple AI agent runtimes from one repository — with shared base layers, per-agent contracts, and a predictable release path.
</p>

<p align="center">
  <a href="#featured-agents">Featured Agents</a> •
  <a href="#why-teams-use-this-repo">Why This Repo</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#add-a-new-agent">Add a New Agent</a>
</p>

---

## The pitch

This repository is designed to feel less like “a pile of Dockerfiles” and more like “an agent runtime catalog”.

You define each agent once, give it a clear contract, register it in the registry, and the same repository can:

- build it
- validate it
- smoke test it
- include it in CI
- publish it through a shared release flow

That makes the repo a good fit for teams who expect to support more than one agent over time.

---

## Featured Agents

<table>
  <tr>
    <td valign="top" width="50%">
      <h3>Hermes</h3>
      <p><strong>Recommended for:</strong> terminal-first agent workflows, interactive CLI usage, and teams that want a real Hermes runtime image built from upstream source.</p>
      <p><strong>Why pick it:</strong> good default starting point if your workflow is Hermes-centric and you want a real, testable CLI image rather than a thin demo wrapper.</p>
      <p><strong>Runtime source:</strong> official <code>NousResearch/hermes-agent</code> repository</p>
      <p><strong>Base:</strong> <code>ubuntu</code></p>
      <p><strong>Image:</strong> <code>agent-hub/hermes:dev</code></p>
      <p>
        <a href="./agents/hermes/README.md">Open agent README</a>
      </p>
      <pre lang="bash">make build-agent AGENT=hermes
make test-agent AGENT=hermes

docker run --rm agent-hub/hermes:dev version</pre>
    </td>
    <td valign="top" width="50%">
      <h3>OpenClaw</h3>
      <p><strong>Recommended for:</strong> OpenClaw CLI and gateway-style runtime packaging.</p>
      <p><strong>Why pick it:</strong> ideal when you want a real OpenClaw image wired for CLI/gateway workflows and verified through the same build-and-test pipeline as the rest of the repo.</p>
      <p><strong>Runtime source:</strong> official <code>openclaw</code> npm package and upstream project</p>
      <p><strong>Base:</strong> <code>ubuntu</code></p>
      <p><strong>Image:</strong> <code>agent-hub/openclaw:dev</code></p>
      <p>
        <a href="./agents/openclaw/README.md">Open agent README</a>
      </p>
      <pre lang="bash">make build-agent AGENT=openclaw
make test-agent AGENT=openclaw

docker run --rm agent-hub/openclaw:dev --version</pre>
    </td>
  </tr>
</table>

---

## Pick the right agent

If you're choosing between the currently supported agents, use this quick guide:

| If you want... | Pick this |
|---|---|
| A terminal-oriented Hermes CLI image | Hermes |
| A real runtime image built from Hermes upstream source | Hermes |
| An OpenClaw-focused CLI/gateway image | OpenClaw |
| A containerized runtime aligned with the official OpenClaw distribution path | OpenClaw |

---

## Why teams use this repo

### 1. Real runtimes only

This repo is optimized for real agent packaging.

That means each supported agent should provide:
- real installation logic
- real startup behavior
- real health checks
- real smoke tests

It is explicitly not designed around:
- fake placeholder daemons
- demo containers that just stay alive
- wrappers that look like agents but do not package the real runtime

### 2. One contract for every agent

Every agent follows the same contract:

- `agent.yaml`
- `Dockerfile`
- `install.sh`
- `entrypoint.sh`
- `healthcheck.sh`
- `tests/smoke.sh`
- `README.md`

That makes the repository easier to extend without turning shared scripts into per-agent snowflakes.

### 3. Registry-driven automation

The registry is the source of truth for what the repository knows how to build and test.

- `registry/bases.yaml` defines reusable base images
- `registry/agents.yaml` defines recognized agent images

This keeps local workflows and CI behavior deterministic.

### 4. Easy growth from one agent to many

The same repository structure works whether you support:
- one internal agent image
- a curated set of recommended agents
- a growing catalog of agent runtimes for a wider team

---

## At a glance

| Area | What it does |
|---|---|
| `base/` | Reusable base image definitions |
| `agents/` | Per-agent runtime definitions and tests |
| `shared/` | Common shell helpers and reusable logic |
| `scripts/` | Build, validate, scaffold, and test entrypoints |
| `registry/` | Enabled bases and agents |
| `.github/workflows/` | CI and release workflows |
| `docs/` | Authoring and architecture guidance |

---

## Supported agent catalog

| Agent | Status | Runtime source | Default image | Best for |
|---|---|---|---|---|
| Hermes | Enabled | GitHub source (`NousResearch/hermes-agent`) | `agent-hub/hermes:dev` | Hermes CLI workflows |
| OpenClaw | Enabled | npm package + upstream project | `agent-hub/openclaw:dev` | OpenClaw CLI / gateway workflows |

---

## Shared base layer

All currently enabled agents build on the reusable Ubuntu base layer.

Included today:
- Ubuntu 24.04
- Python 3 runtime
- shell utilities
- network/debugging tools
- `tini` as init process
- non-root `agent` user

Reference: [`base/ubuntu/README.md`](./base/ubuntu/README.md)

---

## Quick Start

### Validate the repo

```bash
make validate
```

### Build the shared base

```bash
make build-base BASE=ubuntu
```

### Build a featured agent

```bash
make build-agent AGENT=hermes
```

### Smoke test a featured agent

```bash
make test-agent AGENT=hermes
```

### Build and test everything enabled in the registry

```bash
make build-all
make test-all
```

---

## Recommended first commands

For a new contributor, this is the shortest happy path:

```bash
make validate
make build-base BASE=ubuntu
make build-agent AGENT=hermes
make test-agent AGENT=hermes
```

If you want to inspect the runtime directly:

```bash
docker run --rm agent-hub/hermes:dev version
docker run --rm agent-hub/openclaw:dev --version
```

---

## Add a new agent

This repository is intentionally built so adding a new agent stays boring and repeatable.

### Minimal workflow

1. Create a new directory under `agents/`
2. Add the required agent files
3. Register the agent in `registry/agents.yaml`
4. Build and test it through the shared scripts

### Fast scaffold

```bash
make new-agent AGENT=my-agent
```

This copies `agents/_template` into a new agent directory and appends a new registry entry.

### Required per-agent files

```text
agents/<name>/
  agent.yaml
  Dockerfile
  install.sh
  entrypoint.sh
  healthcheck.sh
  tests/smoke.sh
  README.md
```

### Local verification

```bash
make build-agent AGENT=my-agent
make test-agent AGENT=my-agent
```

If the new agent should participate in repo-wide automation, enable it in `registry/agents.yaml` after it builds and passes smoke tests.

More guidance: [`docs/adding-a-new-agent.md`](./docs/adding-a-new-agent.md)

---

## CI and release model

The repository includes a shared delivery path:

- `validate.yml` — structural checks and repository validation
- `build.yml` — build matrix for supported bases and agents
- `release.yml` — release/publish flow

The workflows are intentionally thin and delegate logic to repository scripts instead of duplicating behavior inside workflow YAML.

---

## Design philosophy

A strong agent image repository should be:
- easy to browse
- easy to extend
- hard to break accidentally
- grounded in real runtime verification

This repo is built around that idea.

If you want a clean home for a growing set of agent runtimes, this is the pattern.
