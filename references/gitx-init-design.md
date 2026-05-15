# gitx-init — Design Memo (Phase 3, draft v0.1)

> **Status**: design draft awaiting Boss review. No code yet.
> **Target ship**: gitx-release v1.6.0 (new feature, minor bump).
> **Prior session lock-in**: `A 串行 path / 自动侦测 / .gitx/ + 顶层 RELEASE_GUIDELINE.md`（both, not either）。

---

## 0. One-line summary

`gitx-init` 在任意项目根生成 `.gitx/` 政策包 + 顶层 `RELEASE_GUIDELINE.md` 索引，让该项目里的开发 session AI Agent 知道"本仓发版要走 GitX 标准 + 本仓属于 skill / mac software / both / empty 哪种"，从此自适应。

---

## 1. Command signature

```
gitx-init [--type=auto|skill|mac|both|empty]
          [--force]                # 覆盖已存在的 .gitx/
          [--dry-run]              # 打印动作，不写文件
          [--help]
```

- Default: `--type=auto`
- 入口: `scripts/gitx-init.sh`（dual-source 到 `skills/gitx-release/scripts/gitx-init.sh`，byte-identical 强制）
- 退出码:
  - `0` 成功（含 dry-run）
  - `2` 用法错误（未识别 flag / type 取值非法）
  - `3` `--type=auto` 检测为 empty 且 stdin 非 TTY（CI/pipe 无法交互兜底）
  - `4` `.gitx/` 已存在且未传 `--force`

---

## 2. Auto-detect rules

| 检测信号（priority desc）| 命中 → type |
|---|---|
| `skills/*/SKILL.md` 存在 + `*.xcodeproj` OR `Package.swift` OR `src-tauri/` OR `Cargo.toml`（含 `[[bin]]`）| `both` |
| 仅 `skills/*/SKILL.md` | `skill` |
| 仅 `*.xcodeproj` / `Package.swift` / `src-tauri/Cargo.toml` / `Package@swift-*.swift` | `mac` |
| 都没 + TTY | 交互问 Boss（5 选 1：skill / mac / both / empty / abort）|
| 都没 + 非 TTY | exit 3 + 提示用 `--type=<x>` 显式指定 |

**为什么不把 `go.mod` 当 mac**: Go 项目目标平台太广（CLI / server / library），不能假设 mac。如果将来要支持，开 `--type=go-cli` 显式子类，不混入 auto-detect。

---

## 3. `.gitx/` 包结构

```text
<project-root>/
├── .gitx/
│   ├── policy.md                # TKX 发版政策 v2.3 摘录（核心条款 + Why）
│   ├── scenarios/
│   │   ├── skill-flow.md        # if type ∈ {skill, both} ← 把"skill release flow"教给 dev AI
│   │   └── mac-flow.md          # if type ∈ {mac, both}   ← 把"mac signed release flow"教给 dev AI
│   ├── audit-snippet.sh         # 一行命令 sanity check（dev AI 可直接 dispatch）
│   └── version.txt              # 生成时 gitx-init 版本号，便于未来 upgrade
└── RELEASE_GUIDELINE.md         # 12-section 顶层索引（dev AI 入口）
```

**为什么 RELEASE_GUIDELINE.md 在顶层而不在 `.gitx/`**: dev AI Agent 启动 session 时主要 grep 顶层文件名（README.md / HANDOFF.md / RELEASE_GUIDELINE.md），藏在 `.gitx/` 容易被忽略。`.gitx/` 装"细节 + 模板"，顶层 RELEASE_GUIDELINE.md 装"该看哪 + 该跑哪"导航。

---

## 4. `RELEASE_GUIDELINE.md` 12-section skeleton

每个项目类型生成略不同（{skill-only} / {mac-only} / {both} fence 区段）:

| § | 章节 | 内容（skill 类示例） |
|---|---|---|
| 1 | Project type | auto-detected: `skill` (skills/foo/SKILL.md found at <path>) |
| 2 | Quick start | `bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh` |
| 3 | Pre-flight checklist | tests/run_all.sh 绿 / Release/CHANGELOG.md 有顶部 entry / .sanitize-ignore 就位 / VERSION sidecar 单调递增 |
| 4 | Release artifacts spec | `.skill` bundle / source tarball / full tarball / checksums.txt / SBOM.json / TOKEN_USAGE.json / install.sh |
| 5 | Audit gates | §0_spec / §0b / §1-§11k（自动跑，无需手动）|
| 6 | TKX policy reference | → `.gitx/policy.md` |
| 7 | Test-scenarios contract | TEST-SCENARIOS.md soft-warn since v1.3.2; REQUIRED 8 件 hard-check |
| 8 | CHANGELOG conventions | `## vX.Y.Z — YYYY-MM-DD` 顶部锚定，TODO gate accepts sentinel |
| 9 | Versioning policy | SemVer + `VERSION` sidecar（**not** SKILL.md `metadata.version:`，Gotcha #16）|
| 10 | Sanity-scan red list | 6 类: credentials / abs-path / email / public-IP / MAC / SSH-GPG fingerprint |
| 11 | Multi-CLI install matrix | `~/.claude/skills/` + `~/.agents/skills/` + `~/.config/opencode/skills/`（canonical + 2 symlinks）|
| 12 | Handoff & gotchas | → `HANDOFF.md`（若存在）+ pointer 到本仓 Gotchas list |

`mac` 类版本: §4 加 `.app` / `.dmg` / `.pkg` + codesign-team-id + notarytool submission-id；§5 加 mac-release v0.2.0 audit chapters；§10 加 entitlements + provisioning profile red list。

`both` 类: section §1 写两个 type 并列，子章节用 `### Skill side` / `### Mac side` fence。

---

## 5. Master template 存储 + dual-source 契约

- **In-repo master**: `references/gitx-init/`
  - `policy.template.md` / `scenarios/skill-flow.template.md` / `scenarios/mac-flow.template.md` / `audit-snippet.template.sh` / `RELEASE_GUIDELINE.template.md`
- **Install propagation**: `install.sh` 在第 N 个 checkpoint 增 `cp -R references/gitx-init/` 到 `~/.agents/skills/gitx-release/references/gitx-init/`
- **Runtime read order**: gitx-init.sh 先读 canonical (`$HOME/.agents/skills/gitx-release/references/gitx-init/`)，找不到 fallback dev-tree (`$SCRIPT_DIR/../references/gitx-init/`)
- **Byte-identical 强制**: BDD `tests/test_gitx_init.sh` 断言 dev-tree master ↔ `.skill` bundle 复制 ↔ canonical install ↔ 项目生成产物 四处 byte-identical（除了 placeholder substitution）

---

## 6. Placeholder substitution

模板里用 `{{VAR}}` 占位，gitx-init 渲染时替换:

| 占位符 | 取值来源 |
|---|---|
| `{{PROJECT_NAME}}` | `basename "$PROJECT_ROOT" \| tr '[:upper:]' '[:lower:]'` |
| `{{PROJECT_TYPE}}` | auto-detect 结果 |
| `{{SKILL_NAME}}` | `_skill_name_from_file` from detect-project.sh（仅 skill / both）|
| `{{DATE}}` | `date "+%Y-%m-%d"` |
| `{{GITX_VERSION}}` | gitx-release VERSION sidecar |
| `{{XCODEPROJ_NAME}}` | `basename *.xcodeproj .xcodeproj`（仅 mac / both）|

不使用 `envsubst`（macOS 默认不带）— 用 `sed -e 's/{{VAR}}/value/g'` 多次替换，纯 POSIX。

---

## 7. BDD test matrix（`tests/test_gitx_init.sh`）

**Static (5 assertions)**:
1. `scripts/gitx-init.sh` exists + executable + dual-source 同步
2. `--help` 输出含全部 5 个 `--type` 取值 + 4 个 exit code 说明
3. `references/gitx-init/` 含 5 个 master template 文件 + 非空
4. SKILL.md "工作模式" 表新增 gitx-init 行 + 触发词 ≥3 个（`gitx-init` / `项目初始化` / `init guideline`）
5. `commands/gitx-init.md` slash shim 存在 + frontmatter 合规

**Behavior (10 cases via fixture project)**:
- C1 `--type=skill` fixture(`skills/foo/SKILL.md` only) → 生成 `.gitx/scenarios/skill-flow.md` 不含 mac-flow.md
- C2 `--type=mac` fixture(`Package.swift` only) → 生成 mac-flow.md 不含 skill-flow.md
- C3 `--type=both` fixture(both signals) → 两 scenarios 都生成
- C4 `--type=empty` 显式 → 仍生成最简 .gitx/ + RELEASE_GUIDELINE.md 但 §1 标 "type: empty (deferred decision)"
- C5 `--type=auto` 无信号 + 非 TTY → exit 3 + stderr 含 `--type=<x>` 提示
- C6 `--type=auto` 自动命中 skill → 行为 = C1
- C7 第二次跑（idempotent）→ 不覆盖；若有 user-edit 检测 → 报告并 exit 4
- C8 `--force` 覆盖 → success + 写 `.gitx/.previous-<timestamp>/` 备份目录
- C9 `--dry-run` → 仅打印动作 + exit 0 + 文件系统零写入
- C10 generated `.gitx/policy.md` byte-identical to master template after placeholder substitution

---

## 8. release-audit.sh §0c gate（防 gitx-init 模板 drift）

加 `audit_section_0c_gitx_init_templates()`:
- check: `references/gitx-init/` 含 5 个 expected file
- check: 每个 template 含 ≥3 个 `{{...}}` 占位符（确保模板没被意外硬编码）
- check: `scripts/gitx-init.sh` 存在 + dual-source 同步
- check: `tests/test_gitx_init.sh` 存在 + 至少 15 个 BDD 断言（5 static + 10 behavior）
- check (optional): `commands/gitx-init.md` 存在

仅在本仓 self-bake 触发；外项目 audit 不强制（外项目不一定有 gitx-init 集成）。

---

## 9. SKILL.md 改动（v1.6.0）

将"工作模式：三条命令"改为"四条命令"，加第 4 行:

```markdown
| **项目初始化** | `/gitx-init` | `scripts/gitx-init.sh` | 在当前项目根生成 `.gitx/` 政策包 + `RELEASE_GUIDELINE.md` 索引；auto-detect skill / mac / both / empty |
```

frontmatter `description` 加触发词（注意：pushy + 字数限制 ≤220）:
> "GitX-Release skill — use whenever user mentions release, ship, audit, publish, version bump, **or 项目初始化 / init guideline / .gitx setup**. Packages .skill + tarball, runs Deep Audit, scans secrets. Use via /gitx-release / /gitx-init or 发版."

不超 220 字 limit（待 `quick_validate.py` 验证）。

---

## 10. install.sh 改动（v1.5.0 → v1.6.0）

在第 4 checkpoint（Install canonical）的 references copy step 加一行（已经在 copy `references/*.md`）— 加 `-R` flag 让子目录也走:

```bash
# 已有
run cp -R "$SELF_DIR/references/." "$CANONICAL/references/"
```

如果已经是 `cp -R` 则无改动。需要 verify。

`tests/test_install_path_completeness.sh` 加新断言: canonical 含 `references/gitx-init/` 子目录 + 5 个 file。

---

## 11. Out of scope（Linus #3 "what does it break"）

- ❌ gitx-init **不**改项目现有 source / tests
- ❌ gitx-init **不**调用 git（no commit / push / branch / tag）
- ❌ gitx-init **不**自动填 RELEASE_GUIDELINE.md 业务字段（only structure + project-type-specific defaults；Boss / dev AI 填业务细节）
- ❌ gitx-init **不**自动 create `tests/run_all.sh` / `Release/` / `skills/<name>/` 骨架（那是 `gitx-bootstrap` 未来 candidate，今天不在 scope）

---

## 12. Risk register

| # | Risk | Mitigation |
|---|---|---|
| R1 | 项目已有 `.gitx/` | default refuse + 提示 `--force`；`--force` 时备份到 `.gitx/.previous-<ts>/` |
| R2 | Auto-detect 误判（e.g. Bash skill 偶含 `go.mod` test fixture）| `--type=skill` explicit override + auto-detect 不递归 `tests/`/`fixtures/` 子树 |
| R3 | Template drift（dev-tree / .skill / canonical / 项目产物 四处）| BDD C10 byte-identical 断言 + §0c audit gate |
| R4 | First user 自己 = gitx-release | self-bake 流程跑 `gitx-init --type=skill` on gitx-release 自身，eat-our-own-dogfood |
| R5 | 项目根本不该上 GitX（业务 repo 非 skill / mac）| `--type=empty` 提供"我有 RELEASE_GUIDELINE.md 但放弃强契约"的 escape hatch |

---

## 13. Build sequence (TDD red→green→refactor)

1. **RED**: `tests/test_gitx_init.sh`（5 static + 10 behavior，全 fail）
2. **GREEN A**: 写 `references/gitx-init/` 5 个 template + frontmatter
3. **GREEN B**: 写 `scripts/gitx-init.sh` 最小版（detection + dry-run print） → static asserts 全过
4. **GREEN C**: 实现 placeholder substitution + `.gitx/` 写入 → C1-C4 过
5. **GREEN D**: 实现 idempotent + `--force` + `--dry-run` → C5-C9 过
6. **GREEN E**: byte-identical 断言 → C10 过
7. **GREEN F**: `commands/gitx-init.md` slash shim + SKILL.md table 更新
8. **GREEN G**: `release-audit.sh` §0c gate
9. **GREEN H**: install.sh `references/` 子目录 copy 验证 + `test_install_path_completeness.sh` 加断言
10. **REFACTOR**: dedup detection logic — `_skill_name_from_file` 既然在 detect-project.sh 已有，gitx-init 也 source 它
11. **SELF-BAKE**: 跑 `gitx-init --type=skill` on 本仓 → 生成本仓 `.gitx/` + `RELEASE_GUIDELINE.md` → audit + push v1.6.0
12. **PILOT**: 在 `/tmp/fake-skill-foo` empty dir 跑 `gitx-init --type=skill` → check 产物可被 dev AI session "看懂"

---

## 14. Open design questions（need Boss decision before code）

**Q1**: `.gitx/policy.md` 内容深度

| 选项 | 大小 | 优劣 |
|---|---|---|
| A | full copy of `references/TKX_Git_Release_policy_and_process.md`（46KB）| 完整 / 重复 / dev AI tokens 多 |
| B (Recommended) | 摘录核心 5-10 条条款 + link 到 master（10-15KB）| 平衡 / 维护链清晰 |
| C | 仅 pointer 不含内容 | 最轻 / 但 dev AI 跨仓 read 麻烦 |

**Q2**: `--type=auto` 检测为 empty 且 TTY 时

| 选项 | 行为 |
|---|---|
| A (Recommended) | 5-option `read -p` 交互问 Boss（skill/mac/both/empty/abort）|
| B | 不交互，exit 3 + 提示用 `--type=<x>` |

**Q3**: gitx-init 是否同时初始化 `tests/run_all.sh` / `Release/` / `skills/<name>/` 骨架？

| 选项 | 行为 |
|---|---|
| A (Recommended) | **不**初始化。gitx-init 只装 `.gitx/` + `RELEASE_GUIDELINE.md`；项目骨架交给将来 `gitx-bootstrap`（不同 scope）|
| B | 一并初始化骨架（scope creep risk）|

**Q4**: gitx-release 版本号

| 选项 | 行为 |
|---|---|
| A (Recommended) | v1.6.0（minor — 新 feature，符合 SemVer）|
| B | v1.5.1（patch — gitx-init opt-in 不影响 v1.5.0 用户） |

---

## 15. 估算

- Design memo 落定 + Q1-Q4 决定: **20 min**（Boss review 即可）
- RED phase + GREEN A-G: **3-4 hours**（最大头 = GREEN C 模板渲染）
- GREEN H + REFACTOR + SELF-BAKE: **1 hour**
- PILOT + ship v1.6.0: **30 min**

**总计**: ~5 hours（含 review buffer）

---

**待 Boss confirm Q1-Q4 后启动 RED phase。**
