# GitX

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Tests](https://img.shields.io/badge/tests-36%20suites%20green-brightgreen)](./tests)
[![Policy](https://img.shields.io/badge/TKX%20policy-v2.3-blue)](./references)
[![Scope](https://img.shields.io/badge/scope-claude--skill-orange)](./ROADMAP.md)

一套严肃对待发版的脚本 + 审查策略，把分散的发版动作（版本号 / 测试 / 打包 / 敏感信息扫描 / 开源合规 / 完整性校验）统一到一个命令：`/gitx-release`。

## 📌 当前 Scope（v0.9.x）

**本版本仅支持 Claude Code skill 项目的发版**（布局：根目录 `skills/<name>/SKILL.md` + `tests/run_all.sh` + 双源 `scripts/`）。

**通用化（Swift / Rust / Go / Python / 纯源码包）见 [ROADMAP.md](./ROADMAP.md) — v1.0 以 Swift 作首个非-skill 参考实现。**

本仓库本身不使用自己的 release.sh 发版（它是管线源码，不是 skill-structured 项目）。安装到下游项目后才生效。

## 功能 Features

- ✅ **一键发版** — 测试 → 双源漂移检查 → `.skill` + tarball + `checksums.txt` 打包 → 平摊文档 → 3 次 sanity 扫描 → CHANGELOG 记录 → Deep Audit
- ✅ **TOKEN_USAGE.md** — 发版时自动生成运行时 context token 成本披露（双档 tokenizer: tiktoken 精确 / bash 降级）
- ✅ **CycloneDX SBOM** — 自动生成 `sbom.cyclonedx.json`（SLSA L3 供应链审计，零外部依赖）
- ✅ **可复现构建** — 支持 `SOURCE_DATE_EPOCH`（Debian/Nix/SLSA 标准），source tarball hash 确定性
- ✅ **40+ 项静态审计** — 合规 / 文档 / 结构 / 许可证 / 泄漏 / digest 完整性六类检查，断网也能跑
- ✅ **六维敏感信息扫描** — 凭证（30+ 模式）/ 绝对用户路径 / 真实邮箱 / 公网 IP / MAC / SSH-GPG 指纹
- ✅ **白名单机制** — `.sanitize-ignore` 项目根显式豁免，**无 FORCE 绕过**（S3-1）
- ✅ **--dry-run 模式** — release.sh 支持 `--dry-run` 预览，不实际修改文件系统
- ✅ **失败自动回滚** — release 失败时自动清理半成品 Release 目录
- ✅ **本地诊断日志** — `/gitx-release` 每次正式运行都会写入 `Release/logs/gitx-release-*.log`；成功后同一份日志和 `.sha256` 校验文件也会复制进 `Release/<project>-<version>/`
- ✅ **严格模式** — `set -euo pipefail`，失败即 abort，不存在"跳过敏感发现继续"的选项
- ✅ **政策即代码** — 每条 TKX 政策条款落地为 shell 断言，不只是文档
- ✅ **安全默认** — 从不自动 `git push` / `git tag`（TKX §10.10 护城河）

## 快速开始 Quick Start

### 安装

```bash
git clone https://github.com/TKXLAB-AI/gitx-release.git
cd gitx-release
./install.sh --dry-run       # 预览
./install.sh                 # 正式安装到 ~/.agents/skills/gitx-release/
./install.sh --force         # 已存在/已安装时覆盖升级
```

安装器会同时创建 Claude Code / OpenCode 兼容入口。若看到 `Already installed or occupied`，说明目标路径已有旧安装或占用；确认要升级时使用 `./install.sh --force`。

### 使用（在下游 skill 项目里）

安装后，在目标项目根目录输入：

```text
/gitx-release
```

它会自动读取当前 skill 的 `VERSION` sidecar，递增 patch 版本，同步 `VERSION` 与 `Release/CHANGELOG.md`，然后跑完整 gate、打包、生成 attestations，并在 `Release/<project>-<version>/` 下完成 Deep Audit。

每次正式运行都会生成本地诊断日志：

```text
Release/logs/gitx-release-<timestamp>-<version>.log
Release/<project>-<version>/gitx-release-<timestamp>-<version>.log
Release/<project>-<version>/gitx-release-<timestamp>-<version>.log.sha256
```

第一份是全局流水线日志索引；第二份在成功版本目录里，和本次 release 产物绑定。日志只保存在当前项目，不会自动联网回传。CI 可以把 `Release/logs/` 或具体版本目录作为 artifact 上传；需要排查时，把对应 log 发给维护者即可。

底层脚本仍保留给 CI 或故障排查：

```bash
PROJECT_ROOT=$(pwd) bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh
PROJECT_ROOT=$(pwd) bash ~/.agents/skills/gitx-release/scripts/release-audit.sh v1.0.0
bash ~/.agents/skills/gitx-release/scripts/release-sanitize.sh ./dir-to-scan
```

### Codex CLI

Codex 可用 `/skills` 打开技能列表，也可以输入 `$` 快速检索并选择技能。Codex 会从 `~/.agents/skills/gitx-release` 发现主 skill；安装器不会在 `~/.codex/skills/` 下创建第二个 alias skill，避免同一 skill 在 `$` 列表出现两行。

在 Codex 里可以这样调用：

```text
$gitx-release GitX release this project
```

也可以用 selector alias：

```text
$gitx-release
```

也可以输入 `$` 后选择 **GitX**，再输入 `GitX release this project`。

### 要求

- Bash 4.x / macOS 或 Linux
- 下游项目需满足：`skills/<name>/SKILL.md`、`tests/run_all.sh`、根 `scripts/` 与 `skills/<name>/scripts/` byte-identical 双源
- Codex 兼容：`agents/codex-commands.txt` 必须包含 `$<skill-name>`，且每个 `commands/*.md` 都必须有对应 `$<command-name>`；若命令名含大写，还必须提供小写 `$<command-name>` alias。Deep Audit 会逐项失败拦截

## 文档

- [INSTALL.md](./INSTALL.md) — 详细安装 / 升级 / 卸载
- [TEST-SCENARIOS.md](./TEST-SCENARIOS.md) — 手工端到端测试场景
- [ROADMAP.md](./ROADMAP.md) — 通用化（Swift/Rust/Go/Python）规划
- [SECURITY.md](./SECURITY.md) — 漏洞披露流程
- [CONTRIBUTING.md](./CONTRIBUTING.md) — 开发贡献流程
- [SKILL.md](./SKILL.md) — Claude Code skill 入口
- [references/](./references) — TKX 政策 v2.3 原文

## 命令矩阵 Commands

| 动作 | 触发词 | 脚本 | 说明 |
|------|--------|------|------|
| 一键发版 | `/gitx-release` | `scripts/gitx-release.sh` | 自动版本号 + 全流程编排 |
| 发版底层入口 | `release <version>` | `scripts/release.sh` | 指定版本的强 gate 发版 |
| 审计 | `audit <version>` | `scripts/release-audit.sh` | 40+ 项静态检查 |
| 扫描 | `scan <dir>` | `scripts/release-sanitize.sh` | 敏感信息扫描 |

## 贡献 Contributing

欢迎 PR。提交前请：
- 跑 `bash tests/run_all.sh` 确认 36 套件全绿
- 遵循 TDD：RED → GREEN → REFACTOR
- 详见 [CONTRIBUTING.md](./CONTRIBUTING.md) 与 [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)

## 许可 License

[MIT](./LICENSE) © 2026 TKXLAB.AI
