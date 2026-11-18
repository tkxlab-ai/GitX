---
description: 在当前项目根生成 .gitx/GITHUB_RELEASE_SOP.md —— GitHub 公开镜像发布 runbook（只生成不执行 git/gh）
---

激活 `gitx-release` skill 并执行 `gitx-sop` 子命令（脚本入口 `${CLAUDE_PLUGIN_ROOT}/skills/gitx-release/scripts/gitx-sop.sh`）。若 `${CLAUDE_PLUGIN_ROOT}` 未展开，脚本在本插件的 `skills/gitx-release/scripts/` 目录下。

关键约束（与 SKILL.md 约束 #1 一致）：本子命令**只生成文档不执行任何 git / gh 操作**。
