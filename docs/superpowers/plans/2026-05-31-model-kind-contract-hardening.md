# Model Kind Contract Hardening 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:test-driven-development 和 superpowers:verification-before-completion。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 把 Agent Hub / Agent-Hub-Template / ai-agent-switch 的模型契约从“非 LLM 可选 metadata”收紧为“模板声明、同步命令、CowAgent 配置都显式使用 `apiMode + kind`”。

**架构：** Template 是模型事实源，必须声明每个模型的调用协议 `apiMode` 和用途 `kind`。Agent Hub 只验证、保存、透传模板契约，不猜模型能力。ai-agent-switch 在 CowAgent 多槽位配置时用 `kind` 做硬校验，非主槽位不允许退回模型名猜测。

**技术栈：** TypeScript + Bun（ai-agent-switch）、Go（Agent Hub backend）、React/TypeScript（Agent Hub frontend）、YAML + Bash/Python validator（Agent-Hub-Template）。

---

## 文件职责

- `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/src/clients/cowagent.ts`：CowAgent 非主槽位必须读取模型 `kind` 并按槽位校验。
- `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/tests/client-configure.test.ts`：覆盖缺失 `kind` 时拒绝配置 CowAgent 非主槽位。
- `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/tests/cli-integration.test.ts`：覆盖 `provider init` 非 LLM 模型必须带 `kind`。
- `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/README.md`：说明非 LLM 与多槽位模型必须使用 `modelId:apiMode:kind`。
- `/Users/night/Documents/code/sealos/Agent-Hub-Template/test/validate-agent-contract.sh`：模板校验要求每个模型声明 `kind`，并校验 `apiMode` 与 `kind` 的一致性。
- `/Users/night/Documents/code/sealos/agenthub/backend/internal/agenttemplate/template.go`：后端模板解析校验 `kind` 存在且合法、一致。
- `/Users/night/Documents/code/sealos/agenthub/backend/internal/agenttemplate/source_test.go`：覆盖模板缺失 `kind` 的解析错误。
- `/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/agent_template_settings.go`：选择模型槽位时要求模板候选携带 `kind`。
- `/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/agent_model_sync.go`：同步命令要求模型列表携带 `kind`，避免发出旧格式非 LLM 参数。
- `/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/*_test.go`：更新测试 fixture，使模型槽位 annotation、sync model list 都带 `kind`。

## 任务

### 任务 1：ai-agent-switch 硬化 CowAgent kind 校验

- [x] 步骤 1：在 `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/tests/client-configure.test.ts` 添加失败测试：`cowagent configure rejects non-main slot models without kind metadata`。命令：`bun test tests/client-configure.test.ts -t "rejects non-main slot models without kind metadata"`；预期当前失败，因为缺失 kind 仍会通过。
- [x] 步骤 2：修改 `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/src/clients/cowagent.ts`，`assertCowAgentSlotModelKind()` 对 `vision/image/asr/tts/embedding` 这些已知槽位要求 `kind` 必填；未知槽位保持不限制。
- [x] 步骤 3：更新旧的 CowAgent 多槽位测试，用 `provider init` 或带 kind 的模型 metadata，避免继续依赖模型名猜测。
- [x] 步骤 4：运行 `bun test tests/client-configure.test.ts -t "cowagent configure"`。

### 任务 2：ai-agent-switch provider init 契约文档和测试

- [x] 步骤 1：在 `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/tests/cli-integration.test.ts` 添加失败测试：非 LLM `--model qwen-image-2.0-pro:image_generation` 必须报错提示 `kind`。
- [x] 步骤 2：修改 `parseProviderInitModels()`：`chat_completions/openai_compatible/codex_responses/anthropic_messages` 可省略 kind；`image_generation/video_generation/audio_transcriptions/audio_speech/embeddings` 必须提供 kind。
- [x] 步骤 3：更新 `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/README.md`，写清楚 Agent Hub/CowAgent 多槽位必须使用 `modelId:apiMode:kind`。
- [x] 步骤 4：运行 `bun test tests/cli-integration.test.ts -t "provider init"`。

### 任务 3：Template 合同校验收紧

- [x] 步骤 1：修改 `/Users/night/Documents/code/sealos/Agent-Hub-Template/test/validate-agent-contract.sh`，要求 `regionModelPresets` 和 `regionModelTypes` 所有模型必须有合法 `kind`。
- [x] 步骤 2：同一校验器增加 `apiMode` 与 `kind` 一致性：图像/视频/音频/embedding API mode 只能配对应 kind；文本 API mode 只能配 `llm` 或 `vision`。
- [x] 步骤 3：给 Hermes/OpenClaw 注释示例中的模型补 `kind`，避免文档示例违反合同。
- [x] 步骤 4：运行 `bash test/validate-agent-contract.sh`。

### 任务 4：Agent Hub 后端解析和同步硬化

- [x] 步骤 1：在 `/Users/night/Documents/code/sealos/agenthub/backend/internal/agenttemplate/source_test.go` 添加失败测试：模型缺失 `kind` 时 `ResolveFromSource` 报错。
- [x] 步骤 2：修改 `/Users/night/Documents/code/sealos/agenthub/backend/internal/agenttemplate/template.go`，校验所有模型 `kind` 必填、合法，并与 `apiMode` 一致。
- [x] 步骤 3：修改 `/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/agent_template_settings.go`，解析槽位候选时 `kind` 为空直接 validation error。
- [x] 步骤 4：修改 `/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/agent_model_sync.go`，`agentHubProviderModels()` 遇到缺失 `kind` 的模板模型不静默跳过或输出旧格式，而是返回错误。
- [x] 步骤 5：更新相关 Go 测试 fixture 的 `Kind` 字段和 annotation。
- [x] 步骤 6：运行 `go test ./internal/agenttemplate ./internal/handler ./internal/router -count=1`。

### 任务 5：完整验证与审计

- [x] 步骤 1：运行 `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch` 下 `bun test tests/cli-integration.test.ts tests/client-configure.test.ts tests/client-adapters-extended.test.ts`。
- [x] 步骤 2：运行 `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch` 下 `bun run typecheck`。
- [x] 步骤 3：运行 `/Users/night/Documents/code/sealos/Agent-Hub-Template` 下 `bash test/validate-agent-contract.sh`。
- [x] 步骤 4：运行 `/Users/night/Documents/code/sealos/agenthub/backend` 下 `go test ./internal/agenttemplate ./internal/handler ./internal/router -count=1`。
- [x] 步骤 5：运行 `/Users/night/Documents/code/sealos/agenthub/frontend` 下 `npm run build`。
- [x] 步骤 6：核对三仓 `git diff --check` 与 `git status --short`。
