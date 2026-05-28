# Agent Image Tags 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 让 Agent Hub 部署入口始终使用 `ghcr.io/<owner>/<agent>:latest`，同时让发布流水线额外推送可追溯的 `build-YYYYMMDD-<sha>` 镜像标签。

**架构：** `template.yaml.image` 是 Agent Hub 读取的部署镜像来源，因此真实 agent 目录统一写成 `:latest`。Release workflow 不再从模板读取任意 tag，而是在每次发布时固定推送 `latest` 和一个由 UTC 日期、提交 SHA 生成的不可变追踪 tag。契约测试负责防止历史测试 tag 或 `master` tag 再进入部署模板。

**技术栈：** GitHub Actions、Docker、Bash、Python YAML/JSON 校验、Agent Hub `template.yaml`。

---

## 文件职责

- 修改：`agents/hermes-agent/template.yaml`。部署镜像改为 `ghcr.io/nightwhite/hermes-agent:latest`。
- 修改：`agents/openclaw/template.yaml`。部署镜像改为 `ghcr.io/nightwhite/openclaw:latest`。
- 修改：`agents/cowagent/template.yaml`。部署镜像改为 `ghcr.io/nightwhite/cowagent:latest`。
- 修改：`.github/workflows/release.yml`。发布矩阵只保留 agent 名称和路径；构建推送 `latest` 与 `build-YYYYMMDD-<12位sha>`；同步 job 只确保模板镜像为 `latest`。
- 修改：`test/validate-agent-contract.sh`。新增模板镜像 tag 和 release tag 契约检查。
- 修改：`README.md`。说明 Agent Hub 消费 `latest`，CI 另推 `build-*`。
- 修改：`docs/agent-contract.md`。把模板镜像字段定义为部署 tag 契约。
- 修改：`docs/adding-a-new-agent.md`。新增 agent 时要求 `template.yaml.image` 使用 `latest`。

## 任务 1：先写会失败的 tag 契约测试

- [x] **步骤 1：修改 `test/validate-agent-contract.sh`**

在 `validate_template_metadata()` 的 Python 校验中，读取 `id` 和 `image`，对真实 agent 强制要求：

```python
agent_id = str(template.get("id") or "").strip()
image = str(template.get("image") or "").strip()
expected_owner = os.environ["EXPECTED_IMAGE_OWNER"]
expected_image = f"ghcr.io/{expected_owner}/{agent_id}:latest"
if image != expected_image:
    raise SystemExit(f"{template_path}: image must be {expected_image}")
```

在 `validate_workflow_contracts()` 中删除旧的 `image_tag = image.rpartition(":")` 和 `tag = str(item["image_tag"])` 检查，改为检查 release workflow 包含这些契约片段：

```bash
grep -F 'echo "latest"' .github/workflows/release.yml >/dev/null || \
  fail ".github/workflows/release.yml must publish the latest agent image tag"
grep -F 'trace_tag="build-$(date -u +%Y%m%d)-${short_sha}"' .github/workflows/release.yml >/dev/null || \
  fail ".github/workflows/release.yml must publish traceable build image tags"
grep -F 'image = f"ghcr.io/{owner}/{name}:latest"' .github/workflows/release.yml >/dev/null || \
  fail ".github/workflows/release.yml sync step must keep template images on latest"
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
bash test/validate-agent-contract.sh
```

预期：失败，错误指向 `agents/hermes-agent/template.yaml`、`agents/openclaw/template.yaml` 或 `agents/cowagent/template.yaml` 的 image 不是 `:latest`，或者 release workflow 还没有 trace tag 契约。

## 任务 2：更新模板和 release workflow

- [x] **步骤 1：修改 3 个真实 agent 的 `template.yaml`**

把 image 分别改成：

```yaml
image: ghcr.io/nightwhite/hermes-agent:latest
image: ghcr.io/nightwhite/openclaw:latest
image: ghcr.io/nightwhite/cowagent:latest
```

不要修改 `agents/_template/template.yaml`，它仍然是脚手架占位值。

- [x] **步骤 2：修改 release 矩阵生成逻辑**

`.github/workflows/release.yml` 的矩阵只输出：

```python
enabled.append(
    {
        "name": item["name"],
        "path": item["path"],
    }
)
```

在加入矩阵前校验模板 image 是当前 owner 下的 latest：

```python
expected_image = f"ghcr.io/{os.environ['GITHUB_REPOSITORY_OWNER'].lower()}/{item['name']}:latest"
if image != expected_image:
    raise SystemExit(f"{path / 'template.yaml'}: image must be {expected_image}")
```

- [x] **步骤 3：修改 release tag 生成逻辑**

`Resolve image tags` step 不再读 `matrix.image_tag`，改成：

```bash
short_sha="$(printf '%s' "$GITHUB_SHA" | cut -c1-12)"
trace_tag="build-$(date -u +%Y%m%d)-${short_sha}"
{
  echo "tags<<EOF"
  echo "latest"
  echo "$trace_tag"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
```

- [x] **步骤 4：修改模板同步 job**

`sync-latest-templates` 中不再读取 `image_tag`，直接写：

```python
image = f"ghcr.io/{owner}/{name}:latest"
```

保留自动同步 job，作用从“同步版本镜像”收敛为“确保模板部署镜像引用 latest”。

- [x] **步骤 5：运行测试验证通过**

运行：

```bash
bash test/validate-agent-contract.sh
```

预期：通过。

## 任务 3：更新文档

- [x] **步骤 1：修改 `README.md` 镜像版本规则**

把旧规则替换成：

```markdown
GitHub Actions 会根据 `registry/agents.yaml` 生成构建矩阵。

- Agent Hub 部署镜像固定读取 `agents/<agent>/template.yaml` 中的 `ghcr.io/<owner>/<agent>:latest`
- 每次 release 额外推送一个追踪镜像：`ghcr.io/<owner>/<agent>:build-YYYYMMDD-<12位sha>`

发布成功后，Actions 会确保 enabled agents 的 `template.yaml.image` 保持为 `:latest`。
```

- [x] **步骤 2：修改 `docs/agent-contract.md` 模板契约**

明确真实 agent 的 `template.yaml.image` 必须是：

```text
ghcr.io/<owner>/<agent-id>:latest
```

并说明 `build-*` 只用于审计和回溯，不是 Agent Hub 默认部署入口。

- [x] **步骤 3：修改 `docs/adding-a-new-agent.md`**

在接入步骤或模板职责处补充：

```markdown
真实 agent 的 `template.yaml.image` 必须写成 `ghcr.io/<owner>/<agent-id>:latest`。
Release workflow 会推送 `latest` 和 `build-*`，Agent Hub 只从模板读取 `latest`。
```

## 任务 4：最终验证和 PR 准备

- [x] **步骤 1：运行 shell 语法检查**

运行：

```bash
find base agents test -type f -name '*.sh' | sort | while IFS= read -r file; do bash -n "$file"; done
```

预期：无输出，退出码 0。

- [x] **步骤 2：运行契约测试**

运行：

```bash
bash test/validate-agent-contract.sh
```

预期：输出 `==> agent contract validation passed`。

- [x] **步骤 3：运行 diff 空白检查**

运行：

```bash
git diff --check
```

预期：无输出，退出码 0。

- [x] **步骤 4：检查变更范围**

运行：

```bash
git status --short
git diff --stat
```

预期：只包含本计划列出的 workflow、模板、测试和文档文件。

## 自检

- 规格覆盖度：覆盖了用户关心的 weird tag 来源、Agent Hub 读取最新镜像的方式、CI 自动推镜像的 tag 策略。
- 占位符扫描：没有使用“待定”“后续实现”作为任务内容；每一步都有具体文件、代码或命令。
- 类型一致性：文档、测试和 workflow 都使用同一个契约：模板部署 `latest`，CI 追踪 `build-YYYYMMDD-<12位sha>`。
