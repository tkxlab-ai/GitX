---
description: 在当前项目根生成 .gitx/GITHUB_RELEASE_SOP.md —— GitHub 公开镜像发布 runbook（占位符渲染，只生成不执行 git/gh）
---

激活 `gitx-release` skill 并执行 `gitx-sop` 子命令（脚本入口 `scripts/gitx-sop.sh`）。

执行要求：

- 默认行为：在 `$(pwd)` 下生成 `.gitx/GITHUB_RELEASE_SOP.md`（8-Phase GitHub 公开镜像发布 SOP，已修 #1-#8 疏漏）
- 占位符渲染：`{{REPO}}` / `{{PROJECT}}` / `{{PRIVATE_GIT_HOST}}` / `{{DATE}}` / `{{GITX_VERSION}}`
- 可用 flag: `--repo=<owner/slug>` / `--project=<name>` / `--private-host=<host>` / `--force` / `--dry-run` / `--help`
- 接 `--dry-run` 时仅 stdout 打印 would-write 预览，不动文件系统
- 接 `--force` 时覆盖已存在的 `.gitx/GITHUB_RELEASE_SOP.md`

关键约束（与 SKILL.md 约束 #1 一致）：本子命令**只生成文档不执行任何 git / gh 操作**。生成的 SOP 是给项目 dev-session AI 在人工监督下照做的 runbook，每个 `git push` / `gh release` 仍需用户显式确认（TKX 政策 §10.10）。
