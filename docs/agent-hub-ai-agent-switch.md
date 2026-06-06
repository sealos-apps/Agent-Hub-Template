# Agent Hub And ai-agent-switch Integration Contract

This document fixes the command contract Agent Hub uses when calling `ai-agent-switch`. Templates, images, and the Agent Hub backend must not invent separate initialization flows.

## Scope

- Image builds only install the upstream agent and `ai-agent-switch`.
- Image builds do not initialize models.
- Default image startup does not initialize or switch models.
- Agent Hub runs `ai-agent-switch` commands inside the Devbox at runtime.

## Stable Commands

Agent Hub may only depend on these stable commands:

```bash
ai-agent-switch provider init ...
ai-agent-switch client configure --client ...
ai-agent-switch client show <client> --json
ai-agent-switch status --json
```

Removed Agent Hub-specific subcommands are not part of the current contract. Do not use them in templates, images, Agent Hub backend code, or README examples.

## Client Mapping

The mapping from `template.yaml.id` to `ai-agent-switch --client` is fixed:

| template id | client |
| --- | --- |
| `hermes-agent` | `hermes` |
| `openclaw` | `openclaw` |
| `cowagent` | `cowagent` |

## Provider Mapping

AIProxy provider values in Agent Hub templates map to one `ai-agent-switch` provider:

| template provider | ai-agent-switch provider id |
| --- | --- |
| `custom:aiproxy-chat` | `aiproxy` |
| `custom:aiproxy-responses` | `aiproxy` |
| `custom:aiproxy-anthropic` | `aiproxy` |

AIProxy must remain one provider in `ai-agent-switch`; Chat Completions, Responses, and Anthropic Messages must not split it into multiple providers for Hermes/OpenClaw.

## Template `modelIntegration` Schema

Templates that support model configuration must declare integration data through `modelIntegration`. Templates define data only, not commands. Agent Hub calls `ai-agent-switch provider init` and `ai-agent-switch client configure` from this data.

Current schema:

```yaml
modelIntegration:
  type: ai-agent-switch
  client: hermes
  provider:
    id: aiproxy
    name:
      zh: AI Proxy
      en: AI Proxy
    baseURL:
      source: workspace
    apiKeyEnv: AGENT_MODEL_APIKEY
  slots:
    - key: main
      label:
        zh: 主模型
        en: Main model
      required: true
      mutable: true
      defaultModels:
        us: gpt-5.5
        cn: glm-5.1
      modelTypes:
        - text
```

Field rules:

- `type` is always `ai-agent-switch`.
- `client` must be a supported `ai-agent-switch` client id and match the Client Mapping table.
- `provider.id` is passed to `provider init --id`; AIProxy uses `aiproxy`.
- `provider.name` and `slots[].label` must be i18n maps, not plain strings.
- `provider.baseURL.source: workspace` means Agent Hub reads the base URL from workspace model-service configuration.
- `provider.apiKeyEnv` is passed to `provider init --api-key-env`; Hermes/OpenClaw use `AGENT_MODEL_APIKEY`, while CowAgent uses the env names expected by its native runtime.
- `slots[].key` can only use slot keys supported by the corresponding `ai-agent-switch` adapter; single-model agents use `main`.
- `slots[].required` means the model must be selected when creating or saving configuration.
- `slots[].mutable` means the model can be changed later from Agent Hub settings.
- `slots[].defaultModels` must explicitly declare every supported region, such as `us` and `cn`.
- `slots[].defaultModels.<region>` must reference a model ID available in the same region. Missing or invalid values are errors. Do not fallback to another region or the first model.
- `slots[].modelTypes` references `regionModelTypes.<region>[].key`; Agent Hub only allows users to select models from those types for that slot.

## Model API Mode And Kind Mapping

Every model preset in `template.yaml` must declare both `apiMode` and `kind`. When Agent Hub calls `provider init`, each model must be passed as:

```text
<modelId>:<apiMode>:<kind>
```

Allowed `apiMode` values:

- `chat_completions`
- `openai_compatible`
- `codex_responses`
- `anthropic_messages`
- `image_generation`
- `video_generation`
- `audio_transcriptions`
- `audio_speech`
- `embeddings`

Allowed `kind` values:

- `llm`
- `vision`
- `image_generation`
- `video_generation`
- `asr`
- `tts`
- `embedding`

These values come from `regionModelTypes.<region>[].models[]` or the compatibility-expanded `regionModelPresets.<region>[]`. After the user selects a model, Agent Hub must save the selected model ID, `apiMode`, and `kind` together in slot annotations and pass them through `provider init`.

## Default Model Source

Default models are not baked into images and are not selected by `ai-agent-switch`. They come from the Agent Hub template:

1. The template declares selectable models in `regionModelTypes.<region>[].models[]` or `regionModelPresets.<region>[]`.
2. The template explicitly declares each region default in `modelIntegration.slots[].defaultModels.<region>`.
3. Agent Hub backend flattens `regionModelTypes` into `regionModelPresets`; the frontend flattens the same model data into `modelOptions`.
4. The create page selects the current slot's `defaultModels.<region>` by default.
5. If the user selects another model on the create page or settings page, the user's selection wins.

Each model option must provide at least:

```yaml
value: gpt-5.5
label: GPT-5.5
provider: custom:aiproxy-responses
apiMode: codex_responses
kind: llm
```

CowAgent templates must also declare `runtimeProvider` for every model. It tells Agent Hub which native provider CowAgent should receive after syncing through AIProxy:

```yaml
value: gemini-3.1-flash-image-preview
label: Gemini 3.1 Flash Image Preview
provider: custom:aiproxy-chat
apiMode: image_generation
kind: image_generation
runtimeProvider: gemini
```

Allowed values:

- `openai`: writes the CowAgent `openai` provider and uses OpenAI-compatible `/v1`.
- `gemini`: writes the CowAgent `gemini` provider; CowAgent appends native Gemini `/v1beta/...` paths.
- `dashscope`: writes the CowAgent `dashscope` provider and uses native DashScope paths.

`runtimeProvider` only describes the agent's internal runtime format. It does not change the `provider` shown in the UI. The same AIProxy key may be exported as `OPEN_AI_API_KEY`, `GEMINI_API_KEY`, or `DASHSCOPE_API_KEY` depending on runtime needs.

Current template defaults are declared through `defaultModels.<region>`:

| template id | region | slot | default model | provider | apiMode | kind |
| --- | --- | --- | --- | --- | --- | --- |
| `hermes-agent` | `us` | `main` | `gpt-5.5` | `custom:aiproxy-responses` | `codex_responses` | `llm` |
| `hermes-agent` | `cn` | `main` | `glm-5.1` | `custom:aiproxy-chat` | `chat_completions` | `llm` |
| `openclaw` | `us` | `main` | `gpt-5.5` | `custom:aiproxy-responses` | `codex_responses` | `llm` |
| `openclaw` | `cn` | `main` | `glm-5.1` | `custom:aiproxy-chat` | `chat_completions` | `llm` |
| `cowagent` | `us` | `main` | `gpt-5.4` | `custom:aiproxy-chat` | `chat_completions` | `llm` |
| `cowagent` | `cn` | `main` | `glm-5.1` | `custom:aiproxy-chat` | `chat_completions` | `llm` |

To change a default model, update the corresponding slot's `defaultModels.<region>` in the template. Do not change Agent Hub code. The value must exist in that region's selectable model list; missing or invalid values are errors and must not fallback.

## `provider init` Parameter Sources

Agent Hub derives `provider init` parameters from fixed sources:

| `provider init` parameter | Source |
| --- | --- |
| `--id` | Derived from template provider mapping; Hermes/OpenClaw AIProxy maps to `aiproxy`, while CowAgent splits by `runtimeProvider` into `aiproxy-openai`, `aiproxy-gemini`, and `aiproxy-dashscope` |
| `--name` | Derived from provider mapping; CowAgent runtime providers use `AI Proxy OpenAI`, `AI Proxy Gemini`, and `AI Proxy DashScope` |
| `--type` | CowAgent runtime providers must pass one explicit type: `openai-chat-compatible`, `gemini`, or `dashscope` |
| `--base-url` | Create/settings page `baseURL`, usually from Agent Hub AIProxy base URL config; CowAgent `openai` uses `/v1`, `gemini` uses official `/v1beta`, and `dashscope` uses the AIProxy origin |
| `--api-key-env` | Template `modelIntegration.provider.apiKeyEnv`; CowAgent runtime providers map it to native env names: `OPEN_AI_API_KEY`, `GEMINI_API_KEY`, or `DASHSCOPE_API_KEY` |
| `--model` | Models available to the same provider id in the current region; each model is `<value>:<apiMode>:<kind>`, passed through repeated `--model` flags |
| `--default-model` | Current selected model `value` |

`provider init` does not read template files and does not choose default models. Agent Hub must first compute these values from the template and user selection, then pass the result to `ai-agent-switch` inside the container.

For Hermes/OpenClaw, the three AIProxy template provider values all map to one `aiproxy` provider, so `provider init` should include all models available to the same `aiproxy` provider in the current region. CowAgent must split providers by `runtimeProvider`; otherwise Gemini image generation would be written as OpenAI Images API, and Qwen audio/vector models would use the wrong native configuration. `--default-model` only identifies the currently selected or default main model.

## Initial Deployment Flow

After a user selects a template and model in Agent Hub, Agent Hub creates the Devbox, Service, and Ingress, then writes model configuration into Devbox env and annotations.

Once the Devbox Pod is executable, Agent Hub must run two commands inside the container:

```bash
ai-agent-switch provider init \
  --id aiproxy \
  --name "AI Proxy" \
  --base-url "$AGENT_MODEL_BASEURL" \
  --api-key-env <apiKeyEnv> \
  --model "<model-1>:<apiMode-1>:<kind-1>" \
  --model "<model-2>:<apiMode-2>:<kind-2>" \
  --model "<model-3>:<apiMode-3>:<kind-3>" \
  --default-model "$AGENT_MODEL" \
  --json

ai-agent-switch client configure \
  --client <client> \
  --slot main=aiproxy/"$AGENT_MODEL" \
  -y \
  --json
```

`<client>` is derived from `template.yaml.id` using the Client Mapping table. Multi-model agents must pass one `--slot <slot>=<provider>/<model>` flag for every configured slot. Slot keys come from `modelIntegration.slots[].key`.

These two commands are responsible for separate work:

1. `provider init`: writes or refreshes the `ai-agent-switch` provider configuration.
2. `client configure`: writes client configuration through the adapter's supported capabilities. Native field support is defined by adapter implementation.

The image `Dockerfile`, `install.sh`, `entrypoint.sh`, and default `start` command must not perform these steps. Build time cannot know the user's selected model, and default startup cannot know whether it should overwrite a model the user changed later.

If Agent Hub backend only creates resources, writes env/annotations, and schedules bootstrap without calling these two commands after the Pod is executable, the agent's native configuration will not be initialized automatically. The Agent Hub integration must include initial deployment in the same `provider init + client configure` flow.

## Later Model Switching Flow

After a user switches models from the Agent Hub settings page, Agent Hub first updates Devbox env and annotations, then runs the same two commands inside the container:

```bash
ai-agent-switch provider init \
  --id aiproxy \
  --name "AI Proxy" \
  --base-url "$AGENT_MODEL_BASEURL" \
  --api-key-env <apiKeyEnv> \
  --model "<model-1>:<apiMode-1>:<kind-1>" \
  --model "<model-2>:<apiMode-2>:<kind-2>" \
  --model "<model-3>:<apiMode-3>:<kind-3>" \
  --default-model "$AGENT_MODEL" \
  --json

ai-agent-switch client configure \
  --client <client> \
  --slot main=aiproxy/"$AGENT_MODEL" \
  -y \
  --json
```

Multi-model agents must pass one `--slot <slot>=<provider>/<model>` flag for every saved slot.

CowAgent multi-runtime-provider example:

```bash
export OPEN_AI_API_KEY="$AGENT_MODEL_APIKEY"
export GEMINI_API_KEY="$AGENT_MODEL_APIKEY"
export DASHSCOPE_API_KEY="$AGENT_MODEL_APIKEY"

ai-agent-switch provider init \
  --id aiproxy-openai \
  --name "AI Proxy OpenAI" \
  --type openai-chat-compatible \
  --base-url "https://aiproxy.usw-1.sealos.io/v1" \
  --api-key-env OPEN_AI_API_KEY \
  --model "gpt-5.4:chat_completions:llm" \
  --default-model "gpt-5.4" \
  --json

ai-agent-switch provider init \
  --id aiproxy-gemini \
  --name "AI Proxy Gemini" \
  --type gemini \
  --base-url "https://aiproxy.usw-1.sealos.io/v1beta" \
  --api-key-env GEMINI_API_KEY \
  --model "gemini-3.1-flash-image-preview:image_generation:image_generation" \
  --json

ai-agent-switch provider init \
  --id aiproxy-dashscope \
  --name "AI Proxy DashScope" \
  --type dashscope \
  --base-url "https://aiproxy.usw-1.sealos.io" \
  --api-key-env DASHSCOPE_API_KEY \
  --model "qwen-image-2.0-pro:image_generation:image_generation" \
  --json

ai-agent-switch client configure \
  --client cowagent \
  --slot main=aiproxy-openai/gpt-5.4 \
  --slot image=aiproxy-gemini/gemini-3.1-flash-image-preview \
  -y \
  --json
```

Every switch runs `provider init + client configure` and remains idempotent. Do not run only `client configure`, because a newly selected model may not exist in the provider model list yet.

Model switching does not depend on image rebuilds and does not depend on agent default startup scripts reinitializing models. Agent Hub backend should run the commands above in the running Devbox container.

## Configuration Page Source

Agent Hub configuration pages do not read model lists from images. They read template metadata:

- `settings`: fields shown on configuration pages, their display behavior, and whether they require redeployment.
- `regionModelPresets`: region-specific provider, base URL, model, `apiMode`, `kind`, and CowAgent `runtimeProvider` options.
- `presentation`, `access`, and `actions`: template display, access entries, and operation buttons in Agent Hub.

After model-related fields change, Agent Hub should sync them to the running agent through the Later Model Switching Flow instead of requiring image startup scripts to parse templates.

## Showing Current Model

Agent Hub may show Kubernetes metadata from Devbox annotations/env:

- `agent.sealos.io/model-provider`
- `agent.sealos.io/model-baseurl`
- `agent.sealos.io/model`
- `agent.sealos.io/model-api-mode`
- `agent.sealos.io/model-slots`
- `AGENT_MODEL_PROVIDER`
- `AGENT_MODEL_BASEURL`
- `AGENT_MODEL_APIKEY`
- `AGENT_MODEL`
- `AGENT_MODEL_API_MODE`

To confirm the model actually active inside the agent, run this command inside the container:

```bash
ai-agent-switch client show <client> --json
```

## CowAgent Notes

CowAgent native runtime reads different env names by provider. During sync, Agent Hub exports the same AIProxy key under the runtime provider's native env name:

- `OPEN_AI_API_KEY`
- `GEMINI_API_KEY`
- `DASHSCOPE_API_KEY`
- `AGENT_MODEL_APIKEY`
- `AGENT_MODEL_BASEURL`

When Agent Hub initializes providers, the OpenAI runtime provider uses AIProxy `/v1`, the Gemini runtime provider uses AIProxy `/v1beta`, and the DashScope runtime provider uses the AIProxy origin. When `ai-agent-switch` writes CowAgent config, it converts the AIProxy Gemini `/v1beta` URL to the origin CowAgent expects, because CowAgent source code appends `/v1beta/models/...` itself.

`ai-agent-switch client configure --client cowagent ...` syncs fields supported by the current CowAgent adapter. The adapter currently supports `main`, `vision`, `image`, `asr`, `tts`, and `embedding` slots by `kind`, and writes the matching native CowAgent configuration fields. Runtime env still needs to be guaranteed by the template and Agent Hub.

## rebootstrap Rules

Model-related fields should not rely on rebootstrap:

- `provider`
- `model`
- `baseURL`

These fields should be synced at runtime through `provider init + client configure`.

Only fields that truly require a restart or regenerated service configuration should set `rebootstrap: true`, such as gateway tokens or access authentication settings.
