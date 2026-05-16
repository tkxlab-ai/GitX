---
description: GitX Deep Audit —— 对发版产物运行只读审计闸门
---

激活 `gitx-release` skill 并执行 Deep Audit（脚本入口 `scripts/release-audit.sh`）。

关键约束：审计为只读，不修改文件系统、不执行 git / gh 操作。
