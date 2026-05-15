# Agent Skill 跨 CLI 开发与合规 Guideline

> **术语**：本文档采用业界共识用语 **"Agent Skill"**（`agentskills.io` 官方品牌）。早期文档可能用 "Universal Skill" / "Portable Skill"，已统一为 Agent Skill。
>
> **目标读者**：任何要开发"在 Claude Code / Codex CLI / OpenCode / Gemini CLI 任一或多个 CLI 下都能用"的 Agent Skill 项目开发者。本文档可独立使用，不依赖任何外部上下文。
>
> **覆盖范围**：`agentskills.io` 截至 2026-05 已有 **38+ 兼容 client**（Claude Code、Codex CLI、OpenCode、Gemini CLI、Cursor、Goose、Roo Code、Kiro、Letta、GitHub Copilot、VS Code、Junie、Spring AI、Laravel Boost ...）。本文档以 Claude Code / Codex CLI / OpenCode / Gemini CLI 作 representative 4 端深度展开，其他 client 遵循 spec 自然兼容。
>
> **本文档身份**：TKX Agent Skill 开发规范 v1.1（基于 `agentskills.io` 开放标准 + `npx skills` / `gh skill publish` / `skill-validator` 工具链 + 4 CLI 实战 Gotcha 沉淀）。配套政策文档：`references/TKX_Git_Release_policy_and_process.md`（发版流程）。
>
> **适用对象**：纯 Bash / Python skill；含独立 CLI 入口（`/<name>` / `$<name>`）的发版型 skill；纯 reference 型 skill。**不**适用：纯 prompt 模板、纯 agent 描述（这两类用 agentskills.io spec 即可，无需本规范的发版与多 CLI 适配层）。
>
> **版本 / 维护**：v1.1 — 2026-05-11（v1.0 首发同日升级：术语统一 + 引入 `npx skills` / `gh skill publish` / `skill-validator` 工具链 + 加 §11 Skills vs MCP 速辨）。Source of truth `docs/SKILL_CROSS_CLI_GUIDELINE.md`。本文档变更 = 跨 CLI skill 开发规范升级，须经实战验证（≥1 个项目 self-bake 通过）再合并。

---

## 目录

- [§0 TL;DR — 一图记住](#0-tldr--一图记住)
- [§1 基础层：`agentskills.io` 开放标准](#1-基础层agentskillsio-开放标准)
- [§2 四个 CLI 对比总表](#2-四个-cli-对比总表)
- [§3 `SKILL.md` frontmatter 通用 spec](#3-skillmd-frontmatter-通用-spec)
- [§4 子目录约定](#4-子目录约定)
- [§5 激活方式](#5-激活方式)
- [§6 单源 canonical + symlink 部署模型](#6-单源-canonical--symlink-部署模型)
- [§7 Marketplace 发布渠道](#7-marketplace-发布渠道)
- [§8 已知 cross-CLI Gotchas](#8-已知-cross-cli-gotchas)
- [§9 合规检查清单](#9-合规检查清单)
- [§10 最小可工作 skill 模板](#10-最小可工作-skill-模板)
- [§11 Skills vs MCP 速辨](#11-skills-vs-mcp-速辨)

---

## §0 TL;DR — 一图记住

```
                          单源 canonical 真目录
                                  │
                  ~/.agents/skills/<skill-name>/
                          │
       ┌──────────────────┼──────────────────┐
       │                  │                  │
       │ symlink          │ native read      │ native read
       ▼                  ▼                  ▼
 ~/.claude/skills/   ~/.config/opencode/   ~/.gemini/skills/   (Codex 直读 ~/.agents)
       │                skills/                  (alias)
       │                  │                       │
   Claude Code        OpenCode                 Gemini CLI       Codex CLI
   /skill-name         skill({name})           description-auto $skill-name
```

**4 条硬规则一句话**：
1. **真目录在 `~/.agents/skills/`**，向外 symlink 给 Claude Code；不要反向。
2. **frontmatter 只放 `agentskills.io` spec 的字段**（`name` / `description` 必填 + `license` / `compatibility` / `metadata` / `allowed-tools` 可选），别加自由字段。
3. **`description` 长度 20–1024 chars，禁 `<` `>`，禁 `anthropic` / `claude` 出现在 `name`**。
4. **`assets/` 非空必须含 ≥1 文件**，`SKILL.md` `name` 必须 = 父目录名。

后续章节展开每条规则的 why + 验证方法。

---

## §1 基础层：`agentskills.io` 开放标准

### 历史

2024 年 Anthropic 把 Claude Code 内部的 "Skills" 系统抽出作为开放标准，发布于 [agentskills.io](https://agentskills.io) 与 [agentskills.io/specification](https://agentskills.io/specification)。到 2026-05 已有 **38+ agents / IDE 采纳**，含 Claude Code、Codex CLI、OpenCode、Gemini CLI、Cursor、Goose、Roo Code、Kiro、Letta、GitHub Copilot、VS Code、Junie、Spring AI、Laravel Boost、Antigravity 等。社区统一称之为 "Agent Skill"（非 "Universal Skill" / "Portable Skill" — 后者是非官方造词，本规范统一弃用）。

### Spec 强制内容

任何 spec-compliant CLI **必须**接受以下结构：

```
<skill-root>/
├── SKILL.md          # 必填，YAML frontmatter + Markdown 正文
├── scripts/          # 可选，可执行脚本
├── references/       # 可选，文档参考
└── assets/           # 可选，固定资源（非空时必含 ≥1 文件，见 §8）
```

`SKILL.md` frontmatter（YAML，两条 `---` 之间）：

| 字段 | 必填 | 类型 | 说明 |
|---|---|---|---|
| `name` | ✅ | string | 必须 = 父目录名；匹配 `^[a-z0-9]+(-[a-z0-9]+)*$`；1-64 chars；不准含 XML tags |
| `description` | ✅ | string | 用户面向的一句话说明 + 何时触发；20-1024 chars；禁 `<` / `>` |
| `license` | ❌ | string | SPDX 标识符（如 `MIT` / `Apache-2.0`）|
| `compatibility` | ❌ | string | 平台 / 依赖约束（如 `macOS+Linux, requires git+jq`）≤500 chars |
| `metadata` | ❌ | map | 自由 key/value（**警告**：见 §8 #16，Codex 历史曾收紧此字段）|
| `allowed-tools` | ❌ | string/list | 工具权限白名单（Claude Code 强制执行，其他 CLI 解析但不一定执行）|

Frontmatter 结束第二条 `---` 之后是 Markdown 正文，供 LLM 读取作为 skill 使用说明。

### Ground truth 引用

| 资源 | URL |
|---|---|
| Spec 主页 | https://agentskills.io |
| Spec 详细页 | https://agentskills.io/specification |
| Anthropic 参考实现 + 示例 | https://github.com/anthropics/skills |

**遵守原则**：所有跨 CLI 字段都以 agentskills.io 为 ground truth。**4 个 CLI 在 spec 之上各自扩展，扩展字段不可跨 CLI 假设可用**（详见 §3 + §8）。

---

## §2 四个 CLI 对比总表

| 维度 | Claude Code | Codex CLI | OpenCode | Gemini CLI |
|---|---|---|---|---|
| **官方文档** | code.claude.com/docs/en/skills | developers.openai.com/codex/skills | opencode.ai/docs/skills | geminicli.com/docs/cli/skills |
| **用户级路径** | `~/.claude/skills/<name>/` | `~/.codex/skills/`<br>`~/.agents/skills/`<br>`/etc/codex/skills/`（多源）| `~/.config/opencode/skills/<name>/`<br>+ `~/.claude/skills/`<br>+ `~/.agents/skills/`（多源并扫）| `~/.gemini/skills/<name>/`<br>+ `~/.agents/skills/<name>/`（alias 优先）|
| **项目级路径** | `.claude/skills/<name>/` | `.agents/skills/<name>/` | `.opencode/skills/` + `.claude/skills/` + `.agents/skills/` | `.gemini/skills/` + `.agents/skills/` |
| **激活语法** | `/skill-name` slash + 自动触发 + `Skill(name)` 权限工具 | `$skill-name` prefix + 可选 implicit invocation | `skill({name})` 工具调用（暴露在 `<available_skills>` 块）| description-auto 匹配 + `/skills reload` |
| **自定义 `metadata.*`** | ✅ silently ignored | ⚠️ 官方 free-form，但有过收紧回归（见 §8 #16）| ✅ Zod 允许 free-form | ✅ 未明文限制 |
| **`license` / `compatibility`** | ❌ schema 不识别（silently drop）| ❌ 不在 schema | ✅ 完整支持，`compatibility` ≤ 500 chars | ❌ 未文档化 |
| **`allowed-tools` 是否强制** | ✅ 完整强制（含 `Bash(git add *)` 模式匹配）| ⚠️ 文档化在 `agents/openai.yaml::dependencies.tools` 而非 frontmatter | ⚠️ 解析但**不强制** | ❌ 改为目录级权限，激活时整目录授权 |
| **未知字段处理** | **宽松** — silently drop | **官方宽松**，但有过 metadata 收紧回归 | **严格** — Zod schema fail-fast，发现过 crash on unknown frontmatter（issue #7575）| **宽松** — 只识别 `name` / `description`，其余忽略 |
| **`description` 长度** | ≤ 1024；listing 中 + `when_to_use` 合计 ≤ 1536 chars（多字节截断风险）| 按 spec | **≥ 20** chars（硬底线，OpenCode 独有）+ ≤ 1024 | 按 spec |
| **保留词 / 字符限制** | `name` 禁 `anthropic` / `claude`；`description` 禁 `<` `>`（skill-creator 验证器）| 按 spec | `name` 严格 regex；`description` ≥ 20 | 按 spec |
| **Symlink 加载** | ✅ filesystem watcher 解析 symlink | ❌ **不解析 symlink**（issue #11314，closed "not planned"）| ⚠️ 未文档化但实测可用 | ✅ 自然识别（实际是 alias path 而非 symlink）|
| **Reload 行为** | 文件改动 session 内自动重读 | 文档化为自动检测 | ❌ 需重启 OpenCode | `/skills reload` 或 `/skills refresh` 命令 |
| **打包 / 发布** | `.skill` zip + Claude.ai 上传 + `/v1/skills` API；插件机制 | `$skill-installer` + github.com/openai/skills 目录 | Smithery.ai 目录 + opencode 插件系统 | `gemini extensions install` → `~/.gemini/extensions/<ext>/skills/`；geminicli.com/extensions 目录 |
| **验证工具** | `skill-creator`（Anthropic bundled）| `skills-ref validate`（spec-compliant）| `packages/opencode/src/util/schema.ts` Zod schema | 未文档化 |

### 三句话总结

1. **Codex CLI 是唯一不解析 symlink 的**，所以 canonical real dir 必须放在 `~/.agents/skills/`（Codex 的偏好路径）。
2. **OpenCode 是最严格的 parser**，曾 crash on 未知 frontmatter。开发时按 agentskills.io spec 字段集严格写，不要靠 Claude Code 的"silently drop"。
3. **`allowed-tools` 不可跨 CLI 当成可执行约束**——只在 Claude Code 强制；其他 CLI 当文档读甚至直接忽略。安全相关约束写在 SKILL.md 正文 prose 里更可靠。

---

## §3 `SKILL.md` frontmatter 通用 spec

### 3.1 最小可移植（4 CLI 都 silently 接受）

```yaml
---
name: my-skill
description: 一句话说明 skill 做什么 + 何时触发。20-1024 chars，禁 angle brackets。
---
```

适用场景：纯 prose 型 skill / 简单 reference / 不依赖工具权限的轻量 skill。**这是开发起点**，能跑通 4 CLI loader 不报 schema error。

### 3.2 最大兼容（每个字段 ≥2 CLI 读取，无 CLI 拒绝）

```yaml
---
name: my-skill
description: 一句话说明 + 何时触发。
license: MIT
compatibility: macOS+Linux, requires git+jq, bash 3.2+.
allowed-tools: Bash(git:*) Bash(jq:*) Read Grep
metadata:
  author: Your Name
  homepage: https://github.com/your/repo
---
```

**注意**：
- `metadata.version` **不要放发版号**（Codex 历史回归风险，本规范 §8 #16；版本号写到 `VERSION` sidecar 文件，详见 §10 模板）。
- `license` 用 SPDX 标识符（`MIT` / `Apache-2.0` / `BSD-3-Clause`）便于 OpenCode 与 marketplace 工具识别。
- `compatibility` ≤ 500 chars，写明硬性平台 / 依赖（OpenCode 强校验长度）。
- `allowed-tools` 只对 Claude Code 强制；其他 CLI 当 documentation。如果安全模型要求严格 sandboxing，**不能**靠这个字段——要在 scripts/ 里实际加 guard。

### 3.3 字段值硬约束（违反即报错或 silently 失效）

| 字段 | 硬约束 | 违反后果 |
|---|---|---|
| `name` | `^[a-z0-9]+(-[a-z0-9]+)*$`，1-64 chars | OpenCode Zod fail；其他 CLI silently 用父目录名 fallback |
| `name` | **不能**含 `anthropic` 或 `claude` 子串 | Claude Code skill-creator 拒绝 |
| `name` | 必须 == 父目录名 | Gemini 与 spec 都要求；不一致时 Gemini fallback 到父目录名 |
| `description` | 长度 ≥ 20 chars | OpenCode Zod fail（硬底线，独有）|
| `description` | 长度 ≤ 1024 chars | spec 上限；Claude Code listing 还会截到 1536 chars combined with `when_to_use` |
| `description` | **禁** `<` 和 `>` 字符 | Claude Code skill-creator 拒（XML tag 启发式检测）|

### 3.4 不要做的事

- ❌ **不要往 frontmatter 加 agentskills.io spec 之外的顶层字段**（如 `version` / `author` / `tags`）。OpenCode Zod 可能拒；Claude Code silently drop；写了等于没写。`author` / `tags` 放 `metadata.*` 嵌套字段，**但**仅作 documentation，不要让代码依赖它能跨 CLI 读到。
- ❌ **不要假设 frontmatter 字段值会被某 CLI 渲染给用户**（每个 CLI listing UI 不同；Claude Code 截断；OpenCode 重启才看）。
- ❌ **不要把 description 写成多段长 prose**——一句话 + "Use when ..."；剩下细节放 SKILL.md 正文 Markdown body。

---

## §4 子目录约定

### 4.1 spec 识别的子目录

| 目录 | 用途 | 4 CLI 识别 |
|---|---|---|
| `scripts/` | 可执行脚本（Bash / Python / etc）| 全部 |
| `references/` | 静态文档参考（policy / 长 prose）| 全部 |
| `assets/` | 固定资源（图片 / 模板 / 表格 / fixtures）| 全部 |

skill 正文（SKILL.md body）一般这样引用：

```markdown
完整发版流程见 `references/release-policy.md`，跑 `scripts/release.sh` 即可。
```

LLM 读到这个 hint 后会 fetch 对应文件作为 context。

### 4.2 spec 之外的常见目录

| 目录 | 含义 | 4 CLI 行为 |
|---|---|---|
| `commands/` | slash command 入口（Claude Code 历史约定）| Claude Code 部分版本识别；其他 CLI 当普通目录 |
| `agents/` | 子 agent 定义 / `openai.yaml`（Codex 用）| Codex 读 `agents/openai.yaml` 拿 surface metadata；其他 CLI 不识别 |
| `tests/` | skill 自测试 | 不被任何 CLI loader 识别；运行时只是文件 |
| `evals/` | LLM 评测样本 | 不识别 |
| `VERSION` | 版本号 sidecar（本规范推荐做法，见 §10）| 不识别但安全（不在 frontmatter，避免 Codex 回归）|
| `install.sh` | 多 CLI 安装脚本 | 不识别但安全 |

### 4.3 关键设计原则

- **进 `.skill` bundle 的内容必须无敏感信息**（凭证 / 私钥 / 公网 IP / 真实邮箱）。`.skill` bundle 是 zip 分发产物，任何 sanitize 漏扫直接外泄。本仓 `release-sanitize.sh` 提供工具链层 enforce。
- **`assets/` 非空必须含至少 1 文件**（Claude Code skill-creator zip 剥空目录），用一个 `.gitkeep` 或 `README.md` 占位。
- **`scripts/` 中的脚本必须 chmod +x** 且 shebang 正确。`install.sh` 必须自身 executable + 有 `--dry-run` / `--force` / `--help` 三个 flag（marketplace 合规通用约定，详 §7）。

---

## §5 激活方式

### 5.1 四种激活语法各不同

| CLI | 显式触发 | 隐式触发 | 用户怎么发现 |
|---|---|---|---|
| Claude Code | `/skill-name` slash command | description 自动匹配（默认开启）+ `Skill(name)` 权限工具调用 | `/skills` 列出全部 |
| Codex CLI | `$skill-name` prefix | `policy.allow_implicit_invocation: true` 开启 implicit | `$` 列表 / `/skills` 浏览 |
| OpenCode | `skill({ name: "..." })` 工具调用（LLM 自主决定）| `<available_skills>` 块自动注入 prompt | 提示模型说 "use skill X" |
| Gemini CLI | description 关键词匹配 → 自动激活 | 全自动 | `/skills` reload 后注入 system prompt |

### 5.2 设计 SKILL.md 让 4 CLI 都能正确触发

description 写法要兼顾两种激活：

```yaml
description: |-
  Release a project as a versioned tarball with checksums, SBOM, and audit.
  Use when the user says "release this", "ship vX.Y.Z", or runs /gitx-release / $gitx-release.
```

**关键**：把"用户可能的自然语言意图"和"显式 slash / $ 触发"都写进 description，确保：
- Claude Code description-auto 能 match 自然语言。
- Codex `$` 列表能列出 + implicit 也能 match。
- OpenCode `<available_skills>` 注入后 LLM 知道何时调 `skill({name})`。
- Gemini description-auto 能 match。

### 5.3 install.sh 必须打印各 CLI 的激活提示

接手者装完 skill 不知道怎么用是体验断崖。`install.sh` 收尾必须输出（参考 §10 模板）：

```
Installed CLI commands:
  [Claude Code]     /skill-name                 (slash command 或 自然语言触发)
  [Codex CLI]       $skill-name                 ($ prefix 或 implicit)
  [OpenCode]        say "use skill skill-name"  (LLM 自主调用)
  [Gemini CLI]      describe intent             (description auto-match)
```

这是 marketplace 提交时的合规通用约定（详 §7）。

---

## §6 单源 canonical + symlink 部署模型

### 6.0 首选方案：`npx skills` 工业化 installer

业界已经有成熟的 single-build → multi-CLI installer：[vercel-labs/skills](https://github.com/vercel-labs/skills)，命令 `npx skills`。**生产环境强烈推荐用它，不要自卷脚本**。

**核心能力**：
- **预置 54 CLI agent 的 install path 表**（AiderDesk / Amp / Kimi / Replit / Claude Code / Cursor / Cline / OpenHands / Windsurf / 4 CLI 全收录），无需自己维护
- **symlink / copy 双模式**（默认 symlink；`--copy` flag 强制复制 — 后者用于 Codex CLI 不解析 symlink 的场景，详 §8 G4）
- **source 灵活**：支持 `github.com/owner/repo` / GitLab / 任意 git URL / 本地路径
- **Vercel 维护，是事实标准**：知名 reference skills（vercel-labs/agent-skills、supatest-ai/aiden-skills、anthropic claude-plugins-official）都用它，**不**自卷 install.sh

**最小使用**：

```bash
# 从 GitHub 安装（最常见）
npx skills install owner/repo

# 强制 copy 模式（避开 Codex symlink 雷）
npx skills install owner/repo --copy

# 本地开发安装
npx skills install ./path/to/skill

# 指定目标 CLI（默认全装）
npx skills install owner/repo --targets claude-code,codex,opencode,gemini-cli
```

**与本文档其余章节的关系**：§6.1-§6.4 描述的"canonical + symlink"模型是 `npx skills` 内部使用的同一模型——本文档保留它作为：(a) **底层原理说明**（理解工具背后做了什么）；(b) **fallback 方案**（在禁网环境 / 老 npm 不可用 / 需要定制 install 逻辑时用）。

### 6.1 推荐拓扑（基于 agent 调研 + gitx-release v1.1.x 实战验证）

```
Canonical 真目录：~/.agents/skills/<skill-name>/    （真文件，含 SKILL.md / scripts/ / VERSION / install.sh / 等）
                            │
                            ├── 直接读取
                            │       ↑
                            │   Codex CLI（不解析 symlink，必须真路径在此）
                            │   OpenCode（多源扫描含 ~/.agents/skills/）
                            │   Gemini CLI（~/.agents/skills/ 是 alias path 优先于 ~/.gemini/skills/）
                            │
                            └── symlink 向外
                                    ↓
                              ~/.claude/skills/<skill-name>  →  指向 canonical
                                    ↑
                                Claude Code 通过 symlink 读取
```

### 6.2 为什么必须这样

| 选项 | 验证结果 |
|---|---|
| canonical 在 `~/.claude/skills/`，symlink 给其他 | ❌ Codex 不解析 symlink（issue #11314 closed "not planned"），破 |
| canonical 在 `~/.codex/skills/`，symlink 给其他 | ⚠️ Codex 不 documented 是否优先 `~/.codex/skills/` 还是 `~/.agents/skills/`；OpenCode 默认不扫 `~/.codex/skills/`，需另加 symlink；Gemini 同 |
| **canonical 在 `~/.agents/skills/`**，symlink 给 Claude Code | ✅ Codex 直读 + OpenCode 直读（多源含此）+ Gemini 直读（alias 优先）+ Claude Code 通过 symlink；4/4 都 OK |

### 6.3 install.sh 推荐实现骨架

```bash
#!/bin/bash
# install.sh — install <skill-name> across Claude Code / Codex / OpenCode / Gemini CLI
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_NAME="my-skill"

# 0. checksums verify（marketplace 合规，详 §7）
if [ -f "$SELF_DIR/checksums.txt" ]; then
    ( cd "$SELF_DIR" && shasum -a 256 -c checksums.txt ) || {
        echo "❌ checksums.txt verification FAILED"; exit 1; }
    echo "🔐 checksums.txt verified"
fi

# 1. canonical real dir
CANONICAL="$HOME/.agents/skills/$SKILL_NAME"
mkdir -p "$(dirname "$CANONICAL")"
rsync -a --delete "$SELF_DIR/" "$CANONICAL/"

# 2. symlink 给 Claude Code
CLAUDE_LINK="$HOME/.claude/skills/$SKILL_NAME"
mkdir -p "$(dirname "$CLAUDE_LINK")"
ln -sfn "$CANONICAL" "$CLAUDE_LINK"

# 3. 可选 symlink 给 OpenCode（如果你想强制 OpenCode 看到此 skill；其多源扫描通常自动识别 ~/.agents）
OPENCODE_LINK="$HOME/.config/opencode/skills/$SKILL_NAME"
mkdir -p "$(dirname "$OPENCODE_LINK")"
ln -sfn "$CANONICAL" "$OPENCODE_LINK"

# 4. Gemini / Codex 不需要 symlink（它们直读 ~/.agents/skills/）

# 5. 打印激活提示（§5.3）
cat <<EOF

Installed CLI commands:
  [Claude Code]   /$SKILL_NAME
  [Codex CLI]     \$$SKILL_NAME
  [OpenCode]      say "use skill $SKILL_NAME"
  [Gemini CLI]    describe intent (description-auto)
EOF
```

完整版含 `--dry-run` / `--force` / `--help` 见 §10 模板。

### 6.4 验证安装

```bash
# 三 CLI roots 都到位 + 版本一致
cat ~/.agents/skills/$SKILL_NAME/VERSION
cat ~/.claude/skills/$SKILL_NAME/VERSION
cat ~/.config/opencode/skills/$SKILL_NAME/VERSION
# 三处应输出相同 version

# Symlink 健康
ls -la ~/.claude/skills/$SKILL_NAME
# 应显示 -> .../.agents/skills/$SKILL_NAME

# Codex / Gemini 直读（无 symlink），只需 canonical 存在
ls -la ~/.agents/skills/$SKILL_NAME/SKILL.md
```

---

## §7 Marketplace 发布渠道

### 7.1 四个 CLI 的官方 / 半官方目录

| CLI | Marketplace | 提交方式 | 状态（2026-05）|
|---|---|---|---|
| Claude Code | Claude.ai Skills + `/v1/skills` API | 上传 `.skill` zip 到 Claude.ai，或 API POST | 公开运行，开放上传 |
| Codex CLI | [github.com/openai/skills](https://github.com/openai/skills) catalog + `$skill-installer` | PR 到 catalog repo，含 spec-compliant SKILL.md | 公开运行 |
| OpenCode | [Smithery.ai](https://smithery.ai) + opencode 插件系统 | Smithery.ai 注册 + 提交 plugin manifest | 公开运行 |
| Gemini CLI | [geminicli.com/extensions](https://geminicli.com/extensions) | `gemini extensions install` 兼容的 extension package（skill 放 `~/.gemini/extensions/<ext>/skills/`）| 公开运行 |

### 7.2 通用 marketplace 合规要求（4 CLI 都期望）

提交前**必须**满足：

#### a. SKILL.md 合规

- 严格遵 agentskills.io spec（§3.2 最大兼容字段集，但**不要**加自由字段）
- `name` 匹配 `^[a-z0-9-]+$` + 父目录名一致
- `description` 20-1024 chars，含"何时触发"信息
- `license` 必填且 SPDX 标识符
- body 含 minimal "what / when / how" 三段说明

#### b. 项目元信息

- `LICENSE` 文件存在且符合 SPDX
- `README.md` 含项目标题（h1）+ 安装章节 + 使用 / 快速开始章节 + License 声明 + Contributing 链接
- `CONTRIBUTING.md` 含开发环境说明 + 提交 / PR 规范
- `CHANGELOG.md` 含版本条目（`## vX.Y.Z` 格式）+ 日期（YYYY-MM-DD）
- `CODE_OF_CONDUCT.md` 与 `SECURITY.md`（marketplace 偏好；非硬性但加分）

#### c. 分发包（如果走 `.skill` zip / tarball）

- `checksums.txt`（含 SHA-256，覆盖所有 ship 产物：`.skill` / source.tar.gz / install.sh / sbom）
- `sbom.cyclonedx.json`（CycloneDX 格式，列出 `.skill` / tarball / install.sh）
- `install.sh` 必须支持 `--dry-run` / `--force` / `--help` 三个 flag
- `install.sh` 启动时验证 `checksums.txt`，任何 mismatch 在写入任何文件之前 `exit 1`

#### d. 无敏感信息泄漏

- 不准 `.env` / credentials.json / 任何凭证文件
- prose 文档不准引用真实公网 IP（用 RFC 5737 文档保留段 `192.0.2.x` / `198.51.100.x` / `203.0.113.x` 代替）
- prose 文档不准引用真实邮箱（用 `example@example.com`）
- prose 文档不准引用 user-specific 绝对路径（`/Users/<real-user>/...`）
- 必须通过 `release-sanitize.sh` 一类工具（或 `gitleaks` / `trufflehog`）扫描 clean

#### e. 测试 + audit

- 自带测试套件，可独立运行（`bash tests/run_all.sh` 或等价）
- 自带 audit 脚本验证打包 / 完整性 / 双源一致性
- 测试通过率 100%

### 7.3 各 CLI marketplace 独有要求

#### Claude Code Skills（claude.ai）

- 必须能被 `skill-creator` 验证器通过：`name` 不含 `anthropic` / `claude`；`description` 无 `<` `>`；`assets/` 非空时含 ≥1 文件
- 推荐写 `allowed-tools` frontmatter（其他 CLI 也接受，但只在 Claude Code 强制执行）

#### Codex Skills catalog

- 加 `agents/openai.yaml` 含 `interface.display_name` / `interface.icon_*` / `interface.brand_color` / `dependencies.tools`（Codex 用于 surface 元信息）
- 不要把发版号写到 `metadata.version`（历史回归风险），单独 `VERSION` sidecar

#### OpenCode（Smithery.ai）

- 严格 Zod schema 校验：frontmatter **不**含未知字段
- `description` ≥ 20 chars 硬底线
- `compatibility` ≤ 500 chars
- 推荐附 plugin manifest（Smithery.ai 格式）

#### Gemini extensions

- Skill 须能被 `gemini extensions install` 正确放置（默认 `~/.gemini/extensions/<ext>/skills/`）
- `name` 严格 = 父目录名（Gemini 优先级最严）

### 7.5 `gh skill publish` — GitHub 原生 publish（2026-04-16 GA）

GitHub CLI 在 2026-04-16 加入了原生 `gh skill` 子命令组（[changelog](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/)），是目前**唯一原生**支持 `publish` 操作的 CLI 工具。

**核心能力**：
- `gh skill publish <repo>` — 一次命令完成 agentskills.io spec 校验 + tag protection 检查 + secret scanning + code scanning
- `gh skill install <repo>` — 从 GitHub 安装 skill（与 `npx skills install` 互补，前者锁 GitHub source，后者支持任意 git URL）
- 支持 6 个目标 CLI 直接 install：GitHub Copilot / Claude Code / Cursor / Codex / Gemini CLI / Antigravity
- **不支持 OpenCode** — Smithery.ai 仍是 OpenCode 主战场（详 §7.1）

**典型用法**：

```bash
# publish 当前 repo 为 Agent Skill
gh skill publish .

# 安装别人发的 skill
gh skill install some-org/some-skill

# 列出已安装
gh skill list
```

**GitHub 立场（重要）**：*"Skills are installed at your own discretion. They are not verified by GitHub"* — `gh skill publish` 通过的 spec 校验 **≠** 安全审查，作者自己仍需做 sanitize / audit / SBOM 三件套（详 §7.2）。

**与本规范关系**：`gh skill publish` 替你跑了基础 spec 校验，但**不替代** §9.3 marketplace 提交期合规清单——它只做表层 check，不做内容安全 / 凭证扫描 / SBOM 生成。本规范的完整 ship 流程（§7.4 之外加 `gh skill publish` 作 GitHub source-of-truth publish）：

1. 跑 §9.2 ship 期清单（含 `release-sanitize.sh` / SBOM / checksums / audit）
2. `git tag -a v1.0.0 && git push --tags`
3. `gh skill publish .` — GitHub 端 spec 校验 + 安全扫描
4. 各 marketplace 各自 submit（详 §7.4）

### 7.4 marketplace 通用提交流程模板

1. 自发版本仓打 tag（如 `git tag -a v1.0.0`），push 到公开 git 主机
2. 跑 audit 全 PASS（含 `.skill` / source tarball / checksums / SBOM / install.sh dependencies）
3. 走 sanity scan clean（凭证 / IP / path / email）
4. 上传 `.skill` zip 到 Claude.ai Skills（如发 Claude Code marketplace）
5. PR 到 github.com/openai/skills（如发 Codex catalog）
6. 注册 Smithery.ai + 提交 manifest（如发 OpenCode）
7. 打包 Gemini extension（如发 Gemini marketplace）
8. 各 marketplace 审核（typically 1-3 周）
9. 通过后在项目 README 加 marketplace badge

---

## §8 已知 cross-CLI Gotchas

这些是已经踩过的雷，写新 skill 时**主动**避开。每条标记适用范围（哪些 CLI 受影响）。

### G1 — `metadata.*` 自由字段历史回归
**适用**：Codex CLI（其他 CLI 不严格）
**症状**：旧 skill 在 `metadata:` 下放 `version: vX.Y.Z` / `author: foo` 等自由字段，新版 Codex parser 突然 reject `invalid YAML: metadata: invalid type: string ...`，跳过整个 skill 加载。
**修法**：版本号迁到 `VERSION` sidecar 文件；author / homepage 放到 README.md / package.json 一类 metadata 文件，**不**进 frontmatter。

### G2 — `description` 含 `<` 或 `>` 被拒
**适用**：Claude Code skill-creator
**症状**：`Validation failed: Description cannot contain angle brackets`。
**修法**：用 `NAME` / `VERSION` / `DIR` 大写占位符替代 `<name>` / `<version>` 风格；或用反引号 `\`<name>\`` 写在 SKILL.md body 而非 frontmatter。

### G3 — `assets/` 空目录被 zip 剥离
**适用**：Claude Code skill-creator zip packager
**症状**：`.skill` 解压后 `assets/` 不存在；audit `assets/ 必须存在` ❌ FAIL。
**修法**：`assets/` 内放至少 1 个文件（`assets/README.md` 或 `.gitkeep`），明示"保留目录存在"。

### G4 — Symlink 在 Codex 下失效
**适用**：Codex CLI（issue #11314 closed "not planned"）
**症状**：把 canonical 放在 `~/.claude/skills/` 然后 symlink 给 `~/.agents/skills/` → Codex 看到 symlink 不解析 → skill 不出现在 `$` 列表。
**修法**：canonical real dir 必须在 `~/.agents/skills/`（Codex 直读路径）；symlink 只能从此向外（如向 `~/.claude/skills/`）。

### G5 — OpenCode crash on 未知 frontmatter
**适用**：OpenCode（issue #7575）
**症状**：frontmatter 含 OpenCode 不识别的字段 → Zod schema fail-fast → OpenCode 启动 crash 或跳过 skill。
**修法**：严格按 §3.2 字段集；不要图省事把 Claude Code 专属字段（`disable-model-invocation` / `when_to_use` / `argument-hint` / `model` / `effort` 等）加进 frontmatter。这些字段如必须，写 SKILL.md body prose。

### G6 — `description` 多字节字符在 listing budget 截断处碎裂
**适用**：Claude Code（listing budget ≈1% 上下文窗口，combined description + when_to_use ≤ 1536 chars）
**症状**：中文 description 接近 1536 chars 边界时，字节截断可能切在 UTF-8 多字节字符中间，渲染乱码。
**修法**：中文 description 严格控制 ≤ 200 字（约 600 字节，留 buffer），关键信息放前面。

### G7 — `name` reserved 词
**适用**：Claude Code
**症状**：skill `name` 含 `anthropic` 或 `claude` 子串 → skill-creator 拒。
**修法**：skill 命名避开这两个词；用项目品牌 / 功能词替代。

### G8 — OpenCode `description` < 20 chars 被拒
**适用**：OpenCode（其他 CLI 无硬底线）
**症状**：description 太短（如 `"Release tool."` 14 chars）→ OpenCode Zod fail。
**修法**：写完整 sentence + "Use when ..." 触发说明，自然 > 20 chars。

### G9 — `name` 与父目录名不一致
**适用**：Gemini CLI（spec 也要求）
**症状**：`SKILL.md` 写 `name: foo` 但父目录是 `bar/` → Gemini fallback 到父目录名 `bar`，导致激活时认不到 `foo`。
**修法**：发版流程含 `test_skill_name_matches_dir.sh` 一类自测。

### G10 — `allowed-tools` 跨 CLI 假定可执行
**适用**：所有非 Claude Code 的 CLI
**症状**：开发者依赖 `allowed-tools: Bash(git:*) Read` 阻挡 skill 用其他工具，但在 Codex / OpenCode / Gemini 下该字段不强制 → skill 实际可用任何工具。
**修法**：把硬性安全约束写在 scripts/ 的 guard 代码里（如 sanitize / preflight），不要靠 frontmatter。

### G11 — OpenCode 改 skill 后需重启
**适用**：OpenCode（独有）
**症状**：edit SKILL.md 后 OpenCode 看不到改动 → 误以为 skill 损坏。
**修法**：开发期 every reinstall → 重启 OpenCode CLI；用户层 install.sh 收尾提示重启。

### G12 — Frontmatter 字段中 Chinese 全角标点 + `set -u` shell 互动
**适用**：写 skill scripts 时（不是 frontmatter，是 scripts 内）
**症状**：`echo "$var）"` 在 `set -u` 下被 bash 把 Chinese `）`（U+FF09）当变量名延续吃掉 → `unbound variable`。
**修法**：脚本中所有相邻 Chinese 标点的 `$var` 引用统一写 `${var}` ASCII-delimit。Skill 自带测试中加 grep guard 防 regression。

---

## §9 合规检查清单

按开发阶段切分，每条可独立验证。打 ✅ 才能进下一阶段。

### 9.1 开发期（写新 skill 时）

- [ ] **目录结构**：`<skill-name>/{SKILL.md, scripts/, references/, assets/, install.sh, VERSION, README.md, LICENSE, CHANGELOG.md, CONTRIBUTING.md}`
- [ ] **`name` 合规**：父目录名 = SKILL.md `name` 字段 = `^[a-z0-9]+(-[a-z0-9]+)*$`，不含 `anthropic` / `claude`
- [ ] **`description` 合规**：20-1024 chars，无 `<` / `>`，含"何时触发"语义（自然语言 + slash / `$` 触发都写）
- [ ] **`metadata.*` 安全**：**不放**版本号 / 任何代码依赖的载荷字段（写到 `VERSION` sidecar）
- [ ] **`assets/` 非空时含 ≥1 文件**（`.gitkeep` 或 `README.md` 占位）
- [ ] **`scripts/*.sh` 都 `chmod +x` + shebang 正确**
- [ ] **`scripts/*.sh` 都用 `set -u`** （**不**用 `set -e`，因为 `[ -n "$x" ] && cmd` 在 `set -e` 下会 abort，详 §8 内 Gotcha #24 类）
- [ ] **`scripts/` 中 `$var` 引用避开相邻 Chinese 全角标点**（用 `${var}` ASCII-delimit）
- [ ] **`scripts/` 中找首个 pattern 行号用 `awk '/pat/{print NR;exit}'`** 而**不**是 `grep -n | head -1 | cut`（pipefail+set-e 安全）

### 9.2 ship 期（自发版前必跑）

**首选自动化**（两个工具，互补不互斥）：

```bash
# 1. 官方 spec source-of-truth（Anthropic anthropics/skills/skill-creator）
#    102 行 Python，规则集精准对应 agentskills.io spec。需要 PyYAML（macOS
#    PEP 668 阻止 system pip，用 venv 或 --break-system-packages）。
python3 ~/.claude/plugins/cache/claude-plugins-official/skill-creator/*/skills/skill-creator/scripts/quick_validate.py <skill-dir>

# 2. Community 全面校验（github.com/agent-ecosystem/skill-validator）
brew install agent-ecosystem/tap/skill-validator
skill-validator --strict
```

[`anthropics/skills/skill-creator/scripts/quick_validate.py`](https://github.com/anthropics/skills/blob/main/skills/skill-creator/scripts/quick_validate.py) 是**官方 source-of-truth**——102 行 Python，规则集就是 agentskills.io spec 的精确落地（6 条规则：SKILL.md 存在 + frontmatter 语法 + ALLOWED_PROPERTIES 白名单 + name kebab-case ≤64 + description no `<>` ≤1024 + compatibility ≤500）。Claude Code 安装后会自动 fetch 到 `~/.claude/plugins/cache/claude-plugins-official/skill-creator/<hash>/skills/skill-creator/`，路径里 `<hash>` 是动态 plugin marketplace 分配的 hex（用 glob 展开）。**通过 = 通过官方 spec gate**。

[`agent-ecosystem/skill-validator`](https://github.com/agent-ecosystem/skill-validator) 是 community 维护的更全面校验器，含 14 个 per-platform validators（claude / codex / cursor / gemini / goose / kiro / roo-code / windsurf / ...）+ link validity / content density / imperative ratio / cross-language contamination / token count / LLM-as-judge scoring。**覆盖官方之外的运行时合规**，且原生支持 GitHub Action 模板（PR 上自动跑 + emit PR annotations + markdown job summary）。

**建议组合**：写新 skill 时先跑 `quick_validate.py` 拿到官方 PASS；CI / PR 上跑 `skill-validator --strict` 拿到运行时合规 + 多 CLI 覆盖。本规范的 reference implementation（gitx-release）`audit §0_spec` 章节是 `quick_validate.py` 的纯 bash 等价实现（零 Python 依赖），可作 audit-time enforce 而非仅 PR-time。

下方手工 checklist 仍保留作 (a) `skill-validator` 不覆盖的项目级检查（双源 / SBOM / checksums / install.sh 三 flag / 端到端 install verify），(b) **理解每项 why** 的教学价值——CI 失败时凭这份清单逐项 debug 比对 stack trace 高效。

- [ ] **测试 100% PASS**：`bash tests/run_all.sh`
- [ ] **smoke test PASS**
- [ ] **shellcheck -S warning 0 warnings**（modified files）
- [ ] **`diff -rq` 双源一致**（如有"root scripts/" + "bundle skills/<name>/scripts/" 双源）
- [ ] **`release-sanitize.sh .` clean**（无凭证 / 公网 IP / 真实邮箱 / 真实 user path 泄漏）
- [ ] **`.skill` bundle 构建成功**（zip 含 `SKILL.md` / `scripts/` / `assets/` / 等所有 spec 目录；空目录已用占位文件填）
- [ ] **`source.tar.gz` byte-reproducible**（同 source + 同 `SOURCE_DATE_EPOCH` → 两次构建 `cmp -s` clean）
- [ ] **`checksums.txt` 覆盖**：`.skill` + source.tar.gz + full.tar.gz + install.sh + sbom.cyclonedx.json + TOKEN_USAGE.md
- [ ] **`sbom.cyclonedx.json` 合规**：含 `bomFormat=CycloneDX` + `specVersion=1.x` + `metadata.component.version=vX.Y.Z` + 列出所有 ship 产物
- [ ] **`install.sh` 三 flag**：`--dry-run` / `--force` / `--help` 都能跑
- [ ] **`install.sh` 启动 verify checksums.txt**：tampered tarball 在写文件之前 exit 1
- [ ] **deep audit 全 PASS / 0 FAIL**（建议同时跑 inline 模式和 standalone 模式）
- [ ] **CHANGELOG `## vX.Y.Z` entry 真实**（非 wrapper auto-placeholder）

### 9.3 marketplace 提交期（公开发布前必跑）

- [ ] **9.1 + 9.2 全部 ✅**
- [ ] **README.md 含**：h1 标题 + 安装 / 使用 / License / Contributing 章节
- [ ] **LICENSE 含**：SPDX 标识符（如 `MIT`）+ Copyright 行 + 年份
- [ ] **CONTRIBUTING.md 含**：开发环境说明 + 提交 / PR 规范
- [ ] **CHANGELOG.md 含**：版本条目（`## vX.Y.Z`）+ 日期（YYYY-MM-DD）
- [ ] **CODE_OF_CONDUCT.md** 存在（marketplace 加分项）
- [ ] **SECURITY.md** 存在（marketplace 加分项；写明 vuln 报告渠道）
- [ ] **公开 git 主机有对应 tag**（`v1.0.0` 等 annotated tag pushed）
- [ ] **`install.sh` 末尾打印 4 CLI 激活提示**（详 §5.3）
- [ ] **`SKILL.md` body 含 minimal "what / when / how" 三段**
- [ ] **第三方再 install 测试**：从 git clone 干净仓 → 跑 `install.sh --force` → 三 CLI roots 全装 + 关键功能验证

### 9.4 跨机部署期（含迁移）

- [ ] **canonical real dir** 在 `~/.agents/skills/<skill-name>/`（不是 symlink）
- [ ] **`~/.claude/skills/<skill-name>`** 是 symlink → canonical
- [ ] **`~/.config/opencode/skills/<skill-name>`** 是 symlink（可选，OpenCode 多源已含 `~/.agents`）
- [ ] **Codex 与 Gemini 不需要 symlink**（直读 `~/.agents/skills/`）
- [ ] **`cat <root>/VERSION` 三处一致**（root + skills/ + installed）
- [ ] **Syncthing 同步范围 ignore `.git/**` 与 `.syncthing.*.tmp`**（跨机首次同步避免 `.git/index.sync-conflict-*` 与 staging tmp 残留）

---

## §10 最小可工作 skill 模板

### 10.1 目录骨架

```
my-skill/
├── SKILL.md                 # frontmatter + body（必填）
├── VERSION                  # v0.1.0（sidecar，非 frontmatter）
├── install.sh               # 多 CLI 部署 + 激活提示
├── README.md                # 项目门面
├── LICENSE                  # SPDX 合规
├── CHANGELOG.md             # 版本日志
├── CONTRIBUTING.md          # 协作说明
├── CODE_OF_CONDUCT.md       # 行为准则（marketplace 加分）
├── SECURITY.md              # 漏洞报告（marketplace 加分）
├── scripts/
│   ├── main.sh              # skill 主逻辑入口
│   └── ...                  # 其他可执行脚本
├── references/
│   └── design.md            # 设计 / 政策文档
├── assets/
│   └── README.md            # 占位（避免 zip 剥空目录 §8 G3）
└── tests/
    └── run_all.sh           # skill 自测试
```

### 10.2 SKILL.md 范本

```yaml
---
name: my-skill
description: Brief one-sentence purpose. Use when the user runs /my-skill, $my-skill, or asks to "do X with Y". 20-1024 chars, no angle brackets.
license: MIT
compatibility: macOS+Linux, requires bash 3.2+
---

# my-skill

## What

简介这个 skill 做什么（1-2 段）。

## When to use

- 用户说 "run my-skill" / "use my-skill"
- 用户输入 `/my-skill` slash command
- 用户输入 `$my-skill` Codex prefix
- description-auto 匹配（Gemini / Claude Code 隐式触发）

## How

```bash
bash scripts/main.sh [options]
```

详细见 `references/design.md` 与 `scripts/main.sh --help`。

## Verify

```bash
bash tests/run_all.sh
```
```

### 10.3 install.sh 范本骨架

> **⚠️ 教学 / fallback 版本**——生产环境推荐 `npx skills install owner/repo`（详 §6.0）。下面这个 install.sh 只在 (a) 禁网环境 / (b) 老 npm 不可用 / (c) 需要定制 install 后处理（如本机配置）的场景用。一般 skill 项目**不要自卷 install.sh**，外包给 `npx skills` 减少维护负担。

```bash
#!/bin/bash
# install.sh — install my-skill across Claude Code / Codex / OpenCode / Gemini CLI.
# 教学/fallback 实现；生产推荐 `npx skills install`（详 §6.0）。
set -u  # 注意：不用 set -e（与 [ ] && cmd 冲突）

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_NAME="my-skill"
DRY_RUN=0
FORCE=0

usage() {
    cat <<EOF
Usage: install.sh [--dry-run] [--force] [--help]
  --dry-run  Print actions without modifying filesystem
  --force    Overwrite existing installation
  --help     Show this message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --force) FORCE=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
    esac
done

run() { if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }

# 0. checksums verify
if [ -f "$SELF_DIR/checksums.txt" ]; then
    if [ "$DRY_RUN" = 0 ]; then
        ( cd "$SELF_DIR" && shasum -a 256 -c checksums.txt ) || {
            echo "❌ checksums.txt verification FAILED" >&2; exit 1; }
    fi
    echo "🔐 checksums.txt verified"
fi

# 1. canonical
CANONICAL="$HOME/.agents/skills/$SKILL_NAME"
run mkdir -p "$(dirname "$CANONICAL")"
if [ -e "$CANONICAL" ] && [ "$FORCE" = 0 ]; then
    echo "❌ $CANONICAL already exists. Use --force to overwrite." >&2
    exit 1
fi
run rsync -a --delete "$SELF_DIR/" "$CANONICAL/"

# 2. Claude Code symlink
CLAUDE_LINK="$HOME/.claude/skills/$SKILL_NAME"
run mkdir -p "$(dirname "$CLAUDE_LINK")"
run ln -sfn "$CANONICAL" "$CLAUDE_LINK"

# 3. OpenCode symlink (可选)
OPENCODE_LINK="$HOME/.config/opencode/skills/$SKILL_NAME"
run mkdir -p "$(dirname "$OPENCODE_LINK")"
run ln -sfn "$CANONICAL" "$OPENCODE_LINK"

# 4. 激活提示
cat <<EOF

Installed: $SKILL_NAME ($(cat "$SELF_DIR/VERSION" 2>/dev/null || echo "?"))

[Claude Code]   /$SKILL_NAME              (slash command 或 自然语言触发)
[Codex CLI]     \$$SKILL_NAME              (\$ prefix 或 implicit)
[OpenCode]      say "use skill $SKILL_NAME" (LLM 自主调用)
[Gemini CLI]    describe intent           (description-auto)
EOF
```

### 10.4 起项目命令

```bash
# 1. 从本模板 cp 起新 skill
git clone <this-repo> my-skill
cd my-skill
# 改 SKILL.md name + description + 业务逻辑

# 2. 自测
bash tests/run_all.sh

# 3. 本机安装
bash install.sh --force

# 4. 各 CLI 测试激活
# Claude Code: /my-skill
# Codex CLI: $my-skill
# OpenCode: 让 LLM 调 skill({name:"my-skill"})
# Gemini CLI: 描述 intent 看是否自动激活

# 5. 准备 marketplace 提交：跑 §9.3 全部 checklist
```

### 10.5 配套发版工具链

如果 skill 项目需要打 `.skill` zip / source tarball / SBOM / checksums / audit 等完整发版动作，**不要自己造**——用 `gitx-release` skill：

```bash
# 一键发版（自动 bump VERSION + audit + 产物）
gitx-release  # 或 /gitx-release / $gitx-release
```

`gitx-release` 自身按本规范开发，可作为参考实现：
- canonical 在 `~/.agents/skills/gitx-release/`
- 发版产物含 `.skill` / source.tar.gz / full.tar.gz / install.sh / checksums.txt / sbom.cyclonedx.json / TOKEN_USAGE.md / RELEASE_NOTES.md
- 自带 deep audit（11 章节 170+ 检查）
- 端到端验证 install.sh checksums verify

### 10.6 Vendoring 外部依赖（让 skill 真正 self-contained）

当 skill 依赖外部工具（如 Anthropic 官方 `skill-creator`、`syft`、`gitleaks` 等）时，**vendor 一份核心文件到 skill 自身**让 skill 在禁网 / 新机 / CI / sub-agent 等场景仍能 work。这是本规范 reference implementation `gitx-release` v1.3.x 的实战做法。

**Vendoring 决策原则**:

| 条件 | 决策 |
|---|---|
| 工具核心可 standalone 跑（少量文件，无大依赖）| ✅ Vendor |
| 工具是 LLM-only / 依赖大型 runtime（如 npm / Docker）| ❌ 不 vendor，让 user 自装 |
| 工具有官方开源 license（Apache 2.0 / MIT / BSD）| ✅ 可 vendor，attribution 保留 LICENSE |
| 工具是 proprietary 或 GPL | ❌ 风险高，不 vendor |
| 工具有 marketplace 自动 fetch（如 Claude Code plugin cache）| 🟡 仍可 vendor 作 fallback，cache 缺时 graceful 降级 |

**Vendoring 目录结构**（gitx-release 模式）:

```
scripts/vendored/<tool-name>/
├── VERSION              # pinning 元数据（必填，见下）
├── LICENSE.txt          # upstream LICENSE 文件 attribution
├── scripts/             # 核心 standalone 文件
│   ├── core1.py
│   ├── core2.py
│   └── ...
└── README.md            # 可选，说明 vendor 范围 + 何时升级
```

**`VERSION` pinning 文件格式**（key=value 行，便于 bash awk 解析）:

```ini
# Vendored <tool> pinning metadata.
upstream_commit=<full-40-char-hex>
upstream_date=<YYYY-MM-DD>
upstream_source=https://github.com/owner/repo/tree/<ref>/path/to/tool
vendored_at=<YYYY-MM-DD when this snapshot taken>
vendored_by=<your-skill-name vX.Y.Z>
license=<SPDX-id>
notes=Vendored files: <which subset>; reason: <why this subset only>.
```

**Version 对比 helper 模板**（参考 `scripts/lib/skill-creator-version.sh`）:

```bash
# tool_status() — emits SKC_*-style vars: ALPHA_VENDORED_DATE, ALPHA_SYSTEM_DATE,
# ALPHA_VERDICT (same | system_newer | vendored_newer | system_absent | both_absent).
# Date proxy: plugin cache dir mtime via cross-platform stat (BSD vs GNU).
```

**Decision matrix in release.sh / setup.sh**（gitx-release `build_skill_package` 抽象）:

```
case "$ALPHA_VERDICT" in
    same|system_newer)  use_system ;;
    vendored_newer)
        if [ -t 0 ] && [ -z "${CI:-}" ]; then
            interactive_prompt → user picks system or vendored
        else
            use_vendored  # non-tty default: reproducible vendored
        fi ;;
    system_absent)      use_vendored ;;
    both_absent|*)      fall_back_to_alternative_path ;;
esac
```

**install.sh 注意事项**（gitx-release v1.3.0 ship 漏修教训）:

vendored 目录必须 explicit copy 到 canonical install。**只 copy `scripts/*.sh` 会漏掉 `scripts/vendored/`**:

```bash
# 必须的两行（v1.3.1 hot-patch 加的）:
if [ -d "$SELF_DIR/scripts/vendored" ]; then
    cp -R "$SELF_DIR/scripts/vendored" "$CANONICAL/scripts/vendored"
fi
```

**BDD test 建议**（v1.3.2+ candidate）:

```bash
# tests/test_install_path_completeness.sh — 验证 .skill bundle 内的所有
# 关键路径在 post-install canonical 中也存在
```

防 install.sh 漏 copy 类 bug 重现。

**升级节奏建议**: 手工 + explicit commit。每次升级 vendored 工具时，更新 `VERSION` 文件的 `upstream_commit` + `upstream_date` + `vendored_at`，在 commit message 说明 upstream diff 摘要。**不**做自动 sync —— vendored 是有意识 freezing 的 dependency，升级要走 review 流程。

---

### 10.7 已 4 CLI 验证过的 reference projects（cold-read 学习用）

| 项目 | 用途 | 看点 |
|---|---|---|
| [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills) | Vercel 官方 skill collection | `npx skills` 同源团队的范例写法 |
| [supatest-ai/aiden-skills](https://github.com/supatest-ai/aiden-skills) | 4 CLI explicit 兼容声明 | README 写法 + 不自卷 install.sh（外包 `npx skills`）|
| [poemswe/co-researcher](https://github.com/poemswe/co-researcher) | research 类 skill | Claude Code / Gemini CLI / Codex / OpenCode 4 端兼容 |
| [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) | Anthropic 官方示范 | `plugin.json` + `skills/<name>/SKILL.md` 分层（distribution wrapper vs content）|
| [agentskills/agentskills](https://github.com/agentskills/agentskills) | spec repo + `skills-ref validate` | 官方 reference validator 实现 |

---

## §11 Skills vs MCP 速辨

**两者职能正交，别合并。** 当 skill 又需要工具调用（execute）又需要 instruction prompt（context）时，**必须**维护两个工件——业界目前**没有** hybrid 双 manifest 实践。

### 11.1 核心区别

| 维度 | Agent Skill | MCP Server |
|---|---|---|
| **本质** | 带 artifact（scripts/refs/assets）的**可重用 prompt** | **RPC 协议**：让 client 调远程 / 本地工具 |
| **介质** | `SKILL.md` + Markdown body 注入 LLM context | JSON-RPC over stdio / HTTP，工具调用与结果交换 |
| **激活** | description-match / slash / `$` 触发 → 注入 prompt | client 与 server 建立连接 → 工具自动 advertised |
| **数据流** | 单向（skill → LLM context）| 双向（client ↔ server 工具调用）|
| **典型场景** | 教 LLM 怎么发版 / 怎么写 commit / 怎么做安全审查 | 让 LLM 实际跑 git / SQL / API / 文件操作 |
| **错用代价** | 把工具调用塞进 Skill → context bloat + 安全失控 | 把 prompt instruction 塞进 MCP → 浪费 RPC 通道 + 无 versioning |

### 11.2 官方立场

- **Anthropic / MCP team** ([modelcontextprotocol.io/docs/develop/build-with-agent-skills](https://modelcontextprotocol.io/docs/develop/build-with-agent-skills))：Skills 可作为**"build MCP servers 的脚手架"**——用 Skill 教 agent 如何写 MCP server。**两者不是同一个工件的双 manifest**。
- **第三方权威分析** ([cra.mr/mcp-skills-and-agents](https://cra.mr/mcp-skills-and-agents/))：*"Skills 是带 artifact 的可重用 prompt；MCP 是 RPC 工具协议。两者职能正交，错用都污染 context。"* 作者推测"未来可能看到 MCP 暴露 skills"，但**当前不存在 hybrid 双 manifest 实践**。

### 11.3 选哪个？快速决策树

```
你的 skill 主要价值是什么？

  教 LLM 一套 procedure / convention / policy （含 prose 解释 + 引用文档）
        ↓
    → Agent Skill (SKILL.md)

  让 LLM 实际调用工具完成动作（query database / call API / mutate state）
        ↓
    → MCP Server

  两者都要？
        ↓
    → 维护两个工件：一个 Skill repo 教用法，一个 MCP server repo 跑工具
    → Skill body 里引用 MCP server 的安装链接 / 使用方式
    → 不要混在一个工件里
```

### 11.4 为什么不能合并

1. **加载机制不同**：Skill 由 client load `SKILL.md`（filesystem walk）；MCP server 由 client launch process + JSON-RPC handshake。同一个 `<root>/` 不可能同时被两边按各自规则正确识别。
2. **生命周期不同**：Skill 是静态文件，改了重启 client；MCP server 是 live process，可动态 reload tools。
3. **认证模型不同**：Skill 不需要凭证（纯 markdown）；MCP server 通常需要 OAuth / token / API key 等 secret——硬塞同一个工件会让 secret leak 风险扩大。

---

**附录 A — 工具链推荐**

| 任务 | 推荐工具 |
|---|---|
| **Skill installer（生产首选）** | [`npx skills install`](https://github.com/vercel-labs/skills)（54 CLI 预置 path 表 + symlink/copy 双模）|
| **Skill publisher（GitHub 路径）** | `gh skill publish`（[2026-04-16 GA](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/)，6 CLI 直装 + spec 校验）|
| **Skill validator（CI 集成）** | [`agent-ecosystem/skill-validator`](https://github.com/agent-ecosystem/skill-validator)（brew tap + 14 per-platform validators + GitHub Action 模板）|
| 凭证扫描 | `gitleaks` / `trufflehog` / 本规范配套 `release-sanitize.sh` |
| SBOM 生成 | `syft` → CycloneDX JSON |
| Reproducible build | `SOURCE_DATE_EPOCH` + `tar --no-recursion --owner=0 --group=0 --numeric-owner` + `gzip -n` |
| YAML frontmatter 校验 | `yq` / `python -c 'import yaml; ...'` |
| Skill spec 最小校验 | `skills-ref validate`（Codex 工具）/ `skill-creator`（Claude Code bundled）|
| Cross-CLI 安装测试 | `npx skills install` + 4 CLI roots 验证（详 §6.4）|

**附录 B — 相关项目参考**

- [agentskills.io](https://agentskills.io) — 开放标准 ground truth
- [agentskills/agentskills](https://github.com/agentskills/agentskills) — spec repo + reference validator
- [github.com/anthropics/skills](https://github.com/anthropics/skills) — Anthropic 参考实现
- [github.com/openai/skills](https://github.com/openai/skills) — Codex Skills catalog
- [github.com/vercel-labs/skills](https://github.com/vercel-labs/skills) — `npx skills` installer
- [github.com/agent-ecosystem/skill-validator](https://github.com/agent-ecosystem/skill-validator) — CI / pre-commit validator
- [smithery.ai/skills](https://smithery.ai/skills) — OpenCode marketplace (15K+ skills)
- [geminicli.com/extensions](https://geminicli.com/extensions/) — Gemini CLI extensions marketplace
- gitx-release — 本规范的 reference implementation（公开镜像 GitHub `tkxlab-ai/GitX`）

**附录 C — 业界尚未解决的痛点（2026-05）**

1. **Marketplace federation 不存在**：Claude.ai Skills / Codex catalog / Gemini extensions / Smithery 四家市场各自孤岛，没有任何工具能 "publish once, distribute everywhere"。最现实仍是单 GitHub repo source-of-truth + 各 marketplace 手动 submit。`gh skill publish` 是单一 source publish，**不**等于 federation。
2. **Codex CLI 不读 symlink 这个 runtime 差异无法 abstract**：`npx skills --copy` 是变通方案，但作者仍需理解这个 gotcha。规范层面无解。
3. **MCP × Skills 没有 hybrid 双 manifest pattern**：需要工具+模板的 skill 仍要维护两个工件，没有统一打包方式。社区共识"职能正交，别合并"，但意味着 maintenance overhead 翻倍。

---

**文档结束** · v1.1 · 2026-05-11

**Changelog**:
- **v1.1**（同日升级）：术语 "Universal Skill" → "Agent Skill" 统一；引入工具链 `npx skills` (§6.0) / `gh skill publish` (§7.5) / `skill-validator` (§9.2)；新增 §11 Skills vs MCP 速辨；§10.6 列已 4 CLI 验证 reference projects；附录 C 列业界未解痛点。
- **v1.0**：首发。`agentskills.io` spec + 4 CLI 对比 + 部署模型 + marketplace + Gotchas G1-G12 + 三阶段合规清单 + 模板 skeleton。
