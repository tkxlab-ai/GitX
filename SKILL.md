---
name: gitx-release
description: GitX skill — use whenever user mentions release, ship, audit, publish, or version bump for a skill — even without naming it. Packages .skill + tarball, runs Deep Audit, scans secrets. Use via /gitx-release or 发版.
license: MIT
compatibility: macOS/Linux, bash 3.2+ (POSIX shell), git 2.x, optional python3 + venv for vendored skill-creator path; falls back to deterministic zip packager when Python/PyYAML unavailable.
---

# GitX — TKX 通用发版流水线

一套跨项目的发版脚本 + 审查策略，适用于任何 `skills/<name>/SKILL.md` 布局的项目。把分散的发版动作（版本号 / 打包 / 扫描 / 平摊 / audit）统一到一个主命令：`/gitx-release`。

## 何时触发

- 用户输入 `/gitx-release`
- 用户说 `GitX release` / `GitX 发版` / `一键发版` / `自动打包发布`
- 兼容：用户说 `release` / `发版` / `打版本` / `publish` / `bump` / `出一版`
- 用户在**任何符合结构的项目**里（Handoff / 1by1 / ...）要求自动化发版

## 工作模式

| 动作 | 触发词 | 入口 | 行为 |
|------|--------|------|------|
| **一键发版** | `/gitx-release` | `scripts/gitx-release.sh` | 自动递增 patch 版本 → 同步 SKILL.md + CHANGELOG → 跑完整 release gate；不自动 git push |
| **发版** | `release <version>` | `scripts/release.sh` | 跑测试 → 打包 `.skill` + tarball → 平摊文档 + install.sh → sanity 扫描 → CHANGELOG 记录 → Deep Audit；不自动 git push |
| **补跑审计** | `audit <version>` | `scripts/release-audit.sh` | 对已有 `Release/<ver>/` 重新跑 40+ 项静态审查（断网也能跑）|
| **sanity 扫描** | `scan <dir>` | `scripts/release-sanitize.sh` | 扫指定目录的 6 类敏感信息（凭证 / 绝对用户路径 / 真实邮箱 / 公网 IP / MAC / SSH-GPG 指纹） |
| **项目初始化** | `/gitx-init` · 项目初始化 · `init guideline` | `scripts/gitx-init.sh` | 在当前项目根生成 `.gitx/` 政策包 + `RELEASE_GUIDELINE.md`；auto-detect skill / mac / both / empty（v1.6.0+）|
| **marketplace 同步** | `/gitx-marketplace` · `gitx-marketplace register/bump/list` | `scripts/gitx-marketplace.sh` | 把当前技能加入 / 更新中央 marketplace。首次手动 `register --repo OWNER/REPO`；之后 `gitx-release` 自动 bump（v1.13.0+）|
| **GitHub 发版 SOP** | `/gitx-sop` · `推 GitHub` | `scripts/gitx-sop.sh` | 在当前项目根生成 `.gitx/GITHUB_RELEASE_SOP.md`（GitHub 公开镜像发布 runbook，占位符渲染，**只生成不执行 git/gh**）（v1.7.0+）|
| **推送并发布** | `推送并发布` · `使用 GitX 推送并发布` · `push and publish` | 无新脚本（AI 依次执行两条现有命令） | ① `git push origin main`（只接受 fast-forward，被拒即停）→ ② `scripts/gitx-gitea-release.sh --version <ver>`，远端同版本 tag 字节不同时自动改用 `--force`；不碰 GitHub。详见下方「推送并发布」（v1.13.0+）|

`/gitx-release` 每次正式运行都会写入本地诊断日志：`Release/logs/gitx-release-<timestamp>-<version>.log`，成功后在同目录生成 `.sha256` 摘要。日志**不**进入 `Release/<project>-<version>/`——那是可分发产物目录（已审计、每个文件都在 `checksums.txt` 里），而日志含绝对路径等本机信息，会被 sanitizer 拦下（v1.13.0 起）。日志包含项目、skill、版本、子流程输出和退出码；默认不联网、不自动回传，需要 debug 时由用户或 CI artifact 主动提供。

## 关键约束

1. **不自动 git 操作**：`git tag` / `git push` / `gh release` 一律留给用户手动（TKX 政策 §10.10）。skill 只生成本地 `Release/<version>/` 产物
2. **不改业务代码**：只读项目结构，写入限于 `Release/` 子树 + 根 `CHANGELOG.md` 追加
3. **失败即 abort**：测试失败 / sanity 命中 / audit 未过 → 退出码 1，**禁止 FORCE=1 绕过**（silent ghost release 护城河）
4. **双源脚本检查**：发版前强制 `diff -rq $PROJECT_ROOT/scripts/ $PROJECT_ROOT/skills/$SKILL_NAME/scripts/`，有漂移直接 abort（TKX v2.2 §4 #11）
5. **项目识别靠环境变量**：`PROJECT_ROOT`（默认 cwd）/ `PROJECT_NAME`（默认 cwd 目录名 lowercased）/ `SKILL_NAME`（自动从 `skills/*/SKILL.md` 探测，多个 skill 时必须显式设）

## 执行流程

### 发版（`release <version>`）

`scripts/release.sh` 把发版管线拆为 15 个命名函数（主流程 ~25 行），严格按以下顺序调用：

| # | 函数 | 说明 |
|---|------|------|
| 1 | `preflight_checks` | version 验证 + SKILL.md 一致性 + CHANGELOG gate + clean-tree 预检（wrapper 自己写的 VERSION/CHANGELOG 经 `_GITX_WRAPPER_DIRTY_OK` 放行） |
| 2 | `run_tests` | 跑 tests/run_all.sh（全绿才继续） |
| 3 | `check_dual_source` | 根 scripts/ 与 skill scripts/ byte-identical |
| 4 | `build_skill_package` | .skill 打包（skill-creator 优先 / zip fallback） |
| 5 | `build_source_tarball` | staging + rsync（gitignored 路径剪除）/ scrub-tarball 路径 + 可复现 tarball（mtime 归一 + sorted） |
| 6 | `assert_changelog_tarball_parity` | tarball 内 CHANGELOG 与 Release/ 真相源字节一致 |
| 7 | `run_sanity_scans` | 先扫 staging 目录，再扫 .skill 解压内容（release-sanitize.sh） |
| 8 | `flatten_docs` | 平摊 9 份文档 + scripts/ + references/ + assets/ + install.sh |
| 9 | `generate_attestations` | SBOM (emit-sbom.sh) + TOKEN_USAGE (emit-token-usage.sh) |
| 10 | `generate_release_notes` | 三安装路径 + CHANGELOG inject |
| 11 | `update_changelog` | 平摊 Release/CHANGELOG.md |
| 12 | `generate_checksums` | checksums.txt 覆盖 release dir 内所有出货文件（含 scripts/、references/、CHANGELOG），install.sh 据此校验 |
| 13 | `build_full_tarball` | 全量 tarball + 把自身 hash 追加进外层 checksums.txt |
| 14 | `run_deep_audit` | release-audit.sh --inline（40+ 项全绿才继续） |
| 15 | `update_latest_symlink` | `ln -sfn` 原子更新 Release/latest |
| post | `invoke_gitea_release`（wrapper） | post-release: publish to a private Gitea release repo — opt-in via `.gitx/gitea-release-target`；尽力而为，失败只 ⚠️ 警告，不改 wrapper 退出码 |

入口 wrapper 会在调用 `release.sh` 前创建 `Release/logs/gitx-release-*.log`，并用 `tee` 保存完整输出。无论 release 成功与否，日志和它的 `.sha256` 都只留在 `Release/logs/`，不进入 `Release/<project>-<version>/`（v1.13.0 起；Gitea 发布步骤也以"目录内每个文件都在 checksums.txt 里"为前提）。

wrapper 用法：`gitx-release.sh [--dry-run] [--version vX.Y.Z] [--skip-marketplace] [--skip-gitea-release]`。`--skip-*` 只跳过本次；要长期关闭，删除对应 marker（`rm .gitx/marketplace-target` / `rm .gitx/gitea-release-target`）。

#### Gitea release repo（可选，v1.13.0+）

在项目里放一个 `.gitx/gitea-release-target`（gitignored、本机专用、拒绝软链）即开启；没有它就什么都不做。内容只有一行，语法 `HOST[:SSH_PORT]/OWNER/REPO`，例如 `<gitea-host>:2222/my-releases/MySkill`（SSH 端口默认 22；不允许 `://`、空白、`password`/`token` 字样）。release 成功后 wrapper 调 `scripts/gitx-gitea-release.sh --version vX.Y.Z`：
- 先校验 `checksums.txt`，再把平摊后的 `Release/<project>-<version>/` 作为 `main` 的一次提交 + 注解 tag `vX.Y.Z` 经 SSH 推到 `ssh://git@HOST:PORT/OWNER/REPO.git`（这是约束 1 的显式 opt-in 例外）；
- 再经 `https://HOST/api/v1` 创建 Gitea Release，附 `.skill` / `-full.tar.gz` / `checksums.txt` / `install.sh`。这一步需要 `~/.netrc` 里有该 host 的 `machine` 条目（密码或 token；**绝不**存进仓库）；没有则跳过并 ⚠️ 提示。

运维前提：① host key 必须已在 `known_hosts`——先手动 `ssh -p PORT git@<gitea-host>` 一次（BatchMode 不会提示确认）；② API 固定为 `https://HOST`（443 端口），marker 里的端口只用于 SSH。

失败不影响本地 release；按警告里的命令单独重跑（`bash scripts/gitx-gitea-release.sh --version vX.Y.Z`）。只有两种情况才加 `--force`：① 远端 tag 已存在但 checksums 不同；② tag 一致，但 Gitea Release 的附件已过期（stale）或缺少 `checksums.txt` 附件。

#### 推送并发布（v1.13.0+）

用户说 `推送并发布` / `使用 GitX 推送并发布` / `push and publish` 时，AI 依次做两件事，中间不再追问。这是约束 1「不自动 git push」的第二个显式 opt-in 例外：只在用户说出这句话时执行，脚本本身仍然不推。

1. **推送源码仓**：`git push origin main`。前提：工作树干净、当前在 `main`。只接受 fast-forward；被拒就停下报告，**不** `--force`、不 `--no-verify`、不推 tag，也不进入第 2 步（源码还没上去的产物不能先发出去）。
2. **发布到 Gitea 发布仓**：`bash scripts/gitx-gitea-release.sh --version vX.Y.Z`（版本取 `VERSION` sidecar）。退出码 0 = 已发布（或远端已有且字节一致，输出 ℹ️），正常；退出码 1 且输出里有 `use --force` 字样 = 远端同版本 tag 已存在但 checksums 不同，或 Release 附件过期——这句话术的语义就是「让远端等于本地发布目录」，所以直接改用 `--force` 重跑一次；退出码 2 = 没有 `.gitx/gitea-release-target`（或用法错误），只做第 1 步并说明；其他退出码 1 原样报告、不重试。

前置判断：若发布目录比 HEAD 旧（上次 `gitx-release.sh` 之后又有提交改过会进产物的文件），先重切（`gitx-release.sh --version vX.Y.Z`），再走上面两步。完成后回报两个仓库的 `main` commit、tag 与 Release 链接。GitHub 侧（打 tag、推 GitHub、GitHub Release）不在这句话术里，仍按政策 §4 由用户手动。

辅助脚本：
- `scripts/lib/detect-project.sh` — PROJECT_NAME/SKILL_NAME 自动检测（被 release.sh + audit.sh + sync-dual-source.sh 共享）
- `scripts/emit-sbom.sh` — CycloneDX 1.5 SBOM 生成器（独立调用）
- `scripts/sync-dual-source.sh` — 双源脚本同步工具
- `emit-token-usage.sh` — runtime token 估算器

### 审计（`audit <version>`）

1. 定位 `$PROJECT_ROOT/Release/<version>/`
2. 跑 10 节共 40+ 项静态检查：基础存在性 / 平摊文档 / 根同步 / CHANGELOG 真实性 / tarball 内容 / .skill 解压对齐 / sanity 二扫 / latest 软链 / **双源一致性**（v2.2 新增 §9）/ RELEASE_NOTES 软警告
3. 输出 `🎉 PASS` or `❌ FAIL + 失败详单`

### sanity 扫描（`scan <dir>`）

直接调 `release-sanitize.sh <dir>`，用户可以在任何目录独立跑（不限于 release 产物）。

### 非标准项目升级提示

如果用户是在发版场景中调用 GitX，但当前项目缺少 `skills/*/SKILL.md` 或 `tests/run_all.sh`，不要只做人工结构检查后口头拒绝。必须至少运行一次：

```bash
PROJECT_ROOT="$(pwd)" bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh --dry-run
```

项目识别阶段会 fail-fast；如果发现旧式 flat `SKILL.md`，会在项目根目录生成 `GitX_Upgrade_Guideline.md`。生成 guideline 后再告诉用户：本次没有发版、没有 tag/push，需要先按该文件完成标准化迁移。

## 政策参照

完整的发版政策 / 防呆清单 / 低级错误库在 `references/TKX_Git_Release_policy_and_process.md`（v2.3，1091 行）。需要定制时先读相关章节：
- §1 顶层原则 / §2 生命周期 / §3 SemVer
- §4 Pre-Release Gate（11 项必过）
- §5 脱敏与安全 / §6 产物标准 / §6.11 CLI 脚本统一规范
- §7 CHANGELOG 规范
- §8 Post-Release Deep Audit（14 项必查）
- §10 常见低级错误与防呆（10 大类）
- §11 Git / GitHub 流程
- §12 附录（LICENSE 模板 / 速检清单）

## 何时**不**触发

- 用户问"怎么发版" → 这是**问知识**，引用 `references/` 回答即可，不要直接跑脚本
- 用户要推 GitHub / 打 tag / 发 GitHub Release → 这些是**影响 upstream 的不可逆操作**，必须用户手动，按 CLAUDE.md 规则
- 用户只是做静态咨询且没有要求发版/打包/升级 → 不运行 wrapper；但一旦是发版场景，非标准项目也要运行 `gitx-release.sh --dry-run` 生成升级指南

## 设计哲学

- **TKX 政策即代码**：每条政策尽量用 shell 断言落地，而非仅文档建议（v2.2/v2.3 把 7 条从"aspirational"转成 code-enforce）
- **Dijkstra Invariants over conventions**：用可计算谓词（`diff -rq` / grep pattern）代替模糊判断
- **Norman Gulf of Evaluation**：每步显式输出 `✅ / ❌ / ➖`，不让用户猜
- **跨项目可复用**：零 `handoff` 字面硬编码，PROJECT_NAME / SKILL_NAME 全部环境变量化

## License

MIT — Copyright (c) 2026 TKXLAB.AI — https://github.com/tkxlab-ai
