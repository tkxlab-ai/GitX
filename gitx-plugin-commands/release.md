---
description: GitX 一键发版：fail-closed 闸门 + 密钥扫描 + 可复现 tarball + CycloneDX SBOM + Deep Audit
---

激活 `gitx-release` skill 并执行发版主流程（脚本入口 `scripts/gitx-release.sh`）。

关键约束（与 SKILL.md 一致）：每个 `git push` / `gh release` 仍需用户显式确认（TKX 政策 §10.10），脚本默认 fail-closed。
