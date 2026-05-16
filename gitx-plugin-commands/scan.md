---
description: GitX 密钥/敏感串扫描与脱敏 —— 发版前清理闸门
---

激活 `gitx-release` skill 并执行密钥扫描/脱敏（脚本入口 `scripts/release-sanitize.sh`）。

关键约束：脚本默认 fail-closed，发现敏感串即阻断发版流程。
