---
description: 在当前项目根生成 .gitx/ 政策包 + RELEASE_GUIDELINE.md；auto-detect skill / mac / both / empty
---

激活 `gitx-release` skill 并执行 `gitx-init` 子命令（脚本入口 `scripts/gitx-init.sh`）。

执行要求：

- 默认行为：在 `$(pwd)` 下生成 `.gitx/policy.md` + `.gitx/scenarios/*` + 顶层 `RELEASE_GUIDELINE.md`
- 自动侦测项目类型（基于 `skills/*/SKILL.md` / `*.xcodeproj` / `Package.swift` / `src-tauri/Cargo.toml`）
- 可用 flag: `--type=auto|skill|mac|both|empty` / `--force` / `--dry-run` / `--help`
- 接 `--force` 时先备份旧 `.gitx/` 到 `.gitx/.previous-<ts>/`
- 接 `--dry-run` 时仅 stdout 打印 would-write 预览，不动文件系统

详细行为契约：`references/gitx-init-design.md`（同仓 master 设计 memo）。
