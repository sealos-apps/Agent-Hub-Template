# Agent Hub 与 ai-agent-switch 对接契约

本文档固定 Agent Hub 调用 `ai-agent-switch` 的命令契约，避免模板、镜像和 Agent Hub 后端各自发明初始化方式。

## 适用边界

- 镜像构建阶段只安装 agent 本体和 `ai-agent-switch`。
- 镜像构建阶段不执行模型初始化。
- 镜像默认启动不执行模型初始化或模型切换。
- Agent Hub 负责在 Devbox 运行期执行 `ai-agent-switch` 命令。

## 稳定命令

Agent Hub 只能依赖这些稳定命令：

```bash
ai-agent-switch provider init ...
ai-agent-switch client configure --client ...
ai-agent-switch client show <client> --json
ai-agent-switch status --json
```

已删除的 Agent Hub 专用子命令不存在于当前契约，禁止在模板、镜像、Agent Hub 后端和 README 示例中使用。

## Client 映射

`template.yaml.id` 到 `ai-agent-switch --client` 的映射固定如下：

| template id | client |
| --- | --- |
| `hermes-agent` | `hermes` |
| `openclaw` | `openclaw` |
| `cowagent` | `cowagent` |

## Provider 映射

Agent Hub 模板里的 AIProxy provider 值统一映射为一个 `ai-agent-switch` provider：

| template provider | ai-agent-switch provider id |
| --- | --- |
| `custom:aiproxy-chat` | `aiproxy` |
| `custom:aiproxy-responses` | `aiproxy` |
| `custom:aiproxy-anthropic` | `aiproxy` |

这样 AIProxy 在 `ai-agent-switch` 里始终是一个 provider，不因为 Chat Completions、Responses 或 Anthropic Messages 分裂成多个 provider。

## 模板 `modelIntegration` schema

支持模型配置的模板必须通过 `modelIntegration` 声明模型集成数据。模板只定义数据，不定义命令；Agent Hub 根据这些数据调用 `ai-agent-switch provider init` 和 `ai-agent-switch client configure`。

当前版本 schema：

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

字段约束：

- `type` 固定为 `ai-agent-switch`。
- `client` 必须是 `ai-agent-switch` 已支持的 client id，并与本文档的 Client 映射一致。
- `provider.id` 是传给 `provider init --id` 的 provider id；AIProxy 统一使用 `aiproxy`。
- `provider.name` 和 `slots[].label` 必须是 i18n map，不要写成单一字符串。
- `provider.baseURL.source: workspace` 表示 Agent Hub 从工作区模型服务配置获取 baseURL。
- `provider.apiKeyEnv` 是传给 `provider init --api-key-env` 的容器内环境变量名；Hermes/OpenClaw 使用 `AGENT_MODEL_APIKEY`，CowAgent 使用其原生读取的 `OPEN_AI_API_KEY`。
- `slots[].key` 只能使用对应 `ai-agent-switch` adapter 已支持的 slot key，例如单模型 agent 使用 `main`。
- `slots[].required` 表示创建或保存配置时是否必须选择模型。
- `slots[].mutable` 表示创建后是否允许在 Agent Hub 设置页修改。
- `slots[].defaultModels` 必须按 region 显式声明默认模型，例如 `us` 和 `cn` 都要写出。
- `slots[].defaultModels.<region>` 必须引用同一 region 可选模型中的模型 ID。Agent Hub 按当前 region 读取对应值；缺失或非法必须直接报错，不允许 fallback 到其他 region 或第 1 个模型。
- `slots[].modelTypes` 引用 `regionModelTypes.<region>[].key`，Agent Hub 只允许用户为该 slot 选择这些类型下的模型。

## 模型调用与用途映射

`template.yaml` 的模型预设必须为每个模型声明 `apiMode` 和 `kind`。Agent Hub 调用 `provider init` 时必须把模型写成：

```text
<modelId>:<apiMode>:<kind>
```

当前允许的 `apiMode`：

- `chat_completions`
- `openai_compatible`
- `codex_responses`
- `anthropic_messages`
- `image_generation`
- `video_generation`
- `audio_transcriptions`
- `audio_speech`
- `embeddings`

当前允许的 `kind`：

- `llm`
- `vision`
- `image_generation`
- `video_generation`
- `asr`
- `tts`
- `embedding`

这些值来自 Agent Hub 模板的 `regionModelTypes.<region>[].models[]` 或兼容展开后的 `regionModelPresets.<region>[]`。配置页让用户选择模型后，Agent Hub 必须把选中的模型 ID、`apiMode` 和 `kind` 一起保存到 slot annotation，并在 `provider init` 里透传。

## 默认模型来源

默认模型不是镜像内置值，也不是 `ai-agent-switch` 自己选择的值。它来自 Agent Hub 模板目录：

1. 模板在 `regionModelTypes.<region>[].models[]` 或 `regionModelPresets.<region>[]` 声明可选模型。
2. 模板在 `modelIntegration.slots[].defaultModels.<region>` 为每个 region 显式声明默认模型。
3. Agent Hub 后端会把 `regionModelTypes` 展平成 `regionModelPresets`，前端会把同一批模型展平成 `modelOptions`。
4. 创建页默认选中当前 slot 在当前 region 的 `defaultModels.<region>`。
5. 用户如果在创建页或设置页选择了其他模型，就以用户选择为准。

每个模型选项至少要提供：

```yaml
value: gpt-5.5
label: GPT-5.5
provider: custom:aiproxy-responses
apiMode: codex_responses
kind: llm
```

当前模板里的默认值按 `defaultModels.<region>` 声明：

| template id | region | slot | 默认模型 | provider | apiMode | kind |
| --- | --- | --- | --- | --- | --- | --- |
| `hermes-agent` | `us` | `main` | `gpt-5.5` | `custom:aiproxy-responses` | `codex_responses` | `llm` |
| `hermes-agent` | `cn` | `main` | `glm-5.1` | `custom:aiproxy-chat` | `chat_completions` | `llm` |
| `openclaw` | `us` | `main` | `gpt-5.5` | `custom:aiproxy-responses` | `codex_responses` | `llm` |
| `openclaw` | `cn` | `main` | `glm-5.1` | `custom:aiproxy-chat` | `chat_completions` | `llm` |
| `cowagent` | `us` | `main` | `gpt-5.4` | `custom:aiproxy-chat` | `chat_completions` | `llm` |
| `cowagent` | `cn` | `main` | `glm-5.1` | `custom:aiproxy-chat` | `chat_completions` | `llm` |

如果调整默认模型，不改 Agent Hub 代码，只调整模板里对应 slot 的 `defaultModels.<region>`。该值必须存在于对应 `regionModelTypes.<region>` 可选模型中；缺失或非法直接报错，不 fallback。

## provider init 参数来源

Agent Hub 执行 `provider init` 时，参数来源固定如下：

| `provider init` 参数 | 来源 |
| --- | --- |
| `--id` | 由模板 provider 映射而来；AIProxy 统一为 `aiproxy` |
| `--name` | 由 provider 映射而来；AIProxy 统一为 `AI Proxy` |
| `--base-url` | 创建页/设置页的 `baseURL` 字段，默认来自 Agent Hub 的 AIProxy baseURL 配置 |
| `--api-key-env` | 模板 `modelIntegration.provider.apiKeyEnv`；Hermes/OpenClaw 为 `AGENT_MODEL_APIKEY`，CowAgent 为 `OPEN_AI_API_KEY` |
| `--model` | 当前 region 下同一个 provider id 可用的模型列表；每个模型用 `value`、`apiMode` 和 `kind` 组合成 `<value>:<apiMode>:<kind>`，并重复传多个 `--model` |
| `--default-model` | 当前选中的模型 `value` |

`provider init` 不读取模板文件，也不负责挑默认模型。Agent Hub 必须先从模板和用户选择里算出这些值，再把结果传给容器内的 `ai-agent-switch`。

AIProxy 的 3 个模板 provider 最终都映射成 `aiproxy`，所以 `provider init` 应写入当前 region 下所有属于同一个 `aiproxy` provider 的可用模型，包括文本、图片、音频和向量模型，而不是只写入当前选中的一个模型。`--default-model` 才表示当前选中或默认使用的主模型。

## 初次部署流程

用户在 Agent Hub 选择模板和模型后，Agent Hub 创建 Devbox、Service、Ingress，并把模型配置写入 Devbox env 和 annotations。

Devbox Pod 可执行后，Agent Hub 必须在容器内执行两步：

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

其中 `<client>` 按本文档的 Client 映射表从 `template.yaml.id` 推导。
多模型 agent 必须为每个已配置 slot 传入一个 `--slot <slot>=<provider>/<model>` 参数；slot key 来自模板 `modelIntegration.slots[].key`。

这两步分别负责：

1. `provider init`：写入或刷新 `ai-agent-switch` provider 配置。
2. `client configure`：按 adapter 支持的能力写入 client 配置；原生字段支持范围以 adapter 实现为准。

镜像的 `Dockerfile`、`install.sh`、`entrypoint.sh` 和默认 `start` 命令都不承担这两步。否则构建期无法知道用户选择的模型，默认启动也无法判断是否需要覆盖用户后续切换过的模型。

当前 Agent Hub 后端如果只创建资源、写入 env/annotations、调度 bootstrap，而没有在 Pod 可执行后调用这两步命令，那么 agent 内部原生配置不会自动完成初始化。Agent Hub 对接实现必须把首次部署也纳入同一条 `provider init + client configure` 流程。

## 后续切换模型流程

用户在 Agent Hub 设置页切换模型后，Agent Hub 先更新 Devbox env 和 annotations，再在容器内执行同样的两步命令：

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

多模型 agent 必须为每个本次保存的 slot 传入一个 `--slot <slot>=<provider>/<model>` 参数。

每次切换都执行 `provider init + client configure`，保持幂等。不要只执行 `client configure`，因为新模型可能还没有写入 provider 的模型列表。

切换模型不依赖镜像重建，也不依赖 agent 默认启动脚本重新初始化。Agent Hub 后端应在运行中的 Devbox 容器内执行上面的命令。

## 配置页来源

Agent Hub 配置页不从镜像内读取模型列表，而是读取模板元数据：

- `settings`：定义配置页里的字段、展示方式和是否需要重新部署。
- `regionModelPresets`：定义不同区域可选的 provider、baseURL、模型、`apiMode` 和 `kind`。
- `presentation`、`access`、`actions`：定义模板在 Agent Hub 里的展示、访问入口和操作按钮。

模型相关字段变更后，Agent Hub 应按「后续切换模型流程」同步到运行中的 agent，而不是要求镜像启动脚本自行解析模板。

## 查看当前模型

Agent Hub 展示 K8s 元数据时可以读取 Devbox annotations/env：

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

如果要确认 agent 内部真实生效的模型，必须在容器内执行：

```bash
ai-agent-switch client show <client> --json
```

## CowAgent 注意事项

CowAgent 原生运行时仍读取 `OPEN_AI_API_KEY` 和 `OPEN_AI_API_BASE`。模板需要继续注入 CowAgent 原生 env，同时也注入 Agent Hub 标准 env：

- `OPEN_AI_API_KEY`
- `OPEN_AI_API_BASE`
- `AGENT_MODEL_APIKEY`
- `AGENT_MODEL_BASEURL`

`ai-agent-switch client configure --client cowagent ...` 只保证同步 CowAgent 当前 adapter 已支持的 `main` 原生字段。当前 adapter 已按 `kind` 支持 CowAgent 的 `main`、`vision`、`image`、`asr`、`tts` 和 `embedding` slot，并写入 CowAgent 对应原生配置字段。运行时 env 仍需要由模板保证。

## rebootstrap 规则

模型相关字段不应该依赖 rebootstrap：

- `provider`
- `model`
- `baseURL`

这些字段应通过 `provider init + client configure` 完成运行期同步。

只有真正需要重启或重新生成服务配置的字段才应该设置 `rebootstrap: true`，例如网关 token、入口鉴权等非模型配置。
