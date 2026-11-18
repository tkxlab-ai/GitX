---
description: GitX 密钥/敏感串扫描与脱敏 —— 发版前清理闸门
---

激活 `gitx-release` skill 并执行密钥扫描/脱敏（脚本入口 `${CLAUDE_PLUGIN_ROOT}/skills/gitx-release/scripts/release-sanitize.sh`）。若 `${CLAUDE_PLUGIN_ROOT}` 未展开，脚本在本插件的 `skills/gitx-release/scripts/` 目录下。

关键约束：脚本默认 fail-closed，发现敏感串即阻断发版流程。
