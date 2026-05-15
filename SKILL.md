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
| **GitHub 发版 SOP** | `/gitx-sop` · `推 GitHub` | `scripts/gitx-sop.sh` | 在当前项目根生成 `.gitx/GITHUB_RELEASE_SOP.md`（GitHub 公开镜像发布 runbook，占位符渲染，**只生成不执行 git/gh**）（v1.7.0+）|

`/gitx-release` 每次正式运行都会写入本地诊断日志：`Release/logs/gitx-release-<timestamp>-<version>.log`。成功后同一份日志和 `.sha256` 校验文件也会复制进 `Release/<project>-<version>/gitx-release-<timestamp>-<version>.log`，和本次 release 产物绑定。日志包含项目、skill、版本、子流程输出和退出码；默认不联网、不自动回传，需要 debug 时由用户或 CI artifact 主动提供。

## 关键约束

1. **不自动 git 操作**：`git tag` / `git push` / `gh release` 一律留给用户手动（TKX 政策 §10.10）。skill 只生成本地 `Release/<version>/` 产物
2. **不改业务代码**：只读项目结构，写入限于 `Release/` 子树 + 根 `CHANGELOG.md` 追加
3. **失败即 abort**：测试失败 / sanity 命中 / audit 未过 → 退出码 1，**禁止 FORCE=1 绕过**（silent ghost release 护城河）
4. **双源脚本检查**：发版前强制 `diff -rq $PROJECT_ROOT/scripts/ $PROJECT_ROOT/skills/$SKILL_NAME/scripts/`，有漂移直接 abort（TKX v2.2 §4 #11）
5. **项目识别靠环境变量**：`PROJECT_ROOT`（默认 cwd）/ `PROJECT_NAME`（默认 cwd 目录名 lowercased）/ `SKILL_NAME`（自动从 `skills/*/SKILL.md` 探测，多个 skill 时必须显式设）

## 执行流程

### 发版（`release <version>`）

`scripts/release.sh` 把发版管线拆为 12 个命名函数（主流程 ~25 行），严格按以下顺序调用：

| # | 函数 | 说明 |
|---|------|------|
| 1 | `preflight_checks` | version 验证 + SKILL.md 一致性 + CHANGELOG gate |
| 2 | `run_tests` | 跑 tests/run_all.sh（全绿才继续） |
| 3 | `check_dual_source` | 根 scripts/ 与 skill scripts/ byte-identical |
| 4 | `build_skill_package` | .skill 打包（skill-creator 优先 / zip fallback） |
| 5 | `build_source_tarball` | staging + rsync + 可复现 tarball（mtime 归一 + sorted） |
| 6 | `run_sanity_scans` | 先扫 staging 目录，再扫 .skill 解压内容（release-sanitize.sh） |
| 7 | `flatten_docs` | 平摊 9 份文档 + scripts/ + references/ + assets/ + install.sh |
| 8 | `generate_attestations` | SBOM (emit-sbom.sh) + TOKEN_USAGE (emit-token-usage.sh) + checksums |
| 9 | `generate_release_notes` | 三安装路径 + CHANGELOG inject |
| 10 | `update_changelog` | 平摊 Release/CHANGELOG.md |
| 11 | `run_deep_audit` | release-audit.sh --inline（40+ 项全绿才继续） |
| 12 | `update_latest_symlink` | `ln -sfn` 原子更新 Release/latest |

入口 wrapper 会在调用 `release.sh` 前创建 `Release/logs/gitx-release-*.log`，并用 `tee` 保存完整输出。release 成功时，wrapper 会把日志复制到 `Release/<project>-<version>/`；release gate 失败时，日志仍保留在 `Release/logs/`，用于跨项目问题复盘。

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
