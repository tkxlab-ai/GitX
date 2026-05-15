# TKX Git Release Policy and Process

> **Purpose**: 一份可复用的 release 政策与流程标准，适用于 TKXLAB.AI 所有要推到 GitHub 的项目。
> **版本**: **v2.3**
> **Last updated**: 2026-04-21
> **Origin**: 从 Handoff skill v0.1 → v0.9.2 全流程演化 + 1by1 skill v0.3-β 发布实战总结。

---

## 🆕 v2.3 相对 v2.2 的升级（2026-04-21 当日 · 四坑一口气）

| 升级项 | 位置 | 动机（实战踩过） |
|-------|------|-------|
| **HANDOFF.md 历史 Dev Log 累积绝对路径泄漏** 🆕 | §10.4 新增行 | Handoff v0.9.1 首发：旧 Dev Log 条目里有 `/Users/<n>/tkbox/...` 等历史开发路径，sanity gate 命中 → 发版前必须 redact 为 `~/...` / `<sibling-project>/...` 占位 |
| **仓库根 `*.bak` 未被 rsync 通配 exclude** 🆕 | §10.3 新增行 | v0.9.1/v0.9.2 每次发版都要手动 stash `TKX_*policy*.v1.md.bak` 到 `/tmp`，因为 release.sh 只 `--exclude='HANDOFF.md.bak'`（具名）不通配 |
| **CLI 脚本 `${1:?}` 抛丑错 + 缺 `--help` + 无默认文件** 🆕 | §6.11 新增章节 | v0.9.2 整轮修的——5 脚本无参数应默认 `./HANDOFF.md`、`-h/--help` 清爽两行、`❌ file not found` 统一错误 |
| **CHANGELOG / RELEASE_NOTES 用字面 `/Users/...` 做示例被 sanity 命中** 🆕 | §10.4 新增行 | v0.9.1 发版 CHANGELOG 写 "redact 绝对路径（`/Users/jarvis/...` → `~/...`）" 被拦——示例路径必须也用占位符 |

---

## 🆕 v2.2 相对 v2.1 的升级（2026-04-21 当日）

| 升级项 | 位置 | 动机（实战踩过） |
|-------|------|-------|
| **双源脚本漂移 → silent ghost release** 🆕 | §4 / §8.1 / §10.1 / §12.5 | Handoff v0.9.1 首发：根 `scripts/` 改了 regex，skill bundle `skills/<n>/scripts/` 未同步；audit 只对比 bundle-vs-bundle（盲区），所以"40/40 通过"，但实际 shipped `.skill` 里还是旧代码。用户装上去 = 没修。**新规**：release.sh 前置、pre-flight、audit 必须 `diff -rq 根/scripts/ skill-bundle/scripts/`，不一致 abort。|

---

## 🆕 v2.1 相对 v2.0 的升级

| 升级项 | 位置 | 动机 |
|-------|------|------|
| **Pre-release 前置三要素** | §2.1 / §4 | gate 前先确认代码冻结 / 独立评审 / 无 blocking TODO |
| **Yank / 撤回流程** | §11.5 新增 | 发布后 24h 内发现严重问题的标准动作 |
| **git 历史脱敏** | §5.5 新增 | 当前文件净化 ≠ 历史净化；必须扫 git log 并 filter-repo |
| **install.sh 标准接口 + 禁止事项** | §6.10 新增 | 统一 `--dry-run/--force/--help`；禁止无备份 rm、隐式 sudo、联网下载 |
| **备份路径反例** | §10.1 扩展 | 备份不得放在工具扫描目录内（skills/.bak 被当新 skill） |
| **`.skill` 必须包含 commands** | §6.8 扩展 | 单文件安装缺 shim 导致 slash command 不可用是功能缺陷，不是可接受的取舍 |
| **Edit old_string 唯一性校验** | §2 扩展 | Edit 前先 Grep 确认唯一，再改；否则误替换他处 |
| **Pre-release 后缀 + GA 判据** | §3.2/§3.4 新增 | `-alpha/-beta/-rc.1` 语义 + GA 升级硬条件 |
| **10 分钟速检清单** | §12.5 新增附录 | 打包后推送前的肌肉记忆 10 条 grep |
| **ROADMAP 与 CHANGELOG 分离** | §7.5 新增 | CHANGELOG 只写已发布；未来计划归 ROADMAP.md |
| **72h 观察期 + 人类验证** | §8.5 新增 | 非作者读一遍 README；72h 无 P0 才考虑 pre-release → GA |
| **大文档分批写入（>200 行）** | §2 / §10.9 新增 | 禁止单次 Write 倾倒大内容；先 touch 骨架，再每轮 ≤200 行 append + read-back |

## 🆕 v2.0 相对 v1.0 的升级

| 升级项 | 位置 | 动机 |
|-------|------|------|
| **强制 Post-Release Deep Audit** | §8 | v1.0 只做 pre-release gate，用户发现后才知道产物错；v2.0 发版后立即自动回审 |
| **文档同步 pre-commit 检查** | §9 扩展 | 避免"Edit 没生效"之类低级错误 |
| **CHANGELOG 真实性验证** | §7 扩展 | 防止 TODO 占位进仓库 + 防止条目错配到其他版本 |
| **Release 目录平摊文档** | §6.6 升级 | 用户不解压就能浏览 6+ 份文档 |
| **Per-version 文件命名改 `RELEASE_NOTES.md`** | §6.7 | 避免和平摊的主 `README.md` 冲突 |
| **防呆清单扩展** | §10 从 8 类扩到 10 类 | 含 CHANGELOG 未同步、KB 写死、文件同名冲突等 |
| **Edit → Read-back 验证模式** | §2 新增 | 修改关键文件后立即回读确认，不假设 Edit 一定生效 |

---

## 📖 目录

- [1. 顶层原则](#1-顶层原则)
- [2. Release 生命周期](#2-release-生命周期)（§2.1 前置三要素 🆕）
- [3. 版本号规则（SemVer）](#3-版本号规则semver)（§3.2 pre-release 后缀 / §3.4 GA 判据 🆕）
- [4. 发版前强制检查清单（Pre-Release Gate）](#4-发版前强制检查清单pre-release-gate)
- [5. 脱敏与安全扫描需求](#5-脱敏与安全扫描需求)（§5.5 git 历史脱敏 🆕）
- [6. 文件产物标准](#6-文件产物标准)（§6.10 install.sh 标准接口 🆕）
- [7. CHANGELOG 规范](#7-changelog-规范)（§7.5 ROADMAP 分离 🆕）
- [8. Post-Release Deep Audit](#8-post-release-deep-auditv20-新增-)（§8.5 观察期 / §8.6 人类验证 🆕）
- [9. Release.sh 强制做的事](#9-releasesh-强制做的事)
- [10. 常见低级错误与防呆清单](#10-常见低级错误与防呆清单v20-扩展)
- [11. Git / GitHub 流程](#11-git--github-流程)（§11.5 Yank 流程 🆕）
- [12. 附录](#12-附录)（§12.5 10 分钟速检清单 🆕）

---

## 1. 顶层原则

| # | 原则 | 动机 |
|---|------|------|
| 1 | **幂等** | 同一命令跑多次结果一致 |
| 2 | **失败即停** | 测试 / sanity / audit 失败 → abort |
| 3 | **三态诚信** | `✅ 通过 / ⚠️ 发现 / ➖ 跳过`，永不伪装 |
| 4 | **文档先行** | 产物文档必须和当前源码同步 |
| 5 | **可计算谓词优先** | 能 grep 就不要 LLM 判断 |
| 6 | **原子提交** | 多文件 mutation 用 staging + atomic mv |
| 7 | **双保险脱敏** | 源码 + 打包产物都要扫 |
| 8 | **用户数据不可删** | 卸载只删 skill，保留用户文档 |
| 9 | **Edit → Read-back** | 改完关键文件立即回读验证，不假设 Edit 生效 |
| 10 | **Post-release audit** | 发版后强制深度回审，不等用户发现错 |
| 11 | **Install path > Code path** 🆕 | 用户拿到包第一件事是装；README 第一屏必须是装/升/回滚 |
| 12 | **评审不可自评** 🆕 | sub-agent 评自家产品天然偏高；至少 1 次独立视角或对抗 prompt |
| 13 | **可回滚** 🆕 | 任何发布必须附带可执行回滚命令，不能是"联系作者" |
| 14 | **大文档分批写入** 🆕 | 预估 > 200 行的文件：先 `touch` 创建空文件，再用 Edit/append 每轮 ≤ 200 行；禁止单次 Write 倾倒大内容 |

---

## 2. Release 生命周期（v2.0）

```
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ 开发迭代 │→│ 本地全绿 │→│ release  │→│ Deep     │→│ Git tag  │
│ + 文档   │  │ (99 用例)│  │ gate     │  │ Audit 🆕 │  │ + push   │
└──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘
                                  │              │
                                  v              v
                         ┌────────────┐   ┌────────────────┐
                         │ Release/   │   │ audit-report   │
                         │ vX.Y.Z/    │   │ 必须全绿才允许 │
                         │ (10+ files)│   │ 推 GitHub      │
                         └────────────┘   └────────────────┘
```

### 2.1 Pre-release 前置三要素 🆕

进入 Pre-Release Gate（§4）**之前**必须全部满足，否则不启动 release：

- [ ] **代码/内容冻结**：本次要发的改动已全部合入 release 分支，无 in-flight
- [ ] **独立评审完成**：至少 1 次非作者视角审查（code review 或专家复审；自评不算）
- [ ] **无阻塞 TODO**：源码 `grep -rE 'TODO|FIXME|HACK|XXX'` 的结果要么已修，要么已登记为 issue 并显式 defer

### 触发方式

| 方式 | 版本决策 |
|------|---------|
| 用户说 "release" / "发布" | 自动 patch+1（有新功能则 minor+1） |
| 用户说 "release v0.9" | 按指定 |
| CI tag 触发 | 按 tag |

### Edit → Read-back 模式（v2.0 强制 + v2.1 扩展）

修改 CHANGELOG / README / INSTALL / policy 这类关键文件后，**立即**读回验证：

```bash
# 反模式（v1.0 踩过）
edit CHANGELOG.md
cp CHANGELOG.md Release/   # ← 没确认 Edit 生效就复制，结果复制的是旧的

# 正确模式（v2.0）
edit CHANGELOG.md
head -25 CHANGELOG.md | grep -q "期望的新内容" || abort "Edit 未生效"
cp CHANGELOG.md Release/
```

**Edit old_string 唯一性校验（v2.1 新增 🆕）**：

1by1 实战踩过：Edit 的 `old_string` 非唯一，覆盖了他处内容（Problem 3 改动误替换了 Problem 2）。规避：

```bash
# Edit 前先数一下命中次数
rg -cF "<old_string fragment>" target_file
# 必须 = 1；若 > 1，扩大 old_string 上下文直至唯一，或使用 replace_all 并自验
```

### 大文档分批写入（v2.1 强制 🆕）

**原则**：任何预估超过 200 行的文档/脚本，**禁止**单次 Write 一次性写入。

**动机**：
- 大块 Write 出错率高（截断 / 编码 / 上下文耗尽 / tool-call 失败后难定位回滚点）
- 审阅者无法逐段 review，容易引入低级错误
- 与 `Edit → Read-back`（§2 原则 9）冲突 —— 单次倾倒无法即时回读验证

**强制流程**：

| 步骤 | 动作 |
|------|------|
| 1 | 预估文件行数；> 200 行 → 进入分批模式 |
| 2 | 先创建**骨架文件**：`touch file.md` 或 Write 一个 ≤ 100 行的 TOC + 占位锚点 |
| 3 | 每轮用 Edit（或 append 模式 Write）追加一段，**单轮 ≤ 200 行** |
| 4 | 每轮写完立即 Read-back 验证（§2 原则 9）：`head` / `tail` / `wc -l` 确认 |
| 5 | 关键锚点（章节标题、命令块）用 `grep -c` 断言数量 |
| 6 | 全部写完再跑 §12.5 的 10 分钟速检 |

**示例**：

```bash
# 反模式（禁止）
Write file.md  <800 行一次性倾倒>

# 正确模式
touch file.md
Edit file.md  # 写骨架 + TOC（≤100 行）
wc -l file.md  # 读回确认
Edit file.md  # 追加 §1-§3（≤200 行）
wc -l file.md  # 再次读回
# ...直到完成
grep -c "^## " file.md  # 断言章节数 = 预期
```

**release.sh 必查**：任何自动生成的 `RELEASE_NOTES.md` / `CHANGELOG.md` 段落，若 > 200 行，CI 应 warn（软警告）并建议拆分。

---

## 3. 版本号规则（SemVer）

### 3.1 基础三段

**格式**：`vMAJOR.MINOR.PATCH`（PATCH 可省略）

| 位 | 何时升 | 例 |
|----|-------|---|
| MAJOR | 破坏性变更 / 老数据不可读 / 必须迁移 | v0.x → v1.0 |
| MINOR | 新增功能，向后兼容 | v0.8 → v0.9 |
| PATCH | Bug 修复 / 文档修订 | v0.8 → v0.8.1 |

release.sh 必须正则验证 `^v[0-9]+\.[0-9]+(\.[0-9]+)?(-(alpha|beta|rc)\.?[0-9]*)?$`。

### 3.2 Pre-release 后缀（v2.1 新增 🆕）

格式：`vX.Y.Z-{stage}[.N]`

| 后缀 | 语义 | 稳定承诺 |
|------|------|---------|
| `-alpha.N` | 内部探索 | 接口可能随时变 |
| `-beta` / `-beta.N` | 功能冻结，public 可试用 | 预期有 bug，接口不再大改 |
| `-rc.N` | Release candidate | 除非发现阻塞 bug 否则直升 GA |
| 无后缀 | GA（General Availability） | 生产可用 |

### 3.3 版本号三处一致

同一版本号必须在**三处**完全同步，任一漂移即 abort：

1. 程序可读字段：`SKILL.md` metadata / `package.json` / `pyproject.toml` 的 version
2. 人类可读：`CHANGELOG.md` 本版段标题
3. 发布物命名：`Release/vX.Y.Z/` 目录名 + `.skill` / `.tar.gz` 文件名

**反例**（1by1 v0.3 踩过）：metadata 写 `1.2.0-beta`，目录叫 `1by1-v0.3`，文档混用 `v0.3-alpha / v0.3-β`。读者无法判断本版真实阶段。

### 3.4 Pre-release → GA 硬判据（v2.1 新增 🆕）

从任何 pre-release 升 GA 必须**全部**满足：

- [ ] 至少 **2 周**无新 breaking 改动
- [ ] TEST-SCENARIOS 全部通过（不是 70%）
- [ ] 对公开项目：至少 **3 位**独立用户的反馈已收敛
- [ ] CHANGELOG 的 breaking changes 列表稳定（无最后一刻追加）

---

## 4. 发版前强制检查清单（Pre-Release Gate）

| # | 检查项 | 失败后果 |
|---|-------|---------|
| 0 | 前置三要素（§2.1）全过 🆕 | abort（根本不启动 release） |
| 1 | `tests/run_all.sh` 全 PASS | abort |
| 2 | Staging 脱敏扫描 clean | abort |
| 3 | `.skill` 解压后再扫 clean | abort |
| 4 | 版本号格式合规 + 三处一致（§3.3） | abort |
| 5 | CHANGELOG 顶部有当前版本条目（非 TODO） | abort |
| 6 | 根目录有 README / INSTALL / CHANGELOG / TEST-SCENARIOS / LICENSE | abort |
| 7 | install.sh 符合 §6.10 标准接口 🆕 | abort |
| 8 | git 历史无 secret 泄漏（§5.5） 🆕 | abort |
| 9 | `.skill` 包含 commands/ 目录（§6.8） 🆕 | abort |
| 10 | Release/ 目录可清理重建 | 自动 |
| 11 | **双源脚本一致性** 🆕 v2.2 — `diff -rq 根/scripts/ skill-bundle/scripts/`（共享名文件 byte-identical） | abort（silent ghost release 的唯一护城河） |

---

## 5. 脱敏与安全扫描需求

### 5.1 6 类敏感信息

| 类别 | 检测模式 | 豁免 |
|------|---------|------|
| 🔐 凭证 | OpenAI / Anthropic / GitHub / AWS / Slack / Supabase / Private Key 前缀 | — |
| 📁 绝对用户路径 | `/Users/<n>/` `/home/<n>/` `C:\Users\<n>\` | `<user>` `<your-user>` `<name>` 占位符 |
| 📧 真实邮箱 | `u@d.tld` | example.com / test.com / localhost / yourco / placeholder |
| 🌐 公网 IP | IPv4 | 127/10/192.168/172.16-31 / 1.1.1.1 / 8.8.8.8 / 169.254.* |
| 🔌 MAC | `aa:bb:cc:dd:ee:ff` | — |
| 🔑 SSH/GPG 指纹 | `SHA256:...` / `ssh-rsa AAAA...` | — |

### 5.2 豁免目录

- `tests/fixtures/` — 故意的脏测试数据
- `tests/test_*_sanitize.sh` / `test_scan_credentials.sh` — meta 测试
- `scripts/release-sanitize.sh` / `scan-credentials.sh` — 扫描器的正则文档
- `*/evals/*` — eval 数据
- `Release/` / `.git/`
- **`TKX_Git_Release_policy_and_process.md`** 🆕 — 本文件含反例举例
- **`TEST-SCENARIOS.md`** 🆕 — 含反例举例

### 5.3 双扫描时机

1. 扫 staging 目录
2. 扫 **解压后** 的 `.skill` 内容

### 5.4 作者个人信息处理

| 项 | 处理 |
|----|------|
| 家目录 / 用户名 | `$HOME` / `~` / `<user>` 替代 |
| 内部项目名 | 删或 `<internal-project>` |
| 私有邮箱 | 换 `user@example.com` |
| `.claude/settings.local.json` | 进 `.gitignore` |

### 5.5 git 历史脱敏（v2.1 新增 🆕）

**核心认知**：当前文件净化 ≠ git 历史净化。即使 HEAD 已清洁，历史 commit 可能仍含秘密。Push 到公开远端后再清理**为时已晚**（已被克隆 / 索引）。

**Pre-release gate 必扫**：

```bash
# 1. 扫历史中的 secret 形状
git log --all --source --remotes -S'sk-' --oneline
git log --all -p | rg -iP 'api[_-]?key|secret|password|token' | head -50

# 2. 扫历史中的个人绝对路径
git log --all -p | rg -n "/Users/\w+|/home/\w+" | head -20

# 3. 扫曾 commit 后删除的敏感文件名
git log --all --diff-filter=D --name-only | rg -iE '\.env$|credentials|id_rsa|\.pem$'
```

**若发现历史泄漏，按顺序**：

1. **立刻吊销该 secret**（不管历史怎么处理，假设它已泄漏）
2. 用 `git filter-repo`（**不是** `filter-branch`，后者已 deprecated）重写历史
3. Force-push 到公开远端；通知已 clone 的人 re-clone
4. 私有远端可跳过 force-push，但 secret 吊销仍必须

### 5.6 自动化脱敏工具建议（v2.1 🆕）

- **gitleaks** — CI 集成首选，规则丰富
- **trufflehog** — 深度历史扫描，熵检测
- **git-secrets**（AWS Labs）— pre-commit hook 简单可靠
- **detect-secrets**（Yelp）— 基于熵 + 过滤器

**TKX 基线**：pre-commit 装 `git-secrets`；CI 跑 `gitleaks`。

---

## 6. 文件产物标准

### 6.1 根目录必须有的文件

| 文件 | 用途 |
|------|------|
| `README.md` | 项目说明（Philosophy / Logic）|
| `INSTALL.md` | 操作手册（装 / 升 / 删 / 修）|
| `CHANGELOG.md` | 全版本历史 |
| `TEST-SCENARIOS.md` | 验证场景手册 |
| `LICENSE` | MIT |
| `CONTRIBUTING.md` | 贡献约定 |
| `install.sh` | 幂等安装脚本 |
| `release.sh` | 发版脚本 |
| `TKX_Git_Release_policy_and_process.md` | 本政策（每个 TKXLAB 项目都应有）|

**pre-release gate 必须检查这些文件存在**，否则 abort。

### 6.2 README.md 标准

**定位**：讲 "是什么、为什么值得用、怎么想的"。

必含：一句话定位 / License badge / 目录 / 1. 为什么需要 / 2. **设计哲学（Philosophy）** / 3. **逻辑结构（Logical Model）** / 4. 工作原理 / 5. 核心命令 / 6. 装升删（只列最基础命令，详细跳 INSTALL.md）/ 7. 目录结构 / 8. 许可与贡献。

禁止：CLI 参数矩阵、排错、dev-only 内容。

### 6.3 INSTALL.md 标准

**定位**：所有"怎么装、怎么升、怎么删、怎么查"的命令 + 注解。

必含 9 节：0. 文件位置速查表 / 1. 安装（多方式）/ 2. 首次项目初始化 / 3. 升级 / 4. 卸载 / 5. 验证 / 6. 发版（开发者）/ 7. 日常维护 / 8. 排错（至少 6 种问题）。

每条 bash 命令**必须附注解**；禁止绝对路径。

### 6.4 TEST-SCENARIOS.md 标准

必含 5 维场景：Happy / 边界 / 错误 / 安全 / 幂等。每场景 4 字段：**Setup / Action / Expected / Verify**（机器可验证优先）。

### 6.5 LICENSE + Copyright

MIT 文本见附录。SKILL.md 和主 README 末尾必须追加 License section，带 TKXLAB.AI 版权行。

### 6.6 Release/vX.Y.Z/ 目录结构（v2.0）

用户下载后**不解压**就能看到：

```
Release/vX.Y.Z/
├── handoff-vX.Y.Z.skill              分发包 A
├── handoff-vX.Y.Z-source.tar.gz      分发包 B
├── README.md                         ← 从根拷的（平摊）
├── INSTALL.md                        ← 从根拷的
├── CHANGELOG.md                      ← 从根拷的
├── TEST-SCENARIOS.md                 ← 从根拷的
├── LICENSE                           ← 从根拷的
├── CONTRIBUTING.md                   ← 从根拷的
├── SKILL.md                          ← 从 skill bundle 拷的
└── RELEASE_NOTES.md                  ← 本版本特有（release.sh 生成）
```

**关键规则（v1.0 踩过的坑）**：
- ❌ per-version 文件**不能**叫 `README.md` —— 会覆盖平摊的主 README
- ✅ 改叫 `RELEASE_NOTES.md`，只写本版本独有信息

### 6.7 RELEASE_NOTES.md 标准（v2.0）

release.sh 自动生成。内容：

- 分发包清单（**不写死 KB 数字**，避免过时）
- 平摊文档清单
- 快速安装（A/B 两种）
- 指向 `CHANGELOG.md` 的 `vX.Y.Z` 条目

### 6.8 Skill .skill 文件

`.skill` 本质是 zip。必须通过 `skill-creator` 的 `✅ Skill is valid!`。大小目标 < 50 KB。

**`.skill` 必须包含 slash command shims（v2.1 强制 🆕）**

单文件 `.skill` 安装是用户最常用的轻量安装方式。**缺少 commands = 缺少基本功能**，不是可接受的简单性取舍。

**要求**：`.skill` 解压后必须同时包含 skill 本体和 commands 目录：

```
<name>/                    ← skill 本体（解压到 ~/.claude/skills/）
  ├── SKILL.md
  ├── references/
  ├── scripts/
  └── assets/
commands/                  ← slash command shims（解压到 ~/.claude/commands/）
  ├── <name>.md
  ├── <name>-<sub1>.md
  └── <name>-<sub2>.md
```

**安装命令相应调整为**：

```bash
mkdir -p ~/.claude/skills ~/.claude/commands
unzip -o ./<name>-vX.Y.Z.skill -d ~/.claude/skills/   # skill 本体
unzip -oj ./<name>-vX.Y.Z.skill "commands/*" -d ~/.claude/commands/  # shims
chmod +x ~/.claude/skills/<name>/scripts/*.sh
```

或由 release.sh 在 `.skill` 内附带一个 `install-skill.sh` 脚本，用户只需：

```bash
unzip -o ./<name>-vX.Y.Z.skill -d /tmp/<name>-install
bash /tmp/<name>-install/install-skill.sh
rm -rf /tmp/<name>-install
```

**Pre-release gate 检查**：

```bash
# .skill 必须包含 commands/ 目录
unzip -l *.skill | grep -q "commands/" || abort ".skill 缺少 commands/"
```

**反例**（Handoff v0.9 踩过）：`.skill` 只打包了 `handoff/` 目录，缺少 `commands/handoff*.md`。用户用 `unzip -d ~/.claude/skills/` 安装后，`/handoff-recall` 和 `/handoff-tidy` 无法独立补全，被 fuzzy 匹配成 `/handoff`——基本功能丧失。

### 6.9 Source Tarball

**必须排除**：
```
.git/ Release/ .claude/ .DS_Store *.bak *.pyc __pycache__
tests/.tmp/ handoff.skill skills/*-workspace/ commands/
```

大小目标 < 100 KB。

### 6.10 install.sh 标准接口（v2.1 新增 🆕）

**必须提供的参数**：

| 参数 | 行为 | 必需性 |
|------|------|-------|
| `(无参)` | 默认安装到 `~/.claude/skills/<name>/` | 必需 |
| `--dry-run` | 只打印将做的事，不写任何文件 | 必需 |
| `--force` | 同版本也覆盖（默认同版本应跳过） | 必需 |
| `--prefix <path>` | 自定义安装根目录 | 推荐 |
| `--no-backup` | 跳过备份（配合 CI / 容器场景） | 推荐 |
| `--help` | 打印用法 + 退出码说明 | 必需 |

**必须做的事**：

1. 检测当前已装版本（if any），决定 skip / overwrite / upgrade
2. 备份到**工具扫描目录之外**的位置（见 §10.1 反例）
3. 保留用户数据（`preferences.md` / `config.json` / sessions），安装完恢复
4. 结束时打印 "下一步" 提示 + **回滚命令**（原则 §1.13）

**禁止的行为**：

| 禁止 | 原因 |
|------|------|
| `rm -rf "$DEST"` 而不先备份 | 除非 `--no-backup` 显式传入 |
| 隐式 sudo | 任何提权必须前置 echo 警告并要求确认 |
| 联网下载 release 内容 | release 包应自带一切；需联网写独立 `bootstrap.sh` |
| 触碰用户数据目录 | 代码目录与数据目录严格分离 |

**退出码约定**：

- `0` — 安装成功（包括 idempotent skip）
- `1` — 安装失败（任何写失败 / 脱敏失败 / 版本不兼容）
- `2` — 参数错误 / `--help`

### 6.11 CLI 脚本统一规范（v2.3 新增 🆕）

适用于项目 `scripts/` 下所有用户会手动调用的辅助脚本（validate / tidy / scan / rotation / archive 等）。统一体感 = 减少认知负担。

**必须做到**：

| 规范 | 反例 | 正例 |
|------|------|------|
| **无参数有默认** | `FILE="${1:?Usage:...}"` — bash 抛 `line 6: 1: Usage:` 丑错误 | `FILE="${1:-HANDOFF.md}"`，用户在项目根直跑 `./scripts/validate-handoff.sh` 即工作 |
| **`-h/--help` 有清爽输出** | 没 help，只有 `${1:?}` | `case "${1:-}" in -h\|--help) echo "Usage: $0 [file]"; echo "Exit: 0 ok / 1 ... / 2 ..."; exit 0;; esac` |
| **文件不存在错误统一** | `file not found: X` 单行 stderr | `echo "❌ file not found: $FILE" >&2; echo "   Usage: $0 [file]" >&2; exit 2` — emoji + usage hint 双行 |
| **退出码三档** | 所有情况 exit 0 或 exit 1 混用 | 0 = clean / 1 = findings / 2 = usage or file missing（与 §6.10 install.sh 一致）|
| **stdin 兼容**（仅 filter 类如 scan）| 只读文件不接 pipe | arg > stdin > default file 三级回落 |

**模板**（直接复用）：

```bash
#!/bin/bash
# xxx.sh — 一句话说明
# usage: xxx.sh [file]    (default: ./HANDOFF.md)
# exit:  0 ok / 1 findings / 2 file not found

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [file]   (default: ./HANDOFF.md)"
        echo "Exit: 0 ok / 1 findings / 2 file not found"
        exit 0
        ;;
esac

FILE="${1:-HANDOFF.md}"
if [ ! -f "$FILE" ]; then
    echo "❌ file not found: $FILE" >&2
    echo "   Usage: $0 [file]   (default: ./HANDOFF.md)" >&2
    exit 2
fi
```

**动机**（Handoff v0.9.2 实战）：用户在项目根输入 `./scripts/validate-handoff.sh`（无参数），直接碰到 bash `${1:?}` 参数展开的原始格式——`./scripts/validate-handoff.sh: line 6: 1: Usage: ...`——不符合 CLI 工具应有的体感。5 个脚本批量统一后，无参数自动默认 `./HANDOFF.md`，`-h/--help` 输出两行标准格式，错误消息 `❌ file not found:` 带 usage hint。

---

## 7. CHANGELOG 规范

### 7.1 格式

```markdown
# <项目名> — Release History

记录各版本的关键变化。最新版本在最上面。

## vX.Y.Z — YYYY-MM-DD

**一句话主题**

- ✨ 新增：...
- 🔧 修复：...
- 💥 破坏性：...
- 🗑️ 移除：...
- 📝 文档：...

Artifacts: `Release/vX.Y.Z/`

---
```

### 7.2 规则

- 最新在最上面
- 每条变更用 emoji 分类（✨🔧💥🗑️📝）
- **绝对禁止**留 `<!-- TODO -->` 占位符进 git（release.sh 必须检查）
- **变更内容必须属于本版本**（v1.0 踩过：把 v0.8 的 "tarball 瘦身" 误归到 v0.9）
- 引用 `Artifacts: Release/vX.Y.Z/` 便于查找

### 7.3 CHANGELOG 真实性验证（v2.0 新增）

release.sh 和 post-release audit 都要检查：

```bash
# 1. 无 TODO 占位
grep -q "<!-- TODO" CHANGELOG.md && abort "CHANGELOG 有 TODO 占位"

# 2. 顶部版本号与本次 release 一致
first_version=$(grep -m1 '^## v' CHANGELOG.md | awk '{print $2}')
[ "$first_version" = "$VERSION" ] || abort "CHANGELOG 顶部不是 $VERSION"

# 3. 本版本条目内容不应提及其他版本号（除了"合并进 vX.Y"这种显式引用）
# （AI 辅助 review，不强制）
```

### 7.4 CHANGELOG 三处同步

```
根目录/CHANGELOG.md                        ← 主副本（开发者编辑）
Release/CHANGELOG.md                       ← 累积历史（release.sh 维护）
Release/vX.Y.Z/CHANGELOG.md                ← 平摊副本（release.sh 从根复制）
```

**Edit → Read-back**：改完根目录 CHANGELOG，立即：

```bash
head -25 CHANGELOG.md | grep -q "^## vX.Y.Z" || abort
diff CHANGELOG.md Release/CHANGELOG.md && echo same || abort "CHANGELOG 没同步"
```

### 7.5 CHANGELOG 与 ROADMAP 分离（v2.1 新增 🆕）

**原则**：CHANGELOG **只写已发布**；未来计划、未尽事项、候选功能一律归 `ROADMAP.md`。

**反例**（1by1 实战）：CHANGELOG 里列 "未尽事项 → v0.4 候选"，既污染本版变更视图，又和 ROADMAP 重复。用户翻 CHANGELOG 是为了查"本版变了什么"，不是"作者下版想做什么"。

**ROADMAP.md 标准**（可选但推荐，项目根）：

```markdown
# ROADMAP

## v0.next（计划中）
- [ ] 功能 A — priority:P1 — owner:X — rationale:...

## v1.0 候选
- [ ] 功能 B — 需要先收敛 X

## 长期愿景
- 方向 1：...
```

---

## 8. Post-Release Deep Audit（v2.0 新增 🆕）

**动机**：v1.0 只有 pre-release gate。今天发现 pre-release 过了，产物内部照样有问题（RELEASE_NOTES 写死大小、CHANGELOG 条目错配、per-version README 覆盖主 README、文件未同步等）。**v2.0 强制在 release.sh 末尾自动跑 deep audit**，未全绿不允许推 GitHub。

### 8.1 Audit 必查 11 项

| # | 检查项 | 如何验证 |
|---|-------|---------|
| 1 | `Release/vX.Y.Z/` 存在且包含 ≥ 10 个文件 | `ls Release/vX.Y.Z/ | wc -l` |
| 2 | 6 份平摊文档存在 | `for f in README INSTALL CHANGELOG TEST-SCENARIOS LICENSE CONTRIBUTING; do test -f Release/vX.Y.Z/$f.md || fail; done` |
| 3 | 平摊文档与根目录字节级相同 | `diff $f ../../$f` 必须 0 退出 |
| 4 | SKILL.md 平摊版 = skill bundle 版 | `diff Release/vX.Y.Z/SKILL.md skills/*/SKILL.md` |
| 5 | `.skill` 解压内容 = `skills/<name>/` 源（除 evals/）| `unzip + diff -r` |
| 6 | `.skill` 文件有效 | `skill-creator validate` 或再解压自检 |
| 7 | source tarball 能成功解压且含 install.sh | `tar tzf | grep -q install.sh` |
| 8 | source tarball **不含**被排除目录 | `tar tzf | grep -qE 'Release/\|handoff-workspace\|.claude/settings.local' && fail` |
| 9 | CHANGELOG 顶部版本号 = 本次 release 版本 | `head -10 | grep -q "^## $VERSION"` |
| 10 | CHANGELOG 无 TODO 占位 | `grep -q "<!-- TODO" && fail` |
| 11 | RELEASE_NOTES.md 不包含硬编码的 KB 数字（易过时）| `grep -E '[0-9]+ KB' && warn`（软警告）|
| 12 | 所有文档无 sanity 敏感信息 | 二次运行 `release-sanitize.sh` |
| 13 | Per-version 文件不叫 `README.md`（避免冲突）| `test ! -f Release/vX.Y.Z/README.md.release-only` 类型的区分 |
| 14 | **双源脚本 byte-identical** 🆕 v2.2 | `diff -rq <root>/scripts/ <root>/skills/<n>/scripts/` 仅显示 dev-only 工具（如 `release-*.sh`）；任何同名文件 diff 即 FAIL。<br>**盲区故事**：之前 audit 只做 `.skill` vs bundle（横向），不做 bundle vs dev-source（另一横向），所以修改根 scripts 而忘同步 bundle 会 silent-ship 旧代码。 |

### 8.2 Audit 脚本：`scripts/release-audit.sh`

**输入**：`release-audit.sh <version>`
**输出**：逐项 PASS/FAIL 报告
**退出码**：0 全绿 / 1 有 FAIL / 2 usage 错误

```bash
#!/bin/bash
# release-audit.sh — post-release deep audit
set -u
VERSION="${1:?Usage: $0 vX.Y.Z}"
DIR="Release/$VERSION"
FAIL=0
check() { if "$@"; then echo "  ✅ $TITLE"; else echo "  ❌ $TITLE"; FAIL=$((FAIL+1)); fi }

# 1. 基础存在性
TITLE="目录存在"; check test -d "$DIR"
TITLE=".skill 存在"; check test -f "$DIR"/*.skill
TITLE="tarball 存在"; check test -f "$DIR"/*.tar.gz

# 2. 平摊文档存在
for f in README INSTALL CHANGELOG TEST-SCENARIOS LICENSE CONTRIBUTING; do
    TITLE="$f.md 平摊"; check test -f "$DIR/$f.md"
done
TITLE="SKILL.md 平摊"; check test -f "$DIR/SKILL.md"
TITLE="RELEASE_NOTES.md 存在"; check test -f "$DIR/RELEASE_NOTES.md"

# 3. 平摊文档与根同步
for f in README INSTALL CHANGELOG TEST-SCENARIOS LICENSE CONTRIBUTING; do
    TITLE="$f.md 与根同步"
    check diff -q "$DIR/$f.md" "./$f.md" >/dev/null
done

# 4. CHANGELOG 真实性
TITLE="CHANGELOG 顶部版本 = $VERSION"
check grep -q "^## $VERSION " "$DIR/CHANGELOG.md"
TITLE="CHANGELOG 无 TODO 占位"
check ! grep -q "<!-- TODO" "$DIR/CHANGELOG.md"

# 5. Tarball 不含 dev-only
tar tzf "$DIR"/*.tar.gz > /tmp/tar-list
TITLE="tarball 不含 Release/"
check ! grep -q "Release/" /tmp/tar-list
TITLE="tarball 不含 workspace/"
check ! grep -q "handoff-workspace" /tmp/tar-list
TITLE="tarball 含 install.sh"
check grep -q "install.sh" /tmp/tar-list

# 6. .skill 与 source bundle 一致
TMP=$(mktemp -d)
unzip -q "$DIR"/*.skill -d "$TMP"
TITLE=".skill SKILL.md = bundle 版"
check diff -q "$TMP"/*/SKILL.md skills/*/SKILL.md >/dev/null
rm -rf "$TMP"

# 7. Sanity 二次扫描
TITLE="sanitize 二次扫描（平摊文档）"
check bash scripts/release-sanitize.sh "$DIR" >/dev/null 2>&1 || true  # warn only

echo ""
if [ "$FAIL" = "0" ]; then
    echo "🎉 Deep audit PASS — 可推 GitHub"
    exit 0
else
    echo "❌ Deep audit FAIL — $FAIL 项问题，禁止 push"
    exit 1
fi
```

### 8.3 集成到 release.sh

release.sh 最后强制调用：

```bash
# ... 前面所有步骤 ...
echo "🔍 Running post-release deep audit..."
if ! bash scripts/release-audit.sh "$VERSION"; then
    echo "❌ Audit 失败，已生成的产物可能不完整"
    echo "   修复后用 'rm -rf Release/$VERSION && ./release.sh $VERSION' 重跑"
    exit 1
fi
```

### 8.4 Audit 未过不允许 push

`git push` 前，CI 或 pre-push hook 应运行 audit。人工推之前至少跑一次：

```bash
bash scripts/release-audit.sh v0.9 && git push --tags
```

### 8.5 发布后观察期（v2.1 新增 🆕）

Post-release audit 只保证产物结构合法，**不**保证真实可用性。发布后观察期是第二道网：

| 窗口 | 动作 | 触发后果 |
|------|------|---------|
| **24h** | 监控 issue tracker / 反馈渠道；作者本人再装一次新系统 | 发现 P0 → 24h 内发 `X.Y.(Z+1)` hotfix **或** yank（§11.5） |
| **72h** | 持续收集反馈 | 72h 无 P0 才考虑 pre-release → GA 转正 |
| **2 周** | Breaking changes 列表稳定 | 配合 §3.4 其它判据才可升 GA |

### 8.6 人类验证（v2.1 新增 🆕）

自动化 audit 检不出"外行友好度"。Pre-release gate 过后、公开推之前：

- [ ] 至少 **1 位非作者**通读 README 和 INSTALL，无需追问就能完成安装
- [ ] 若本版有 breaking：至少 **1 位用户**按 migration guide 实际走一遍
- [ ] 若是 Skill 类：在**干净的 Claude Code 会话**中真实触发 ≥ 3 个 TEST-SCENARIOS 剧本

**反例**（1by1 iteration-3 踩过）：专家复审只审了文档，没在 Claude Code 里真跑剧本。结果文档分数都过了，实际 trigger 路径未验证。

---

## 9. Release.sh 强制做的事（v2.0 流程）

顺序 + 通过条件：

```bash
./release.sh v0.9
```

1. **版本号验证**（正则）
2. **根目录必备文件存在性检查**（§6.1 清单）🆕
3. **跑回归**（全 PASS）
4. **CHANGELOG 真实性检查**（§7.3）🆕
5. **Staging rsync**（排除 dev-only）
6. **Staging 脱敏扫描** ← gate 1
7. **打 `.skill`**
8. **`.skill` 解压再扫** ← gate 2
9. **打 source tarball**
10. **平摊 6 份核心文档 + SKILL.md 到 Release/vX.Y.Z/**
11. **生成 per-version `RELEASE_NOTES.md`**（不写死 KB 数字）
12. **更新 `Release/latest` 软链接**
13. **同步 `Release/CHANGELOG.md` = 根 CHANGELOG**
14. **Post-release deep audit** ← gate 3 🆕
15. **打印下一步建议**（git tag、push、gh release create）

**不自动做**：
- 不自动 `git tag` / `push`
- 不自动发 GitHub Release
- 不自动 `FORCE=1`

---

## 10. 常见低级错误与防呆清单（v2.0 扩展）

### 10.1 产物内容不同步 + 备份路径

| 错误 | 如何防 |
|------|-------|
| 改完 README/INSTALL 忘重打 | release.sh 改文档后必须 `rm -rf Release/vX.Y.Z && ./release.sh vX.Y.Z` |
| `.skill` 里 SKILL.md 是旧版 | scripts 改动先复制到 `skills/<n>/scripts/`，再打包 |
| per-version README 硬编码模板 | 改叫 RELEASE_NOTES.md + 平摊主 README |
| 根目录缺 CHANGELOG/TEST-SCENARIOS | pre-release gate §6.1 强制检查 |
| `Release/vX.Y.Z/` 顶层只有压缩包 | release.sh 平摊 6 份核心 + SKILL.md |
| sanity 误报新 meta 文档 | 立即加入 `release-sanitize.sh` 豁免；别 FORCE |
| **备份放在工具扫描目录内被误识别**（1by1 E1 🆕）| 备份一律到 `~/.claude/skills-backup/`，**不要**用 `~/.claude/skills/<n>.bak-*`（Claude Code 会把它当新 skill 列出）|
| **dev 源与 release 目录双向漂移** 🆕 | release.sh 只读 dev 源 → 生成 release；**禁止**手改 release 目录 |
| **用户数据与 skill 代码混放** 🆕 | preferences / sessions 必须在 `{cwd}/.{skill-name}/`，不得进 skill 目录 |
| **双源脚本 silent ghost release**（Handoff v0.9.1 首发踩过）🆕 v2.2 | 仓库内同一脚本有两个副本——根 `scripts/`（用于开发/测试/dev-only 工具）和 skill bundle `skills/<n>/scripts/`（随发版分发）。改一份忘同步另一份时，audit 若只对比 `.skill` vs bundle（同一份自比），则看不到分歧，**shipped 产物悄悄带旧代码**。<br>**防**：①每次编辑任一份立即 `cp` 到另一份；②release.sh 在 build 之前强制 `diff -rq 根/scripts/ skill-bundle/scripts/`（只允许 dev-only 工具单边存在），不一致直接 abort；③更激进的选项：根 `scripts/` 改为 symlink 指向 bundle，物理消灭双副本。 |

### 10.2 CHANGELOG 错配 🆕

| 错误 | 如何防 |
|------|-------|
| TODO 占位进仓库 | pre-release + audit 双检查 |
| 把上一版变更误归本版 | AI 填 CHANGELOG 时对比上一版 CHANGELOG，看字段是否重叠 |
| 漏记本版真实变更（今天真实踩过）| 发版前 grep `git log` 或对话上下文，列出本版新增文件 / 修改的脚本 / 新增测试等 |
| `Edit` 没生效就 `cp`（今天真实踩过）| Edit → Read-back 验证 → 再 cp |
| Release/CHANGELOG.md 和根 CHANGELOG 不同步 | release.sh 自动 `cp` + audit 验证 `diff -q` |

### 10.3 Tarball 内容越界

| 错误 | 如何防 |
|------|-------|
| 打进 `skills/*-workspace/` eval 产物 | rsync `--exclude` |
| 打进 `commands/` 源文件 | exclude |
| 打进 `.claude/settings.local.json` | `.gitignore` + rsync 双保险 |
| 打进 `*.bak` tidy 备份 | exclude |
| **仓库根 `*.bak` 具名 exclude 不覆盖新备份**（Handoff v0.9.1/v0.9.2 踩过）🆕 v2.3 | release.sh rsync 必须用**通配** `--exclude='*.bak'` 而非具名 `--exclude='HANDOFF.md.bak'`。发版时才发现漏掉 `TKX_*policy*.v1.md.bak` 这种根目录历史备份，每次都要手动 stash 到 `/tmp`。|

### 10.4 脱敏误报与漏报

| 错误 | 如何防 |
|------|-------|
| 扫描器自己的正则文档被判泄漏 | `! -name 'release-sanitize.sh'` |
| meta 测试被判泄漏 | exclude 对应 test_*.sh |
| policy / test-scenarios 文档的反例举例被判泄漏 🆕 | exclude `TKX_*policy*.md` 和 `TEST-SCENARIOS.md` |
| 占位符 `<user>` 被判路径 | 黑名单 grep |
| `example.com` 被判真邮箱 | 白名单域 |
| 只扫源码不扫 .skill | 双扫 |
| **HANDOFF.md Dev Log 历史条目累积绝对路径泄漏**（Handoff v0.9.1 踩过）🆕 v2.3 | Dev Log 长期累积后会含真实开发机路径（`/Users/<name>/proj/...`）。发版 sanity gate 命中后必须 redact 为 `~/...` / `<sibling-project>/...` 占位。**建议**：每次 `/handoff` 写入时就用占位符，而非真实路径。|
| **CHANGELOG / RELEASE_NOTES 写"示例路径"用字面 `/Users/...` 被 sanity 拦**（v0.9.1 踩过）🆕 v2.3 | 文档里提"原来是 `/Users/jarvis/...`"这种描述本身就是泄漏。即使说明文字里也必须用占位符：`/Users/<user>/...` 或 `~/...` 或 `<your-home>/...`。|

### 10.5 原子性与并发

| 错误 | 如何防 |
|------|-------|
| 先 mv 主后写次（断电丢数据）| staging + atomic mv |
| 脚本失败留临时文件 | `trap cleanup EXIT` |
| 幂等性没测 | 测试套件含"连跑 2 次" |

### 10.6 退出码不诚信

| 错误 | 如何防 |
|------|-------|
| 脚本永远 exit 0 | 0=clean / 1=findings / 2=usage |
| 脚本缺失伪装成通过 | 三态：`✅ 通过 / ⚠️ 发现 / ➖ 跳过` |
| pipeline 脚本语义不一致 | 全部按 0/1/2 对齐 |

### 10.7 UX 陷阱

| 错误 | 如何防 |
|------|-------|
| Slash fuzzy match | 每个子命令加独立 shim |
| **`.skill` 安装后子命令不可用**（v0.9 踩过 🆕）| `.skill` 打包必须包含 `commands/` 目录；单文件安装不能牺牲基本功能 |
| 文档命令用绝对路径 | 全部 `./` 或 `~/`，配合 "先 cd 到文件所在目录" |
| README 只讲安装，缺 philosophy | 严格按 §6.2 章节要求 |
| 自动化命令无输出 | 每步至少一行状态 |

### 10.8 文档一致性

| 错误 | 如何防 |
|------|-------|
| README 说 2 条命令实际 3 条 | 加/删命令时全仓库 grep 计数 |
| INSTALL 写旧版本号 | 用 `v<版本>` 占位 + 发版时模板替换 |
| CHANGELOG 留 TODO 进 git | pre-release + audit 双检查 |
| per-version README 冲突主 README | 改名 RELEASE_NOTES.md |
| RELEASE_NOTES 写死 "26 KB" 过时（今天真实踩过）🆕 | 不写死数字，用"≈ XX KB" 或直接描述 |

### 10.9 Edit → Read-back 模式违反 🆕

| 错误 | 如何防 |
|------|-------|
| Edit 失败但未检查就下一步 | 每次 Edit 关键文件后 `head`/`grep` 验证 |
| cp 前没确认源文件正确 | `diff` 源和期望，或 `head` 看头几行 |
| 文件级操作（mv/rm）没先 `ls` 确认 | 破坏性操作前 `ls -la` |
| **Edit old_string 非唯一，误替换他处**（v2.1 🆕）| Edit 前 `rg -cF "<frag>"` 必须 = 1 |
| **单次 Write 倾倒 > 200 行大文档**（v2.1 🆕）| 先 `touch` 骨架，每轮 Edit/append ≤ 200 行 + 读回 |

### 10.10 发布外越权

| 错误 | 如何防 |
|------|-------|
| release.sh 自动 `git push` | 绝不自动 push |
| 忘记更新 `Release/latest` | release.sh 自动做 |
| Tag 推错分支 | 先 `git branch --show-current` 确认 |
| `git push -f` 强推 | 永不允许（除非用户显式 + feature 分支）|

---

## 11. Git / GitHub 流程

### 11.1 首次推送

```bash
git init
git add .
git commit -m "initial release v0.1"
git branch -M main
git remote add origin git@github.com:tkxlab-ai/<repo>.git
git push -u origin main
```

### 11.2 常规发版

```bash
# 开发 → 测试通过
bash tests/run_all.sh

# 同步文档（如有行为变化）
vim README.md INSTALL.md TEST-SCENARIOS.md CHANGELOG.md

# Release + 自带 audit
./release.sh v0.9

# 确认 CHANGELOG 无 TODO
grep -n "<!-- TODO" CHANGELOG.md && echo "❌" || echo "✅"

# 提交 + tag + push
git add .
git commit -m "release: v0.9"
git tag v0.9 -m "v0.9 — <主题>"
git push origin main
git push --tags
```

### 11.3 GitHub Release

```bash
gh release create v0.9 \
  Release/v0.9/handoff-v0.9.skill \
  Release/v0.9/handoff-v0.9-source.tar.gz \
  --title "v0.9 — <主题>" \
  --notes-file Release/v0.9/RELEASE_NOTES.md
```

### 11.4 `.gitignore` 必备

```
.DS_Store
.claude/settings.local.json
tests/.tmp/
*.bak
HANDOFF.md.bak
__pycache__/
*.pyc
*.log
handoff.skill
```

### 11.5 Yank / 撤回流程（v2.1 新增 🆕）

发布后 24h 内（或任何时间）发现**严重问题**（安全漏洞 / 数据丢失 / 无法安装），标准动作：

1. **不要** force-push 删 tag。保留 history 可追溯。
2. GitHub Release 改为 `pre-release` 标记，或直接 `delete`（tag 保留）
3. 打 **追加 tag**：`git tag -a v{X}-yanked -m "yanked: <reason>"` + `git push origin v{X}-yanked`
4. **立即**发下一版（hotfix 或 bump），CHANGELOG 首段明写：

   ```markdown
   ## v{X+1} — YYYY-MM-DD

   **⚠️ v{X} yanked due to <reason>, do not use.**
   ```

5. 若涉及安全（secret / 凭据泄漏）：按 §5.5 吊销 + filter-repo 重写历史
6. 通知已下载 / 已 clone 的用户（GitHub issue / 社群公告）

**为什么不 force-push 删 tag**：外部 fork / mirror / 缓存可能已固化，删不干净；留 yanked tag 是诚实的警告信号。

---

## 12. 附录

### 12.1 MIT LICENSE 模板

```
MIT License

Copyright (c) <year> TKXLAB.AI - https://github.com/tkxlab-ai

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, ... [truncated for brevity]
```

### 12.2 License section（追加到 SKILL.md / README 末尾）

```markdown
## License

![License: MIT](https://opensource.org/licenses/MIT)

This project is licensed under the MIT License - see the LICENSE file for details.

Copyright (c) 2026 TKXLAB.AI - https://github.com/tkxlab-ai

> Permission Notice: Free for personal and commercial use. If you integrate this
> skill into your own agentic workflows, providing a link back to our GitHub
> organization is appreciated.
```

### 12.3 Quick Reference: 发版 6 步

```bash
# 1. 测试绿
bash tests/run_all.sh

# 2. 同步文档
vim README.md INSTALL.md TEST-SCENARIOS.md CHANGELOG.md

# 3. release（内含 pre-gate + audit）
./release.sh v0.9

# 4. 验证 audit PASS（release.sh 最后一行应为 🎉）
echo $?  # 0 才能继续

# 5. 提交
git add . && git commit -m "release: v0.9"
git tag v0.9 -m "v0.9 — <主题>"

# 6. Push
git push origin main
git push --tags
gh release create v0.9 Release/v0.9/*.skill Release/v0.9/*.tar.gz \
  --notes-file Release/v0.9/RELEASE_NOTES.md
```

### 12.4 参考骨架

- `release.sh`、`scripts/release-sanitize.sh`、`scripts/release-audit.sh` 骨架 — 见 Handoff 项目仓库
- `README.md` / `INSTALL.md` / `TEST-SCENARIOS.md` 骨架 — 见 Handoff 项目仓库

### 12.5 10 分钟速检清单（v2.1 新增 🆕）

打包后、推送前用这 10 条肌肉记忆速过。**全过 = Go**；任一不过 = abort 修了再来。

```bash
V=v0.9 DIR=Release/$V

# 1. 结构正确 + 无 junk
cd $DIR && ls -la && find . -name ".DS_Store" -o -name "__pycache__" | head

# 2. README 第一屏含装/升/回滚
head -80 $DIR/README.md | grep -E "安装|Install|升级|Upgrade|回滚|Rollback"

# 3. install.sh --dry-run 无错
bash $DIR/*.skill.d/install.sh --dry-run 2>&1 | tail -20   # 或 tarball 解压后

# 4. 无个人绝对路径
rg -n "/Users/|/home/\w+" $DIR/

# 5. 无明显凭据
rg -niP "api[_-]?key\s*[=:]\s*['\"]|sk-[a-zA-Z0-9]{20,}" $DIR/ | head

# 6. LICENSE year + name 正确
head -3 $DIR/LICENSE

# 7. 版本号三处一致
grep -rE "version|$V" $DIR/SKILL.md $DIR/README.md $DIR/install.sh 2>/dev/null | rg -v "$V" | head

# 8. 单文件 < 500 行
find $DIR -name "*.md" -exec wc -l {} \; | awk '$1>500'

# 9. 无 .DS_Store / 临时文件
find $DIR \( -name ".DS_Store" -o -name "*.bak" -o -name "*.log" \)

# 10. git 状态干净
git status --short

# 11. 双源脚本无漂移（v2.2 🆕）—— 同名文件必须 byte-identical，否则 shipped 旧代码
#     只允许 dev-only 工具（release-*.sh / 发版辅助）单边存在于根 scripts/
diff -rq scripts/ skills/*/scripts/ 2>&1 | grep -v "^Only in.*scripts: release-" | grep -E "differ|Only in"
```

全过 → `git tag -a $V -m "..."` → `git push --tags` → `gh release create`。

---

**Copyright (c) 2026 TKXLAB.AI** — [github.com/tkxlab-ai](https://github.com/tkxlab-ai)
本文档按 MIT 许可分发。v2.3 — 2026-04-21
