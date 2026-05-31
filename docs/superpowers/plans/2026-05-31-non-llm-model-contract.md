# Non-LLM Model Contract 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:test-driven-development 和 superpowers:verification-before-completion。步骤使用复选框（`- [x]`）语法来跟踪进度。

**目标：** 让 ai-agent-switch、Agent-Hub-Template、Agent Hub 对非 LLM 模型使用同一套显式模型契约，避免把图片、音频、向量模型笼统塞进 `openai_compatible`。

**架构：** 模型契约分成 `apiMode`（怎么调用）和 `kind`（模型用途）。Template 负责声明已验证的模型和槽位，Agent Hub 负责把模板选项原样传给 ai-agent-switch，ai-agent-switch 负责持久化模型元数据并按 CowAgent 槽位写入原生配置。

**技术栈：** TypeScript + Bun（ai-agent-switch）、Go（Agent Hub backend）、React/TypeScript（Agent Hub frontend）、YAML（Agent-Hub-Template）。

---

## 文件职责

- `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/src/config/schema.ts`：定义 `ModelApiMode`、`ModelKind`、`ModelProfile`。
- `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/src/cli/main.ts`：解析 `--model modelId:apiMode[:kind]`。
- `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/src/clients/cowagent.ts`：CowAgent 槽位优先使用模型 `kind` 判断，不靠模型名猜测。
- `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/tests/cli-integration.test.ts`：覆盖 provider init 新格式。
- `/Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch/tests/client-configure.test.ts`：覆盖 CowAgent 非 LLM 槽位配置。
- `/Users/night/Documents/code/sealos/Agent-Hub-Template/agents/*/template.yaml`：把模板模型改成显式 `apiMode` + `kind`。
- `/Users/night/Documents/code/sealos/agenthub/backend/internal/agenttemplate/template.go`：读取并输出 `kind`。
- `/Users/night/Documents/code/sealos/agenthub/backend/internal/handler/agent_model_sync.go`：provider init 拼接 `modelId:apiMode:kind`。
- `/Users/night/Documents/code/sealos/agenthub/backend/internal/dto/agent.go`：模型槽位保留 `kind`。
- `/Users/night/Documents/code/sealos/agenthub/frontend/src/domains/agents/types.ts`：前端模型选项和槽位选择保留 `kind`。

## 任务

### 任务 1：ai-agent-switch 模型契约

- [x] 步骤 1：写失败测试，期望 `provider init --model qwen-image-2.0-pro:image_generation:image_generation` 保存 `apiMode` 和 `kind`。
- [x] 步骤 2：运行 `bun test tests/cli-integration.test.ts -t "provider init stores model api mode and kind metadata"`，确认失败。
- [x] 步骤 3：扩展 schema 和 CLI 解析，支持 `modelId:apiMode[:kind]`。
- [x] 步骤 4：运行同一测试确认通过。

### 任务 2：CowAgent 非 LLM 槽位

- [x] 步骤 1：写失败测试，期望 `kind=image_generation/asr/tts/embedding` 的模型配置到 CowAgent 对应原生字段。
- [x] 步骤 2：运行 `bun test tests/client-configure.test.ts -t "cowagent configure uses model kind metadata for non-LLM slots"`，确认失败。
- [x] 步骤 3：让 CowAgent adapter 优先读取模型 `kind`，并按 `kind` 校验槽位用途。
- [x] 步骤 4：运行同一测试确认通过。

### 任务 3：Template 声明契约

- [x] 步骤 1：更新三个 agent 模板模型，LLM 用 `kind: llm`，视觉槽位里的多模态 LLM 用 `kind: llm`，图片/音频/向量用对应 kind。
- [x] 步骤 2：运行 `bash test/validate-agent-contract.sh`。

### 任务 4：Agent Hub 传递契约

- [x] 步骤 1：写 Go 测试，期望模型同步命令包含 `--model 'qwen-image-2.0-pro:image_generation:image_generation'`。
- [x] 步骤 2：运行目标 Go 测试确认失败。
- [x] 步骤 3：后端模板结构、DTO、annotation、sync script 支持 `kind`。
- [x] 步骤 4：前端类型与 payload 支持 `kind`。
- [x] 步骤 5：运行后端目标测试和前端 build。

### 任务 5：完整验证

- [x] 步骤 1：运行 ai-agent-switch 目标测试。
- [x] 步骤 2：运行 Agent-Hub-Template 合同验证。
- [x] 步骤 3：运行 Agent Hub 后端 handler 相关测试。
- [x] 步骤 4：运行 Agent Hub frontend build。
