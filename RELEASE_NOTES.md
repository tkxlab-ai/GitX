# Release Notes

> Latest highlights only. Full history: [`Release/CHANGELOG.md`](Release/CHANGELOG.md).
> Per-version notes ship inside each GitHub Release and
> `Release/git_release_skill-vX.Y.Z/RELEASE_NOTES.md`.
> Current version: see [`VERSION`](VERSION).

## Latest — v1.8.0

**Claude Code plugin distribution + MacAudit-grade community standard.**

- **Installable as a Claude Code plugin**: `.claude-plugin/marketplace.json`
  + `.claude-plugin/plugin.json` →
  `/plugin marketplace add tkxlab-ai/GitX` then
  `/plugin install gitx-release@tkx-skills`. Dual-path: `install.sh` (flat
  `/gitx-sop`, 4 CLIs) is retained alongside the plugin path (namespaced
  `/gitx-release:gitx-sop`, Claude-Code-only, marketplace-updatable).
- **Community-file standard**: bilingual `README` + `CONTRIBUTING` /
  `CONTRIBUTING_CN`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, top-level
  `RELEASE_NOTES.md`, layered `docs/` — modeled on the Claude-MacAudit
  repository standard.
- **gitx-sop SOP enrichment**: the generated GitHub-publish runbook now
  guides any project to the same professional page standard (bilingual
  README, community files, per-command docs, Releases per tag).

## How releases work

Every tagged version has a matching GitHub Release with 3 assets
(`.skill` + `checksums.txt` + `sbom.cyclonedx.json`) and is verifiable
offline via `shasum -a 256 -c checksums.txt`. The pipeline never pushes
upstream automatically — publishing is always a reviewed, human action.
