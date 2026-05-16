<!-- Deep-Audit N/0/1 count is NOT gitx-managed — §0f consistency + §0i exactness + per-repo test (Decision 0018/0019). -->
<div align="center">

# 🚀 GitX

**把"发版"当工程纪律来做的跨项目发布流水线，而不是一件杂活。**

[English](README.md) · [中文](README_CN.md)

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-95%2B%20suites%20%2F%200%20fail-brightgreen.svg)](tests/run_all.sh)
[![Deep Audit](https://img.shields.io/badge/deep%20audit-240%2F0%2F1-brightgreen.svg)](scripts/release-audit.sh)
[![CLIs](https://img.shields.io/badge/CLI-Claude%20Code%20%C2%B7%20Codex%20%C2%B7%20OpenCode%20%C2%B7%20Gemini-blue.svg)](#快速开始)
[![Shell](https://img.shields.io/badge/bash-3.2%2B%20POSIX-orange.svg)](SKILL.md)

</div>

> 一条命令，把零散又易错的发版仪式——版本号 / 测试 / 打包 / 敏感信息扫描 /
> 文档平摊 / 完整性证明 / 深度审计——收敛成一条 fail-closed 流水线。每条
> 政策都是会让构建中止的 shell 断言，而不是没人看的 wiki 条目。

**版本号**：见 [`VERSION`](VERSION) / [`Release/CHANGELOG.md`](Release/CHANGELOG.md) ·
**运行时**：纯 Bash 3.2+（POSIX）、git 2.x、可选 `python3 + venv` ·
**适用范围**：任何 `skills/<name>/SKILL.md` 布局的项目，四个 CLI 安装面。

---

## 更新摘要 What's New

**最新**：
<!-- gitx:managed:whats-new -->
v1.10.0 — 2026-05-16
<!-- /gitx:managed:whats-new -->

| 版本 | 要点 |
|------|------|
| v1.9.8 | README 语义数字陈腐根治 + `§0f` 审计闸 + 单仓 README 精确性闸 |
| v1.9.6–1.9.7 | superpowers 11 轮 loop + codex 迭代审计：`.python-version` 公开 tarball 泄漏根治、`gitx-sop` 凭证门系统性修复、bootstrap-safe 安装闸、`.github-publish-wt` 防御纵深、handoff-v2 五面一致 |
| v1.9.0–1.9.5 | `/gitx:*` plugin namespace + central `tkxlab-ai/marketplace` + gitx-init auto-provision + codex 审计加固 |
| v1.8.x | Claude Code plugin distribution + community-file standard |
| v1.7.5 | slash shim 装入 `~/.claude/commands/`（Claude Code 命令发现修复）|
| v1.7.4 | `gitx-sop` 加固为可对*其他*技能用（可移植脱敏 + 完整性闸）|
| v1.7.2–1.7.3 | doc 版本陈腐根治 + `§0e` 审计闸 + README 命令完整性闸 |
| v1.7.0–1.7.1 | `gitx-sop` 子命令（GitHub 发布 runbook）+ `commands/` 分发修复 |
| v1.6.0 | `gitx-init` 子命令——项目自我教会发版 |
| v1.0–1.5 | 内嵌 Anthropic skill-creator、可复现构建、5-skill 安装标准 |

---

## 📊 实时构建指标

**版本**：
<!-- gitx:managed:version -->
v1.10.0
<!-- /gitx:managed:version -->

**发版日期**：2026-05-16 · **所用模型**：Claude / Codex（开发 + 对抗式评审）· **累计 AI token 消耗（项目至今，估算）**：约 5 亿+ 输入/输出 + 约 60 亿+ 缓存，跨数百个会话 · **数据一览**：95+ BDD 套件 / 0 失败 · Deep Audit 全绿 · 20+ 次发版 · 每个 tag 一个 GitHub Release。

> **安装任意 TKX 技能** —— 添加一次中心 marketplace，按名安装：
> ```
> /plugin marketplace add tkxlab-ai/marketplace
> /plugin install gitx@tkx-skills
> ```
> `install.sh`（见[快速开始](#快速开始)）仍可用于多 CLI 直接安装。

---

## 目录 Table of Contents

- [为什么需要 GitX](#为什么需要-gitx)
- [设计哲学](#设计哲学)
- [命令矩阵 Commands](#命令矩阵-commands)
- [方法论](#方法论)
- [快速开始](#快速开始)
- [架构](#架构)
- [测试](#测试)
- [安全模型](#安全模型)
- [参考与引用](#参考与引用)
- [兼容性](#兼容性)
- [贡献](#贡献)
- [许可](#许可)

---

## 为什么需要 GitX

手工发版会以可预测且昂贵的方式出错：

- **静默泄密**——一个绝对路径、一个私有 Git host、CHANGELOG 里的一个 token
  推上公开镜像，且无法撤回。
- **不可复现产物**——`tar` 内嵌 mtime、`gzip` 内嵌文件名；同一份源码每次
  打出的 tarball 都不同，没人能验证"我下载的就是你发布的那个"。
- **政策只是愿望**——"先跑测试"写在 wiki 里，发版人赶 deadline 时跳过。
  文档不是强制。
- **漂移**——根脚本与打包 bundle 分叉；文档写 `v0.9` 而代码是 `v1.7`；
  slash 命令装进宿主根本不扫描的目录。

GitX 存在的理由是：**上述每一种失败都是可计算谓词**。一条规则若能被脚本
检查，它就该让构建失败——而不是半年后一句 code review 评论。本项目是 30+
真实事故（每条都已固化为回归测试或审计闸）逐条从"踩过的坑"
转化为回归测试或审计闸的累积。

它帮你：

- 用**一条命令** + fail-closed 闸链发版一个 skill / 项目。
- 产出**逐字节可复现**的 source tarball（SLSA 式 provenance）。
- 每个版本附 **CycloneDX SBOM** + SHA-256 `checksums.txt`。
- 不泄漏私有 dev tree 地推向**公开 GitHub 镜像**（`/gitx-sop`），并让任何
  项目拥有自己的发版政策（`/gitx-init`）。

---

## 设计哲学

GitX 建立在四条承重原则上，每条都可追溯到一个具名思想：

1. **政策即代码**。每条发版规则都是会中止流水线的 shell 断言，绝非散文
   建议。内部政策 v2.2/v2.3 把 7 条"愿望式"规则转成 code-enforce 闸。
   血缘：*基础设施即代码 / 可执行规范* 传统。

2. **不变量优于约定**——*E. W. Dijkstra*。用可计算谓词取代模糊的人类
   判断：`diff -rq` 验双源一致、anchored `grep` 抓凭证类、exit-code 闸验
   测试。你*期望*成立的约定，被机器*证明*成立的不变量取代。见 Dijkstra,
   *A Discipline of Programming*（1976）。

3. **消除评估鸿沟（Gulf of Evaluation）**——*Donald A. Norman*。每个流水线
   步骤显式输出 `✅ / ❌ / ➖`，操作者永不需推断系统状态。出自 Norman,
   *The Design of Everyday Things*（1988）——"评估鸿沟"即系统状态与用户
   感知之间的落差；GitX 把它每步压到零。

4. **零硬编码、跨项目**。`PROJECT_NAME` / `SKILL_NAME` / `PROJECT_ROOT`
   全由环境推导，流水线里没有任何项目专属字面量。发布 GitX 自身的脚本
   原样发布任何 sibling 技能——已在多个项目生产验证。

第五条运维原则约束项目自身维护：**每个缺陷都变成一道 guard**。测试驱动
开发（*Kent Beck*, *Test-Driven Development: By Example*, 2002）red→green→
refactor 应用于每个行为；隐性运维知识按 *Nonaka & Takeuchi* 的 SECI 知识
转化模型（*The Knowledge-Creating Company*, 1995）外化进项目内部 dev log。

---

## 命令矩阵 Commands

| 动作 | 触发词 | 脚本 | 行为 |
|------|--------|------|------|
| 一键发版 | `/gitx-release` | `scripts/gitx-release.sh` | 自动 patch 递增 → 同步 SKILL.md + CHANGELOG → 全闸链；不自动 git push |
| 发版（指定版本）| `release <version>` | `scripts/release.sh` | 12 函数流水线：测试→打包→tarball→脱敏→平摊→证明→Deep Audit |
| 补审 | `audit <version>` | `scripts/release-audit.sh` | 对已有 `Release/<ver>/` 跑 40+ 静态检查（可断网）|
| 敏感扫描 | `scan <dir>` | `scripts/release-sanitize.sh` | 6 类：凭证 / 绝对用户路径 / 真实邮箱 / 公网 IP / MAC / SSH-GPG 指纹 |
| 项目初始化 | `/gitx-init` | `scripts/gitx-init.sh` | 生成 `.gitx/` 政策包 + `RELEASE_GUIDELINE.md`（auto-detect skill/mac/both/empty）|
| GitHub 发布 SOP | `/gitx-sop` | `scripts/gitx-sop.sh` | 生成 `.gitx/GITHUB_RELEASE_SOP.md`——占位符渲染的公开镜像 runbook，**只生成不执行 git/gh** |

> **硬约束**：`git tag` / `git push` / `gh release` 一律不由流水线自动化
> （TKX 政策 §10.10）。GitX 只产出本地 `Release/<version>/` 产物；推上游
> 永远是人工动作。

---

## 方法论

### 发版流水线（`release.sh`，12 个具名函数）

严格顺序执行；任一步非 0 即中止（无 `FORCE=1` 绕过——silent ghost release
护城河）：

| # | 函数 | 保证 |
|---|------|------|
| 1 | `preflight_checks` | 版本号语法 + SKILL.md 一致性 + CHANGELOG 闸 |
| 2 | `run_tests` | `tests/run_all.sh` 全绿否则 abort |
| 3 | `check_dual_source` | 根 `scripts/` ≡ bundle `scripts/`（`diff -rq`）|
| 4 | `build_skill_package` | 内嵌 Anthropic skill-creator 打 `.skill`（zip 回退）|
| 5 | `build_source_tarball` | 可复现 tarball（mtime 归一 + 排序）|
| 6 | `run_sanity_scans` | staging + 解压 `.skill` 双扫 6 类敏感信息 |
| 7 | `flatten_docs` | 9 文档 + scripts/ + references/ + commands/ + install.sh |
| 8 | `generate_attestations` | CycloneDX SBOM + token 用量 + `checksums.txt` |
| 9 | `generate_release_notes` | 3 安装路径 + CHANGELOG 注入 |
| 10 | `update_changelog` | 平摊 `Release/CHANGELOG.md` |
| 11 | `run_deep_audit` | `release-audit.sh --inline`，40+ 检查全绿否则 abort |
| 12 | `update_latest_symlink` | **审计通过后**原子 `ln -sfn` |

该顺序编码 **gate-then-ship 不变量**：`Release/latest` 永不指向未验证产物
（11 → 12 不可调换）。

### 可复现构建（SLSA 式 provenance）

`build_source_tarball` 消除 tar 三大不确定性：(a) `touch -t
$SOURCE_DATE_EPOCH` 归一 mtime，(b) `find | LC_ALL=C sort | tar
--no-recursion -T -` 固定遍历序，(c) `gzip -n` 去掉内嵌文件名/时间戳。
结果：同源 → 逐字节相同 tarball → 任何人可 `shasum -a 256 -c
checksums.txt` 离线验证。遵循 **SLSA** 构建 provenance 模型
（[slsa.dev](https://slsa.dev)）与 *reproducible-builds.org* 实践。

### 深度审计 Deep Audit

`release-audit.sh` 跑约 14 节 / 240 项纯静态分析（无网络）：spec 合规、
安装标准、`gitx-init`/`gitx-sop` 模板完整性（`§0c`/`§0d`）、doc 版本陈腐
（`§0e`）、双源一致、CHANGELOG 真实性、可复现性、脱敏复扫。三态输出
（`✅ PASS / ❌ FAIL / ➖ SKIP`）——Norman 原则的落地。

### 纵深防御

敏感信息在**三个独立边界**扫描：pre-release staging、解压 `.skill`
bundle、以及（`/gitx-sop`）公开 worktree——含一道*强制 post-redaction
验证 grep*，无论走哪条脱敏路径都 fail-closed 运行。

---

## 快速开始

### 方式 A —— Claude Code 插件（Claude Code 用户推荐）

<!-- gitx:managed:install -->
```bash
/plugin marketplace add tkxlab-ai/marketplace
/plugin install gitx@tkx-skills
```
<!-- /gitx:managed:install -->

插件命令在 `gitx` 插件下**强制命名空间化**（Claude Code 官方策略）：
`/gitx:release` `/gitx:sop` `/gitx:init` `/gitx:audit` `/gitx:scan`（不是扁平的
`/gitx-sop`）。更新：`/plugin marketplace update tkx-skills`。

### 方式 B —— `install.sh`（多 CLI：Claude Code · Codex · OpenCode · Gemini，扁平 `/gitx-sop`）

```bash
# 安装（克隆公开镜像）
git clone https://github.com/tkxlab-ai/GitX.git
cd GitX
./install.sh --dry-run        # 预览
./install.sh                  # 装到 ~/.agents/skills/gitx-release/（+ Claude/OpenCode symlink + ~/.claude/commands/ shim）
./install.sh --force          # 已有安装时重装（原地覆盖）
```

两条路径并存，二选一。插件 = 命名空间化、可 marketplace 更新、仅
Claude Code。`install.sh` = 扁平命令名、四个 CLI。

```bash
# 在任何 skills/<name>/SKILL.md 项目里使用
/gitx-release                 # 一键发版（自动 patch 递增）
release v1.2.0                # 指定版本
audit v1.2.0                  # 补审已有 release
scan ./some-dir               # 独立敏感扫描
/gitx-init                    # 在项目里生成 .gitx/ 政策包
/gitx-sop                     # 生成 GitHub 发布 runbook
```

Codex CLI：`/skills` 打开技能列表，或输 `$` 选 **GitX**（选择器
`$gitx-release`）。OpenCode / Gemini：说 "gitx release"。slash 子命令
（`/gitx-init`、`/gitx-sop`）在 install 后需 **新开 Claude Code 会话**
（命令在启动时加载）。

---

## 架构

```
gitx-release/
├── SKILL.md                  # skill 清单（name: gitx-release，品牌：GitX）
├── install.sh                # 四 CLI 安装器 + ~/.claude/commands/ shim
├── scripts/                  # 双源（根 ≡ skills/gitx-release/scripts/）
│   ├── gitx-release.sh       # wrapper：VERSION 递增 + CHANGELOG + 编排
│   ├── release.sh            # 12 函数流水线
│   ├── release-audit.sh      # Deep Audit（§0–§11）
│   ├── release-sanitize.sh   # 6 类敏感扫描器
│   ├── gitx-init.sh          # .gitx/ 政策生成器
│   ├── gitx-sop.sh           # GitHub 发布 SOP 渲染器
│   ├── lib/                  # detect-project、skill-creator-version、install-style
│   └── vendored/skill-creator/  # Anthropic skill-creator（Apache-2.0，pin）
├── commands/                 # slash shim（双源）→ ~/.claude/commands/
├── references/               # TKX 政策 v2.3、gitx-init/、gitx-sop/ 模板
├── tests/                    # 95+ BDD 套件（run_all.sh）
└── Release/                  # 生成产物 + CHANGELOG（不入 git）
```

**双源契约**：`scripts/` 与 `commands/` 在根与 `skills/gitx-release/` 下
逐字节一致；`check_dual_source` + 审计 `§9` 一旦漂移即 abort。根布局是
`install.sh` 读取的；bundle 是打进 `.skill` 的。

---

## 测试

<!-- gitx:managed:suite-count -->
102
<!-- /gitx:managed:suite-count -->

| 层 | 内容 | 数量 |
|----|------|------|
| BDD 套件 | `tests/run_all.sh`（red→green TDD，每 cycle 一断言）| **102 / 0 fail** |
| 深度审计 | `release-audit.sh` 静态闸（离线）| **240 PASS / 0 FAIL / 1 SKIP / ⚠️0** |
| 可复现性 | 跨次运行逐字节相同 tarball | 强制（`§5` + 专测）|
| 双源 | 根 ≡ bundle | 强制（`§9` + `check_dual_source`）|
| 独立审查 | Codex 对抗式 + review gate（authoring/review 分离）| clean |

每条已知坑（37+）都映射到一个回归测试或审计闸——
缺陷不会静默复发。

---

## 安全模型

- **不自动化上游**：流水线永不跑 `git push`/`gh release`。
- **Fail-closed 闸**：测试、脱敏、双源、Deep Audit、redaction 验证——任一
  失败即在产物被祝福前 abort。
- **公开镜像隔离**（`/gitx-sop`）：只把已脱敏、版本钉死的 release tarball
  推进独立 `.git` 的 per-release worktree；私有 remote 永不加入；token 仅
  env，push 后从 remote URL scrub。
- **供应链**：`install.sh` 校验 `checksums.txt`；内嵌 skill-creator 按
  upstream commit pin；每版本附 SBOM。

---

## 参考与引用

### 方法论与学术血缘

| 思想 | 用于 | 引用 |
|------|------|------|
| 不变量优于约定 | `diff -rq` 双源、谓词闸 | Dijkstra, *A Discipline of Programming*, 1976 |
| 评估鸿沟 | 每步 `✅/❌/➖` 输出 | Norman, *The Design of Everyday Things*, 1988 |
| 测试驱动开发 | 每个行为 red→green→refactor | Beck, *TDD: By Example*, 2002 |
| SECI / 隐性知识 | 内部 dev-log 设计 | Nonaka & Takeuchi, *The Knowledge-Creating Company*, 1995 |
| 语义化版本 | 版本契约 | [semver.org](https://semver.org)（Preston-Werner）|
| 构建 provenance | 可复现 tarball | [slsa.dev](https://slsa.dev)、[reproducible-builds.org](https://reproducible-builds.org) |
| SBOM | 依赖证明 | [CycloneDX](https://cyclonedx.org) 1.5（OWASP）|

### 软件与署名

- **[Anthropic skill-creator](https://github.com/anthropics/skills)**——
  Apache-2.0；内嵌于 `scripts/vendored/skill-creator/`（按 upstream commit
  pin），使 `.skill` 打包自包含且无需联网或插件市场即可复现。许可证原样
  保留。
- **superpowers `test-driven-development`** skill——本项目自身开发每个
  cycle 所遵循的 red→green 纪律。
- **Codex CLI**（OpenAI）——独立对抗式审查，保持 authoring 与 review 处于
  分离上下文。

### 内部文档

| 文档 | 用途 |
|------|------|
| [`references/TKX_Git_Release_policy_and_process.md`](references/TKX_Git_Release_policy_and_process.md) | 完整发版政策 v2.3（生命周期、pre-release 闸、脱敏、Deep Audit、低级错误库）|
| [`docs/SKILL_CROSS_CLI_GUIDELINE.md`](docs/SKILL_CROSS_CLI_GUIDELINE.md) | 跨 CLI skill 编写规范 |
| [`ROADMAP.md`](ROADMAP.md) | 通用化路线（非-skill 源码包）|

---

## 兼容性

| 要求 | 支持 |
|------|------|
| OS | macOS / Linux |
| Shell | Bash 3.2+（POSIX）；BSD 与 GNU coreutils 均处理 |
| git | 2.x |
| Python | 可选——`python3 + venv` 跑内嵌 skill-creator；缺失时确定性 zip 回退 |
| CLI | Claude Code · Codex · OpenCode · Gemini |

---

## 贡献

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。底线：每个改动 TDD（先写失败
测试）、双源保持逐字节一致、Deep Audit 保持全绿、authoring/review 分离
上下文。

## 许可

MIT — Copyright (c) 2026 TKXLAB.AI — <https://github.com/tkxlab-ai>
内嵌 `scripts/vendored/skill-creator/` 为 Apache-2.0（Anthropic），许可证
原地保留。

<div align="center">

**GitX** · TKX 通用发版流水线 · <https://github.com/tkxlab-ai/GitX>

</div>
