---
description: 在当前项目根生成 .gitx/ 政策包 + RELEASE_GUIDELINE.md（auto-detect skill / mac / both / empty）
---

激活 `gitx-release` skill 并执行 `gitx-init` 子命令（脚本入口 `scripts/gitx-init.sh`）。

关键约束：本子命令只生成政策文件，不执行任何 git / gh 操作。
