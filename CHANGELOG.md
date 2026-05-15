# Git Release Pipeline — Release History

记录各版本的关键变化。最新版本在最上面。

> 历史完整累积记录同步到 `Release/CHANGELOG.md`（由 `scripts/release.sh` 自动维护）。

## v1.1.7 — 2026-05-08

> 本版本合并三条独立修复（按发现时序）：
> 1. **Gotcha #33 长期方案**：`build_source_tarball` 改用 git-archive — 由 1by1 项目第三次 .planning/.archive/ 泄漏复发触发（commit `3e55e14` 落代码）。注意：HANDOFF Gotcha 编号此前曾误用 #20；正式编号为 **#33**（原 #20 是 v1.0.4 的 PROJECT_NAME / SKILL_NAME 环境污染，已修复完毕，与本次无关）。
> 2. **Gotcha #32**：`set -u` 下 `$var` 紧接 Chinese 全角标点被 bash 吃成变量名一部分 — 由 mac-release v0.1.0 self-bake 第三次尝试触发，定位到 `release-audit.sh:265` `$first_ver_line）` 这条 echo。
> 3. **`3e55e14` 三个未完成项**：dual-source 镜像未同步（VERSION + release.sh）、`scrub-tarball.sh` 未列入 `check_dual_source` whitelist、新代码路径无 TDD 测试。本次一并补齐。

### 🔒 修复 Gotcha #33 长期方案: `build_source_tarball` 改用 git-archive(发起方:1by1)

**症状**:`scripts/release.sh build_source_tarball` 走 rsync staging 模式 — `rsync` 默认不读 `.gitignore` / `.gitattributes export-ignore`,只信赖函数内手写的 `--exclude=` 列表。结果:

- `.planning/codebase/{ARCHITECTURE,INTEGRATIONS,STACK,STRUCTURE}.md`(.gitignore'd 内部规划)
- `.archive/reference-v0.2-single-file.md`(.gitattributes export-ignored 历史归档)
- `GITX_ALIAS_AUDIT.md` / `GITX_PIPELINE_REVIEW_2026-04-30.md` / `HEURISTIC-EVALUATION.md`(audit / 评估文件,export-ignored)

**全部进了 v0.5.3 / v0.6.0 / v0.6.1 三次连续 release 的 source tarball**。1by1 项目记录了 Gotcha #20(2026-05-06 首发)+ 第三次复发(2026-05-07)。Method 1(发布前 `mv` untracked dirs)被证明不可靠 — 依赖人工记忆。

### 🛠 修复(`scripts/release.sh:366-405`)

`build_source_tarball()` 顶部插 detect-and-delegate 分支:

```bash
PROJECT_SCRUB="$PROJECT_ROOT/scripts/scrub-tarball.sh"
if [ -x "$PROJECT_SCRUB" ] && git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    bash "$PROJECT_SCRUB" "$TAR_OUT" "${PROJECT_NAME}-${VERSION}" HEAD
    return 0
fi
# else fall through to legacy rsync staging mode (unchanged behaviour)
```

`scripts/scrub-tarball.sh` 是项目自带的(1by1 已 vendor,~90 行 bash),内部:

- `git archive --format=tar --prefix --worktree-attributes <ref> | gzip -n`
- 只见 git-tracked 内容(`.gitignore`'d 文件物理在 worktree 但不在 index → 不入 archive)
- `.gitattributes export-ignore` 路径自动排除(用 `--worktree-attributes` 即使 ref 早于 .gitattributes 也读最新规则)
- `gzip -n` 剥离 mtime + filename → byte-deterministic
- 自带 `VERIFY=1` 二跑 cmp 自检模式

### 🧪 验证

- 1by1 v0.6.1 模拟新路径产物:`640K / 339 files / 仅 git-tracked / 0 leak patterns`(符合 `.gitignore` + `.gitattributes export-ignore`)。
- `bash -n release.sh` 语法 OK。
- 向后兼容:无 `scripts/scrub-tarball.sh` 的项目落到 legacy rsync 分支,行为完全不变。
- `--dry-run` 模式两条分支都正确处理(`run` wrapper 已透传)。

### 📌 影响

- **依赖此 wrapper 的所有项目**:从此次发布起,如果你的项目根有 `scripts/scrub-tarball.sh`(可执行 + git repo),`gitx-release.sh` 会自动用它打 source tarball,不必再依赖 wrapper 的硬编码 exclude 列表。
- **没有 `scripts/scrub-tarball.sh` 的项目**:行为不变。但建议 vendor 一份(参考 1by1 项目)以获得 `.gitignore`/`.gitattributes` 自动遵守 + byte-determinism。
- 历史已发布 tarball:不动(immutability);若已知含泄漏,各项目自行 hotfix(参考 1by1 commits `b21c23c` / `5358672`)。

### 🔗 关联

- 发起方:1by1 项目 Gotcha #33 第三次复发 + 用户 autopilot 直接修。
- 1by1 commits:`5358672` v0.6.0 hotfix / `c433194` v0.6.1 patch / `dc6a99c` v0.6.1 release(in-place hotfix)。
- 1by1 HANDOFF.md Decision 2026-05-07(优先级反转 — "v0.7 必修")。

---

### 🔒 Gotcha #32 修复:`set -u` 下 `$var` 紧接 Chinese 全角标点被吞进变量名（发起方:mac-release self-bake）

**症状**: `release-audit.sh:265` 的 echo `❌ 顶部版本号 ≠ ${VERSION}（顶部为: $first_ver_line）` 在某些 bash 版本/locale 下报错 `first_ver_line）: unbound variable`。`$first_ver_line` 上一行刚 grep 赋值，按理已 bound — 但 bash 把后面紧贴的 Chinese 全角闭括号 `）`（U+FF09，UTF-8 `\xef\xbc\x89`）当成 identifier 续接，结果实际 expand 的变量名是 `first_ver_line）`（含 3 字节非 ASCII），那是没赋值过的 → set -u abort。

发现路径:mac-release v0.1.0 self-bake 第三次尝试。gitx-release 自己从未触发，因为 self-bake 时顶部版本号始终匹配，走 then 分支（line 261-262），else 分支（含此 echo）从未在 happy path 上执行过。是 **dogfood 必到外项目才暴露的隐式假设**。

### 🛠 修复(`scripts/release.sh / release-audit.sh`)

- `release-audit.sh:265` 把 `$first_ver_line）` 改为 `${first_ver_line}）`，ASCII `{}` 显式 delimit identifier。
- 加 `tests/test_audit_chinese_paren_safe.sh`(11 个 BDD 断言):2 条行为(`${var}）` 形式始终 OK；裸 `$var）` 形式记录 informational/abort 二态),2 条静态 guard 覆盖 5 个 .sh + scripts/lib/ — 任何未来回归会立即 RED。

### 🔧 `3e55e14` 后续整理

- **dual-source 镜像同步**:`skills/gitx-release/VERSION` v1.1.6 → v1.1.7;`skills/gitx-release/scripts/release.sh` 同步 root。`3e55e14` 只动了 root 端，破坏 byte-identical 契约 — 直到本次发版前两道 pre-flight check 都会硬 abort。
- **`scrub-tarball.sh` 加入 `check_dual_source` whitelist**:`3e55e14` 给项目了一个新选项(可选 vendor `scripts/scrub-tarball.sh`),但忘了它会在 dual-source diff 出 root-only 漂移。`scripts/release.sh:check_dual_source()` 和 `scripts/release-audit.sh §9` 各加一条 case 放行。
- **`scrub-tarball.sh` 路径 TDD 覆盖**:`tests/test_release_tarball_scrub_preferred.sh`(10 个 BDD 断言):6 条静态(PROJECT_SCRUB 路径 / 双 guard / dry-run marker / `return 0` 防 fall-through / rsync fallback 保留 / 1by1 历史注释保留),4 条行为(planted scrub fixture / no-scrub fixture 各两面)。

### 🧪 验证

- `bash tests/run_all.sh` → **78 suites / 0 failed**(76 baseline + 2 new tests)。
- `diff -rq scripts/ skills/gitx-release/scripts/` → clean。
- `bash scripts/release-sanitize.sh .` → ✅ Release sanity clean。
- 自发版通过 `gitx-release.sh --version v1.1.7` 端到端 audit。

### 🔗 关联

- Gotcha #32 / #33(HANDOFF 同时新增条目)。
- mac-release v0.1.0 self-bake 是 gitx-release v1.1.6 第一次跑外项目;暴露的 friction 都已闭合到本版本。
- 后续观察:HANDOFF Gotcha #34 占位为 ".sync-conflict-* 文件污染 dual-source check"(本次以 `.gitignore` 加 `*.sync-conflict-*` 规则解决)。

---

## v0.9.11 — 2026-04-24

### 🧮 新 artifact: `TOKEN_USAGE.md` — 为终端用户披露运行时 context token 成本

被 release 的 skill 装到用户 Claude Code 后,每次触发会占用 AI 的 context window。之前用户装之前看不到这个开销,装完才发现贵;现在 release 产物里带一份 `TOKEN_USAGE.md`,把**这个具体 skill** 在 runtime 进入 context 的 token 量按三档列出(baseline / typical / full references pull),折算 Sonnet/Haiku/Opus 三价。

### 🆕 新脚本: `scripts/emit-token-usage.sh`

- 独立可测,~180 行,零外部依赖
- **Tier-1** tokenizer: `python3 + tiktoken cl100k_base`(±10% vs Claude tokenizer)
- **Tier-0** 降级: 纯 bash 启发式(保守偏高 20-35%,自动标注"install tiktoken for precision")
- 输出分层:
  - `SKILL.md` → **always loaded**(baseline,每次触发必进 context)
  - `references/**.md` → **on-demand**(SKILL.md 指引 AI 按需读取)
  - `scripts/**` → **NOT LOADED**(执行层,由 Bash tool 跑,源码不入 context)
  - 根目录 docs → **bundle-only**(README/CHANGELOG 等纯人看,Claude Code 不加载)
- 价格可通过 env 覆盖: `CLAUDE_SONNET_INPUT_PER_MTOK` / `CLAUDE_HAIKU_INPUT_PER_MTOK` / `CLAUDE_OPUS_INPUT_PER_MTOK`

### 🔧 流水线接入

- `release.sh §2.7b`: 在 SBOM 之后、checksums 之前调 `emit-token-usage.sh`(仅 skill bundle 跑,非 skill 项目静默 skip)
- `release.sh §2.8`: checksums 覆盖面 4 → **5** 件(加入 `TOKEN_USAGE.md`,防篡改对齐 SBOM/install.sh 级别)
- `release-audit.sh §11j`: 6 项检查(存在 / 标题 / SKILL.md baseline 标注 / tokenizer 披露 / 场景表数字合理 / checksums 覆盖);非 skill 项目 ➖ SKIP

### 🧭 Decision

tokenizer 分层选了 **C(两档并存)** 而非 A(强依赖 tiktoken)或 B(只 bash 启发式);audit 严苛度选了 **Y(非 skill SKIP,skill FAIL)** 而非 X(一律 FAIL)。详见 `HANDOFF.md` Decision Log 2026-04-24。

### 🧪 测试

- 新增 `tests/test_token_usage.sh`(14 用例,TDD 严格 RED→GREEN)
- 测试套件: 25 → **26 suites 全绿**

### 📊 对本项目 dogfood 数据(tiktoken 精确)

| 场景 | Input tokens | Sonnet 4.6 |
|---|---:|---:|
| Baseline (trigger only) | 2,015 | $0.006 |
| Typical invocation | 5,015–7,015 | $0.015–$0.021 |
| Full references pull | 24,273 | $0.073 |

Bundle 元数据(README/CHANGELOG/LICENSE 等) 合计 14,275 token — **不进 runtime context**。

---

## v0.9.10 — 2026-04-23

### 🏷 Release 目录带项目名前缀（命名一致化）

之前 `Release/v0.9.9/` 看不出属于哪个项目,在 monorepo / 回审场景下有歧义。改为 `Release/<PROJECT_NAME>-<VERSION>/`,与 artifact 文件名约定(`git_release_skill-v0.9.10.skill` / `-source.tar.gz`)一致。

- `release.sh`: `RELEASE_DIR="$PROJECT_ROOT/Release/${PROJECT_NAME}-${VERSION}"`
- `release.sh`: `ln -sfn "${PROJECT_NAME}-${VERSION}" .../Release/latest`
- `release.sh`: CHANGELOG 脚手架模板同步 `Release/${PROJECT_NAME}-$VERSION/`
- `release-audit.sh`: `DIR` 使用新格式;同时**向后兼容** legacy 布局 — 若新路径不存在但 `Release/$VERSION/` 存在,audit 降级到 legacy 模式,可以审计历史版本
- `release-audit.sh §8`: latest target 期望值按 `LEGACY_LAYOUT` flag 切换(legacy → bare $VERSION;new → `${PROJECT_NAME}-${VERSION}`)

### 🔄 已有 Release/ 目录迁移

原地 `mv`:

```
Release/v0.9.6 → Release/git_release_skill-v0.9.6
Release/v0.9.7 → Release/git_release_skill-v0.9.7
Release/v0.9.8 → Release/git_release_skill-v0.9.8
Release/v0.9.9 → Release/git_release_skill-v0.9.9
Release/latest → git_release_skill-v0.9.9
```

### 🧪 测试

- 新增 `tests/test_release_dir_naming.sh`（5 用例）
  - release.sh `RELEASE_DIR` 包含 `$PROJECT_NAME-$VERSION`
  - release-audit.sh `DIR` 同格式
  - `ln -sfn` 目标参数同格式
  - audit §8 期望值按新格式比对
  - 功能断言: `Release/latest` 指向 `<name>-<version>/` 而非 bare `<version>/`
- 测试套件：24 → **25 suites 全绿**

### 📝 备注

- 向后兼容: standalone `audit v0.9.6` (老版本)仍可工作(自动检测 legacy 布局)
- 产物内容未变(`.skill` / tarball / SBOM / checksums)只有外层目录名改
- `Release/CHANGELOG.md` 的 `Artifacts:` 行从 v0.9.10 开始写新路径

## v0.9.9 — 2026-04-23

### ✨ 新功能 — A + B + D（v0.9.x 产出物质量升级）

#### A. SOURCE_DATE_EPOCH 支持

按 Debian / Nix / SLSA 标准，release.sh 尊重 `$SOURCE_DATE_EPOCH` 环境变量：

- 已设：使用该 epoch 作为 staging mtime（典型用法 `SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)`）
- 未设：沿用 v0.9.8 的默认 `200001010000.00`

跨 BSD `date -r EPOCH` 和 GNU `date -d @EPOCH` 两种风格自动兼容。接入 CI 后可让 tarball hash 与 commit SHA 一一对应。

#### B. RELEASE_NOTES 注入 CHANGELOG 当前版条目

之前的 `RELEASE_NOTES.md` 只列文件清单和三条安装路径，用户要打开 `CHANGELOG.md` 才知道本版改了什么。现在 release.sh 在 RELEASE_NOTES 末尾自动 append 一个 `## What's new in $VERSION` 章节，内容来自 `Release/CHANGELOG.md` 的对应块（awk 按 `## vX.Y.Z` 起始、`---` 结束提取）。

#### D. CycloneDX 1.5 SBOM 生成

新产出物 `Release/<ver>/sbom.cyclonedx.json`，列出 `.skill` / tarball / install.sh 的 name + version + SHA-256 哈希。满足 SLSA L3 / 开源供应链审计最低要求。

- 零外部依赖（纯 bash + 已有的 `shasum`/`sha256sum`）
- 确定性：timestamp 跟随 SOURCE_DATE_EPOCH，serialNumber 由 artifact hashes 派生
- 自身被 checksums.txt 覆盖（tamper-evident）
- Audit 新增 §11i 校验 SBOM 形态：bomFormat / specVersion / metadata.component.version / 各 artifact 入列

### 🧪 测试

- 新增 `tests/test_source_date_epoch.sh`（5 用例）— 含"同 epoch → byte-identical / 异 epoch → 不同"双向功能断言
- 新增 `tests/test_release_notes_changelog_inject.sh`（3 用例）— 含 awk 提取隔离性验证
- 新增 `tests/test_sbom_generation.sh`（5 用例）— 含 JSON 解析 + CycloneDX shape 校验
- 测试套件：21 → **24 suites 全绿**

### 📝 备注

- 无破坏性变更
- checksums.txt 现覆盖 4 件（.skill / tarball / install.sh / sbom.cyclonedx.json）
- RELEASE_NOTES 文本首次真正"自说明"（不用二次跳转）

## v0.9.8 — 2026-04-23

### 🔒 Reproducible source tarball（Gotcha #14）

v0.9.7 幂等重跑时发现：`.skill` 和 `install.sh` hash 稳定，**source tarball hash 每次不同**。用户无法离线验证"我手上的 tarball 是否与官方一致"，违反 SLSA L3 可复现构建。

三个不确定性来源逐一修复：

1. **文件 mtime** 写进 tar header → `find "$STAGE_SUB" -exec touch -t 200001010000.00 {} +` 归一化到固定 epoch
2. **文件系统遍历顺序** 不稳定 → `find | LC_ALL=C sort | tar --no-recursion -T -` 显式排序
3. **gzip header 内嵌时间戳和文件名** → `gzip -n`（strip name + timestamp）

跨 BSD tar (macOS) / GNU tar 兼容。

### 🐛 顺带发现 Gotcha #15 — BSD mv 破坏 latest 软链

自审验证 idempotency 时发现 `mv -f .latest.tmp latest` 在 BSD mv (macOS) 上 follow 目标软链:当 `latest → v0.9.7/` 已存在,`mv -f .latest.tmp latest` 把 `.latest.tmp` 移进了 `v0.9.7/` 目录(BSD mv 解释 `latest` 为目标目录),结果:

- `latest` 软链原地不动,指向旧版本
- `v0.9.7/.latest.tmp` 孤儿文件累积
- standalone audit §8 `❌ Release/latest → v0.9.7(应为 v0.9.8)` 挂

修复: 改用 `ln -sfn "$VERSION" "$PROJECT_ROOT/Release/latest"` — `-n` flag 让 BSD/GNU ln 一致把已存在的 symlink-to-directory 当普通文件替换,跨平台原子 swap。

### 🧪 测试

- 新增 `tests/test_tarball_reproducibility.sh`（4 用例）
  - 静态断言：release.sh 含 `gzip -n` / `touch -t` / `find | sort | tar -T -`
  - 功能断言：两次 build 同一 staging → tarball byte-identical
- 新增 `tests/test_release_latest_swap.sh`（4 用例）
  - 静态断言：release.sh 用 `ln -sfn`（非 `mv -f`）
  - 功能断言：recipe 正确替换 symlink-to-directory
  - 回归守卫：`v0.9.x/.latest.tmp` 孤儿检测
  - 平台诊断：BSD mv 行为探针(记录 macOS/Linux 实际表现)
- 测试套件：19 → **21 suites 全绿**

### 📝 备注

- 无破坏性变更；任何下游项目自动受益（触发条件只在 release.sh 流程中）
- checksums.txt 的 tarball hash 现在是确定的——发版者和下载者可离线比对
- idempotency sanity: 同一 source 两次 `bash scripts/release.sh v0.9.8` → `.skill` / tarball / install.sh 三件 sha256 完全一致

## v0.9.7 — 2026-04-23

### 🔍 自审 sprint — 产物回审迭代

v0.9.6 首次自举成功后，对发版产物（`.skill` / tarball / 平摊文档 / install.sh / checksums）进行深度回审，四轮迭代共发现并修复 5 个隐藏问题：

#### F1 tarball 泄漏内部自发版镜像

- 症状: 用户解压 `*-source.tar.gz` 看到根级 `scripts/` 和 `skills/git-release-pipeline/scripts/` 两份完全相同的文件，困惑
- 根因: flat-layout 项目使用 `skills/<name>/` 作为 self-release 镜像（解决 v0.9.x skill-creator 布局兼容），rsync 未排除
- 修复: `release.sh` rsync 启发式——若 `$PROJECT_ROOT/SKILL.md` 存在，自动 `--exclude='/skills'`；`release-audit.sh §5` 同步改为 flat-aware（校验根级 scripts/ + SKILL.md 而非 skills/）
- 影响面: 仅本项目 + 未来任何采用 flat-bootstrap 的新项目

#### F2 RELEASE_NOTES 方式 B 指示 `cp commands/*.md` 但 bundle 无 commands/

- 症状: 用户跟随 Method B 执行到 `cp ~/.claude/skills/git-release-pipeline/commands/*.md ~/.claude/commands/` 报错（源文件不存在）
- 根因: `release.sh` RELEASE_NOTES 模板硬编码假设 skill 有 slash command shim；本项目（及任何纯逻辑 skill）无 commands/
- 修复: 检测 `$SKILL_SRC_DIR/commands/*.md` 存在时才 emit `mkdir -p ~/.claude/commands` 和 `cp .../commands/*.md ...` 两行；否则只 emit `mkdir -p ~/.claude/skills`

#### F4 install.sh 从 Release 目录运行会 abort（Method A broken）

- 症状: `cd Release/v0.9.7 && ./install.sh` 报 `❌ Missing required file: .../scripts/release.sh`，自此 **任何使用本 release.sh 的项目 Method A 都 broken**
- 根因: `release.sh` 平摊步骤只拷了 docs + install.sh + SKILL.md 到 `Release/<ver>/`，没拷 `scripts/` / `references/` / `assets/`；但 install.sh line 60-66 要求这几个目录在 `$SELF_DIR` 下
- 修复: `release.sh` 平摊步骤新增 `cp -R $SKILL_SRC_DIR/{scripts,references,assets} $RELEASE_DIR/`（条件拷贝），并 `chmod +x scripts/*.sh`

#### F5 README 链 `ROADMAP.md` 但未平摊到 Release/<ver>/

- 症状: Method A 用户在 Release dir 打开 README 点 ROADMAP.md 链接 → 404
- 根因: `release.sh` 平摊白名单遗漏 ROADMAP.md（项目特定文档）
- 修复: 平摊循环加入 ROADMAP.md（存在时才拷，保持 cross-project 兼容）

#### Gotcha #13 audit §8 N+1 发版时 inline audit 误 FAIL

- 症状: 首次自发版 v0.9.7 时，audit §8 `❌ Release/latest → v0.9.6（应为 v0.9.7）`。v0.9.6 的 "latest 缺失→SKIP" 修复没覆盖这个 N+1 场景
- 根因: inline audit 运行时 latest 还指向上一版 v0.9.6（S1-5 故意让 release.sh 在 audit 通过后才原子更新），但 audit §8 mismatch-target 分支硬 FAIL
- 修复: `release-audit.sh` 接受 `--inline` flag；inline 模式下若 `latest_target` 指向的旧版本目录仍存在，§8 emit ➖ SKIP；standalone 调用保留严格 target 校验。`release.sh` 调用 audit 时传 `--inline`
- 新增 `tests/test_audit_inline_flag.sh`（6 用例）防回归

### 📝 备注

- 测试套件从 18 → **19 suites 全绿**（新增 `test_audit_inline_flag.sh`）
- 本次 sprint 未引入破坏性变更；所有修复同时适用于 flat-layout 自发版项目 + 传统 `skills/<name>/` 布局项目
- Method A（`cd Release/<ver> && ./install.sh`） 首次真正可用
- 回审流程: inline audit → unpack .skill → extract tarball → install.sh dry-run → real install → cross-ref scan;每轮问题修好后重包再审

## v0.9.6 — 2026-04-23

### 🔧 自举 sprint — 首次自发版时发现并修复 5 个阻塞

首次尝试用本技能给自己发版时，一口气暴露了 5 个真实 bug。v0.9.6 把它们全部 TDD 修掉，自举 release 终于 119 ✅ / 0 ❌ / 1 ➖。

#### 1. Gotcha #8 `[build]` skill-creator 拒绝顶层 `version:` 字段

- 症状: `release.sh:182` `python -m scripts.package_skill` 静默 abort（stdout → /dev/null），release 停在 "Building .skill via skill-creator..."
- 根因: S3-3 契约在 SKILL.md 顶层声明 `version:`，但 skill-creator 校验器只允许 `{allowed-tools, compatibility, description, license, metadata, name}`
- 修复:
  - `SKILL.md` frontmatter: `version: v0.9.5` → `metadata:\n  version: v0.9.6`
  - `release.sh` S3-3 解析器改 awk 状态机：进入 `metadata:` 块后读取缩进的 `version:`；缺失/不一致仍 abort
  - `test_skill_version_consistency.sh` 扩展到 6 用例（含"顶层不得有 version"防回归 + 解析器嵌套识别）

#### 2. Gotcha #9 `[build]` skill-creator 禁止 `description:` 含 `<` / `>`

- 症状: `❌ Validation failed: Description cannot contain angle brackets (< or >)`
- 根因: SKILL.md description 用 `skills/<name>/`、`release <version>`、`audit <version>`、`scan <dir>` 作占位符
- 修复:
  - SKILL.md: `<name>` → `NAME`、`<version>` → `VERSION`、`<dir>` → `DIR`（语义保持一致）
  - `test_skill_description_word_count.sh`: trigger 断言更新为 uppercase 版本

#### 3. Gotcha #10 `[build]` 空 `assets/` 目录被 skill-creator 剥掉

- 症状: audit §6 `.skill 含 assets/` ❌；`.skill 与 bundle 有差异: Only in bundle: assets` ❌
- 根因: upstream skill-creator zip 剥离空目录，但 audit 要求 `.skill` 解压后含 `assets/`
- 修复: 新增 `assets/README.md` 占位文件，说明"保留目录存在"的意图

#### 4. Gotcha #11 `[build]` `.sanitize-ignore` 未平摊到 Release/<ver>/

- 症状: audit §7 post-release sanity 扫描命中 `SECURITY.md` 的业务联络邮箱（本应由白名单豁免）
- 根因: `release-sanitize.sh` 从 `$DIR/.sanitize-ignore` 加载白名单；pre-release 扫 staging 目录（rsync 带来了 `.sanitize-ignore`），post-release 扫 `Release/<ver>/` 却没有
- 修复: `release.sh` §2.6 平摊步骤新增 `.sanitize-ignore` → `Release/<ver>/`

#### 5. Gotcha #12 `[build]` audit §8 `latest` 缺失硬 FAIL 破坏自身契约

- 症状: 首次发版时 `❌ Release/latest 软链接不存在`
- 根因: S1-5 故意让 release.sh 在 audit 通过后才原子创建 latest（避免"audit 失败却已更新 latest"），但 audit 在 release.sh 中是 inline 调用，此时 latest 确实不存在——audit 反过来 FAIL 自己
- 修复:
  - `release-audit.sh §8`: latest 缺失从 ❌ FAIL → ➖ SKIP（保留"target 错误时仍 FAIL"的关键不变量）
  - 新增 `tests/test_audit_latest_symlink_skip.sh`（5 用例）：断言 SKIP 分支 + 防 target-mismatch 分支回归
  - run_all.sh 加载新套件

#### 附带: `$VAR（` 多字节字符解析 bug

- 症状: release.sh line 401 执行 `echo "...$VERSION（..."` 报 `VERSION�: unbound variable`
- 根因: bash locale 相关，`$VERSION` 后紧跟全角 `（` 时被当作变量名一部分
- 修复: 3 处显式加括号 `${VERSION}` `${latest_target}`（release.sh 1 处、release-audit.sh 2 处）

### 📝 备注

- **v0.9.5 从未发布**: 所有 v0.9.5 的 Sprint 2/3 加固与 GitHub 开源标准补全工作保留在代码中
- 无破坏性变更: 下游项目只需把 SKILL.md 顶层 `version:` 移到 `metadata.version:` 即可
- 测试套件从 17 → **18 suites 全绿**（新增 `test_audit_latest_symlink_skip.sh`）

## v0.9.5 — 2026-04-23 *(yanked — never shipped due to Gotcha #8)*

### 🔧 Sprint 2/3 TDD 加固

- **S2-1 (已先落地)**: `release-sanitize.sh` 改用 `find -print0 | while read -d ''`，支持含空格文件名
- **S2-2**: `release.sh` + `release-audit.sh` §4 使用 `SAFE_VERSION`（dot 转义）+ `grep -F`，杜绝 `v1.0.0` 误匹配 `v1X0Y0` 假阳性
- **S2-3/4/5/6/7 (已先落地)**: 白名单扩展 / evals 缩窄 / §2b §6b warn / trap 统一清理 / install.sh §6.10 接口验证
- **S3-2**: `SKILL.md` description 精简到 66 词（原 118 词），保留三条 trigger 语义
- **S3-3**: `SKILL.md` frontmatter 新增 `version:` 字段，`release.sh` 加一致性校验 gate（不一致即 abort）
- **S3-4**: `release-audit.sh §9` 双源缺失从 ➖ SKIP 升级为 ❌ FAIL，执行 v2.3 byte-identical 政策
- **S3-6**: `release-audit.sh §10` 硬编码 `[0-9]+ KB` 从 ⚠️ 软警告升级为 ❌ FAIL
- **S3-7**: `release.sh` 启用 `set -euo pipefail`

### ✨ GitHub 开源标准补全

- 新增 `README.md` / `LICENSE` (MIT) / `CONTRIBUTING.md` / `CHANGELOG.md`（本文件）

### 🧪 测试

- 测试套件从 8 suites / 31 用例 → **12 suites / 47+ 用例全绿**
- 新增测试文件：`test_skill_version_consistency.sh` / `test_audit_dual_source_required.sh` / `test_audit_kb_hardcode.sh` / `test_skill_description_word_count.sh`

Artifacts: `Release/v0.9.5/`

---

## v0.9.4 — 2026-04-22

### 🔧 Sprint 1 TDD 修复（4 个 CRITICAL）

- **S1-1**: `release-audit.sh` 空 `assets/` 目录从 ❌ FAIL → ➖ SKIP
- **S1-2**: `SKILL.md` 删除无实现的 `check policy` 触发词，替换为 `scan <dir>`
- **S1-3**: audit summary 改为三态 `✅N / ❌N / ➖N`，所有 ➖ 分支计数 SKIP
- **S1-4**: `release.sh` audit 失败消息删除 `<重跑 release>` 占位符，改为可执行命令
- **S1-5**: `release.sh` latest 软链从 Step 4 移到 audit 通过后，原子 `ln -sf + mv`

### 🧪 测试基础建设

- 新建 `tests/run_all.sh` + 7 个测试文件 + fixtures（31 个用例）

Artifacts: `Release/v0.9.4/`

---
