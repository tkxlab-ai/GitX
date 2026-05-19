# GitX —— 更新日志

本项目所有重要变更记录于此，最新在最上。

**发布模型。** GitX 只有单一**稳定**线——没有 nightly 或 preview 通道；每个版本
发布前都过门（全量测试绿 + Deep Audit + 双引擎评审）。预发布工作留在流水线之后，
不作为单独轨道暴露。

格式遵循 **[Keep a Changelog 1.1.0](https://keepachangelog.com/zh-CN/1.1.0/)**；
版本号遵循 **[语义化版本 2.0.0](https://semver.org/lang/zh-CN/)**。
子节：`新增` · `变更` · `修复` · `加固` · `安全`
（`加固` ≡ 既非用户可见修复也非新特性的纵深防御）。
条目面向公开读者撰写——不含内部 jargon。English: [`CHANGELOG.md`](CHANGELOG.md).

---

## v1.12.1 — 2026-05-18

### Fixed
- **公开 CHANGELOG 链接 GitHub 上 404** —— README 链 `Release/CHANGELOG.md` / `Release/CHANGELOG_CN.md`（私有树路径），但公开镜像平摊掉 `Release/`（Gotcha #80）。链接改指扁平 `CHANGELOG.md` / `CHANGELOG_CN.md`；根镜像在 source tarball 前由真相源 `Release/CHANGELOG.md` 生成，公开 changelog 为全史、非陈旧 stub。
- **`CHANGELOG_CN.md` 从未公开** —— `release.sh` flatten 只发 EN changelog；CN 平行 + 根镜像现一并发，`README_CN` 的 changelog 链接得解析。
- **`release.sh` 可复现发版日期读了陈旧根 `/CHANGELOG.md`**（Gotcha #81）—— 改读真相源 `Release/CHANGELOG.md`，终结约 11 个版本的静默 wall-clock 兜底。
- **README curated 数值偏离真相源** —— Deep-Audit 引用为 `245` 而实时审计总数 `246`（`§0i` deep-audit-exactness 闸），且「Full history」发布数 `59` 落后实际 `61` 条 CHANGELOG。双语 README + 模板 + skill 镜像全部校正——正是 `§0f`/`§0i` 守护要消灭的 curated-number rot。

### Changed
- **`Quick Start` 移到 `Why GitX` 之后（`Comparison` 之前）** —— 经 docs-contract manifest；ToC 同步重排，新增 `test_toc_order` 断言守护。
- **新增 `Install troubleshooting` 子节**（中英）—— 覆盖本机 git `insteadOf` HTTPS→SSH 改写致 marketplace 安装失败（含线上核验解法）。
- **新增非计数 release-audit `§0l` published-layout 引用闸** —— 对解包 source tarball（真公开布局）解析每个 README 链接，private-valid/public-broken 链接即中止发版（Gotcha #80 修类）。

## v1.12.0 — 2026-05-18

### Fixed
- **`v1.11.0` 后对抗审加固** —— 连续六条 `codex` 发现按修类全部闭合：reusable 模板 scaffold 出缺失 hero 图；`docs-audit` `H10` 丢失 origin 强制；强制依赖 README 引用；可选 `grep` 在 `set -euo pipefail` 下未保护致整审计 abort；`hero_asset` 声明被误镜像进 bundled skill；被引用的缺失资产被静默跳过。
- **`tests/test_docs_pipeline.sh`** —— 最后一处 `set -e` 不安全的 `rc` 捕获改为项目标准安全 idiom。

### Changed
- **Hero 展示图 origin 专属** —— 从 reusable README 模板移除硬编码 `<img>`；host-specific 图仅存于 origin 的 live README，由 manifest 驱动的 `hero_asset:` 闸强制，`H10` 回归严格。
- **README badge 换新** —— 改为 `shields.io` `for-the-badge` 系列 + 品牌 logo；`@machine` Tests 令牌与 Deep-Audit 引用保持字节冻结，零 gate 不变量漂移。
- **Hero 资产替换** —— 换为 Boss 提供的 web 优化版（`docs/assets/release-demo.jpeg`）——更小、内容等价。

---

## v1.11.0 — 2026-05-17

### Added
- **独立双语文档流水线** —— README 与 CHANGELOG 的每个区块均确定性生成（LLM 不参与回路），并由硬 fail-closed 文档契约审计器逐项校验。
- **CI 平价 shellcheck 闸** —— 发版流水线现在运行与 GitHub CI 完全相同的 shellcheck 命令，本地流水线绿即代表公开 CI 绿。

### Changed
- **专业双语 README** —— 重构为标准版式（hero、价值主张、多版本更新摘要、目录、对比表、安全、常见问题）；中英两版保持结构平价。

### Hardening
- **断链不可 ship** —— 公开 README 中每个仓内链接与图像均须在发版时可解析，否则发版中止。

---

## v1.10.1 — 2026-05-16

### Fixed
- **"更新摘要"不再 rot** —— `gr_whats_new` 现在从 CHANGELOG 机器派生版本、日期与顶部要点；此前版本附带一张未受保护的手工维护摘要表，连自身发版信息都漏掉了。

### Added
- **`gr_command_surface` 命令面区块** —— 确定性生成并记录两种安装路径（扁平安装 vs 插件市场 `/gitx:*`）的命令面；两个区块均由现有通用 §0g 闸守护；新的 `gitx-readme --init` 脚手架自动包含这两个区块。

### Hardening
- **封堵私有态泄漏面** —— 知识图谱产物与本地项目配置现已满足五维对称平价标准（`.gitignore` + `.sanitize-ignore` + rsync `--exclude` + fail-closed 正则 + 品牌重命名白名单 + TDD 锁），双源字节一致。

---

## v1.10.0 — 2026-05-16

### Added
- **`scripts/gitx-readme.sh` 确定性 README 生成器**（projen 范式，不依赖 LLM/git/gh）—— 支持 `--init` 脚手架、刷新、`--check` 漂移检测；fail-closed 校验（exit 5）；多行内容通过临时文件管理；从非循环来源获取测试套件数/版本/安装/更新摘要；提供 `references/readme/README.template.md`（含中文版）通用脚手架。
- **`release-audit.sh §0g/§0h/§0i`** —— README 同步 fail-closed 闸、中央安装闸、深度审计精确性元闸，均为通用 SKIP + errexit 安全 + 双源设计。
- 依赖技能的每个仓由 `--init` 自动生成 `test_readme_numeric_accuracy.sh`。

### Changed
- **`README.md` / `README_CN.md` 迁移至 projen managed-region 模型**（自采用）；深度审计计数 §0f/§0i 纳入管理。

---

## v1.9.8 — 2026-05-16

**修复（公开 README 在 v1.9.x 期间静默腐烂）并新增 `§0f` 文档数值 rot 守护。** 每次 v1.9.x 发版仅外科式更新 README 版本号字符串，导致徽章数、BDD 套件计数、Deep-Audit 编号及"What's New"表格全部过时并流入公开镜像。本版修正所有数值（Deep-Audit 230、套件数 97、CN `95+`），同时新增通用跨项目守护 `release-audit.sh §0f doc-numeric-rot`（双源字节一致），确保后续发版不再出现 README 数值与实际产物脱节。还新增更严格的按仓测试 `tests/test_readme_numeric_accuracy.sh`。

---

## v1.9.7 — 2026-05-16

**修复（`gitx-sop` 自发版暴露的凭证扫描门与发布 worktree 卫生缺陷）。** 生成的 GitHub 发版 SOP 的 Phase 1.4/4.4 将目录传给只接受单文件的 `scan-credentials.sh`，致扫描无效；Phase 5 使用未遵守 `.sanitize-ignore` 的 `git diff | grep`，导致对项目自身白名单文件误报失败。三处门控全部改为优先调用项目权威的 `release-sanitize.sh`（含白名单感知），并以逐文件 `scan-credentials.sh` 兜底。发布 worktree `.github-publish-wt/` 现已实现五维对称遏制（`.gitignore` + `.sanitize-ignore` + rsync `--exclude` + fail-closed 正则 + 品牌重命名白名单）；TDD 锁定。

---

## v1.9.6 — 2026-05-16

**加固（superpowers 11 轮迭代 + codex 审计）：handoff v1→v2 工作内存文件类全部加入五维发版遏制，并修复长期存在的 `.python-version` 公开 tarball 泄漏。** `GOTCHAS.md`、`Handoff_Logs/`、`Handoff_Decisions/`、`HANDOFF.md.pre-v2-backup` 等内部文件现已在 `.gitignore`、`release.sh` rsync `--exclude`（双源一致）、`.sanitize-ignore`、`guard #10 case` 及品牌重命名白名单中得到与 `HANDOFF.md` 完全对称的处理。`guard #10` 同步加固（新增 `#10b`、`#10c` 回归检查）。Codex 审计发现 `.python-version` 自 v1.3.0 起一直泄漏进公开 source tarball——已双层修复：rsync `--exclude` 防止泄漏，`release-audit.sh` fail-closed 正则检测泄漏（两处均双源锁定）。

---

## v1.9.5 — 2026-05-16

**修复（codex 止步门）：`guard #10` 豁免了本应保护的已发布文件。** `tests/test_plugin_manifest.sh` 本身会打包进公开 tarball，但 `guard #10` 因 grep 模式和注释中含有被禁字面量而必须自我豁免，导致该字符串实际仍随测试文件流出，guard 的"覆盖所有已发版文件"承诺存在漏洞。修复：搜索模式改用正则括号类（`Git[X]`）规避字面量自匹配，移除自我豁免，`guard #10` 现在扫描包括自身在内的所有已发版文件。

---

## v1.9.4 — 2026-05-16

**修复（codex 止步门）：过时的按仓市场安装命令仍流入已发布文件。** `.claude-plugin/marketplace.json` 和模板 `description` 仍告知用户执行 `/plugin marketplace add tkxlab-ai/GitX`（旧的按仓形式）并流向 GitHub。已修正为中央统一命令 `/plugin marketplace add tkxlab-ai/marketplace`；`test_plugin_manifest.sh` 新增 `#10` 断言，代码层面禁止任何已发版清单或文档中出现旧的按仓 `marketplace add tkxlab-ai/GitX` 字面量。

---

## v1.9.3 — 2026-05-15

**修复：内部设计文档被打包进公开镜像。** `docs/superpowers/{plans,specs}/*`（内部设计记录）自 v1.7.x 起一直包含在公开 source tarball 中，与 `HANDOFF.md` 同属内部文件但未被排除。现已加入 source tarball 的 rsync `--exclude` 列表；`references/marketplace/marketplace.json.template` 移除 `_pending` 字段（中央仓是唯一可信源）。`test_plugin_manifest.sh` 新增 `#8` 断言静态强制排除，新增 `#9` 断言确保公开文档中不出现内部专属文件（如 `HANDOFF.md`）的链接或引用。

---

## v1.9.2 — 2026-05-15

**文档整洁（用户反馈陈旧/过度复杂）。** 移除所有旧版按仓 `/plugin marketplace add tkxlab-ai/GitX` 指令（改为中央 `tkxlab-ai/marketplace`）；将冗长的 `Live build metrics` 多行块替换为一行简洁摘要（版本·日期·模型·token 估算·数字总览）；从 `README/README_CN/RELEASE_NOTES/SOP` 模板中清除所有外部项目名称引用；刷新徽章（95+ 套件）及 `What's New` 表（补入 v1.8.x/v1.9.x 行）。SOP Phase 4.6 + `test_gitx_sop` BEHAVIOR 13 更新至简洁契约，并在旧措辞或外部仓库名重现时报错。

---

## v1.9.1 — 2026-05-15

**修复（对 v1.9.0 的迭代审计）：** `gitx-init` 将目标 `VERSION` 原始写入插件/市场 `JSON`——保留 `v` 前缀（`schema` 要求纯 `semver`）且多行 `VERSION` 可能破坏 `heredoc JSON`。新增 `semver_norm()`（去前缀 `v`、仅取首行、严格 `semver` 正则、无效时降级 `0.0.0`），两份清单均适用；双源字节一致。另修复中央市场模板版本漂移（1.8.1 vs 当前仓版本），`test_central_marketplace` 4b 现在代码强制模板版本等于 `VERSION`；新增 `v` 前缀剥离、恶意 `VERSION` 输入及模板漂移的回归测试。

---

## v1.9.0 — 2026-05-15

### Added
- **插件命名空间 `/gitx:*`**、**中央 TKX 市场**、**`gitx-init` 自动配置**、**MacAudit 级页面标准**，由超级代理驱动的 TDD 构建后经 Codex 审计。

### Changed
- VERSION 升至 v1.9.0；插件清单版本与描述同步更新。

---

## v1.8.1 — 2026-05-15

### Fixed
- 修复插件市场清单因 `name` 非 kebab-case 及 `source` 路径格式错误导致 Claude 验证器拒绝的问题；更新 README 与测试以锁定合规格式。

---

## v1.8.0 — 2026-05-15

### Added
- **`.claude-plugin/`** 插件清单——仓库现可通过插件市场安装；新增 `CONTRIBUTING_CN.md`、`CONTRIBUTING.md`、`RELEASE_NOTES.md` 社区文件集；`test_plugin_manifest.sh`（7 项检查）守护清单合规性。

### Changed
- `README.md` / `README_CN.md` 新增"作为 Claude Code 插件安装"章节；`gitx-sop` SOP 模板 Phase 4.6 要求社区文件完整性，`test_gitx_sop.sh` BEHAVIOR 12 守护。

---

## v1.7.8 — 2026-05-15

### Fixed
- 修复 v1.7.7 中 Phase 6 无令牌 URL 回退路径为死代码的问题——Phase 1.5 硬性要求 `gh auth status` 导致 SOP 在预检阶段即中止，使回退路径永远不可达；现在 Phase 1.5 同时接受 gh OAuth 或 `GH_TOKEN`，回退路径真正可达。

---

## v1.7.7 — 2026-05-15

### Changed
- SOP Phase 6 改为优先使用 gh 凭证助手（通过 `gh auth setup-git` 经 keyring 认证），token-in-URL 仅作无 gh 时的显式回退，令牌不再触碰远端 URL 或 `.git/config`。

---

## v1.7.6 — 2026-05-15

### Changed
- 将原有简陋 README 替换为全面双语 GitHub 级 README（`README.md` 英文主版 + `README_CN.md` 中文并行版），涵盖设计哲学、工作原理、12 函数流水线及参考文献引用。

---

## v1.7.5 — 2026-05-15

### Fixed
- 修复斜杠命令安装到错误目录导致 Claude Code 无法发现的问题——`install.sh` 现在将子命令垫片安装至 `~/.claude/commands/`（扁平 `.md` 格式）；新增 `test_gitx_sop.sh` BEHAVIOR 10 功能验证。

---

## v1.7.4 — 2026-05-15

### Fixed (SOP template)
- 修复四处会导致其他技能 SOP 中断或静默失败的可移植性缺口：Phase 4.5 可移植性、回滚 D 需同时清除标签、Phase 7 多版本 Latest 重新断言、Phase 8 完整性闸；新增 `test_gitx_sop.sh` BEHAVIOR 9 回归守护。

---

## v1.7.3 — 2026-05-15

### Fixed
- 修复 README 命令矩阵未记录 `/gitx-init` 与 `/gitx-sop` 的问题；新增 `test_readme_command_completeness.sh` 守护，确保每个 `commands/*.md` 垫片都在 README 中有对应记录。

---

## v1.7.2 — 2026-05-15

### Fixed
- 修复 README 与 ROADMAP 中版本号硬编码导致文档随版本演进而静默过时的问题；新增 `release-audit.sh §0e` 文档版本 rot 闸及 `test_audit_doc_version_rot.sh` 守护。

---

## v1.7.1 — 2026-05-15

### Fixed
- 修复斜杠命令垫片从未被分发的问题——`commands/` 现在双源（根目录 + `skills/gitx-release/`，字节一致）；`release.sh` 不再将 `/commands` 排除于源 tarball；`test_install_path_completeness.sh` 取消对 `commands` 的跳过。

### Changed
- VERSION v1.7.0 → v1.7.1（补丁）；流水线行为不变，仅修复分发完整性。

---

## v1.7.0 — 2026-05-15

### Added
- **`gitx-sop` 子命令** —— 在任意项目根目录运行 `bash scripts/gitx-sop.sh` 即可生成 `.gitx/GITHUB_RELEASE_SOP.md`：包含 8 个阶段的参数化 SOP，用于将发版产物发布至公开 GitHub 镜像而不泄漏私有 Git 主机；`release-audit.sh §0d` 守护模板完整性；`test_gitx_sop.sh` 16 个断言。
- **`references/gitx-sop/GITHUB_RELEASE_SOP.template.md`** 主模板——8 阶段 + 回滚 + AI 清单，占位符渲染。
- **`commands/gitx-sop.md`** 斜杠垫片 + `agents/codex-commands.txt` `$gitx-sop` 选择器（根目录 + 包均字节一致）。

### Fixed

- SOP 评审：模板补齐 8 处缺口
- 修复 SOP 模板审查发现的 8 处缺口，包括测试步骤由打印改为真实闸、Phase 6 令牌清理、Phase 4.3 强制中止、Phase 7 校验和验证、Phase 5.2 扫描覆盖面、Phase 7.2 重跑引导、变量表示例更正及回滚场景 D 改用强制重写模型。

### Changed
- Codex 命令选择器上限从 3 扩展至 4；`SKILL.md` 工作模式表新增 GitHub 发版 SOP 行；品牌重命名为 **GitX**（纯品牌层），规范文件系统标识符保持小写 `gitx-release` 不变。

---

## v1.6.0 — 2026-05-12

### Added
- **`gitx-init` 子命令** —— 自动检测项目类型（技能/Mac 应用/两者/空）并生成 `.gitx/` 策略包 + 顶层 `RELEASE_GUIDELINE.md`；支持 `--type`/`--force`/`--dry-run`/`--help`；`references/gitx-init/` 5 个主模板；`test_gitx_init.sh` 30 个断言；`release-audit.sh §0c` 守护模板完整性。
- `commands/gitx-init.md` 斜杠垫片；`$gitx-init` Codex 选择器（根目录 + 包均字节一致）。

### Changed
- `install.sh` 恢复 `commands/` 传播至规范安装路径；`SKILL.md` "工作模式"表头更新并新增第五行映射 `gitx-init`。
- `test_audit_codex_command_selectors.sh` 改为基于集合比较，替代原硬编码计数。

### Verification
- `bash tests/run_all.sh` → **90 套件 / 0 失败**；双源 diff 清洁；`release-audit.sh §0c` 正确触发。

---

## v1.5.0 — 2026-05-11

### Added
- **`scripts/lib/install-output-style.sh`** 统一安装输出助手——公开 API 含 banner/checkpoint/step/cli-table 等函数；ASCII 纯净回退（`TKX_INSTALL_NO_EMOJI=1`）；`test_install_output_style.sh` 覆盖公开 API 全面。
- **`references/INSTALL_TEMPLATE_STANDARD.md`** 权威 8 节英文 INSTALL 模式——所有 TKX 技能的 `INSTALL.md` 须遵循。
- **`release-audit.sh §0b`** INSTALL 统一标准强制闸。

### Changed
- `install.sh` 端到端重写——保留 v1.4.1 全部闸，输出改用新助手渲染 6 检查点 banner。
- `INSTALL.md` 重写为完整 8 节英文模式实现。

### Verification
- `bash tests/run_all.sh` 全绿；`TKX_INSTALL_NO_EMOJI=1` ASCII 纯净验证；双源字节一致。

---

## v1.4.1 — 2026-05-11

### 🎨 Polish
- `description` 改为 "pushy" 形式（含显式触发词，防 LLM undertrigger）；frontmatter 新增 `license: MIT` 与 `compatibility` 字段（spec line 67/68）。

### 🔧 调试过程踩到的 3 个雷
- description 含 `<>`、YAML `Triggers:` 被解析为键、品牌保留测试失败——三处细节均已修复并文档化。

### 📊 Test surface
- **88 套件 / 0 失败**（纯 SKILL.md 打磨，无新 BDD）；官方 `quick_validate.py` 三处全 `Skill is valid!`。

### ✅ 官方对齐总览（post-v1.4.1）
- 严格 `spec` 合规、`pushy` `description`、`frontmatter` `license`+`compatibility`、参考文档目录（`references` `ToC`）、行数限制、标准目录——全部达标。

---

## v1.4.0 — 2026-05-11

### ✨ Features
- **venv + PyYAML 自动安装** —— `ensure_pyyaml_via_venv()` 在系统缺 PyYAML 时自动创建临时 venv 并安装，使 vendored skill-creator 路径在新机/禁网/CI 均可用。
- **audit §0 Python 交叉验证** —— 检测到 PyYAML 可用时额外运行官方 `quick_validate.py` 提升 spec 一致性精度。
- SKILL.md audit §2b/§6b 关键词列表显式文档化；vendored skill-creator 手工升级流程文档化。

### 🛡 Hardening
- **Gotcha #34** `.syncthing.*.tmp` 显式 `.gitignore` 规则；新 BDD `test_no_syncthing_residue.sh`（6 断言）。
- `__pycache__/` 双重排除（dual-source diff 过滤 + `PYTHONDONTWRITEBYTECODE=1`）。

### 📊 Test surface
- **88 套件 / 0 失败**（+2 新 BDD：`test_pyyaml_venv_auto.sh` + `test_no_syncthing_residue.sh`）。

### 🔬 v1.4.1+ candidates（low priority，留作 future polish）
- 跨项目 v1.1.5 改进同步、GitHub Actions 周期性 sync 评估、audit §0 Python 交叉验证在 venv 模式下工作。

---

## v1.3.2 — 2026-05-11

### ✨ Features
- **`test_install_path_completeness.sh`**（14 断言）防止 v1.3.0 类 bug 再现——`.skill` 包内每个顶级目录/文件须有对应 `install.sh` copy 命令。
- **audit §2 TEST-SCENARIOS.md → soft-warn** —— 缺失仅产生 ⚠️ advisory 而非 ❌ FAIL，降低新项目接入门槛。

### 🔧 Fix
- 修复 `test_install_path_completeness.sh` 在 `release.sh` `run_tests` 上下文中因 pipefail 意外 abort 的问题——改用纯 shell glob 替代外部 pipeline。

### 📊 Test surface
- **86 套件 / 0 失败**（+2 新 BDD：install 路径完整性 + audit §2 soft-warn）。

### 🔬 v1.3.3+ 候选
- audit §2b keyword 列表显式文档化、Gotcha #34 显式 `.gitignore` 规则、venv 自装 PyYAML 评估。

---

## v1.3.1 — 2026-05-11

### 🔧 Fix
- 修复 v1.3.0 中 `install.sh` 漏复制 `scripts/vendored/` 导致 self-contained 特性对仅通过 `install.sh` 安装的用户静默失效的问题；新增 8 行检测并条件复制逻辑。

### 📊 Test surface
- **84 套件 / 0 失败**（无新 BDD）；post-install 手工验证 vendored 目录完整。

---

## v1.3.0 — 2026-05-11

### ✨ Features
- **Vendoring** —— `scripts/vendored/skill-creator/` 内嵌官方 skill-creator 核心 4 个 Python 文件（Apache 2.0，32KB），使 gitx-release 真正 self-contained。
- **`scripts/lib/skill-creator-version.sh`** —— 单一入口探测系统与 vendored skill-creator 并输出 6 种 verdict，指导 `build_skill_package` 决策矩阵。

### 🔧 Fix
- 修复 Gotcha #32 复发——新增中文 prose 时 `$var` 紧接全角标点导致 `set -u` abort，统一改用 `${var}` 形式。

### 📊 Test surface
- **84 套件 / 0 失败**（+1 新 BDD：`test_skill_creator_vendoring.sh` 15 断言）。

### 🛡 安全 / 合规
- vendored Python 文件与 Apache 2.0 `LICENSE` 一同入包分发；`VERSION` 固定含上游 commit hash，便于审计追溯。

### 🔬 v1.3.1+ 候选
- 评估 venv 自装 PyYAML、audit §0 升级至 PyYAML 严格模式、周期性自动 sync upstream。

---

## v1.2.1 — 2026-05-11

### 🔧 Fixes
- **skill-creator 发现路径修复** —— `_discover_skill_creator()` glob 展开真实 hash 目录名，替代原硬编码占位符路径；新增 `test_release_skill_creator_discovery.sh`（8 断言）。
- **PyYAML 优雅降级** —— 缺失时回退 zip 模式，不阻断发版。

### ✨ Audit §0：SKILL.md spec conformance（NEW）
- 新增 audit §0_spec，等价于官方 `quick_validate.py` 的 6 条规则，纯 bash+awk+grep 实现（不依赖 Python），守护 SKILL.md 格式合规。

### 📊 Test surface
- **83 套件 / 0 失败**（+2 新 BDD：discovery 8 + spec conformance 11 = 19 新断言）。

### 🔬 v1.2.2+ 候选
- venv 自装 PyYAML、audit §0 升级至 PyYAML 严格模式、探索 `npx skills` 替代 install.sh。

---

## v1.2.0 — 2026-05-10

### 🔧 Fixes
- **[hot-patch]** 修复 `build_source_tarball` 现代路径漏设 `STAGE_SUB` 导致下游 `run_sanity_scans` 在 `set -u` 下 abort 的问题。
- **[A1]** `ensure_changelog_entry` 锚定首个 `## ` 行，修复 minimalist CHANGELOG 插入位置偏移问题。
- **[A4]** `.skill` 包内 sanitize 继承项目根 `.sanitize-ignore`，修复 mac-release self-bake 假阳性 abort。

### 🛡 Hardening
- `test_sanitize_ignore_hardening.sh` 精化：仅标记非临时路径的 `cp .sanitize-ignore`。

### 📊 Test surface
- **81 套件 / 0 失败**（+3 新 BDD：hot-patch 6 + A1 9 + A4 6 = 21 新断言）。

### 🔬 v1.2.1+ 候选（未 ship）
- Gotcha #36 文档化（`grep | head | cut` 在 pipefail 下 abort）；v1.1.7 新机 baseline 核验。

---

## v1.1.7 — 2026-05-08

### 🔒 修复 Gotcha #33 长期方案: `build_source_tarball` 改用 git-archive(发起方:1by1)
- `build_source_tarball()` 顶部插入 detect-and-delegate 分支：项目提供 `scripts/scrub-tarball.sh` 时自动用 `git archive` 打包，彻底遵守 `.gitignore` + `.gitattributes export-ignore`，终结 rsync 模式漏包问题。

### 🔒 Gotcha #32 修复:`set -u` 下 `$var` 紧接 Chinese 全角标点被吞进变量名（发起方:mac-release self-bake）
- `release-audit.sh:265` 将 `$first_ver_line）` 改为 `${first_ver_line}）`；新增 `test_audit_chinese_paren_safe.sh`（11 断言）防回归。

### 🔧 `3e55e14` 后续整理
- 补齐 dual-source 镜像（VERSION + `release.sh`）；`scrub-tarball.sh` 加入 `check_dual_source` 白名单；新增 `test_release_tarball_scrub_preferred.sh`（10 断言）TDD 覆盖新路径。

### 🛠 修复(`scripts/release.sh:366-405`)
- 详见上方 Gotcha #33 长期方案修复说明。

### 🛠 修复(`scripts/release.sh / release-audit.sh`)
- 详见上方 Gotcha #32 修复说明。

### 🧪 验证
- **78 套件 / 0 失败**（76 基线 + 2 新测试）；dual-source diff 清洁；自发版通过端到端审计。

### 🔗 关联
- Gotcha #32 / #33 同步新增 HANDOFF 条目；mac-release v0.1.0 self-bake 暴露的所有 friction 已闭合。

---

## v1.1.6 — 2026-05-05

**稳定性重新自发版，验证 v1.1.5 sanitizer 在生产自测中可通过自身审计门。** 相比 v1.1.5 无任何源码改动；本版本存在的唯一目的是证明 v1.1.5 sanitizer 在完成四项 UX 缺陷修复和 IP 策略收紧后，能够通过自身审计。值得记录的过程发现：v1.1.6 第一次尝试被已安装的 v1.1.5 sanitizer 在审计 §7（发布后扫描）阶段正确拦截——原因是 v1.1.5 CHANGELOG 条目正文含有样本用户路径、样本邮箱及真实公网 IP 字面量；通过将两处 `CHANGELOG.md` 的描述改写为语义替代形式后解决（与 `Gotcha #31` 同类根因，不同代码路径）。所有脚本、测试、契约与 v1.1.5 字节一致；`bash tests/run_all.sh` → 76 套件 / 0 失败；Deep Audit 170 PASS / 0 FAIL / 1 SKIP。

---

## v1.1.5 — 2026-05-05

**Sanity-scan UX 加固 + IP 策略收紧。** 对四个下游项目的六次 gitx-release 日志进行运营审计后发现并修复四个操作影响问题，新增 31 项 TDD 断言。- **Bug A**：`scan-credentials.sh` 多次命中同一文件时，每行报告现在都带文件路径前缀（此前仅首行带前缀）。- **Bug B**：扫描结果改为显示项目相对路径，不再显示 staging mktemp 绝对路径。- **Bug C**：`release-sanitize.sh` 新增 `--label <name>` 参数，区分 staging 与 `.skill` bundle 两次扫描的输出。- **Bug D**：公网 IP 改为硬 FAIL（`❌`），与策略一致；RFC 5737 文档示例地址段加入白名单。新增回归测试套件 `tests/test_sanitize_output_format.sh`（31 断言）。

---

## v1.1.4 — 2026-05-05

**仅文档发版。** 由外部 Codex 对抗性评审及 HANDOFF 漂移审计驱动，无源码、测试或契约改动。- **`GETTING_STARTED.md §8` 安装路径拆分为已验证版本（`§8a` 推荐，下载 tarball 后 `install.sh` 自动校验 `checksums.txt`）和开发克隆版本（`§8b`，明确标注绕过校验，不可用于生产机器）**。- **`Release/CHANGELOG.md` 补全四个空白条目**（v1.0.8 / v1.0.9 / v1.0.10 / v1.1.1），这些条目此前由 `Gotcha #29` wrapper sentinel 自动生成后未填写真实内容，导致每次 gitx-release 运行都触发发布拦截警告。所有脚本和测试与 v1.1.3 字节一致；75 个测试套件全绿。

---

## v1.1.3 — 2026-05-04

**处理 v1.1.2 评审反馈（Important #1、#2、#3 及 Minor #6、#7）。** - **`§11k` 误报修复**：审计不再从注释行提取 `$SELF_DIR/...` 路径，注释示例不再触发审计失败。- **`§11k` 大括号形式覆盖**：正则扩展至同时捕获 `"${SELF_DIR}/<path>"` 形式。- **`GETTING_STARTED.md §5` Option C 修正**：`.release-flatten` 标注改为 v1.1.2 已发布（此前误标为"计划中"）。- **`GETTING_STARTED.md §6` 依赖检查配方**：替换为 `gitx-release.sh --dry-run` 权威调用方式。新增 TDD 用例 D（注释中的 `cp` 不触发）和 E（大括号形式的缺失依赖被捕获）；发现并修复一个 `sed` `BSD` 与 `GNU` 可移植性问题。审计计数不变：`170 PASS / 0 FAIL / 1 SKIP`；75 个套件全绿。

---

## v1.1.2 — 2026-05-04

**闭合"claudemex `install.sh`"失效模式。** 下游项目发现 `install.sh` 可能引用标准 8 文件列表之外的项目专属文件，导致用户安装时 `cp $SELF_DIR/<file>` 失败。双层修复：- **Flatten 层**：`flatten_docs()` 现在读取可选的 `.release-flatten` 清单（每行一路径，兼容注释和空行），列出的路径与标准 8 文件一同复制进 `Release/<ver>/`；缺少清单则行为不变（向后兼容）。- **审计层**：新增 `release-audit.sh §11k`，解析 `Release/<ver>/install.sh` 中的 `"$SELF_DIR/<path>"` 引用并验证每个路径可解析，在用户运行 `install.sh` 前提前捕获遗漏的 flatten 项。另新增 `GETTING_STARTED.md` 顶层前置文档，供 AI 代理和技能作者参考。TDD：`test_flatten_manifest.sh`（8 断言）+ `test_audit_install_dependencies.sh`（5 断言）均先 RED 后 GREEN；审计计数增至 170。

---

## v1.1.1 — 2026-05-04

**处理 v1.1.0 第五轮评审反馈（Important #1–#5）及测试套件健壮性修复。** - **#1**：`INSTALL.md` 卸载块由 bulk sed 误压缩的四个不同 CLI 根路径已恢复为完整 10 路径序列。- **#2**：`INSTALL.md` alias 示例句重写，明确说明小写规范名的原因及废弃 alias 保留契约。- **#3**：`release.sh` `commands/` flatten 分支增加说明性注释，澄清其为任何下游技能发版使用的通用管道契约（非死代码）。- **#4**：`agents/codex-commands.txt` 废弃注释移入新 `agents/README.md`，清单恢复为纯净的 2 个选择器行。- **#5**：`test_audit_codex_command_selectors.sh` 新增精确计数断言（`==2`），防止额外选择器悄无声息地混入。`test_release_pipeline_smoke.sh` VERSION 断言修复，避免发版中途误失败。

---

## v1.1.0 — 2026-05-04

**BREAKING — 规范名品牌重命名，消除 `/` 菜单重复条目。** 技能全面重命名为 `gitx-release`（目录、`SKILL.md name:`、安装路径、测试 fixtures）。`commands/GitX-release.md` 斜杠命令垫片已删除——Claude Code 现在自动将重命名后的技能推广为 `/gitx-release`（单一规范入口，消除同时显示多个斜杠命令条目的隐性知识负担）。Codex 别名：`$gitx-release` 为主；旧别名作为废弃别名保留一个小版本（v1.2.0 移除）。`./install.sh --force` 自动清理所有旧版路径。选用小写 `gitx-release` 而非 `GitX-Release` 作为文件系统规范名的原因：macOS HFS+ 大小写不敏感，两者在默认 macOS 文件系统上会冲突（Decision 2026-04-30 + `Gotcha #16`）。

---

## v1.0.10 — 2026-05-04

**无操作稳定性重新自发版。** 相比 v1.0.9 无任何源码改动。唯一目的：验证 v1.0.8 加固和 v1.0.9 自发版在第四次连续运行后仍具确定性，并在 v1.1.0 品牌重命名切割前立即演练发版流水线。所有脚本、测试、契约与 v1.0.9 字节一致；`bash tests/run_all.sh` → 72 套件 / 0 失败；Deep Audit 176 PASS / 0 FAIL / 1 SKIP；`shasum -a 256 -c checksums.txt` → 6/6 OK。

---

## v1.0.9 — 2026-05-04

**v1.0.8 加固的稳定性自发版。** 相比 v1.0.8 无任何源码改动，为第三次连续自发版（继 v1.0.7 / v1.0.8 之后），证明第五轮加固的发版到发版确定性。所有脚本、测试、契约与 v1.0.8 字节一致；`bash tests/run_all.sh` → 72 套件 / 0 失败；`Deep Audit 176 PASS / 0 FAIL / 1 SKIP`；`shasum -a 256 -c checksums.txt` → 6/6 正常；`gitx-release.sh` 哨兵 ⚠️ 正确触发（`Gotcha #29` + v1.0.8 §11h 新契约）。

---

## v1.0.8 — 2026-05-04

**第五轮独立评审加固。** 三位并行评审员（安全 / `bash` / 架构）审计约 2900 行核心代码，共发现 0 严重、13 重要、13 次要问题，所有 P0/P1 在多项目使用前全部闭合。供应链门：`install.sh` `checksums.txt` 校验（`Gotcha #30`），写入前先 `shasum -a 256 -c` 验证。审计完整性：`release-audit.sh --inline` 溯源保护（`Gotcha #27`）、`VERSION` 正则验证、`§6` `unzip` 干净失败、`§5 LIST trap` 隔离。扫描器：`release-sanitize.sh` 路径锚定（`Gotcha #28`）、`scan-credentials.sh` 流式读取、新增 7 种凭证模式。契约：`gitx-release.sh` 哨兵（`Gotcha #29`）、`preflight_external_tools()` 前置探测、`RELEASE_DATE` 挂钟保护。Phase D 防御加固：多处 `set -e` 危险模式修复、`json_escape()` helper、项目名校验白名单。新增 8 个 TDD 文件，套件从 64 增至 72 个。

---

## v1.0.7 — 2026-05-04

- 自动化 GitX 发版：运行完整门控套件，打包产物，生成 attestation，完成 Deep Audit。

---

## v1.0.6 — 2026-05-01

- 自动化 GitX 发版：运行完整门控套件，打包产物，生成 attestation，完成 Deep Audit。

---

## v1.0.5 — 2026-05-01

- 自动化 GitX 发版：运行完整门控套件，打包产物，生成 attestation，完成 Deep Audit。

---

## v1.0.4 — 2026-04-30

- 自动化 GitX 发版：运行完整门控套件，打包产物，生成 attestation，完成 Deep Audit。

---

## v1.0.3 — 2026-04-30

- 自动化 GitX 发版：运行完整门控套件，打包产物，生成 attestation，完成 Deep Audit。

---

## v1.0.2 — 2026-04-30

- 自动化 GitX 发版：运行完整门控套件，打包产物，生成 attestation，完成 Deep Audit。

---

## v1.0.1 — 2026-04-30

### 跨 CLI 安装支持
- 重写 `install.sh`，实现跨 Claude/Codex/OpenCode/Gemini 四平台安装，修复双源同步与审计 §6b。

---

## v1.0.0 — 2026-04-29

### 🎉 v1.0.0 — 五专家审查 + 全量 TDD 修复 + 三轮回审
- 首个正式稳定版，经五位专家三轮启发式评估，18 余项发现全部经 TDD 迭代修复并通过三轮代码回审。

### 🔴 P0 修复 (3 项)
- 修复 dry-run 契约、全链路贯通及 Test 5 断言，确保 dry-run 不产生任何真实文件或目录。

### 🟠 P1 修复 (6 项)
- 消除 trap 覆写、扩展安全扫描 pattern/扩展名、修复 warn() 计数及 E2E smoke test。

### 🔍 三轮回审额外修复
- `CLEANUP_EXTRAS` 改为 bash 数组、Test 7 传入 `PROJECT_NAME`、bash 3.2 trap exit code 修复。

### 📊 数据
- **40 套件 / 329 断言 / 0 失败**；shellcheck 0 警告；12 凭证 pattern；20 种文件扩展名。

---

## v0.9.11 — 2026-04-24

### 🧮 新 artifact: `TOKEN_USAGE.md` — 为终端用户披露运行时 context token 成本
- 发版产物新增 `TOKEN_USAGE.md`，按三档披露该技能运行时 context token 量及三种模型估算费用。

### 🆕 新脚本: `scripts/emit-token-usage.sh`
- 独立可测，优先 tiktoken 精确模式，降级为纯 Bash 启发式；支持价格 env 覆盖。

### 🔧 流水线接入
- `release.sh §2.7b` 接入 token 用量生成；checksums 覆盖扩展至 5 件；`release-audit.sh §11j` 6 项检查。

### 🧭 Decision
- tokenizer 选 C（两档并存）；audit 严苛度选 Y（非技能 SKIP，技能 FAIL）。

### 🧪 测试
- 新增 `test_token_usage.sh`（14 用例）；套件从 36 扩展至 **38 套件全绿**，`run_all.sh` 改为自动发现。

### 🔧 流水线增强 (v0.9.11)
- release.sh/release-audit.sh/release-sanitize.sh 多处健壮性提升；新增 `scripts/README.md` 入口索引。

### 📊 对本项目 dogfood 数据(tiktoken 精确)
- Baseline 2015 tokens；典型调用 5015–7015 tokens；完整 references 24273 tokens。

---

## v0.9.10 — 2026-04-23

### 🏷 Release 目录带项目名前缀（命名一致化）
- `RELEASE_DIR` 改为 `Release/<PROJECT_NAME>-<VERSION>/`，与 artifact 文件名约定一致。

### 🔄 已有 Release/ 目录迁移
- v0.9.6–v0.9.9 四个历史目录原地重命名为新格式。

### 🧪 测试
- 新增 `test_release_dir_naming.sh`（5 用例）；套件 24 → **25 套件全绿**。

### 📝 备注
- 向后兼容：standalone audit 旧版本仍自动检测 legacy 布局。

---

## v0.9.9 — 2026-04-23

### ✨ 新功能 — A + B + D（v0.9.x 产出物质量升级）
- 支持 `SOURCE_DATE_EPOCH` 可复现构建；`RELEASE_NOTES` 自动注入当前版本 CHANGELOG 条目；新增 CycloneDX 1.5 SBOM 产物。

### 🧪 测试
- 新增 source date epoch / release notes 注入 / SBOM 生成三个测试套件；21 → **24 套件全绿**。

### 📝 备注
- checksums 覆盖扩展至 4 件；`RELEASE_NOTES` 首次真正"自说明"。

---

## v0.9.8 — 2026-04-23

### 🔒 Reproducible source tarball（Gotcha #14）
- 修复三个不确定性来源（文件 mtime、遍历顺序、gzip header），实现 tarball 字节确定性。

### 🐛 顺带发现 Gotcha #15 — BSD mv 破坏 latest 软链
- 改用 `ln -sfn` 替代 `mv -f`，跨平台原子替换已有 symlink-to-directory。

### 🧪 测试
- 新增 tarball reproducibility / latest swap 两个套件；19 → **21 套件全绿**。

### 📝 备注
- checksums tarball hash 现在确定——发版者与下载者可离线比对。

---

## v0.9.7 — 2026-04-23

### 🔍 自审 sprint — 产物回审迭代
- v0.9.6 首次自举后四轮迭代，修复 `tarball` 泄漏内部镜像（`F1`）、`RELEASE_NOTES` 方式B命令错误（`F2`）、`install.sh` 从发布目录运行中止（`F4`）、README 链接 ROADMAP.md 未平摊（`F5`）及 audit §8 N+1 场景误 FAIL（Gotcha #13）。

### 📝 备注
- 测试套件 18 → **19 套件全绿**；Method A 首次真正可用。

---

## v0.9.6 — 2026-04-23

### 🔧 自举 sprint — 首次自发版时发现并修复 5 个阻塞
- 修复 `skill-creator` 拒绝顶层 `version:` 字段（`Gotcha #8`）、`description` 含 `<>`（`Gotcha #9`）、空 `assets/` 被剥掉（`Gotcha #10`）、`.sanitize-ignore` 未平摊（`Gotcha #11`）及 audit §8 `latest` 缺失硬 FAIL（`Gotcha #12`）；首次自发版 119 ✅ / 0 ❌ / 1 ➖。

### 📝 备注
- 测试套件 17 → **18 套件全绿**；v0.9.5 从未发布。

---

## v0.9.5 — 2026-04-23 *(yanked — never shipped due to Gotcha #8)*

### 🔧 Sprint 2/3 TDD 加固
- v0.9.4 基础上叠加 S2/S3 系列加固（`sanitize` 空格支持、`SAFE_VERSION`、白名单扩展、`trap` 统一清理、`SKILL.md` `description` 精简、双源 `SKIP` 升 `FAIL` 等），因 Gotcha #8 未能发布。

### ✨ GitHub 开源标准补全
- 补全 `SECURITY.md`、`CODE_OF_CONDUCT.md`、`CONTRIBUTING.md`、`LICENSE` 等开源社区文件。

### 🧪 测试
- 新增多项 TDD 套件；`run_all.sh` 从硬编码改为自动发现。

---

## v0.9.4 — 2026-04-22

### 🔧 Sprint 1 TDD 修复（4 个 CRITICAL）
- 修复发版日期、VERSION 同步、dry-run 副作用、测试隔离等四个关键问题，确保流水线在 `set -euo pipefail` 下可靠运行。

### 🧪 测试基础建设
- 建立 TDD 基础设施：首批测试套件、`run_all.sh` 自动发现、CRITICAL 修复的 RED→GREEN 验证。
