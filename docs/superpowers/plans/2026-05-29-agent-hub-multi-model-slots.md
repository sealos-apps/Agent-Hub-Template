# Agent Hub 多模型槽位实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 让 Agent Hub 可以基于模板为一个 agent 配置多个模型槽位，并通过 `ai-agent-switch` 在运行期热同步到 agent 原生配置。

**架构：** `ai-agent-switch` 提供稳定的 `client configure --slot ...` 命令和 adapter 槽位能力；`Agent-Hub-Template` 只声明模型槽位、区域模型池和 i18n 展示元数据；`agenthub` 负责渲染、保存、校验和通过 K8s exec 执行同步。模板不定义 shell 命令，Agent Hub 不直接写 agent 原生配置。

**技术栈：** TypeScript/Bun、Go/Gin、React/TypeScript、Kubernetes exec、YAML template schema。

---

## 总体顺序

1. `ai-agent-switch`：先完成多槽位命令和 adapter 能力。
2. `Agent-Hub-Template`：再定义模板多模型 schema 和三类 agent 示例。
3. `agenthub`：最后接入后端 DTO/同步逻辑和前端表单。

原因：Agent Hub 最终要调用容器里的 `ai-agent-switch`。如果 CLI 契约没有先稳定，模板和 Agent Hub 会再次产生错误命令。

## 文件结构

### `/Users/night/Documents/code/sealos/a/agent-switch`

- 修改：`src/clients/types.ts`，增加 slot 配置输入、当前状态和 adapter 能力类型。
- 修改：`src/core/app.ts`，增加 `configureClient()` 原子配置入口。
- 修改：`src/cli/main.ts`，增加 `client configure --slot key=provider/model` 命令。
- 修改：`src/clients/cowagent.ts`，实现 CowAgent 多槽位写入。
- 修改：`src/clients/hermes.ts`，实现 Hermes `main` 槽位，暂不虚构 Hermes 不支持的槽位。
- 修改：`src/clients/openclaw.ts`，实现 OpenClaw `main` 槽位，暂不虚构 OpenClaw 不支持的槽位。
- 修改：`README.md`、`README_CN.md`，记录新命令，删除已过时的多模型说法。
- 新增或修改：`tests/client-configure.test.ts`，覆盖命令解析、原子写入和 unsupported slot。

### `/Users/night/Documents/code/sealos/Agent-Hub-Template`

- 修改：`docs/agent-hub-ai-agent-switch.md`，把单模型契约升级为模型槽位契约。
- 修改：`docs/agent-contract.md`，记录模板字段归属。
- 修改：`docs/adding-a-new-agent.md`，给新增 agent 的 slot/schema 规范。
- 修改：`agents/_template/template.yaml`，增加标准 schema 示例。
- 修改：`agents/hermes-agent/template.yaml`，定义单 `main` 槽位。
- 修改：`agents/openclaw/template.yaml`，定义单 `main` 槽位。
- 修改：`agents/cowagent/template.yaml`，定义 CowAgent 当前需要的多模型槽位。
- 修改：`test/validate-agent-contract.sh`，校验槽位、i18n label、region 模型引用、禁止旧 `agent-hub init` 命令。

### `/Users/night/Documents/code/sealos/agenthub`

- 修改：`backend/internal/agenttemplate/template.go`，解析 `modelIntegration`。
- 修改：`backend/internal/dto/template.go`，向前端输出模型槽位 schema。
- 修改：`backend/internal/handler/template.go`，按 region 输出 slot 可选模型。
- 修改：`backend/internal/handler/agent_template_settings.go`，校验和映射多槽位 payload。
- 修改：`backend/internal/handler/agent_model_sync.go`，从单 `switch` 改为 `provider init + client configure`。
- 修改：`backend/internal/handler/agent.go`、`backend/internal/handler/agent_settings_update.go`，创建和修改时统一触发多槽位同步。
- 修改：`backend/internal/dto/agent.go`、`backend/internal/dto/agent_contract.go`，返回当前槽位选择。
- 修改：`frontend/src/domains/agents/types.ts`，增加 `modelIntegration`、`modelSlots` 类型。
- 修改：`frontend/src/domains/agents/templates.ts`，初始化 blueprint 的槽位默认值。
- 修改：`frontend/src/components/business/agents/AgentConfigForm.tsx`，创建页渲染多个模型槽位。
- 修改：`frontend/src/app/pages/agent-hub/components/AgentSettingsWorkspace.tsx`，设置页渲染多个可修改槽位。
- 修改：`frontend/src/components/business/agents/ModelCapabilitySelect.tsx`，复用为 slot 模型选择器。
- 修改：`frontend/src/i18n.tsx`，补充用户可见文案。

---

## 任务 1：为 `ai-agent-switch` 定义 slot 类型

**文件：**
- 修改：`/Users/night/Documents/code/sealos/a/agent-switch/src/clients/types.ts`

- [ ] **步骤 1：编写失败的类型使用测试**

在 `/Users/night/Documents/code/sealos/a/agent-switch/tests/client-configure.test.ts` 新增最小测试骨架：

```ts
import { describe, expect, test } from "bun:test";
import type { ClientSlotTarget } from "../src/clients/types";

describe("client slot targets", () => {
  test("represents named provider/model slots", () => {
    const target: ClientSlotTarget = {
      slot: "main",
      providerId: "aiproxy",
      modelId: "glm-5.1",
    };

    expect(target.slot).toBe("main");
    expect(target.providerId).toBe("aiproxy");
    expect(target.modelId).toBe("glm-5.1");
  });
});
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd /Users/night/Documents/code/sealos/a/agent-switch
bun test tests/client-configure.test.ts
```

预期：FAIL，报错包含 `ClientSlotTarget` 未导出。

- [ ] **步骤 3：增加最小类型**

在 `/Users/night/Documents/code/sealos/a/agent-switch/src/clients/types.ts` 增加：

```ts
export type ClientSlotTarget = {
  slot: string;
  providerId: string;
  modelId: string;
};

export type ApplyClientSlotsInput = {
  slots: Array<{
    slot: string;
    provider: ProviderProfile;
    modelId: string;
  }>;
};

export type ClientCurrentSlotState = ClientSlotTarget & {
  configPath: string;
};
```

- [ ] **步骤 4：运行测试验证通过**

运行：

```bash
cd /Users/night/Documents/code/sealos/a/agent-switch
bun test tests/client-configure.test.ts
```

预期：PASS。

- [ ] **步骤 5：Commit**

```bash
cd /Users/night/Documents/code/sealos/a/agent-switch
git add src/clients/types.ts tests/client-configure.test.ts
git commit -m "feat(client): add model slot target types"
```

---

## 任务 2：实现 `client configure --slot`

**文件：**
- 修改：`/Users/night/Documents/code/sealos/a/agent-switch/src/core/app.ts`
- 修改：`/Users/night/Documents/code/sealos/a/agent-switch/src/cli/main.ts`
- 测试：`/Users/night/Documents/code/sealos/a/agent-switch/tests/client-configure.test.ts`

- [ ] **步骤 1：编写失败的 CLI 测试**

在 `tests/client-configure.test.ts` 增加：

```ts
test("client configure requires at least one slot", async () => {
  const result = await Bun.spawn({
    cmd: ["bun", "src/cli/main.ts", "client", "configure", "--client", "cowagent", "--json"],
    cwd: import.meta.dir + "/..",
    env: { ...process.env, HOME: await Bun.file("/tmp").text().catch(() => "/tmp") },
    stdout: "pipe",
    stderr: "pipe",
  }).exited;

  expect(result).not.toBe(0);
});
```

如果现有测试工具里已有 CLI runner，改用项目现有 runner，不新增第二套 runner。

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd /Users/night/Documents/code/sealos/a/agent-switch
bun test tests/client-configure.test.ts
```

预期：FAIL 或命令报 `Unsupported client action: configure`。

- [ ] **步骤 3：在 core 增加配置入口**

在 `AiAgentSwitchApp` 中增加方法：

```ts
async configureClient(input: {
  clientId: ClientId;
  slots: ClientSlotTarget[];
  yes: boolean;
}): Promise<UseClientResult> {
  if (input.slots.length === 0) {
    throw new Error("Missing --slot");
  }
  if (input.slots.some((slot) => !slot.slot || !slot.providerId || !slot.modelId)) {
    throw new Error("Invalid --slot; expected name=provider/model");
  }
  if (input.slots.length !== new Set(input.slots.map((slot) => slot.slot)).size) {
    throw new Error("Duplicate slot");
  }

  const first = input.slots[0]!;
  return this.switchClient({
    clientId: input.clientId,
    providerId: first.providerId,
    modelId: first.modelId,
    yes: input.yes,
  });
}
```

这一步先保持单槽位兼容，不实现多槽位写文件。多槽位 adapter 在任务 3 落地。

- [ ] **步骤 4：在 CLI 增加解析**

在 `client <action> [client]` 命令增加选项：

```ts
.option("--slot <slot>", "Model slot, repeatable, format name=provider/model", { default: [] })
```

在 action 中加入：

```ts
if (action === "configure") {
  const clientId = parseClientId(stringOption(options.client ?? client, "client"));
  const result = await app.configureClient({
    clientId,
    slots: parseClientSlots(options.slot),
    yes: Boolean(options.yes) && !options.dryRun,
  });
  if (options.json) {
    console.log(JSON.stringify(result, null, 2));
    return;
  }
  printPatchPlan(result.plan);
  return;
}
```

增加解析函数：

```ts
function parseClientSlots(value: unknown): ClientSlotTarget[] {
  return normalizeModels(value).map((entry) => {
    const equals = entry.indexOf("=");
    const slash = entry.indexOf("/", equals + 1);
    if (equals <= 0 || slash <= equals + 1) {
      throw new Error(`Invalid --slot: ${entry}`);
    }
    return {
      slot: entry.slice(0, equals).trim(),
      providerId: entry.slice(equals + 1, slash).trim(),
      modelId: entry.slice(slash + 1).trim(),
    };
  });
}
```

- [ ] **步骤 5：运行测试验证通过**

运行：

```bash
cd /Users/night/Documents/code/sealos/a/agent-switch
bun test tests/client-configure.test.ts
```

预期：PASS。

- [ ] **步骤 6：Commit**

```bash
cd /Users/night/Documents/code/sealos/a/agent-switch
git add src/core/app.ts src/cli/main.ts tests/client-configure.test.ts
git commit -m "feat(cli): add client configure slot command"
```

---

## 任务 3：让 adapter 原子写入多槽位

**文件：**
- 修改：`/Users/night/Documents/code/sealos/a/agent-switch/src/clients/types.ts`
- 修改：`/Users/night/Documents/code/sealos/a/agent-switch/src/core/app.ts`
- 修改：`/Users/night/Documents/code/sealos/a/agent-switch/src/clients/cowagent.ts`
- 修改：`/Users/night/Documents/code/sealos/a/agent-switch/src/clients/hermes.ts`
- 修改：`/Users/night/Documents/code/sealos/a/agent-switch/src/clients/openclaw.ts`
- 测试：`/Users/night/Documents/code/sealos/a/agent-switch/tests/client-configure.test.ts`

- [ ] **步骤 1：编写失败的 CowAgent 多槽位测试**

在 `tests/client-configure.test.ts` 增加：

```ts
test("cowagent configure writes multiple slots atomically", async () => {
  // 使用项目现有临时 HOME/config store 工具；如果没有，则创建临时目录并设置 HOME、COWAGENT_HOME。
  // 断言 config.json 内有 ai_agent_switch.slots.main 和 ai_agent_switch.slots.vision。
});
```

实际断言目标：

```json
{
  "ai_agent_switch": {
    "slots": {
      "main": { "provider": "aiproxy", "model": "glm-5.1" },
      "vision": { "provider": "aiproxy", "model": "glm-4.6v" }
    }
  }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd /Users/night/Documents/code/sealos/a/agent-switch
bun test tests/client-configure.test.ts
```

预期：FAIL，因为 adapter 没有 `planApplySlots`。

- [ ] **步骤 3：扩展 adapter 接口**

在 `ClientAdapter` 增加可选方法：

```ts
planApplySlots?(input: ApplyClientSlotsInput): Promise<PatchPlan>;
```

在 `AiAgentSwitchApp.configureClient()` 中改为：

```ts
const adapter = this.adapters.get(input.clientId);
if (!adapter) throw new Error(`Client not supported: ${input.clientId}`);
if (!adapter.planApplySlots && input.slots.length > 1) {
  throw new Error(`Client ${input.clientId} does not support multiple model slots`);
}
```

解析每个 slot 的 provider/model，校验 provider 和 model 存在，然后调用 `planApplySlots`。如果只有一个 `main` 且 adapter 没有 `planApplySlots`，保留现有 `planApply` 路径。

- [ ] **步骤 4：实现 CowAgent 多槽位**

在 `CowAgentAdapter` 增加：

```ts
async planApplySlots(input: ApplyClientSlotsInput): Promise<PatchPlan> {
  const main = input.slots.find((slot) => slot.slot === "main");
  if (!main) throw new Error("CowAgent requires main slot");

  const before = await readTextIfExists(this.configPath);
  const config = parseJsonObject(before);

  const mainFields = cowAgentProviderFields(resolveModelType(main.provider, main.modelId));
  config.model = main.modelId;
  config.bot_type = mainFields.botType;
  if (mainFields.apiBaseKey) config[mainFields.apiBaseKey] = main.provider.baseUrl;
  if (mainFields.apiKeyKey) config[mainFields.apiKeyKey] = cowAgentApiKey(main.provider, mainFields);

  const aiAgentSwitch = recordAt(config, "ai_agent_switch");
  const slots = recordAt(aiAgentSwitch, "slots");
  for (const slot of input.slots) {
    slots[slot.slot] = {
      provider: slot.provider.id,
      model: slot.modelId,
    };
  }

  const file = before === undefined
    ? { path: this.configPath, after: stringifyJson(config) }
    : { path: this.configPath, before, after: stringifyJson(config) };
  return { clientId: this.id, summary: "Configure CowAgent model slots", files: [file] };
}
```

不要猜 CowAgent 原生的 `vision`、`image` 字段名；如果当前 CowAgent 原生只支持主模型，就只把非 `main` slot 记录在 `ai_agent_switch.slots`。需要写原生字段前，必须先查 CowAgent 官方配置并单独确认。

- [ ] **步骤 5：Hermes/OpenClaw 显式拒绝多槽位**

在 Hermes/OpenClaw adapter 中实现只接受 `main` 的 `planApplySlots`，多于一个 slot 直接报错：

```ts
if (input.slots.length !== 1 || input.slots[0]?.slot !== "main") {
  throw new Error("Hermes Agent currently supports only main model slot");
}
return this.planApply({ provider: input.slots[0].provider, modelId: input.slots[0].modelId });
```

OpenClaw 同理。

- [ ] **步骤 6：运行测试验证通过**

运行：

```bash
cd /Users/night/Documents/code/sealos/a/agent-switch
bun test tests/client-configure.test.ts
bun test
```

预期：PASS。

- [ ] **步骤 7：Commit**

```bash
cd /Users/night/Documents/code/sealos/a/agent-switch
git add src/clients/types.ts src/core/app.ts src/clients/cowagent.ts src/clients/hermes.ts src/clients/openclaw.ts tests/client-configure.test.ts
git commit -m "feat(client): configure model slots atomically"
```

---

## 任务 4：更新 `ai-agent-switch` 文档

**文件：**
- 修改：`/Users/night/Documents/code/sealos/a/agent-switch/README.md`
- 修改：`/Users/night/Documents/code/sealos/a/agent-switch/README_CN.md`

- [ ] **步骤 1：新增命令说明**

加入示例：

```bash
ai-agent-switch client configure \
  --client cowagent \
  --slot main=aiproxy/glm-5.1 \
  --slot vision=aiproxy/glm-4.6v \
  -y \
  --json
```

说明：

```md
`client configure` atomically writes one or more named model slots for a client. `main` is the default runtime model. Other slot names are client-specific and must be supported by the adapter.
```

- [ ] **步骤 2：运行文档相关测试**

运行：

```bash
cd /Users/night/Documents/code/sealos/a/agent-switch
bun test
```

预期：PASS。

- [ ] **步骤 3：Commit**

```bash
cd /Users/night/Documents/code/sealos/a/agent-switch
git add README.md README_CN.md
git commit -m "docs(client): document model slot configuration"
```

---

## 任务 5：定义模板 `modelIntegration` schema

**文件：**
- 修改：`/Users/night/Documents/code/sealos/Agent-Hub-Template/docs/agent-hub-ai-agent-switch.md`
- 修改：`/Users/night/Documents/code/sealos/Agent-Hub-Template/docs/agent-contract.md`
- 修改：`/Users/night/Documents/code/sealos/Agent-Hub-Template/docs/adding-a-new-agent.md`

- [ ] **步骤 1：写入 schema 文档**

在 `docs/agent-hub-ai-agent-switch.md` 增加当前版本 schema：

```yaml
modelIntegration:
  type: ai-agent-switch
  client: cowagent
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
      defaultModel: glm-5.1
      modelTypes:
        - text
    - key: vision
      label:
        zh: 视觉模型
        en: Vision model
      required: false
      mutable: true
      modelTypes:
        - multimodal
```

约束写清楚：

- `label` 必须是 i18n map。
- `slots[].key` 只能由 adapter 支持。
- `modelTypes` 引用 `regionModelTypes.<region>[].key`。
- 模板只定义数据，不定义命令。
- Agent Hub 调用 `provider init` 和 `client configure`。

- [ ] **步骤 2：更新新增 agent 文档**

在 `docs/adding-a-new-agent.md` 增加：

```md
新增支持模型配置的 agent 时，必须声明 `modelIntegration`。如果 agent 只有一个模型，声明单个 `main` slot。不要再通过 `settings.agent` 新增 `provider/model/baseURL` 三个字段。
```

- [ ] **步骤 3：提交文档**

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
git add docs/agent-hub-ai-agent-switch.md docs/agent-contract.md docs/adding-a-new-agent.md
git commit -m "docs(contract): define model slot integration schema"
```

---

## 任务 6：改造三个模板

**文件：**
- 修改：`/Users/night/Documents/code/sealos/Agent-Hub-Template/agents/_template/template.yaml`
- 修改：`/Users/night/Documents/code/sealos/Agent-Hub-Template/agents/hermes-agent/template.yaml`
- 修改：`/Users/night/Documents/code/sealos/Agent-Hub-Template/agents/openclaw/template.yaml`
- 修改：`/Users/night/Documents/code/sealos/Agent-Hub-Template/agents/cowagent/template.yaml`

- [ ] **步骤 1：写入 `_template` 示例**

在 `_template/template.yaml` 增加：

```yaml
modelIntegration:
  type: ai-agent-switch
  client: example
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
      defaultModel: glm-5.1
      modelTypes: [text]
```

- [ ] **步骤 2：Hermes/OpenClaw 单槽位**

在 Hermes/OpenClaw 增加：

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
      defaultModel: gpt-5.5
      modelTypes: [text]
```

OpenClaw 的 `client` 改成 `openclaw`。

- [ ] **步骤 3：CowAgent 多槽位**

在 CowAgent 增加：

```yaml
modelIntegration:
  type: ai-agent-switch
  client: cowagent
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
      defaultModel: glm-5.1
      modelTypes: [text]
    - key: vision
      label:
        zh: 视觉模型
        en: Vision model
      required: false
      mutable: true
      modelTypes: [multimodal]
```

如果当前 CowAgent 实际还需要 `image` 或其他槽位，先查 CowAgent 原生配置；没有确认前不要添加。

- [ ] **步骤 4：暂时保留旧 settings 单模型字段**

为了让 Agent Hub 分阶段接入，先保留现有 `settings.agent.provider/model/baseURL`。在 Agent Hub 任务完成后再单独删除旧字段，避免一次性破坏现有创建流程。

- [ ] **步骤 5：Commit**

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
git add agents/_template/template.yaml agents/hermes-agent/template.yaml agents/openclaw/template.yaml agents/cowagent/template.yaml
git commit -m "feat(template): add ai agent switch model slots"
```

---

## 任务 7：模板校验多槽位契约

**文件：**
- 修改：`/Users/night/Documents/code/sealos/Agent-Hub-Template/test/validate-agent-contract.sh`

- [ ] **步骤 1：增加失败校验**

在 Python 校验段中检查：

```python
integration = template.get("modelIntegration")
if not isinstance(integration, dict):
    raise SystemExit(f"{template_path}: modelIntegration is required")
if integration.get("type") != "ai-agent-switch":
    raise SystemExit(f"{template_path}: modelIntegration.type must be ai-agent-switch")
if not integration.get("client"):
    raise SystemExit(f"{template_path}: modelIntegration.client is required")
slots = integration.get("slots")
if not isinstance(slots, list) or not slots:
    raise SystemExit(f"{template_path}: modelIntegration.slots must be a non-empty list")
slot_keys = set()
for slot in slots:
    key = str(slot.get("key", "")).strip()
    if not key:
        raise SystemExit(f"{template_path}: modelIntegration.slots[].key is required")
    if key in slot_keys:
        raise SystemExit(f"{template_path}: duplicate modelIntegration slot {key}")
    slot_keys.add(key)
    label = slot.get("label")
    if not isinstance(label, dict) or not label.get("zh") or not label.get("en"):
        raise SystemExit(f"{template_path}: modelIntegration.slots.{key}.label must include zh and en")
    model_types = slot.get("modelTypes")
    if not isinstance(model_types, list) or not model_types:
        raise SystemExit(f"{template_path}: modelIntegration.slots.{key}.modelTypes must be non-empty")
```

- [ ] **步骤 2：运行校验**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
bash test/validate-agent-contract.sh
```

预期：PASS。

- [ ] **步骤 3：Commit**

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
git add test/validate-agent-contract.sh
git commit -m "test(template): validate model slot contract"
```

---

## 任务 8：Agent Hub 后端解析 `modelIntegration`

**文件：**
- 修改：`/Users/night/Documents/code/sealos/agenthub/backend/internal/agenttemplate/template.go`
- 修改：`/Users/night/Documents/code/sealos/agenthub/backend/internal/dto/template.go`
- 修改：`/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/template.go`
- 测试：`/Users/night/Documents/code/sealos/agenthub/backend/internal/agenttemplate/source_test.go`
- 测试：`/Users/night/Documents/code/sealos/agenthub/backend/internal/router/router_test.go`

- [ ] **步骤 1：编写失败的解析测试**

在 agenttemplate testdata 模板加入 `modelIntegration`，测试读取：

```go
if definition.ModelIntegration.Type != "ai-agent-switch" {
    t.Fatalf("ModelIntegration.Type = %q, want ai-agent-switch", definition.ModelIntegration.Type)
}
if len(definition.ModelIntegration.Slots) != 1 {
    t.Fatalf("slots len = %d, want 1", len(definition.ModelIntegration.Slots))
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd /Users/night/Documents/code/sealos/agenthub/backend
go test ./internal/agenttemplate ./internal/router
```

预期：FAIL，结构体没有字段或 DTO 不输出。

- [ ] **步骤 3：增加 Go 类型**

在 `template.go` 增加：

```go
type ModelIntegration struct {
    Type     string                         `yaml:"type"`
    Client   string                         `yaml:"client"`
    Provider ModelIntegrationProvider       `yaml:"provider"`
    Slots    []ModelIntegrationSlot         `yaml:"slots"`
}

type LocalizedText map[string]string

type ModelIntegrationProvider struct {
    ID       string                     `yaml:"id"`
    Name     LocalizedText              `yaml:"name"`
    BaseURL  ModelIntegrationValueSource `yaml:"baseURL"`
    APIKeyEnv string                    `yaml:"apiKeyEnv"`
}

type ModelIntegrationValueSource struct {
    Source string `yaml:"source"`
}

type ModelIntegrationSlot struct {
    Key          string        `yaml:"key"`
    Label        LocalizedText `yaml:"label"`
    Required     bool          `yaml:"required"`
    Mutable      bool          `yaml:"mutable"`
    DefaultModel string        `yaml:"defaultModel"`
    ModelTypes   []string      `yaml:"modelTypes"`
}
```

并在 `Definition` 增加：

```go
ModelIntegration ModelIntegration `yaml:"modelIntegration"`
```

- [ ] **步骤 4：增加 DTO 输出**

在 `dto/template.go` 增加同构 JSON 类型，字段名使用 `modelIntegration`。

- [ ] **步骤 5：运行测试验证通过**

运行：

```bash
cd /Users/night/Documents/code/sealos/agenthub/backend
go test ./internal/agenttemplate ./internal/router
```

预期：PASS。

- [ ] **步骤 6：Commit**

```bash
cd /Users/night/Documents/code/sealos/agenthub
git add backend/internal/agenttemplate/template.go backend/internal/dto/template.go backend/internal/handler/template.go backend/internal/agenttemplate backend/internal/router
git commit -m "feat(template): expose model integration slots"
```

---

## 任务 9：Agent Hub 后端保存多槽位选择

**文件：**
- 修改：`/Users/night/Documents/code/sealos/agenthub/backend/internal/dto/agent.go`
- 修改：`/Users/night/Documents/code/sealos/agenthub/backend/internal/dto/agent_contract.go`
- 修改：`/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/agent_template_settings.go`
- 修改：`/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/agent.go`
- 测试：`/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/agent_create_settings_test.go`
- 测试：`/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/agent_runtime_settings_update_test.go`

- [ ] **步骤 1：定义 payload**

新增请求字段：

```json
{
  "modelSlots": {
    "main": "glm-5.1",
    "vision": "glm-4.6v"
  }
}
```

Go DTO：

```go
ModelSlots map[string]string `json:"modelSlots,omitempty"`
```

- [ ] **步骤 2：编写失败测试**

测试提交未知 slot：

```go
req := dto.UpdateAgentSettingsRequest{
    ModelSlots: map[string]string{"unknown": "glm-5.1"},
}
err := validateSettingsUpdateRequest(req, templateDef, "us")
if err == nil {
    t.Fatal("expected validation error")
}
```

- [ ] **步骤 3：实现校验**

规则：

- slot key 必须在 `templateDef.ModelIntegration.Slots`。
- required slot 创建时必须有值，修改时可只提交部分 mutable slot。
- slot model 必须存在于当前 region 且属于 slot 允许的 `modelTypes`。
- 不添加 fallback；模板没有模型或用户提交不合法直接报 validation error。

- [ ] **步骤 4：保存到 annotations/env**

建议 annotation：

```text
agent.sealos.io/model-slots={"main":{"provider":"custom:aiproxy-chat","model":"glm-5.1","apiMode":"chat_completions"}}
```

标准单模型字段暂时继续写入 `main`，保持列表页兼容：

- `agent.sealos.io/model`
- `agent.sealos.io/model-provider`
- `agent.sealos.io/model-api-mode`

- [ ] **步骤 5：运行测试**

```bash
cd /Users/night/Documents/code/sealos/agenthub/backend
go test ./internal/handler
```

预期：PASS。

- [ ] **步骤 6：Commit**

```bash
cd /Users/night/Documents/code/sealos/agenthub
git add backend/internal/dto backend/internal/handler
git commit -m "feat(agent): persist model slot selections"
```

---

## 任务 10：Agent Hub 后端执行 `client configure`

**文件：**
- 修改：`/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/agent_model_sync.go`
- 测试：`/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/agent_model_sync_test.go`

- [ ] **步骤 1：编写失败测试**

断言 exec script 包含：

```bash
ai-agent-switch provider init
ai-agent-switch client configure --client cowagent --slot main=aiproxy/glm-5.1 --slot vision=aiproxy/glm-4.6v -y --json
```

- [ ] **步骤 2：运行测试验证失败**

```bash
cd /Users/night/Documents/code/sealos/agenthub/backend
go test ./internal/handler -run TestSyncAgentModelConfig
```

预期：FAIL，当前还是 `ai-agent-switch switch`。

- [ ] **步骤 3：改同步脚本**

生成：

```bash
ai-agent-switch provider init \
  --id aiproxy \
  --name "AI Proxy" \
  --base-url "$AGENT_MODEL_BASEURL" \
  --api-key-env AGENT_MODEL_APIKEY \
  --model "glm-5.1:chat_completions" \
  --model "glm-4.6v:chat_completions" \
  --default-model "glm-5.1" \
  --json >/dev/null

ai-agent-switch client configure \
  --client cowagent \
  --slot "main=aiproxy/glm-5.1" \
  --slot "vision=aiproxy/glm-4.6v" \
  -y \
  --json >/dev/null
```

不要保留 `ai-agent-switch switch` 作为 fallback。若新命令不可用，应直接失败，提示镜像内 `ai-agent-switch` 版本不满足契约。

- [ ] **步骤 4：运行测试**

```bash
cd /Users/night/Documents/code/sealos/agenthub/backend
go test ./internal/handler -run TestSyncAgentModelConfig
go test ./...
```

预期：PASS。

- [ ] **步骤 5：Commit**

```bash
cd /Users/night/Documents/code/sealos/agenthub
git add backend/internal/handler/agent_model_sync.go backend/internal/handler/agent_model_sync_test.go
git commit -m "feat(agent): sync model slots through ai agent switch"
```

---

## 任务 11：Agent Hub 前端渲染多模型槽位

**文件：**
- 修改：`/Users/night/Documents/code/sealos/agenthub/frontend/src/domains/agents/types.ts`
- 修改：`/Users/night/Documents/code/sealos/agenthub/frontend/src/domains/agents/templates.ts`
- 修改：`/Users/night/Documents/code/sealos/agenthub/frontend/src/components/business/agents/AgentConfigForm.tsx`
- 修改：`/Users/night/Documents/code/sealos/agenthub/frontend/src/app/pages/agent-hub/components/AgentSettingsWorkspace.tsx`
- 修改：`/Users/night/Documents/code/sealos/agenthub/frontend/src/i18n.tsx`
- 测试：`/Users/night/Documents/code/sealos/agenthub/frontend/src/components/business/agents/AgentConfigForm.test.tsx`

- [ ] **步骤 1：写失败测试**

在 `AgentConfigForm.test.tsx` 增加：

```tsx
it("renders all model integration slots", () => {
  // 构造 template.modelIntegration.slots = main + vision
  // 断言页面出现 “主模型” 和 “视觉模型”
});
```

- [ ] **步骤 2：运行测试验证失败**

```bash
cd /Users/night/Documents/code/sealos/agenthub/frontend
npm test -- AgentConfigForm.test.tsx
```

如果项目使用 `bun test` 或 `vitest`，按现有 `package.json` 脚本执行，不新增测试 runner。

- [ ] **步骤 3：增加前端类型**

在 `types.ts` 增加：

```ts
export interface TemplateLocalizedText {
  zh?: string;
  en?: string;
}

export interface TemplateModelIntegrationSlot {
  key: string;
  label: TemplateLocalizedText;
  required: boolean;
  mutable: boolean;
  defaultModel?: string;
  modelTypes: string[];
}

export interface TemplateModelIntegration {
  type: "ai-agent-switch";
  client: string;
  slots: TemplateModelIntegrationSlot[];
}
```

`AgentTemplateCatalogItem` 增加：

```ts
modelIntegration?: TemplateModelIntegration;
```

`AgentBlueprint` 增加：

```ts
modelSlots: Record<string, string>;
```

- [ ] **步骤 4：创建页渲染 slots**

在 `AgentConfigForm.tsx` 中，如果 `template.modelIntegration?.slots` 存在，则按 slots 渲染 `ModelCapabilitySelect`。模型 options 根据 `slot.modelTypes` 过滤 `template.modelTypes`。

slot label 使用当前语言：

```ts
const slotLabel = locale === "en" ? slot.label.en || slot.key : slot.label.zh || slot.key;
```

- [ ] **步骤 5：设置页渲染 mutable slots**

在 `AgentSettingsWorkspace.tsx` 中只渲染 `slot.mutable !== false` 的 slot。不可修改 slot 只展示当前值。

- [ ] **步骤 6：运行前端测试**

```bash
cd /Users/night/Documents/code/sealos/agenthub/frontend
npm test -- AgentConfigForm.test.tsx
```

预期：PASS。

- [ ] **步骤 7：Commit**

```bash
cd /Users/night/Documents/code/sealos/agenthub
git add frontend/src/domains/agents/types.ts frontend/src/domains/agents/templates.ts frontend/src/components/business/agents/AgentConfigForm.tsx frontend/src/app/pages/agent-hub/components/AgentSettingsWorkspace.tsx frontend/src/i18n.tsx frontend/src/components/business/agents/AgentConfigForm.test.tsx
git commit -m "feat(web): render model slot selectors"
```

---

## 任务 12：端到端验证和清理旧单模型字段

**文件：**
- 修改：`/Users/night/Documents/code/sealos/Agent-Hub-Template/agents/*/template.yaml`
- 修改：`/Users/night/Documents/code/sealos/Agent-Hub-Template/test/validate-agent-contract.sh`
- 修改：`/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/*`
- 修改：`/Users/night/Documents/code/sealos/agenthub/frontend/src/**/*`

- [ ] **步骤 1：本地联调启动 Agent Hub**

```bash
cd /Users/night/Documents/code/sealos/agenthub/backend
REGION=us \
AGENT_TEMPLATE_GITHUB_URL= \
AGENT_MANIFEST_TEMPLATE_DIR=/Users/night/Documents/code/sealos/Agent-Hub-Template/agents \
go run ./cmd/app
```

前端按项目现有 README 启动。

- [ ] **步骤 2：创建 CowAgent 验证 payload**

在创建页选择 CowAgent，确认有 `主模型` 和 `视觉模型`。提交后后端应保存 `modelSlots`，并执行 `client configure`。

- [ ] **步骤 3：设置页修改模型**

修改 `main` 或 `vision` slot，确认不会触发 rebootstrap，只执行 K8s exec。

- [ ] **步骤 4：容器内查看当前配置**

```bash
ai-agent-switch client show cowagent --json
```

当前 `client show` 如未显示 slots，则在 `ai-agent-switch` 增加 show 输出 slots 的单独任务，不在 Agent Hub 中添加读取原生 config 的 fallback。

- [ ] **步骤 5：删除旧单模型 settings 字段**

确认 Agent Hub 已完全使用 `modelIntegration` 后，从模板删除：

- `settings.agent.provider`
- `settings.agent.model`
- `settings.agent.baseURL`

保留非模型配置，例如 `webPassword`、`gatewayToken`。

- [ ] **步骤 6：全量验证**

```bash
cd /Users/night/Documents/code/sealos/a/agent-switch
bun test

cd /Users/night/Documents/code/sealos/Agent-Hub-Template
bash test/validate-agent-contract.sh

cd /Users/night/Documents/code/sealos/agenthub/backend
go test ./...

cd /Users/night/Documents/code/sealos/agenthub/frontend
npm test
```

- [ ] **步骤 7：Commit**

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
git add agents test docs
git commit -m "refactor(template): remove legacy single model settings"

cd /Users/night/Documents/code/sealos/agenthub
git add backend frontend
git commit -m "refactor(agent): use model integration slots"
```

---

## 风险和确认点

- CowAgent 非 `main` 槽位是否有原生字段：未确认前只写 `ai_agent_switch.slots`，不猜字段名。
- `client show` 是否要返回 slots：如果 Agent Hub 要展示容器内真实 slots，需要 `ai-agent-switch` 增加输出。
- 旧模板兼容：本计划建议分阶段兼容，最后统一删除旧 `provider/model/baseURL` settings。
- 不添加 fallback：新命令不存在、模板缺模型、slot 不合法都直接失败。

## 自检清单

- 规格覆盖：包含 `ai-agent-switch`、`Agent-Hub-Template`、`agenthub` 三仓库。
- 命令契约：只使用 `provider init` 和 `client configure`，不恢复 `agent-hub init`。
- 多语言：slot label 使用 `zh/en` map。
- 生命周期：部署期和后续修改均通过同一套 slot payload 和 exec 流程。
- 验证：每个仓库都有最小测试命令和全量测试命令。
