# 极简 Agent Base 镜像实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将 Agent Hub 模板仓库收敛为「极简 base 镜像 + 每个 agent 自己按 Linux 本地方式安装 latest + `template.yaml` 作为唯一部署元数据」。

**架构：** `base/` 只提供 Devbox runtime、Node.js、npm、Python、pip、venv、uv、ripgrep 和最小系统工具。每个 `agents/<agent>/` 目录保留部署模板和镜像构建文件，删除 `index.json` 与 `build.env` 契约。CI 从 `registry/agents.yaml` 和 `template.yaml` 读取构建信息，不再维护重复 catalog 元数据。

**技术栈：** Docker、Bash、GitHub Actions、Python YAML/JSON 校验、Sealos Devbox runtime、Agent Hub 模板。

---

## 文件职责

- 修改：`base/install.sh`。收敛 base 安装内容，保留 Devbox runtime、语言工具链和最小系统工具。
- 修改：`base/Dockerfile`。保持 base 构建入口简单，继续复制 Devbox runtime tooling 脚本和 `base/install.sh`。
- 修改：`base/smoke.sh`。验证新的 base 契约，不再检查 `yarn`、`pnpm`、TypeScript 等不属于 base 的工具。
- 修改：`test/validate-agent-contract.sh`。删除 `index.json` 和 `build.env` 必填契约，改为以 `template.yaml` 和 manifests 为部署元数据源。
- 修改：`.github/workflows/build.yml`。构建矩阵从 `registry/agents.yaml` 和 agent 目录读取，不再依赖 `index.json` 或 `AI_AGENT_SWITCH_*`。
- 修改：`.github/workflows/release.yml`。发布逻辑不再读取或回写 `index.json`，镜像 tag 使用约定 tag（建议先使用 `latest` 或 `master`，由 `template.yaml.image` 决定）。
- 删除：`agents/_template/index.json`、`agents/hermes-agent/index.json`、`agents/openclaw/index.json`、`agents/cowagent/index.json`。
- 删除：`agents/_template/build.env`、`agents/hermes-agent/build.env`、`agents/openclaw/build.env`、`agents/cowagent/build.env`。
- 修改：`agents/*/Dockerfile`。移除 `COPY build.env` 和 `AI_AGENT_SWITCH_*` 参数，改为直接运行 `install.sh`。
- 修改：`agents/*/install.sh`。把必要常量内聚到脚本顶部，按 Linux 本地安装 latest agent，并通过官方安装脚本安装 latest `ai-agent-switch`。禁止未确认 fallback。
- 修改：`README.md`、`docs/agent-contract.md`、`docs/adding-a-new-agent.md`、`test/README.md`。同步新目录契约和验证方式。

## 实现约束

- 不添加 fallback 或兜底逻辑；安装失败就失败。
- 不引入 agent 版本 pin。
- 不引入 `AI_AGENT_SWITCH_VERSION`、`AI_AGENT_SWITCH_METADATA` 或 `ai_agent_switch_version`。
- 不把 `ai-agent-switch` 放进 base。
- 不把 agent 特定依赖放进 base。
- 不修改已有未提交的 `agents/cowagent/template.yaml` 内容；实现时需要先确认并避开或单独处理该 dirty 文件。

### 任务 1：收敛 base smoke 测试

**文件：**
- 修改：`base/smoke.sh`

- [ ] **步骤 1：更新 smoke 测试期望**

将工具检查改为以下集合：

```bash
command -v node >/dev/null
command -v npm >/dev/null
command -v python3 >/dev/null
command -v pip3 >/dev/null
python3 -m venv /tmp/base-venv-check
rm -rf /tmp/base-venv-check
command -v uv >/dev/null
command -v rg >/dev/null
for tool in bash busybox curl wget git file less openssl tar gzip xz zip unzip rsync ssh sshd locale logrotate ps ip ping lsof getent find grep sed gawk; do
  command -v "$tool" >/dev/null
done
```

删除这些检查：

```bash
command -v yarn >/dev/null
command -v pnpm >/dev/null
```

- [ ] **步骤 2：运行 shell 语法检查**

运行：

```bash
bash -n base/smoke.sh
```

预期：命令成功，无输出。

- [ ] **步骤 3：Commit**

```bash
git add base/smoke.sh
git commit -m "test(base): align smoke check with minimal base"
```

### 任务 2：收敛 base 安装脚本

**文件：**
- 修改：`base/install.sh`

- [ ] **步骤 1：移除 base 中的非必要工具安装**

在 `install_node_runtime()` 中移除：

```bash
npm install -g typescript yarn pnpm
```

保留 Node.js 和 npm 安装。

- [ ] **步骤 2：确保最小系统工具由 base 安装**

在 `install_common_agent_packages()` 中只安装设计文档认可的通用包。如果 `reference/devbox-runtime/tooling/scripts/install-base-pkg-deb.sh` 已经安装某些包，`base/install.sh` 不重复安装。需要补齐的包集中写在一个 `apt-get install -y --no-install-recommends` 块中：

```bash
apt-get update
apt-get install -y --no-install-recommends \
  file \
  less \
  zip \
  unzip \
  netbase \
  gawk \
  python3 \
  python3-pip \
  python3-venv \
  ripgrep
rm -rf /var/lib/apt/lists/*
```

不要加入 `build-essential`、`ffmpeg`、`espeak`、`libavcodec-extra`、`jq`。

- [ ] **步骤 3：保留 uv 安装**

保留 `install_uv()`，但不要新增 fallback。若下载失败，构建失败。

- [ ] **步骤 4：更新 `verify_base()`**

删除 `yarn`、`pnpm` 检查，新增 `rg` 和最小工具检查：

```bash
command -v rg >/dev/null
for tool in bash busybox curl wget git file less openssl tar gzip xz zip unzip rsync ssh sshd locale logrotate ps ip ping lsof getent find grep sed gawk; do
  command -v "$tool" >/dev/null
done
python3 -m venv /tmp/base-venv-check
rm -rf /tmp/base-venv-check
```

- [ ] **步骤 5：运行 base 脚本语法检查**

运行：

```bash
bash -n base/install.sh
bash -n base/smoke.sh
```

预期：全部成功。

- [ ] **步骤 6：构建并验证 base 镜像**

运行：

```bash
docker build -f base/Dockerfile -t agent-hub/agent-devbox-base:local .
IMAGE=agent-hub/agent-devbox-base:local bash base/smoke.sh
```

预期：构建成功，输出包含 `==> base smoke passed`。

- [ ] **步骤 7：Commit**

```bash
git add base/install.sh base/smoke.sh
git commit -m "refactor(base): keep only common runtime tools"
```

### 任务 3：删除 `index.json` 和 `build.env` 目录契约

**文件：**
- 修改：`test/validate-agent-contract.sh`
- 删除：`agents/_template/index.json`
- 删除：`agents/hermes-agent/index.json`
- 删除：`agents/openclaw/index.json`
- 删除：`agents/cowagent/index.json`
- 删除：`agents/_template/build.env`
- 删除：`agents/hermes-agent/build.env`
- 删除：`agents/openclaw/build.env`
- 删除：`agents/cowagent/build.env`

- [ ] **步骤 1：更新 required files**

把：

```bash
required_files=(Dockerfile build.env install.sh entrypoint.sh index.json template.yaml README.md)
```

改成：

```bash
required_files=(Dockerfile install.sh entrypoint.sh template.yaml README.md)
```

- [ ] **步骤 2：删除 `validate_index()` 调用和函数**

删除 `validate_index()` 函数，以及主循环中的：

```bash
validate_json_file "$agent_dir/index.json"
validate_index "$agent_dir"
```

- [ ] **步骤 3：让 `validate_template_metadata()` 不再读取 index**

把 `validate_template_metadata()` 改成只读取 `template.yaml`，并校验这些字段：

```python
required = [
    "id",
    "name",
    "shortName",
    "description",
    "image",
    "port",
    "defaultArgs",
    "backendSupported",
    "workingDir",
    "user",
    "presentation",
    "workspaces",
    "access",
    "actions",
    "settings",
]
```

保留 `defaultArgs`、`port`、`presentation`、`settings`、`regionModelTypes` / `regionModelPresets`、`access.files.rootPath`、`manifestDir` 等现有校验。

删除这些校验：

```python
if template["id"] != index["id"]:
...
if template["image"] != index["image"]:
...
```

- [ ] **步骤 4：删除文件**

运行：

```bash
rm agents/_template/index.json agents/hermes-agent/index.json agents/openclaw/index.json agents/cowagent/index.json
rm agents/_template/build.env agents/hermes-agent/build.env agents/openclaw/build.env agents/cowagent/build.env
```

- [ ] **步骤 5：运行契约校验，确认预期失败点**

运行：

```bash
bash test/validate-agent-contract.sh
```

预期：如果 Dockerfile 仍引用 `build.env`，会失败在 Dockerfile 契约或后续检查。这是合理的，因为下一任务会改 Dockerfile。

- [ ] **步骤 6：Commit**

```bash
git add test/validate-agent-contract.sh agents
git commit -m "refactor(agent): remove index and build env contracts"
```

### 任务 4：简化 agent Dockerfile

**文件：**
- 修改：`agents/_template/Dockerfile`
- 修改：`agents/hermes-agent/Dockerfile`
- 修改：`agents/openclaw/Dockerfile`
- 修改：`agents/cowagent/Dockerfile`

- [ ] **步骤 1：移除 `COPY build.env`**

删除所有：

```dockerfile
COPY agents/<agent>/build.env /tmp/build.env
```

- [ ] **步骤 2：移除 `set -a` 读取 build.env**

把类似：

```dockerfile
RUN chmod +x /tmp/install.sh \
    && set -a \
    && . /tmp/build.env \
    && set +a \
    && /tmp/install.sh install \
    && rm -f /tmp/build.env /tmp/install.sh
```

改成：

```dockerfile
RUN chmod +x /tmp/install.sh \
    && /tmp/install.sh install \
    && rm -f /tmp/install.sh
```

CowAgent 保持实际命令形式：

```dockerfile
RUN chmod +x /tmp/install.sh \
    && /tmp/install.sh install agent \
    && rm -f /tmp/install.sh
```

- [ ] **步骤 3：移除 `AI_AGENT_SWITCH_*` Docker build args 和 labels**

删除：

```dockerfile
ARG AI_AGENT_SWITCH_VERSION
ARG AI_AGENT_SWITCH_METADATA
ARG AI_AGENT_SWITCH_SOURCE_URL
ARG AI_AGENT_SWITCH_SOURCE_REF
```

删除 label：

```dockerfile
org.sealos.ai-agent-switch.version=...
org.sealos.ai-agent-switch.metadata=...
```

删除 `RUN` 中导出 `AI_AGENT_SWITCH_*` 的语句。

- [ ] **步骤 4：运行 Dockerfile 文本检查**

运行：

```bash
rg -n "build.env|AI_AGENT_SWITCH_|org.sealos.ai-agent-switch" agents/*/Dockerfile
```

预期：无匹配。

- [ ] **步骤 5：Commit**

```bash
git add agents/*/Dockerfile
git commit -m "refactor(agent): simplify docker build inputs"
```

### 阶段边界说明

任务 1 到任务 4 只处理 base 镜像、目录契约和 Dockerfile 输入，不安装 `ai-agent-switch`。`ai-agent-switch` 只属于 agent 镜像层；任务 5 是为了让任务 6 能够使用官方无版本安装脚本。

### 任务 5：先让 `ai-agent-switch` 官方安装脚本支持 latest

**文件：**
- 外部仓库：`reference/ai-agent-switch/install.sh`
- 外部仓库：`reference/ai-agent-switch/README.md`
- 外部仓库：`reference/ai-agent-switch/README_CN.md`
- 外部仓库：`reference/ai-agent-switch/tests/install-script.test.ts`

- [ ] **步骤 1：确认当前安装脚本行为**

运行：

```bash
sed -n '1,140p' reference/ai-agent-switch/install.sh
sed -n '1,45p' reference/ai-agent-switch/README.md
```

预期：当前脚本要求传入 `vX.Y.Z`，README 中容器安装示例也是：

```bash
curl -fsSL https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh | sh -s -- vX.Y.Z
```

- [ ] **步骤 2：在 `ai-agent-switch` 仓库实现 latest 安装**

在 `reference/ai-agent-switch/install.sh` 对应上游仓库中修改脚本：当没有传 `VERSION` 时，解析 GitHub latest release tag，并继续走同一条 release asset 下载逻辑。实现必须失败即失败，不添加备用 npm 安装路径。

脚本逻辑应等价于：

```sh
resolve_latest_version() {
  latest_url="https://github.com/${AI_AGENT_SWITCH_REPO}/releases/latest"
  if command -v curl >/dev/null 2>&1; then
    resolved="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$latest_url")"
  elif command -v wget >/dev/null 2>&1; then
    resolved="$(wget -qO- --server-response "$latest_url" 2>&1 | awk '/^  Location: / {print $2}' | tail -n 1 | tr -d '\r')"
  else
    echo "curl or wget is required" >&2
    exit 1
  fi
  version="${resolved##*/}"
  case "$version" in
    v*.*.*) printf '%s\n' "$version" ;;
    *) echo "Failed to resolve latest ai-agent-switch version from ${latest_url}" >&2; exit 1 ;;
  esac
}

if [ -z "$VERSION" ]; then
  VERSION="$(resolve_latest_version)"
fi
```

不要把这个代码直接应用到当前仓库，除非执行者正在 `reference/ai-agent-switch` 的真实上游工作区提交 PR。

- [ ] **步骤 3：更新 `ai-agent-switch` 文档**

将 README 的容器安装示例改为：

```bash
curl -fsSL https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh | sh
```

保留显式版本安装作为可选高级用法：

```bash
curl -fsSL https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh | sh -s -- vX.Y.Z
```

- [ ] **步骤 4：更新 `ai-agent-switch` 测试**

在 `reference/ai-agent-switch/tests/install-script.test.ts` 对应上游仓库中新增或调整测试，至少覆盖：

```ts
expect(text).toContain("releases/latest");
expect(english).toContain("install.sh | sh");
expect(chinese).toContain("install.sh | sh");
```

- [ ] **步骤 5：在 `ai-agent-switch` 仓库验证**

在 `reference/ai-agent-switch` 对应上游工作区运行：

```bash
bun test tests/install-script.test.ts
```

预期：测试通过。

- [ ] **步骤 6：先合并或发布 `ai-agent-switch` 安装脚本变更**

只有当 `https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh | sh` 已支持 latest 后，才能继续本仓库的任务 6。否则本仓库不得猜测 latest release 下载 URL，也不得改用 npm 作为替代。

### 任务 6：安装 latest `ai-agent-switch`

**文件：**
- 修改：`agents/hermes-agent/install.sh`
- 修改：`agents/openclaw/install.sh`
- 修改：`agents/cowagent/install.sh`
- 修改：`agents/_template/install.sh`

- [ ] **步骤 1：删除版本化安装逻辑**

从每个非模板 agent 的 `install.sh` 删除：

```bash
AI_AGENT_SWITCH_VERSION=...
AI_AGENT_SWITCH_SOURCE_URL=...
AI_AGENT_SWITCH_SOURCE_REF=...
install_ai_agent_switch_from_npm()
install_ai_agent_switch_from_source()
verify_ai_agent_switch_agent_hub()
```

- [ ] **步骤 2：新增 latest 安装函数**

使用已支持 latest 的 `ai-agent-switch` 官方安装脚本。禁止添加备用下载路径，禁止改用 npm。

函数形态：

```bash
install_ai_agent_switch() {
  curl -fsSL https://raw.githubusercontent.com/sealos-apps/ai-agent-switch/main/install.sh | sh
  command -v ai-agent-switch >/dev/null 2>&1
  command -v as >/dev/null 2>&1
}
```

官方安装脚本需要同时安装 `ai-agent-switch` 和 `as`。如果还未支持无版本 latest 安装，回到任务 5，不要在本仓库添加临时逻辑。

- [ ] **步骤 3：模板 agent 保持 scaffold**

`agents/_template/install.sh` 不需要真的安装 agent，但 README 和脚本应表达新契约：真实 agent 应安装 latest `ai-agent-switch`，且失败即失败。

- [ ] **步骤 4：运行脚本语法检查**

运行：

```bash
for file in agents/*/install.sh; do bash -n "$file"; done
```

预期：全部成功。

- [ ] **步骤 5：确认没有版本 pin**

运行：

```bash
rg -n "AI_AGENT_SWITCH_|ai_agent_switch_version|org.sealos.ai-agent-switch|npm.*ai-agent-switch|source_ref=.*ai-agent-switch|versions/ai-agent-switch" agents test .github README.md docs
```

预期：只允许设计文档或历史计划文档中描述禁止项；实现文件不得匹配。

- [ ] **步骤 6：Commit**

```bash
git add agents/*/install.sh
git commit -m "refactor(agent): install latest ai agent switch"
```

### 任务 7：按 Linux 本地安装逻辑调整 agent 安装

**文件：**
- 修改：`agents/hermes-agent/install.sh`
- 修改：`agents/openclaw/install.sh`
- 修改：`agents/cowagent/install.sh`

- [ ] **步骤 1：OpenClaw 使用 latest npm 安装**

把 OpenClaw 安装逻辑从指定版本：

```bash
npm install -g "openclaw@${OPENCLAW_VERSION}"
```

改成：

```bash
npm install -g openclaw
```

删除 `OPENCLAW_VERSION`、`OPENCLAW_UPSTREAM_REF`。

- [ ] **步骤 2：Hermes 使用最新上游安装**

删除 `HERMES_BRANCH`、`HERMES_REF` pin。保留上游 URL，clone 默认分支：

```bash
git clone "$HERMES_GIT_URL" "$HERMES_SRC"
```

不再 checkout 固定 commit。

- [ ] **步骤 3：CowAgent 使用最新上游安装**

保留：

```bash
COWAGENT_GIT_URL="${COWAGENT_GIT_URL:-https://github.com/zhayujie/CowAgent.git}"
```

删除固定 `COWAGENT_REF` 语义。clone 默认分支：

```bash
git clone --depth 1 "$COWAGENT_GIT_URL" "$COWAGENT_SRC"
```

- [ ] **步骤 4：agent 特定依赖留在 agent 层**

Hermes 如需 `ffmpeg`，CowAgent 如需 `espeak`、`ffmpeg`、`libavcodec-extra`，仍在对应 `install_system_packages()` 中安装，不放 base。

- [ ] **步骤 5：禁止 fallback 检查**

运行：

```bash
rg -n "\\|\\||fallback|skipping Agent Hub|warn \"Agent Hub|warn \"skipping|return 0" agents/hermes-agent/install.sh agents/openclaw/install.sh agents/cowagent/install.sh
```

逐条确认：安装路径中不得出现失败后继续的 fallback。若发现运行时模型同步相关 fallback，本轮应删除该隐式同步逻辑或改为严格失败；不要静默保留。

- [ ] **步骤 6：运行脚本语法检查**

```bash
for file in agents/hermes-agent/install.sh agents/openclaw/install.sh agents/cowagent/install.sh; do bash -n "$file"; done
```

预期：全部成功。

- [ ] **步骤 7：Commit**

```bash
git add agents/hermes-agent/install.sh agents/openclaw/install.sh agents/cowagent/install.sh
git commit -m "refactor(agent): install latest upstream agents"
```

### 任务 8：更新 CI 构建和发布逻辑

**文件：**
- 修改：`.github/workflows/build.yml`
- 修改：`.github/workflows/release.yml`

- [ ] **步骤 1：build workflow 删除 switch version resolve**

删除 `.github/workflows/build.yml` 中的：

```yaml
workflow_dispatch.inputs.ai_agent_switch_source_url
workflow_dispatch.inputs.ai_agent_switch_source_ref
steps.ai-agent-switch
needs.prepare.outputs.ai-agent-switch-*
```

删除 Docker build args：

```yaml
--build-arg "AI_AGENT_SWITCH_VERSION=..."
--build-arg "AI_AGENT_SWITCH_METADATA=..."
--build-arg "AI_AGENT_SWITCH_SOURCE_URL=..."
--build-arg "AI_AGENT_SWITCH_SOURCE_REF=..."
```

- [ ] **步骤 2：build workflow 保持矩阵按 registry path 选择**

`build.yml` 只需要 `registry/agents.yaml` 中的 `name` 和 `path`，不读取 `index.json`。

- [ ] **步骤 3：release workflow 不读取 index.json**

在 `.github/workflows/release.yml` 的矩阵生成中，不再读取：

```python
index = json.loads(Path(item["path"], "index.json").read_text())
```

改为从 registry item 读取：

```python
enabled.append({"name": item["name"], "path": item["path"]})
```

- [ ] **步骤 4：release tag 与 template image 对齐**

先使用简单规则：release push 构建并推送 `ghcr.io/<owner>/<agent>:latest`。`template.yaml.image` 后续由人工或独立同步任务维护；本轮删除自动回写 `index.json`。

`Resolve image tags` 输出：

```bash
{
  echo "tags<<EOF"
  echo "latest"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
```

- [ ] **步骤 5：删除 sync-version-templates job**

删除 `sync-version-templates` job，避免 CI 回写 `index.json` 或 `template.yaml`。

- [ ] **步骤 6：运行 workflow 文本检查**

```bash
rg -n "index\\.json|AI_AGENT_SWITCH_|ai-agent-switch-version|sync-version-templates|image_tag" .github/workflows
```

预期：无匹配。

- [ ] **步骤 7：Commit**

```bash
git add .github/workflows/build.yml .github/workflows/release.yml
git commit -m "ci(agent): build latest template images without catalog metadata"
```

### 任务 9：更新文档

**文件：**
- 修改：`README.md`
- 修改：`docs/agent-contract.md`
- 修改：`docs/adding-a-new-agent.md`
- 修改：`test/README.md`
- 修改：`agents/_template/README.md`
- 修改：`agents/hermes-agent/README.md`
- 修改：`agents/openclaw/README.md`
- 修改：`agents/cowagent/README.md`

- [ ] **步骤 1：README 删除 `index.json` 和 `build.env`**

目录契约改为：

```markdown
- `Dockerfile`
- `install.sh`
- `entrypoint.sh`
- `template.yaml`
- `manifests/devbox.yaml.tmpl`
- `manifests/service.yaml.tmpl`
- `manifests/ingress.yaml.tmpl`
- `README.md`
```

- [ ] **步骤 2：文档写明 base / agent 边界**

在 `README.md` 和 `docs/agent-contract.md` 中写明：

```markdown
base 镜像只提供 Devbox runtime、Node.js、npm、Python、pip、venv、uv、ripgrep 和最小系统工具。具体 agent 依赖、重型系统包和 `ai-agent-switch` 由每个 agent 镜像自行安装。
```

- [ ] **步骤 3：新增 latest 安装契约**

写明：

```markdown
agent 安装逻辑尽量贴近 Linux 本地安装方式，不维护 agent 版本 pin。`ai-agent-switch` 使用官方安装脚本安装 latest，不维护版本 pin。
```

- [ ] **步骤 4：删除旧 metadata 描述**

删除所有把 `index.json` 描述为 Agent Hub 元数据来源的段落。

- [ ] **步骤 5：运行文档搜索**

```bash
rg -n "index\\.json|build\\.env|ai_agent_switch_version|AI_AGENT_SWITCH_VERSION|image_tag" README.md docs agents/*/README.md test/README.md
```

预期：无实现契约引用；历史计划或规格文档可以保留。

- [ ] **步骤 6：Commit**

```bash
git add README.md docs/agent-contract.md docs/adding-a-new-agent.md test/README.md agents/*/README.md
git commit -m "docs(agent): simplify template directory contract"
```

### 任务 10：完整契约与镜像验证

**文件：**
- 修改：`test/validate-agent-contract.sh`
- 修改：`test/hermes-smoke.sh`
- 修改：`test/openclaw-smoke.sh`
- 修改：`test/ccswitch-smoke.sh`

- [ ] **步骤 1：更新 smoke 脚本 build args**

从 smoke 脚本中删除 `AI_AGENT_SWITCH_*`、`index.json` 或版本 pin 相关逻辑。

- [ ] **步骤 2：更新 `validate-agent-contract.sh` 全局禁止项**

添加实现文件禁止项：

```bash
if grep -R --line-number -E 'AI_AGENT_SWITCH_|ai_agent_switch_version|org\.sealos\.ai-agent-switch|index\.json|build\.env' \
  .github agents test README.md docs \
  --exclude-dir=superpowers \
  --exclude=validate-agent-contract.sh; then
  fail "agent templates must not depend on index.json, build.env, or ai-agent-switch version metadata"
fi
```

- [ ] **步骤 3：运行契约校验**

```bash
bash test/validate-agent-contract.sh
```

预期：通过。

- [ ] **步骤 4：构建 base**

```bash
docker build -f base/Dockerfile -t agent-hub/agent-devbox-base:local .
IMAGE=agent-hub/agent-devbox-base:local bash base/smoke.sh
```

预期：通过。

- [ ] **步骤 5：构建 agent 镜像**

先构建一个 Node agent 和一个 Python agent：

```bash
docker build --build-arg AGENT_BASE_IMAGE=agent-hub/agent-devbox-base:local -f agents/openclaw/Dockerfile -t agent-hub/openclaw:local .
docker build --build-arg AGENT_BASE_IMAGE=agent-hub/agent-devbox-base:local -f agents/hermes-agent/Dockerfile -t agent-hub/hermes-agent:local .
```

预期：两者构建成功。

- [ ] **步骤 6：运行 agent smoke**

```bash
IMAGE=agent-hub/openclaw:local bash test/openclaw-smoke.sh
IMAGE=agent-hub/hermes-agent:local bash test/hermes-smoke.sh
```

预期：如果 smoke 依赖本地模型服务或 token，应在输出中明确记录缺失条件；不能把失败改成 fallback。

- [ ] **步骤 7：Commit**

```bash
git add test/validate-agent-contract.sh test/hermes-smoke.sh test/openclaw-smoke.sh test/ccswitch-smoke.sh
git commit -m "test(agent): verify simplified latest install contract"
```

### 任务 11：最终审查与 PR 整理

**文件：**
- 检查：全仓库

- [ ] **步骤 1：检查 dirty worktree**

```bash
git status --short --branch
```

确认只剩预期变更。特别注意不要误提交任务开始前已有的 `agents/cowagent/template.yaml` 改动，除非用户明确要求纳入。

- [ ] **步骤 2：全局搜索旧契约**

```bash
rg -n "index\\.json|build\\.env|AI_AGENT_SWITCH_|ai_agent_switch_version|org\\.sealos\\.ai-agent-switch|OPENCLAW_VERSION|HERMES_REF|COWAGENT_REF" .
```

预期：实现文件无旧契约；设计或计划文档中的历史描述可保留。

- [ ] **步骤 3：运行最终验证**

```bash
bash test/validate-agent-contract.sh
docker build -f base/Dockerfile -t agent-hub/agent-devbox-base:local .
IMAGE=agent-hub/agent-devbox-base:local bash base/smoke.sh
```

预期：全部通过。

- [ ] **步骤 4：整理 PR body**

创建临时 Markdown 文件，例如 `/tmp/agent-hub-template-pr.md`：

```markdown
## Summary
- Simplify base image into Devbox runtime plus common Node/Python tooling.
- Remove `index.json` and `build.env` from per-agent contracts.
- Install agents and `ai-agent-switch` through latest Linux-style install paths.
- Update CI and tests to use `template.yaml` and manifests as the deployment source of truth.

## Validation
- `bash test/validate-agent-contract.sh`
- `docker build -f base/Dockerfile -t agent-hub/agent-devbox-base:local .`
- `IMAGE=agent-hub/agent-devbox-base:local bash base/smoke.sh`
```

- [ ] **步骤 5：Commit 计划文档**

```bash
git add docs/superpowers/plans/2026-05-27-minimal-agent-base.md
git commit -m "docs(base): plan minimal agent template refactor"
```

## 自检

- 规格覆盖度：计划覆盖 base 镜像、agent 镜像、`index.json` 删除、`build.env` 删除、CI、文档、契约测试和验证。
- 占位符扫描：计划没有使用「待定」「TODO」「后续实现」作为任务内容；`ai-agent-switch` 安装命令已固定为官方脚本的无版本 latest 调用，并把上游安装脚本支持 latest 作为前置任务。
- 类型一致性：所有路径使用当前仓库真实路径；提交信息使用 Conventional Commits。
