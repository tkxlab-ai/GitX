# GitX — Changelog

All notable changes per release, newest first. Chinese parallel: [`CHANGELOG_CN.md`](CHANGELOG_CN.md).

## v1.12.1 — 2026-05-18

### Fixed
- Public CHANGELOG links 404'd on GitHub — README linked `Release/CHANGELOG.md` / `Release/CHANGELOG_CN.md` (private-tree paths) but the published mirror flattens `Release/` away (Gotcha #80). Links now point to flat `CHANGELOG.md` / `CHANGELOG_CN.md`; root mirrors are generated from the source-of-truth `Release/CHANGELOG.md` before the source tarball, so the public changelog is full history, not a stale stub.
- `CHANGELOG_CN.md` was never published — `release.sh` flatten shipped only the EN changelog; the CN parallel + a root mirror now ship so `README_CN`'s changelog link resolves.
- `release.sh` derived the reproducible release date from the stale root `/CHANGELOG.md` (Gotcha #81); it now reads the source-of-truth `Release/CHANGELOG.md`, ending ~11 releases of silent wall-clock fallback.
- README curated numbers had drifted from ground truth — the Deep-Audit citation read `245` while the live audit total is `246` (the `§0i` deep-audit-exactness gate), and "Full history (59 releases)" lagged the actual `61` CHANGELOG entries; both corrected across the bilingual README + templates + skill mirrors — the exact curated-number rot the `§0f`/`§0i` guards exist to catch.

### Changed
- `Quick Start` moved to right after `Why GitX` (before `Comparison`) via the docs-contract manifest; the ToC was reordered with it and is now guarded by a new `test_toc_order` assertion.
- Added an `Install troubleshooting` subsection (EN + CN) covering the local git `insteadOf` HTTPS→SSH rewrite that breaks marketplace install, with web-verified remedies.
- New non-counting release-audit `§0l` published-layout ref gate resolves every README link against the extracted source tarball (the true public layout), so a private-valid/public-broken link aborts the release (Gotcha #80 class fix).

## v1.12.0 — 2026-05-18

### Fixed
- Post-`v1.11.0` adversarial-review hardening — six successive `codex` findings closed at the class: a reusable template scaffolded a missing hero image; `docs-audit` `H10` lost origin enforcement; enforcement was contingent on a README reference; an optional `grep` under `set -euo pipefail` aborted the whole audit; the `hero_asset` declaration was wrongly mirrored into the bundled skill; a referenced missing asset was silently skipped.
- `tests/test_docs_pipeline.sh` — the last `set -e`-unsafe `rc` capture converted to the project-standard safe idiom.

### Changed
- Hero showcase is origin-only — the hardcoded `<img>` was removed from the reusable README templates; the host-specific image now lives solely in the origin's live README, enforced by a manifest-driven `hero_asset:` gate, and `H10` is strict again.
- README badges restyled to the `shields.io` `for-the-badge` family with brand logos; the `@machine` Tests token and the Deep-Audit citation stay byte-frozen so no gate invariant shifts.
- Hero asset replaced with a Boss-supplied web-optimized build (`docs/assets/release-demo.jpeg`) — smaller, content-equivalent.

## v1.11.0 — 2026-05-17

### Added
- Independent bilingual documentation pipeline — every README/CHANGELOG region is generated deterministically (no LLM in the loop) and verified by a hard, fail-closed document-contract auditor.
- CI-parity shellcheck gate (§0j) — the release pipeline now runs the exact shellcheck command GitHub CI enforces, so a green local pipeline means a green public CI.

### Changed
- Professional bilingual README — restructured to the standard layout (hero, value proposition, multi-version What's New, comparison, security, FAQ); English and Chinese kept at structural parity.

### Hardening
- No broken links can ship — every repository-local link and image in the published README must resolve at release time, or the release aborts.

## v1.10.1 — 2026-05-16

### Fixed
- What's-New rot: `gr_whats_new` now machine-derives version + date +
  top-entry highlights from `Release/CHANGELOG.md` (v1.10.0 shipped a bare
  version line + an unguarded hand-maintained Highlight table that missed
  its own release — Boss-found). Stale hand table removed.

### Added
- `gr_command_surface` + `<!-- gitx:managed:command-surface -->` region:
  deterministically documents the install.sh-flat vs marketplace-`/gitx:*`
  command surfaces (the colon namespace is plugin-only — official Claude
  Code docs). Both regions are guarded by the existing generic §0g
  (`gitx-readme --check`, no new audit section) for GitX and for skills
  released through gitx ≥ v1.10.1 that adopt these managed regions; new
  `gitx-readme --init` scaffolds inherit them.

### Hardening
- graphify-out/ + CLAUDE.md private-state leak surface closed to the
  documented five-facet symmetric-parity standard (.gitignore +
  .sanitize-ignore + release.sh rsync --exclude + release-audit.sh
  fail-closed regex (extended in place, no new check — no §0f/§0i count
  rot) + rebrand allow-list + TDD-lock), dual-source byte-identical
  (commit cd843dd, Decision 0021).

## v1.10.0 — 2026-05-16

### Added
- `scripts/gitx-readme.sh` — deterministic README ghostwriter (projen
  pattern, NO LLM/git/gh): `--init` scaffold / refresh / `--check`.
  Own-line markers, fail-closed validation (exit 5), multi-line via temp
  file. Manages suite-count/version/install/whats-new from non-circular
  truths. `references/readme/README.template.md`(+CN) generic scaffold.
- `release-audit.sh §0g readme-sync` (fail-closed `gitx-readme --check`),
  `§0h central-install` (plugin → tkx-skills), `§0i deep-audit-exactness`
  (non-counting meta-gate: README count == live total). All generic-safe
  SKIP + errexit-safe + dual-source.
- Per-repo `test_readme_numeric_accuracy.sh` scaffolded by `--init` for
  dependent skills (Decision 0019, Boss=Both).
- Tests: test_gitx_readme / test_audit_readme_sync /
  test_audit_central_install / test_audit_deep_audit_exactness; boundary
  guard added to test_readme_numeric_accuracy.

### Changed
- README.md/README_CN.md adopt projen managed regions (dogfood). Deep-Audit
  count §0f-consistency + §0i-exactness owned (Decision 0018/0019).

## v1.9.8 — 2026-05-16

**Fix (public README rotted across v1.9.x) + new `§0f` doc numeric-rot guard.** Every v1.9.x release only surgically bumped the README metrics-line version token; the shields badges, suite counts, Deep-Audit numbers, dir-tree comments and the "What's New" table silently rotted and shipped to the public mirror (Deep-Audit badge `227` vs real `230`, `94 BDD suites` vs real `97`, `README_CN` `90+` vs EN `95+`, What's New 7 versions behind). `§0e` only catches version *strings*, not these semantic numbers. Fixes: README.md + README_CN.md corrected (Deep-Audit 230 — verified against a clean build, suite count 97, CN aligned to `95+`, What's New backfilled v1.9.0–v1.9.8). New generic cross-project guard **`release-audit.sh §0f` doc-numeric-rot** (dual-source byte-identical): all README Deep-Audit citations (badge/prose/table) must agree and a public README must not advertise a non-green audit; generic-safe — a project with no README or no audit citation SKIPs (never FAILs, so it cannot break a minimal/fixture project releasing via gitx-release) and is `set -euo pipefail`-safe (each grep `|| true`). Plus the stronger per-repo `tests/test_readme_numeric_accuracy.sh` (exact suite count == live `run_all.sh`, audit citations consistent, 0-FAIL advertised). superpowers + codex iterative audit converged CLEAN (a codex P2 was empirically disproven against a clean build).

Artifacts: `Release/git_release_skill-v1.9.8/`

---

## v1.9.7 — 2026-05-16

**Fix (gitx-sop self-publish exposed a systemic credential-gate bug + a publish-worktree hygiene gap).** The generated GitHub-publish SOP's Phase 1.4/4.4 called `scan-credentials.sh <dir>` (that scanner only accepts ONE file/stdin → a bare-dir arg was a broken/no-op gate) and Phase 5 used a raw `git diff | grep` that does NOT honor `.sanitize-ignore`, so it false-FAILED on the project's own intentional sanitizer self-test fixtures (and `SECURITY.md`'s real contact email). Fixed: all three gates now prefer the project's authoritative `.sanitize-ignore`-aware `release-sanitize.sh` (the SAME gate `release.sh`/`release-audit.sh §11` use) with a recursive per-file `scan-credentials.sh` fallback; since `release-sanitize.sh` reads the whitelist from `<scanned-dir>/.sanitize-ignore`, the artifact-dir scans seed the project-root whitelist in (only if absent), scan, then remove it — artifact unchanged, no false-FAIL. Phase 5 reduced to a tight token+host residual grep (never-whitelisted). The gitx-sop publish worktree `.github-publish-wt/` (own `.git`, public-mirror only) is now five-facet contained: `.gitignore` + `.sanitize-ignore` + `release.sh` rsync `--exclude` (dual-source) + `release-audit.sh` fail-closed regex (dual-source, defense-in-depth) + the rebrand allow-list. Template dual-source byte-identical; TDD-locked via `test_gitx_sop` BEHAVIOR 14 + `test_release_private_state_excludes` Test 1/2c/2d. superpowers 11-round loop + codex iterative audit converged CLEAN.

Artifacts: `Release/git_release_skill-v1.9.7/`

---

## v1.9.6 — 2026-05-16

**Hardening (superpowers 11-round loop + codex iterative audit): handoff v1→v2 working-memory class is now exempted across all five release facets, plus a real long-standing `.python-version` public-tarball leak is closed.** The handoff migration created internal git-orthogonal files (`GOTCHAS.md`, `Handoff_Logs/`, `Handoff_Decisions/`, `HANDOFF.md.pre-v2-backup`); they are now treated exactly like `HANDOFF.md` in `.gitignore`, `release.sh` rsync `--exclude` (dual-source byte-identical), `.sanitize-ignore`, guard #10 `case`, and the rebrand allow-list — five-facet path-set parity, proven symmetric. Guard #10 was hardened: the `grep -vE` pre-filter is reduced to a provable strict subset of the authoritative `case` (`/Release/|/\.git/` only — name exemptions live solely in the `case`; new regression check **#10b**), and the HANDOFF-backup exemption is now explicit `*/HANDOFF.md.bak|*/HANDOFF.md.pre-v2-backup` instead of an unanchored `*/HANDOFF.md.*` that let a `HANDOFF.md.<x>/` directory over-exempt (new regression check **#10c**). codex review then found a genuine P2: `release.sh`'s rsync staging ignores `.gitignore`, so an untracked root `.python-version` (pyenv pin) had been leaking into the public source tarball since ~v1.3.0. Fixed defense-in-depth: `.python-version` added to the rsync `--exclude` list (prevention) **and** to `release-audit.sh`'s fail-closed private-state regex + the artifact scanner (detection) — both dual-source byte-identical, TDD-locked. 26 stale leaked historical source tarballs purged from local `Release/`. No behavior change to the public release contract; all guard fixes are comment-accurate (Tacit#4) and three independent reviewers + codex converged clean.

Artifacts: `Release/git_release_skill-v1.9.6/`

---

## v1.9.5 — 2026-05-16

**Fix (codex stop-gate): guard #10 exempted a shipped file it claimed to protect.** `tests/test_plugin_manifest.sh` ships in the public tarball; guard #10 had to self-exempt because its grep pattern + comment contained the banned literal `marketplace add tkxlab-ai/GitX` — so the stale string still shipped (inside the test) and the guard's "all shipped files" guarantee had a hole. Fixed: the search needle is now assembled with a regex bracket class (`Git[X]`) so the file never contains the literal verbatim; the self-exemption is removed; guard #10 now scans every shipped file **including itself**. Zero shipped files contain the legacy per-repo add literal.

## v1.9.4 — 2026-05-16

**Fix (codex stop-gate): stale per-repo marketplace-add command still shipped.** `.claude-plugin/marketplace.json` + the template `description` still told users `/plugin marketplace add tkxlab-ai/GitX` (the stale per-repo form) — that ships to GitHub. Fixed to the central `/plugin marketplace add tkxlab-ai/marketplace`; stale test header comment updated. `test_plugin_manifest.sh` #10 now code-enforces: no `marketplace add tkxlab-ai/GitX` in any shipped manifest/doc (CHANGELOG history + the guard's own pattern exempt).

## v1.9.3 — 2026-05-15

**Fix: internal design docs were shipping to the public mirror.** `docs/superpowers/{plans,specs}/*` (internal design records, sibling-project naming) had been included in the public source tarball since v1.7.x. Now excluded from the source tarball (same class as HANDOFF). `references/marketplace/marketplace.json.template` `_pending` removed (central repo is source of truth; render strips it anyway — no external-looking repo names checked in). `test_plugin_manifest.sh` #8 statically enforces the docs/superpowers staging exclude.
- **Public docs no longer reference internal-only files**: removed all `HANDOFF.md` links/mentions from README/README_CN (they 404 on the public mirror since HANDOFF is excluded). `test_plugin_manifest.sh` #9 code-enforces: public docs must not reference any internal-only excluded file.

## v1.9.2 — 2026-05-15

**Docs cleanup (user-reported staleness/over-complexity).** Removed all stale `/plugin marketplace add tkxlab-ai/GitX` (→ central `tkxlab-ai/marketplace`); replaced the verbose multi-line "Live build metrics" block + owner-estimate disclaimer with ONE concise line (version · date · models · rough token estimate · by-the-numbers); removed every external-project name (`Claude-MacAudit`/`MacAudit`) from README/README_CN/RELEASE_NOTES/SOP template; refreshed badges (95+ suites) + What's New (v1.8.x/v1.9.x rows). SOP Phase 4.6 + test_gitx_sop BEHAVIOR 13 updated to the concise contract (and now FAIL if the verbose wording or any external repo name reappears).

## v1.9.1 — 2026-05-15

**Fix (codex iterative audit of v1.9.0):** [HIGH] `gitx-init` emitted the target `VERSION` raw into generated plugin/marketplace JSON — kept a `v` prefix (schema wants semver) and a hostile/multiline VERSION could corrupt the heredoc JSON. Added `semver_norm()` (strip leading `v`, first-line-only, strict semver regex, `0.0.0` fallback) on both manifests; dual-source byte-identical. [MED] central marketplace template gitx version drifted (1.8.1 vs repo) — pinned to bare VERSION + `test_central_marketplace` 4b now code-enforces template-version == VERSION. Regression tests for v-strip + hostile VERSION + template drift.

## v1.9.0 — 2026-05-15

**Plugin namespace `/gitx:*` + central TKX marketplace + gitx-init auto-provision + MacAudit-grade page standard.** Built via superpowers subagent-driven TDD (4 tasks, per-task spec+quality review) then codex audit.

### Added

- **Plugin is now `gitx`** → namespaced commands `/gitx:release` `/gitx:sop` `/gitx:init` `/gitx:audit` `/gitx:scan` (custom `gitx-plugin-commands/` path; default `commands/` flat install.sh path `/gitx-sop` unchanged). Canonical `gitx-release` (SKILL.md/scripts/dual-source/install) untouched — `test_rebrand` green.
- **Central marketplace template** `references/marketplace/marketplace.json.template` + `tests/test_central_marketplace.sh` — one `/plugin marketplace add tkxlab-ai/marketplace` then `/plugin install <skill>@tkx-skills`; gitx live via github source, siblings tracked in `_pending`.
- **gitx-init auto-provision**: emits target project's `.claude-plugin/plugin.json` + `.gitx/marketplace-entry.json` (github source; hostile-name-safe via shared `kebab()` helper) + registration instructions. Dual-source byte-identical.
- **MacAudit-grade page standard**: README/README_CN gain a bilingual `📊 Live build metrics` block (Version→VERSION, Models used factual, AI-token line **explicitly owner-maintained estimate, never fabricated**, by-the-numbers). gitx-sop SOP Phase 4.6 now requires this block + central-marketplace registration + a "never invent precise token counts" rule. test_gitx_sop BEHAVIOR 13 guards it.

### Changed

- VERSION → v1.9.0; plugin.json/marketplace.json version + description aligned.

## v1.8.1 — 2026-05-15

**Fix (codex stop-gate): plugin marketplace manifest failed Claude's validator.** `marketplace.json` used `name: "GitX"` (not kebab-case — uppercase is rejected by Claude.ai marketplace sync) and `source: "."` (relative source must start with `./`).

### Fixed

- `marketplace.json`: `name` → `tkx-skills` (kebab-case; install suffix is now `gitx-release@tkx-skills`), `source` → `./`, added `email`/`keywords`. plugin.json version tracks VERSION.
- README/README_CN/RELEASE_NOTES updated to `@tkx-skills` + `marketplace update tkx-skills`.
- `tests/test_plugin_manifest.sh` 4b: enforces kebab-case names + `./` source so the manifest can never again fail Claude's validator.

## v1.8.0 — 2026-05-15

**Claude Code plugin distribution + MacAudit-grade community standard.**

### Added

- **`.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`** — the repo is now installable via `/plugin marketplace add tkxlab-ai/GitX` then `/plugin install gitx-release@GitX`. Dual-path: `install.sh` (flat `/gitx-sop`, 4 CLIs) is retained alongside the plugin path (namespaced `/gitx-release:gitx-sop`, Claude-Code-only, marketplace-updatable). `tests/test_plugin_manifest.sh` (7 checks) guards manifest validity, name/version-vs-VERSION consistency, root component dirs, README dual-path docs, and tarball inclusion.
- **`CONTRIBUTING_CN.md`** + English-primary `CONTRIBUTING.md` (language-linked) + top-level **`RELEASE_NOTES.md`** — community-file set modeled on the Claude-MacAudit repository standard.

### Changed

- `README.md` / `README_CN.md` gain an "Install as a Claude Code plugin" section documenting both paths and the plugin namespacing tradeoff.
- **gitx-sop SOP template Phase 4.6 (new)**: community-file completeness gate — the generated runbook now guides any project to a MacAudit-grade public page (bilingual README, CONTRIBUTING/CONTRIBUTING_CN, SECURITY, CODE_OF_CONDUCT, RELEASE_NOTES, per-command docs, plugin manifests, Release per tag). `tests/test_gitx_sop.sh` BEHAVIOR 12 guards it.

## v1.7.8 — 2026-05-15

**Fix (codex stop-gate): unreachable Phase 6 fallback.** v1.7.7's no-gh token-in-URL fallback was dead code — Phase 1.5 hard-required `gh auth status`, so the SOP aborted at pre-flight before the fallback could ever run. Codex adversarial stop-gate caught the internal contradiction.

### Fixed

- `GITHUB_RELEASE_SOP.template.md` Phase 1.5 now accepts **gh auth OR `GH_TOKEN`** (gh OAuth preferred; explicit token for gh-less CI). The Phase 6 token-in-URL fallback is now genuinely reachable instead of unreachable dead code.
- `tests/test_gitx_sop.sh` BEHAVIOR 11 + `preflight-reachable` sentinel guards the pre-flight/Phase-6 consistency.

## v1.7.7 — 2026-05-15

**Harden gitx-sop Phase 6: prefer gh credential helper over token-in-URL.** When `gh` is installed and authenticated (browser OAuth via `gh auth login`), `gh auth setup-git` makes `git push` authenticate through gh's keyring — no PAT ever touches the remote URL or `.git/config`, nothing to scrub. Token-in-URL (FIX #4) survives only as an explicit no-gh fallback that refuses to push without an explicit `GH_TOKEN`. Strictly safer than the previous always-token-in-URL approach.

### Changed

- `references/gitx-sop/GITHUB_RELEASE_SOP.template.md` Phase 6.0 — gh-helper-first; 6.3/6.4 scrub now conditional on the fallback path (`USED_TOKEN_URL`).
- `tests/test_gitx_sop.sh` BEHAVIOR 11 (new) + BEHAVIOR 7 #4 sentinel updated (token-derivation superseded by gh helper; fallback must still guard empty token).

## v1.7.6 — 2026-05-15

**Docs: full bilingual GitHub-grade README.** Replaced the thin README with a comprehensive English `README.md` + Chinese `README_CN.md` (language-linked, not duplicated inline). Covers philosophy (4 load-bearing principles with named lineage), why the skill exists, what it does, the methodology (12-function pipeline, gate-then-ship invariant, reproducible builds, Deep Audit, defense-in-depth), and a References & Citations section attributing every borrowed idea: Dijkstra (invariants), Norman (Gulf of Evaluation), Beck (TDD), Nonaka & Takeuchi (SECI), SemVer, SLSA, CycloneDX, and the vendored Apache-2.0 Anthropic skill-creator. Structure modeled on the Claude-MacAudit README standard.

### Changed

- `README.md` rewritten (English, primary); new `README_CN.md` (Chinese parallel). Brand/§0e/command-completeness invariants preserved (guards green).

## v1.7.5 — 2026-05-15

**Fix: slash commands installed to the wrong directory — Claude Code never saw them.** `/gitx-sop` (and `/gitx-init`) reported "Unknown command" for three releases. Root cause: install.sh propagated `commands/` only into the skill bundle (`$CANONICAL/commands`), but Claude Code discovers slash commands solely from `~/.claude/commands/*.md` (this is why `/handoff-recall` works and `/gitx-sop` did not). The v1.6.0/v1.7.1 "commands propagation" fixes targeted a directory Claude Code does not scan.

### Fixed

- **install.sh now installs subcommand shims to `~/.claude/commands/`** (flat `.md`, like every working slash command). `/gitx-release` is excluded — it auto-promotes from SKILL.md `name:` and a duplicate shim would double-list it.
- **`tests/test_gitx_sop.sh` BEHAVIOR 10** — functional: installs into a throwaway `HOME` and asserts `~/.claude/commands/{gitx-sop,gitx-init}.md` land where Claude Code actually discovers slash commands (not just the bundle).

## v1.7.4 — 2026-05-15

**Harden gitx-sop SOP for use by *other* skills.** The GitX self-publish session exposed 4 gaps that would break or silently fail for any non-gitx-release skill.

### Fixed (SOP template)

- **Phase 4.5 portability** — most skills lack `scripts/release-sanitize-public.sh` (gitx-release itself does). Now: detect it, else a generic redaction fallback (delete dev-only files + sed-redact `{{PRIVATE_GIT_HOST}}`), and a MANDATORY post-redaction verification grep that runs after either path, fail-closed.
- **Rollback D + tag** — force-rewriting `main` does not clean a tag built from the leaked snapshot; added explicit `git push origin :refs/tags/<ver>` + `gh api -X DELETE` step (the exact thing the v1.7.0 GitHub tag needed manually).
- **Phase 7 multi-release Latest** — `gh release create` steals "Latest" on the most-recently-created release; added a re-assert step on the highest semver after backfilling.
- **Phase 8 completeness gate** — every pushed tag must have a matching GitHub Release (Phase 7 was skipped for 3 versions this session); now a hard gate before sign-off. Checklist updated.

- **`tests/test_gitx_sop.sh` BEHAVIOR 9** — sentinels asserting all 4 hardening fixes are present in the rendered SOP.

## v1.7.3 — 2026-05-15

**Fix: README never documented the new subcommands.** The 命令矩阵 Commands table listed only `/gitx-release` — `/gitx-init` (v1.6.0) and `/gitx-sop` (v1.7.0) were absent, and the clone URL still pointed at the pre-rebrand `TKXLAB-AI/gitx-release`. Same doc-rot class as v1.7.2: docs not synced when capability shipped, no guard catching it.

### Fixed

- **README.md 命令矩阵** now has `/gitx-init` + `/gitx-sop` rows; clone URL corrected to `tkxlab-ai/GitX`.
- **`tests/test_readme_command_completeness.sh`** (new guard): every `commands/*.md` shim MUST be referenced in README.md and the 命令矩阵 must carry the new rows — recurrence of "command not in README" now fails the suite.

## v1.7.2 — 2026-05-15

**Fix: doc version-rot + systemic guard.** `README.md` shipped `## 📌 当前 Scope（v0.9.x）` / "本版本仅支持 Claude Code skill" and `ROADMAP.md` `## 当前状态 — v0.9.x` long after the skill reached v1.7.x multi-CLI — stale claims that rode onto the public mirror. Root cause: docs hardcoded versions inside scope/status claims, `gitx-release.sh` bumped VERSION without syncing them, and no audit caught the drift.

### Fixed

- **README.md / ROADMAP.md scope+status made version-agnostic** — defer to `VERSION` / `Release/CHANGELOG.md` instead of pinning a number; corrected the false "this repo does not self-bake" line (it self-bakes every release).
- **`release-audit.sh §0e` doc version-rot gate** (root + bundle) — any `当前 Scope` / `当前状态` line that pins a `vN` token now FAILs the Deep Audit. Treats the rot class as code-enforced, not aspirational.
- **`tests/test_audit_doc_version_rot.sh`** — static (gate present) + behavioral (regex flags stale, passes fixed) + regression (live README/ROADMAP clean).

## v1.7.1 — 2026-05-15

**Fix: slash-command shims were never distributed.** `/gitx-init` (since v1.6.0) and `/gitx-sop` (v1.7.0) shipped only in `skills/gitx-release/commands/` — there was no root-level `commands/`, the source tarball excluded it (`release.sh --exclude='/commands'`, a stale v1.1.0-era decision), and `test_install_path_completeness.sh` explicitly skipped `commands`. Net effect: `install.sh`'s `[ -d "$SELF_DIR/commands" ]` guard (line 249) was dead from a dev-root install, and the public mirror never received the command shims. Two releases shipped with undistributed slash commands.

### Fixed

- **`commands/` is now dual-sourced** (root + `skills/gitx-release/`, byte-identical) like `scripts/` / `references/` / `agents/`. `install.sh` line 249 now resolves.
- **`release.sh` no longer excludes `/commands`** from the source tarball — `/gitx-init` + `/gitx-sop` shims now reach the source tarball, the public GitHub mirror, and every install path. Stale flatten/exclude comments corrected.
- **`test_install_path_completeness.sh` de-skips `commands`** — the v1.1.0 skip masked the dead guard for two releases; it now functionally guards.
- **`test_gitx_sop.sh` BEHAVIOR 8** (new, functional): installs into a throwaway `HOME` and asserts `commands/{gitx-sop,gitx-init}.md` land in the canonical — not a grep, an actual install.

### Changed

- VERSION v1.7.0 → v1.7.1 (patch). No behavior change to the pipeline itself; this is a distribution-completeness fix.

## v1.7.0 — 2026-05-15

**`gitx-sop` subcommand — projects get a hardened GitHub-publish runbook.** Run `bash scripts/gitx-sop.sh` in any project root and it renders `.gitx/GITHUB_RELEASE_SOP.md`: a parameterized 8-Phase SOP for publishing a release to a public GitHub mirror without leaking the private Git host. Generalized from a battle-tested Handoff-specific SOP (de-hardcoded via placeholders) and upgraded with eight gap fixes found in review. Generate-only — it NEVER runs `git`/`gh` (SKILL.md constraint #1, TKX policy §10.10); the rendered SOP is a runbook for a human-supervised AI. Designed via superpowers `test-driven-development` red→green cycles.

### Added

- **`scripts/gitx-sop.sh`** + dual-source bundle copy — new subcommand. Flags: `--repo=<owner/slug>`, `--project=<name>`, `--private-host=<host>`, `--force`, `--dry-run`, `--help`. Exit codes: 0 success (incl dry-run), 2 usage error, 4 target exists and `--force` not passed. Single `sed` pass substitutes `{{REPO}}` / `{{PROJECT}}` / `{{PRIVATE_GIT_HOST}}` / `{{DATE}}` / `{{GITX_VERSION}}` (pure POSIX, no envsubst).
- **`references/gitx-sop/GITHUB_RELEASE_SOP.template.md`** master template — 8 Phases + rollback + AI checklist, placeholder-rendered.
- **`commands/gitx-sop.md`** slash shim + `agents/codex-commands.txt` `$gitx-sop` selector (root + bundle byte-identical).
- **`release-audit.sh §0d`** gitx-sop template-integrity gate (mirrors §0c): wrapper executable + shebang + template non-empty + has placeholder + slash shim present. Skipped silently when the bundle does not ship `scripts/gitx-sop.sh` (legacy back-compat).
- **`tests/test_gitx_sop.sh`** — 16 BDD assertions (static + behavior + the 8-fix content regression guard).

### Fixed

- SOP review: 8 gaps upgraded into the template
- **#1** Phase 1.3 test step was print-only — now a real gate (`grep -qE '0 (failures|failed)' || exit 1`).
- **#2** SOP assumed a single shell; Phase 6 token cleanup relied solely on a `trap`. Added explicit idempotent token-scrub verification + a one-shell caveat.
- **#3** Phase 4.3 key-file check only warned — now aborts on any missing file.
- **#4** Phase 7 now `shasum -a 256 -c checksums.txt` verifies artifacts before `gh release create`.
- **#5** Phase 5.2 staged-diff scan now covers the same 8 redaction classes as Phase 4.5 (was one dev-home path only).
- **#6** Phase 7.2 re-run guidance: tag/commit already pushed → points at rollback B instead of a bare exit.
- **#7** Variable-table `VER_BARE` example corrected (`v2.2.1` → `2.2.1`).
- **#8** Rollback scenario D switched to the SOP's own force-rewrite model; `git filter-repo` demoted to optional.

### Changed

- `tests/test_audit_codex_command_selectors.sh` upper-bound widened from 3 to 4 selectors (`$gitx-sop` added) — set-based comparison preserved.
- `SKILL.md` 工作模式 table gains a `GitHub 发版 SOP` row (root + bundle byte-identical).
- **Brand rename → "GitX"** (pure-brand layer): SKILL.md H1, description, README.md H1, and Codex `display_name` collapse from "Git Release Pipeline" / "GitX-Release" to **GitX**. Canonical filesystem identifier stays lowercase `gitx-release` (skill-creator requires `name:` = parent dir, kebab-case) — directory, install paths, `/gitx-release` slash, `$gitx-release` selector, `default_prompt` all unchanged (zero path churn, no breakage to installed environments). `test_rebrand_single_canonical_name.sh` Test 7 + `test_codex_skill_metadata.sh` updated to the new brand contract (pipefail-safe per Gotcha #36).

## v1.6.0 — 2026-05-12

**`gitx-init` subcommand — projects teach themselves how to release.** Run `bash scripts/gitx-init.sh` in any project root and it auto-detects whether you have a skill, a Mac app, both, or neither, then drops a `.gitx/` policy package + a top-level `RELEASE_GUIDELINE.md` index aimed at the project's dev-session AI agent. Designed via 18 TDD red→green cycles using the superpowers `test-driven-development` skill — every behavior bullet below was a failing test before it was code.

### Added

- **`scripts/gitx-init.sh`** + dual-source bundle copy — new subcommand. Accepts `--type=auto|skill|mac|both|empty` (default auto), `--force`, `--dry-run`, `--help`. Exit codes: 0 success, 2 usage error, 3 `--type=auto` saw no signals on a non-TTY, 4 `.gitx/` already exists and `--force` not passed. Auto-detect rule: `skills/*/SKILL.md` → skill; `*.xcodeproj` / `Package.swift` / `src-tauri/Cargo.toml` → mac; both signals → both; neither → empty (after the non-TTY check fires exit 3).
- **`references/gitx-init/` master template package** (5 files): `policy.template.md` (project-level TKX policy excerpt, 5 core invariants), `RELEASE_GUIDELINE.template.md` (12-section dev-AI entry-point: project type / quick start / pre-flight / artifacts / audit gates / TKX policy ref / test-scenarios / CHANGELOG conventions / versioning / sanity-scan red list / multi-CLI install matrix / handoff & gotchas), `scenarios/skill-flow.template.md`, `scenarios/mac-flow.template.md`, and the design memo `references/gitx-init-design.md`. All four production templates use `{{PROJECT_NAME}}` / `{{PROJECT_TYPE}}` / `{{DATE}}` / `{{GITX_VERSION}}` placeholders, substituted at render time via a single `sed` pass (no `envsubst` dependency — pure POSIX).
- **`tests/test_gitx_init.sh`** — 30 BDD assertions covering: wrapper bootstrap, `--help` lists 5 types + 4 exit codes, unknown flag and invalid `--type` value both exit 2, explicit `--type=<X>` reflected in dry-run output, auto-detect on fixture projects (skill-only / mac-only / both / no-signal+non-TTY → exit 3), non-dry-run writes `.gitx/` + `RELEASE_GUIDELINE.md`, `.gitx/policy.md` has non-empty content + zero placeholder leak, second-run guard exits 4, `--force` bypasses, `--dry-run` writes nothing + emits `would write:` preview, scenarios are type-conditional, RELEASE_GUIDELINE ships 6 sentinel sections, SKILL.md table lists gitx-init, slash shim valid, install.sh propagates `commands/`, codex selector declared, `release-audit.sh §0c` gate present in both dual-source copies.
- **`release-audit.sh §0c gitx-init template integrity`** — new audit gate. Hard-checks wrapper executable, bash shebang, `references/gitx-init/` propagated to bundle, all 4 templates exist + non-empty + carry at least one `{{...}}` placeholder, and `commands/gitx-init.md` slash shim present. Skipped silently for legacy bundles that do not ship `scripts/gitx-init.sh` — preserves backward compat with older external projects.
- **`skills/gitx-release/commands/gitx-init.md`** slash shim. Frontmatter follows sibling skill convention (`description:` only — slash name derived from filename, matching 1by1 / handoff pattern).
- **`$gitx-init`** added to `agents/codex-commands.txt` (root + bundle byte-identical) — Codex CLI now sees the selector alongside `$gitx-release` and the deprecated `$git-release-pipeline` alias.

### Changed

- **`install.sh`**: propagation of `commands/` to canonical install restored. The v1.1.0 rationale for removing the propagation (avoiding a duplicate `/gitx-release` shim alongside Claude Code's auto-promotion of `$CLAUDE_LINK`) no longer applies because the new shim is `/gitx-init` — a subcommand without an auto-promotion path. Without the restored line, `/gitx-init` would only work for users who unpack the `.skill` bundle directly; the install.sh path would silently lack the slash shim.
- **`skills/gitx-release/SKILL.md`** "工作模式" section: header renamed from "工作模式：三条命令" (which had already drifted to 4 rows) to "工作模式"; new fifth row added for `项目初始化 / /gitx-init` mapping to `scripts/gitx-init.sh`.
- **`tests/test_audit_codex_command_selectors.sh`**: upper-bound check rewritten from "exactly 2 selectors" hardcode to set-based comparison `{$gitx-release, $gitx-init, $git-release-pipeline}`. Any drift surfaces immediately rather than passing because the count happens to match.

### Verification

- `bash tests/run_all.sh` → **90 suites / 0 failed** (89 baseline + 1 new `test_gitx_init.sh`).
- `bash tests/test_gitx_init.sh` → 30 PASS / 0 FAIL covering all 18 TDD cycles' assertions.
- Dual-source `diff -rq scripts/ skills/gitx-release/scripts/` clean (new `gitx-init.sh` mirrored byte-identical).
- `release-audit.sh §0c` fires correctly in self-bake: §0c check messages visible in audit output, references/gitx-init/ propagation confirmed.
- TDD audit trail: each new behavior had a failing test (red) before any code (green) per superpowers `test-driven-development` skill.

Artifacts: `Release/git_release_skill-v1.6.0/`

---

## v1.5.0 — 2026-05-11

**Unified install standard across all TKX skills.** Boss flagged five skills (gitx-release / mac-release / handoff / 1by1 / ClaudeMeX) shipped five different `install.sh` outputs + five different `INSTALL.md` schemas — visually unprofessional. v1.5.0 makes gitx-release the master of the standard and pilots it on itself.

### Added

- **`scripts/lib/install-output-style.sh`**: unified install.sh runtime output helper. Public API: `install_style_init` / `install_banner_top` / `install_checkpoint` (n/total auto-increment) / `install_step_ok` / `install_step_warn` / `install_step_fail` / `install_banner_bottom` / `install_cli_table_begin` / `install_cli_row` / `install_cli_table_end` / `install_next_block` / `install_next_hint`. ASCII-portable via `TKX_INSTALL_NO_EMOJI=1` (em-dash and bullet also fall back). Double-source guard. No-exit-on-source. `install_style_init` silently coerces non-numeric / empty input to 0 to avoid stderr noise. Master copy lives here; downstream skills will vendor byte-identical copies.
- **`references/INSTALL_TEMPLATE_STANDARD.md`**: authoritative 8-section EN schema (§0 file locations / §1 install A-D + SSH / §2 project init / §3 upgrade / §4 uninstall / §5 verify / §6 release / §7 maintenance / §8 troubleshooting). Every TKX skill's `INSTALL.md` MUST follow.
- **`tests/test_install_output_style.sh`**: BDD coverage for the helper public API surface and runtime behavior (banner render / counter increment + reset / non-numeric init coercion / ASCII fallback end-to-end purity / cli_row column alignment / stderr routing / idempotent double-source).
- **`release-audit.sh §0b INSTALL.md + install.sh 统一标准`**: enforces the standard. INSTALL.md top-level numbered headings (`## 0` through `## 8`) plus the ToC anchor are validated via soft `warn` so legacy / fixture projects still ship with visible ⚠️; install.sh helper-usage is hard-checked via `check` only when the bundle ships `scripts/lib/install-output-style.sh` (skill opted in to the standard).

### Changed

- **`install.sh`** rewritten end-to-end: preserves every v1.4.1 gate (checksum verify / preflight / dry-run / force / canonical install / symlinks / legacy cleanup / validation) but renders the 6-checkpoint banner via the new helper. Identical visual structure now used by every TKX skill that vendors the helper. Em-dash separators in user-facing status strings replaced with ASCII `--` so `TKX_INSTALL_NO_EMOJI=1` output is byte-pure ASCII end-to-end.
- **`INSTALL.md`** rewritten root + flatten target: from mixed-ZH/EN intro doc to the full 8-section EN schema implementation for gitx-release itself.

### Verification

- `bash tests/run_all.sh` → all suites green (v1.4.1 baseline plus the new `test_install_output_style.sh` BDD).
- `bash install.sh --force` renders the full 6-checkpoint banner with single `[v<version>]`, four-CLI table, and Next-step bullets.
- `bash install.sh --dry-run` renders Checkpoints 1–3 and exits cleanly with `(dry-run)` suffix on the success banner.
- `TKX_INSTALL_NO_EMOJI=1 bash install.sh --dry-run | LC_ALL=C grep '[^[:print:][:space:]]'` returns empty (end-to-end ASCII purity).
- `diff -q` between root and skill-bundle copies of `release-audit.sh` and `install-output-style.sh` returns empty (dual-source byte-identical).
- 3-round code-reviewer audit loop passed with zero issues before tag (per Boss directive).

Artifacts: `Release/git_release_skill-v1.5.0/`

---

## v1.4.1 — 2026-05-11

**Patch release：SKILL.md 对齐官方 skill-creator best practice — 4 gap 清零**

Boss 让我读官方 anthropics/skills/skill-creator + check 架构对齐。结果：严格 spec 合规 100% 但 4 个 best practice gap。Gap #2（references ToC）实际已满足。剩 2 个真 gap fix（gap #4 imperative form 改写 risk 高，跳过）。

### 🎨 Polish

- **gap #1: description 改 "pushy" form**（spec line 67 — 防 LLM undertrigger）: 旧 description 169 chars 偏静态描述功能。新 description 220 chars 含 `Make sure to use whenever user mentions release, ship, audit, publish, or version bump for a skill — even without naming it`，包含 spec 推荐的 pushy hook + 保留品牌名 "GitX-Release" + 触发触发词 + 主要功能。`Use via /gitx-release or 发版` 末尾给显式 trigger 指令。
- **gap #3: frontmatter 加 `license: MIT` + `compatibility`**（spec line 68）: 之前缺这两个 optional 字段。v1.4.1 加 `license: MIT` 与 LICENSE 文件 SPDX 一致 + `compatibility: macOS/Linux, bash 3.2+ (POSIX shell), git 2.x, optional python3 + venv for vendored skill-creator path; falls back to deterministic zip packager when Python/PyYAML unavailable.`（176 chars ≤500）。marketplace 提交时这两个字段是 metadata 加分项 + 让 user 一眼看到运行依赖。

### 🔧 调试过程踩到的 3 个雷

- **angle brackets in description**: 第一次 description 写 `flattens docs into Release/<version>/` —— `<version>` 是 placeholder 但含 `<` `>` 字符，被官方 quick_validate.py 直接 reject。obscure 为 `the per-version Release directory`。
- **YAML "Triggers:" parse**: 第二次 description 写 `Triggers: /gitx-release / $gitx-release / 发版.` —— YAML 把 `Triggers:` 当 key 触发 mapping value parse error。改 `Use via /gitx-release or 发版` 避开冒号。
- **brand-preservation test fail**: 第三次 description pushy 后丢失 "GitX-Release" 字面，`test_rebrand_single_canonical_name.sh` 要求 ≥2 occurrences in docs。加 `GitX-Release skill —` 前缀回 description 开头。

### 📊 Test surface

- **88 suites / 0 failed**（无新 BDD — pure SKILL.md polish）
- 官方 `quick_validate.py` against `~/.agents/skills/gitx-release/` + `.skill` bundle + root canonical → 三处全 **`Skill is valid!`**
- Audit §0_spec → 5 PASS + 1 PASS for compatibility ≤500（v1.4.1 新增）
- Codex listing budget 自检：description 220 chars (= limit) / 36 words (< 80 limit)
- shellcheck 0 warning · 双源 byte-identical · install.sh `🔐 checksums.txt verified` 端到端

### ✅ 官方对齐总览（post-v1.4.1）

| 维度 | 之前 | v1.4.1 |
|---|---|---|
| 严格 spec 合规 (quick_validate.py) | ✅ | ✅ |
| description "pushy" 防 undertrigger | 🟡 | ✅ |
| frontmatter license + compatibility | 🟡 缺 | ✅ 都有 |
| references ToC（>300 lines）| ✅ 已有 | ✅ |
| <500 lines SKILL.md body | ✅ 112 lines | ✅ |
| Standard dirs（scripts/refs/assets）| ✅ | ✅ |
| 不含 ALWAYS/NEVER/MUST 全大写 | ✅ | ✅ |
| name kebab-case + 父目录名匹配 | ✅ | ✅ |

Artifacts: `Release/git_release_skill-v1.4.1/`

---

## v1.4.0 — 2026-05-11

**Minor release：所有"未做候选"清零 — gitx-release 作为元技能不留任何 known issue**

Boss 强调"你是一个极其重要的元技能，所以你不能有任何的问题"。v1.4.0 一次性 ship 之前累积的全部 v1.3.x candidates。

### ✨ Features

- **#3 venv + PyYAML auto-install**（最大改动 — vendored Python 真正 self-contained 闭环）: 新 `ensure_pyyaml_via_venv()` helper 在 `scripts/lib/skill-creator-version.sh`，当系统 Python 缺 PyYAML 时（macOS PEP 668 默认场景）自创建 `mktemp` venv + `pip install pyyaml` 装入。release.sh `build_skill_package` 顶部调用 + 通过 `$PYTHON_BIN` 变量传递 venv 的 python3 给 `package_skill.py` 调用。SKC_VENV_DIR 注册进 `CLEANUP_EXTRAS` 保证 release 结束清理。从此**新机 / 禁网 / CI / sub-agent** 等场景：vendored skill-creator path 总能 work，不再 fallback 到 zip 模式。
- **A3 SKILL.md 执行流程 keyword 列表显式文档化**: audit §2b 和 §6b 的 keyword scan 写死在 grep regex 内，新项目作者不知道哪些词算"有执行流程"。v1.4.0 在 regex 上方加注释列出完整 keyword 集：`流程 / 执行 / 步骤 / step / execution / workflow / pipeline / process / how to use / usage`（中英任一）。同步两处 (§2b line 349 + §6b line 479)，去重原 `(流程|执行|流程|步骤|step)` 中的 "流程" 重复。
- **Audit §0 Python cross-check advisory**（when PyYAML available）: bash inline §0_spec 仍是主 enforcement（6 条规则，5 PASS），但末尾如检测到 `vendored/skill-creator/scripts/quick_validate.py` 在 + `python3 -c "import yaml"` OK，额外跑官方 Python validator。同意 → +1 PASS "official quick_validate.py cross-validates"；不同意 → +1 ADVISORY "official disagrees: <err>"。**这是 spec 一致性的精度增强**，catch bash inline 无法解析的 block-scalar / multiline YAML edge cases，且 audit PASS/FAIL 主线数字仍稳定。
- **Vendored skill-creator README.md 手工升级 procedure**（`scripts/vendored/skill-creator/README.md`）: 文档化 vendored 文件清单 + 不 vendor 的 LLM-only scripts + manual upgrade 6 步流程（clone upstream / inspect diff / cp fresh / update VERSION pinning / dual-source sync / full test + self-bake）+ "when to upgrade" 决策原则。**故意不自动 sync**（Q2 = 手工升级，v1.3.0 Boss 决定），减少 reproducibility 漂移风险。

### 🛡 Hardening

- **Gotcha #34 explicit `.gitignore` rule**: 新增 `.syncthing.*.tmp` explicit pattern 注释解释 intent（generic `*.tmp` catch-all 已 cover 但 explicit 更利接手者理解）。
- **新 BDD `tests/test_no_syncthing_residue.sh`**（6 断言）: enforce "0 syncthing residue" at release time — 3 行为（`.syncthing.*.tmp` count / `*.sync-conflict-*` count / `.git/` 子树清洁）+ 3 静态（3 `.gitignore` 规则齐全）。release-time guard 防 Gotcha #35 重现。
- **`__pycache__/` 排除 + PYTHONDONTWRITEBYTECODE=1**: vendored Python 跑 `package_skill.py` 时会自动在 `scripts/vendored/skill-creator/scripts/` 写 `__pycache__/`，破坏 dual-source 与 `skills/gitx-release/scripts/vendored/...` 的 byte-identical。v1.4.0 双重 fix: (a) `test_rebrand_single_canonical_name.sh` 的 dual-source diff 加 `--exclude=__pycache__ --exclude='*.pyc'`，(b) `release.sh` 调 Python 时 `PYTHONDONTWRITEBYTECODE=1` env 阻止 cache 生成。

### 📊 Test surface

- 86 → **88 suites** / 0 failed（+2 新 BDD：`test_pyyaml_venv_auto.sh`（9 断言）+ `test_no_syncthing_residue.sh`（6 断言）= 15 新断言）
- v1.4.0 self-bake Deep Audit (inline) → **175 PASS / 0 FAIL / 1 SKIP / ⚠️0**（同 v1.3.2 — §0 cross-check 在 audit subprocess 内不一定能用 venv python，graceful 跳过；audit 数字保持稳定）
- shellcheck 0 warning · 双源 byte-identical（含 vendored/skill-creator 子目录）· install.sh `🔐 checksums.txt verified` 端到端

### 🔬 v1.4.1+ candidates（low priority，留作 future polish）

- 跨项目同步 v1.1.5 sanity-scan 改进至 ClaudeMeX（不是本仓 work，Boss 自处理）
- 评估周期性 sync upstream GitHub Actions（Gitea 兼容性待定，手工升级 procedure 已 work）
- audit §0 Python cross-check 在 venv mode 也工作（需把 SKC_VENV_PYTHON 路径传给 audit subprocess；增加 audit 复杂度，graceful skip 也够用）

Artifacts: `Release/git_release_skill-v1.4.0/`

---

## v1.3.2 — 2026-05-11

**Patch release：quality hardening — install 路径完整性 BDD guard + audit §2 TEST-SCENARIOS.md 改 soft-warn**

### ✨ Features

- **#1 `tests/test_install_path_completeness.sh`** (14 断言): Regression guard 防 v1.3.0-class bug 重现。.skill bundle 内每个顶级 dir + 顶级 file 必须有对应 `cp` 命令在 `install.sh`；同时跑行为测试 fixture install + verify .skill bundle ↔ canonical install 路径 parity。任何未来加 vendored / 新顶级 dir 但 install.sh 漏 copy 都会立即 catch。
- **#2 audit §2 TEST-SCENARIOS.md → soft-warn**（A2）: mac-release v0.1.0 self-bake 第一次接入时 TEST-SCENARIOS.md 缺失硬 FAIL 阻断 onboarding（详 Dev Log 2026-05-07 19:16 的"结构性 friction"）。v1.3.2 把 TEST-SCENARIOS.md 从 hard-`check` 改 soft-`warn`，缺失只产生 ⚠️ advisory 而非 ❌ FAIL。
  - **REQUIRED for self-bake (hard FAIL on missing)**: `README.md` + `INSTALL.md` + `CHANGELOG.md` + `LICENSE` + `CONTRIBUTING.md` + `SKILL.md` + `RELEASE_NOTES.md` + `install.sh`
  - **RECOMMENDED (soft advisory on missing)**: `TEST-SCENARIOS.md`
  - 新 BDD `tests/test_audit_test_scenarios_soft_warn.sh` 11 断言：4 静态（warn 使用 / REQUIRED 未减少 / TEST-SCENARIOS.md 不在 for-loop / warn 函数存在）+ 7 REQUIRED-doc grep guard

### 🔧 Fix

- **test_install_path_completeness.sh 在 release.sh `run_tests` 上下文中 abort**: 第一次跑 self-bake 时 `SKILL_BUNDLE=$(ls -td | head -1 | xargs -I{} sh -c '...' | head -1)` 在 set -euo pipefail 下因 pipeline 某个 process 不稳触发 abort（直接跑 OK，release.sh subshell 内 abort —— Gotcha #24 / #36 同家族 pipefail 风险）。修法：换成纯 shell glob 然后 `[ -f "$cand" ] && SKILL_BUNDLE="$cand"`（last alphabetical = highest semver），不依赖外部 pipeline。**教训**：BDD test 写法也要遵守 Gotcha #36（"pipe 写在 set-eu-pipefail 脚本里需显式处理失败语义"），不只是 release pipeline 代码。

### 📊 Test surface

- 84 → **86 suites** / 0 failed（+2 新 BDD：install path completeness 14 断言 + audit §2 soft-warn 11 断言 = 25 新断言）
- v1.3.2 self-bake Deep Audit (inline) → **175 PASS / 0 FAIL / 1 SKIP / ⚠️0**（同 v1.3.1 baseline — 本仓 TEST-SCENARIOS.md 存在所以 warn 仍 PASS，未来本仓如删该文件会 +1 advisory 而非 +1 FAIL）
- shellcheck 0 warning · 双源 byte-identical · install.sh `🔐 checksums.txt verified` 端到端

### 🔬 v1.3.3+ 候选

- A3: audit §2b SKILL.md "有执行流程说明" 的 keyword scan 列表显式文档化（哪些词算"有执行流程"）— mac-release self-bake 揭示但未阻断
- Gotcha #34 explicit `.gitignore *.syncthing.*.tmp` 规则 + `tests/test_no_syncthing_residue.sh`
- 评估 release.sh 自创建 venv + 自装 PyYAML 让 vendored skill-creator path 在 macOS 默认环境直接用

Artifacts: `Release/git_release_skill-v1.3.2/`

---

## v1.3.1 — 2026-05-11

**Hot-patch：v1.3.0 install.sh 漏复制 `scripts/vendored/`，致 self-contained feature silent break**

### 🔧 Fix

- **[v1.3.0 ship 缺陷]** v1.3.0 把 vendored skill-creator 32KB 全打进了 `.skill` bundle 与 source tarball，但 `install.sh` line 192-198 只 copy `scripts/*.sh` + `scripts/lib/` 到 `$CANONICAL/scripts/`，**没 copy `scripts/vendored/`**。user 装 v1.3.0 后 canonical install 缺 vendored 目录，`build_skill_package` 的 `vendored_newer` / `system_absent` 决策分支 fall through 到 zip fallback——v1.3.0 self-contained 卖点对**只跑 install.sh 不直接读源 repo** 的 user 实际无效。
- **修法**：`install.sh` 加 8 行（含注释）：检测 `$SELF_DIR/scripts/vendored` 存在则 `cp -R` 到 `$CANONICAL/scripts/vendored`。验证：post-install `ls ~/.agents/skills/gitx-release/scripts/vendored/skill-creator/scripts/` 含 4 个 Python 文件 + VERSION pinning 正确暴露 upstream commit。
- **走过的弯路**：v1.3.0 self-bake 成功 + 端到端 reinstall 验证时，我手工 `ls ~/.agents/.../scripts/vendored/` **想验证** vendored 在不在 → 发现 "No such file or directory"。这是 self-bake **打包验证**与 **install 验证** 不对称的 surface：打包 audit 看 .skill 内容（vendored 在），install audit 看 canonical 内容（vendored 不在）。**教训**：未来加新 vendored 资源时，install.sh copy 列表与 .skill bundle 内容必须保持一致；考虑加 BDD test 验证 post-install 路径完整性（v1.3.2 candidate）。

### 📊 Test surface

- 84 suites / 0 failed（无新 BDD —— install.sh 是 release artifact 不是 skill scripts，本仓 audit 已覆盖 .skill 内容完整性；post-install 路径完整性测试列 v1.3.2 candidate）
- v1.3.1 self-bake Deep Audit (inline) → **175 PASS / 0 FAIL / 1 SKIP / ⚠️0**（同 v1.3.0）
- shellcheck install.sh → 0 warning · 双源 byte-identical · install.sh `🔐 checksums.txt verified` 端到端
- post-install 手工验证：`~/.agents/skills/gitx-release/VERSION` → v1.3.1 + `scripts/vendored/skill-creator/scripts/` 4 Python 文件齐 + VERSION pinning 含 `upstream_commit=f458cee...`

Artifacts: `Release/git_release_skill-v1.3.1/`

---

## v1.3.0 — 2026-05-11

**Minor release：vendor 官方 skill-creator 让 gitx-release 真正 self-contained**

### ✨ Features

- **Vendoring**: `scripts/vendored/skill-creator/` 内嵌 Anthropic 官方 skill-creator 核心 4 个 Python 文件（`quick_validate.py` 102 行 + `package_skill.py` 137 行 + `utils.py` + `__init__.py`）+ Apache 2.0 LICENSE + VERSION pinning 文件（upstream commit `f458cee31a7577a47ba0c9a101976fa599385174` @ 2026-05-08）。总 vendored 体积 32KB。**意义**：gitx-release 不再依赖 user 系统装 Claude Code plugin marketplace；跨机迁移 / 新机 / 禁网 / CI 都能直接发版（仅缺 PyYAML 时回退 zip）。
- **`scripts/lib/skill-creator-version.sh` helper**: 单一入口 `skill_creator_status <skill-root>` 同时探测系统 + vendored skill-creator，date-based 版本对比，输出 6 个 enum verdict（`same` / `system_newer` / `vendored_newer` / `system_absent` / `vendored_absent` / `both_absent`）+ PyYAML 可用性。Date proxy 用 plugin cache dir mtime（跨平台 macOS BSD stat vs GNU stat）。
- **`build_skill_package` 决策矩阵**: 根据 verdict + TTY 状态决定用哪个 skill-creator：
  - `same` / `system_newer` → 静默用系统（**实现"系统是最新就不提醒"**）
  - `vendored_newer` + TTY → interactive prompt `[v]endored / [s]ystem`（默认 v 回车即可）
  - `vendored_newer` + 非 TTY（CI / DRY_RUN / pipe）→ 静默用 vendored（reproducible 优先）
  - `system_absent` → 静默用 vendored
  - PyYAML 缺 → 回退 zip fallback（保 v1.2.1 graceful 行为）

### 🔧 Fix

- **Gotcha #32 复发** in v1.3.0 第一次 self-bake：新写的 `echo "...（${SKILL_CREATOR}）..."` 早期版本用 `$SKILL_CREATOR）` 在 `set -u` 下又踩了相邻 Chinese 全角闭括号被吃成变量名的雷（v1.1.7 已修过同款）。修法：所有相邻 Chinese 标点的 `$var` 引用统一改 `${var}` ASCII-delimit。再次提醒：v1.1.7 修过的不是"做完就好"，新增中文 prose 时**必须主动**用 `${var}` 形式。
- `scripts/lib/skill-creator-version.sh` 加 `# shellcheck disable=SC2034` 头注：SKC_* 变量被 source caller 读取，shellcheck 看不到外部使用。

### 📊 Test surface

- 83 → **84 suites** / 0 failed（+1 新 BDD：`test_skill_creator_vendoring.sh` 15 断言：11 静态 + 4 行为 case A `same` / B `system_newer` / C `vendored_newer` / D `system_absent`）
- v1.3.0 self-bake Deep Audit (inline) → **175 PASS / 0 FAIL / 1 SKIP / ⚠️0**（同 v1.2.1 — §0_spec + §1-§11 全绿，结构没动只增加 helper / vendored 资源）
- shellcheck 0 warning · 双源 byte-identical · install.sh `🔐 checksums.txt verified` 端到端

### 🛡 安全 / 合规

- vendored Python 文件 + LICENSE.txt 一同入 `.skill` bundle 与 source tarball 分发（Apache 2.0 attribution 完整）
- VERSION pinning 文件含 upstream commit hash + date + source URL，便于 audit trail
- 新 audit 章节未引入；§0_spec 仍是 quick_validate 纯 bash 等价（v1.2.1 既有）；vendored Python 是 release-time 工具，不是 audit-time 依赖

### 🔬 v1.3.1+ 候选

- 评估 release.sh 自创建 venv + 自装 PyYAML 让 vendored skill-creator path 在 macOS 默认 Python 环境也能直接用（trade-off：复杂度 vs 用户体验）
- 评估 audit §0 升级到调用 vendored `quick_validate.py`（如 PyYAML 可用）替代 bash inline，提高 spec 一致性精度
- 评估周期性自动 sync upstream（GitHub Actions 检测 upstream commit hash 差异 → 开 PR）

Artifacts: `Release/git_release_skill-v1.3.0/`

---

## v1.2.1 — 2026-05-11

**Minor release：官方 skill-creator 信任链对齐 + audit §0 SKILL.md spec gate**

### 🔧 Fixes

- **[skill-creator discovery]** `build_skill_package` 之前 hardcode `skill-creator/unknown/skills/skill-creator` 把字面 `unknown` 当占位符但没实现 glob 展开；Claude Code plugin marketplace 实际给的是真 hash dir 名（如 `76b35e91d1c9`），所以原路径**从来没匹配过**，每次 self-bake 都打印误导性 `⚠️ skill-creator 不在，改用 zip 直接打包`。修法：新 `_discover_skill_creator()` helper 函数 glob 展开 plugin cache 路径 + 回退到 `~/.claude/skills/` 和 `~/.agents/skills/` legacy 位置；每个候选必须含 `scripts/package_skill.py` 才被接受（rejects stale empty dirs）。新 BDD `tests/test_release_skill_creator_discovery.sh` 8 断言（4 静态 + 4 行为 case A/B/C/D：planted cache / fallback / nothing / stale empty）。
- **[PyYAML graceful fallback]** discovery 修好后 expose 了第二个问题：skill-creator `quick_validate.py` import PyYAML，但 macOS Python 3 默认不带 PyYAML 且 PEP 668 阻止系统 `pip install`。release.sh 现在检测 `python3 -c "import yaml"`，缺时优雅降级到 zip fallback（保留之前 v1.2.0 的行为，user 可 `pip3 install pyyaml --break-system-packages` 或 venv opt-in）。

### ✨ Audit §0：SKILL.md spec conformance（NEW）

- 新增 audit §0_spec，相当于 Anthropic 官方 `skill-creator/scripts/quick_validate.py` 在 audit 流程的等价实现，**先官方 6 条规则 spec gate，再走 §1-§11 我们超严 audit 27 章**：
  1. SKILL.md 存在
  2. YAML frontmatter `---...---` 分界
  3. Top-level keys ⊆ `{name, description, license, allowed-tools, metadata, compatibility}`
  4. `name`：kebab-case `^[a-z0-9-]+$`，no leading/trailing/double hyphen，≤64 chars
  5. `description`：no `<` or `>`，≤1024 chars
  6. `compatibility`（可选）：≤500 chars
- 实现：纯 bash + awk + grep（不依赖 Python / PyYAML，audit 总能跑）；flat-scalar frontmatter 解析（well-formed SKILL.md 都是 flat scalar；block-scalar multiline 罕见，fallthrough）
- 新 BDD `tests/test_audit_skill_md_spec_conformance.sh` 11 断言（7 静态 + 4 行为 case A/B/C/D：valid skill / unexpected key / UpperCase name / angle bracket in description）

### 📊 Test surface

- 81 → **83 suites** / 0 failed（+2 新 BDD：discovery 8 + spec conformance 11 = 19 新断言）
- v1.2.1 self-bake Deep Audit (inline) → **175 PASS / 0 FAIL / 1 SKIP / ⚠️0**（vs v1.2.0 170/0/1，**+5 PASS 全部来自新 §0**）
- shellcheck 0 warning · 双源 byte-identical · install.sh `🔐 checksums.txt verified` 端到端

### 🔬 v1.2.2+ 候选

- 评估 release.sh 自创建 venv + 自装 PyYAML 让 skill-creator path 总能用（trade-off：复杂度 vs official-build 路径覆盖率）
- audit §0 升级到 PyYAML 严格模式（如果环境可用）；目前 bash inline 是 quick_validate 的 95% 等价（flat scalar 限制）
- 探索 `npx skills` 替代自卷 install.sh 作为 production install path（Guideline v1.1 §6.0 已记录方向）

Artifacts: `Release/git_release_skill-v1.2.1/`

---

## v1.2.0 — 2026-05-10

**Minor release：v1.1.7 hot-patch + 两项 mac-release self-bake 揭示的 friction polish**

### 🔧 Fixes

- **[hot-patch] `build_source_tarball` 现代路径漏设 STAGE_SUB**（v1.1.7 自身 regression）：v1.1.7 加 scrub-tarball.sh detect-and-delegate 后，现代路径 `return 0` 前未设 `STAGE/STAGE_SUB/SKILL_STAGE`，下游 `run_sanity_scans` 在 `set -u` 下读 `$STAGE_SUB` unbound abort，阻塞所有 vendor `scripts/scrub-tarball.sh` 的下游项目（1by1 v0.6.2 撞到）。本仓 self-bake 没踩到是因本仓不 vendor scrub-tarball.sh，走 legacy fallback。修法：现代路径 return 前 `mktemp STAGE` + `tar -xzf` 解压 tarball 到 `STAGE`，下游 sanity scan 看到 ship 实际内容；CLEANUP_EXTRAS 注册防 /tmp leak。新 BDD `tests/test_release_modern_path_sanity_input.sh` 6 断言守 regression。
- **[A1] wrapper `ensure_changelog_entry` 锚定首个 `## ` 行**（mac-release header friction）：v1.0.8 起 wrapper 用 `head -4 + tail -n +5` 写死，假设 CHANGELOG 顶部恰好 4 行 header；mac-release v0.1.0 自发版只有 2 行 → wrapper 把 v0.0.1-dev entry 当 header 一部分插入，sentinel 落到错位置 → audit §4 看顶部仍是旧 entry FAIL。修法：用 `awk '/^## / { print NR; exit }'` 找首个 entry 行号 anchor 插入。awk 永远 exit 0（empty 表无匹配），不像 grep|head|cut 在 pipefail+set-e 下 abort（这是 Gotcha #24 同家族第二形态，A1 调试时发现）。新 BDD `tests/test_wrapper_changelog_anchor.sh` 9 断言覆盖 default 4-line / 2-line minimalist / no-CHANGELOG fallback / idempotent / set-e 安全 anchor pattern。
- **[A4] `.skill` bundle 内部 sanitize 继承项目根 `.sanitize-ignore`**（Gotcha #11 surface 3）：mac-release v0.1.0 自发版头两次失败：`assets/TEST-SCENARIOS.md` 含 MAC-pattern literal fixture，release.sh 解压 `.skill` 跑 sanity scan 时不继承项目根 `.sanitize-ignore`（按 Gotcha #11 原契约，`.sanitize-ignore` 不能进 `.skill` bundle 分发包，否则白名单泄露），豁免失效 false-positive abort。修法：扫 `SKILL_STAGE/$SKILL_NAME`（实际 bundle 解压根）而不是 `SKILL_STAGE`，file-path-relative-to-scan-root 与 PROJECT_ROOT 扫一致，原 `.sanitize-ignore` pattern 直接 match；临时 cp 进 `SKILL_STAGE/$SKILL_NAME/`，扫完 success + failure 路径都立即 rm（mirrors `release-audit.sh §7` line 504-508 模式）。新 BDD `tests/test_skill_bundle_sanitize_inherits_ignore.sh` 6 断言守 regression。
- **[anti-self-trip] obscure MAC literal 字面避免 Gotcha #31 surface 1 retrigger**：v1.2.0 第一次 self-bake 失败：commit `be5db70` 把 MAC-literal 字面写进 release.sh A4 注释 + 测试文件注释和 fixture heredoc，staging sanity scan 命中 abort。修法：注释 obscure 为"MAC-literal patterns"语义描述；fixture 拆字符串 runtime 拼接，source file 静态扫不到完整字面，runtime 组装出真 MAC 让 sanitize 行为 case 仍触发 —— 沿用 v1.0.8 hardening 时 credential test fixture 对 Bearer/Stripe 字符串 anti-self-trip 既有惯例。

### 🛡 Hardening

- `tests/test_sanitize_ignore_hardening.sh` 守卫精化：v0.9.6 时代 guard 把所有 `cp .sanitize-ignore` flag 为 leak risk，但 mktemp 临时 staging 不是 release artifact 实属安全。改为只 flag 非临时路径的 cp（排除 SKILL_STAGE / mktemp / staging / /tmp 字串）。

### 📊 Test surface

- 78 → **81 suites** / 0 failed（+3 新 BDD：hot-patch 6 + A1 9 + A4 6 = 21 新断言）
- v1.2.0 self-bake Deep Audit (inline) → **170 PASS / 0 FAIL / 1 SKIP / ⚠️0**
- shellcheck 0 warning · 双源 byte-identical · install.sh `🔐 checksums.txt verified` 端到端

### 🔬 v1.2.1+ 候选（未 ship）

- Gotcha #36 候选文档化：`grep | head | cut` 在 `set -euo pipefail` 下 abort（A1 调试中途发现的 Gotcha #24 同家族第二形态）
- v1.1.7 standalone Deep Audit 在新机已 171/0/0/0 baseline（5/10），本 release 沿用同源代码不重跑

Artifacts: `Release/git_release_skill-v1.2.0/`

---

## v1.1.7 — 2026-05-08

> 本版本合并三条独立修复（按发现时序）：
> 1. **Gotcha #33 长期方案**：`build_source_tarball` 改用 git-archive — 由 1by1 项目第三次 .planning/.archive/ 泄漏复发触发（commit `3e55e14` 落代码）。注意：HANDOFF Gotcha 编号此前曾误用 #20；正式编号为 **#33**（原 #20 是 v1.0.4 的 PROJECT_NAME / SKILL_NAME 环境污染，已修复完毕，与本次无关）。
> 2. **Gotcha #32**：`set -u` 下 `$var` 紧接 Chinese 全角标点被 bash 吃成变量名一部分 — 由 mac-release v0.1.0 self-bake 第三次尝试触发，定位到 `release-audit.sh:265` `$first_ver_line）` 这条 echo。
> 3. **`3e55e14` 三个未完成项**：dual-source 镜像未同步（VERSION + release.sh）、`scrub-tarball.sh` 未列入 `check_dual_source` whitelist、新代码路径无 TDD 测试。本次一并补齐。

### 🔒 修复 Gotcha #33 长期方案: `build_source_tarball` 改用 git-archive(发起方:1by1)

**症状**:`scripts/release.sh build_source_tarball` 走 rsync staging 模式 — `rsync` 默认不读 `.gitignore` / `.gitattributes export-ignore`,只信赖函数内手写的 `--exclude=` 列表。结果:

- `.planning/codebase/{ARCHITECTURE,INTEGRATIONS,STACK,STRUCTURE}.md`(.gitignore'd 内部规划)
- `.archive/reference-v0.2-single-file.md`(.gitattributes export-ignored 历史归档)
- `GITX_ALIAS_AUDIT.md` / `GITX_PIPELINE_REVIEW_2026-04-30.md` / `HEURISTIC-EVALUATION.md`(audit / 评估文件,export-ignored)

**全部进了 v0.5.3 / v0.6.0 / v0.6.1 三次连续 release 的 source tarball**。1by1 项目记录了 Gotcha #20(2026-05-06 首发)+ 第三次复发(2026-05-07)。Method 1(发布前 `mv` untracked dirs)被证明不可靠 — 依赖人工记忆。

### 🛠 修复(`scripts/release.sh:366-405`)

`build_source_tarball()` 顶部插 detect-and-delegate 分支:

```bash
PROJECT_SCRUB="$PROJECT_ROOT/scripts/scrub-tarball.sh"
if [ -x "$PROJECT_SCRUB" ] && git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    bash "$PROJECT_SCRUB" "$TAR_OUT" "${PROJECT_NAME}-${VERSION}" HEAD
    return 0
fi
# else fall through to legacy rsync staging mode (unchanged behaviour)
```

`scripts/scrub-tarball.sh` 是项目自带的(1by1 已 vendor,~90 行 bash),内部:

- `git archive --format=tar --prefix --worktree-attributes <ref> | gzip -n`
- 只见 git-tracked 内容(`.gitignore`'d 文件物理在 worktree 但不在 index → 不入 archive)
- `.gitattributes export-ignore` 路径自动排除(用 `--worktree-attributes` 即使 ref 早于 .gitattributes 也读最新规则)
- `gzip -n` 剥离 mtime + filename → byte-deterministic
- 自带 `VERIFY=1` 二跑 cmp 自检模式

### 🧪 验证

- 1by1 v0.6.1 模拟新路径产物:`640K / 339 files / 仅 git-tracked / 0 leak patterns`(符合 `.gitignore` + `.gitattributes export-ignore`)。
- `bash -n release.sh` 语法 OK。
- 向后兼容:无 `scripts/scrub-tarball.sh` 的项目落到 legacy rsync 分支,行为完全不变。
- `--dry-run` 模式两条分支都正确处理(`run` wrapper 已透传)。

### 📌 影响

- **依赖此 wrapper 的所有项目**:从此次发布起,如果你的项目根有 `scripts/scrub-tarball.sh`(可执行 + git repo),`gitx-release.sh` 会自动用它打 source tarball,不必再依赖 wrapper 的硬编码 exclude 列表。
- **没有 `scripts/scrub-tarball.sh` 的项目**:行为不变。但建议 vendor 一份(参考 1by1 项目)以获得 `.gitignore`/`.gitattributes` 自动遵守 + byte-determinism。
- 历史已发布 tarball:不动(immutability);若已知含泄漏,各项目自行 hotfix(参考 1by1 commits `b21c23c` / `5358672`)。

### 🔗 关联

- 发起方:1by1 项目 Gotcha #33 第三次复发 + 用户 autopilot 直接修。
- 1by1 commits:`5358672` v0.6.0 hotfix / `c433194` v0.6.1 patch / `dc6a99c` v0.6.1 release(in-place hotfix)。
- 1by1 HANDOFF.md Decision 2026-05-07(优先级反转 — "v0.7 必修")。

---

### 🔒 Gotcha #32 修复:`set -u` 下 `$var` 紧接 Chinese 全角标点被吞进变量名（发起方:mac-release self-bake）

**症状**: `release-audit.sh:265` 的 echo `❌ 顶部版本号 ≠ ${VERSION}（顶部为: $first_ver_line）` 在某些 bash 版本/locale 下报错 `first_ver_line）: unbound variable`。`$first_ver_line` 上一行刚 grep 赋值，按理已 bound — 但 bash 把后面紧贴的 Chinese 全角闭括号 `）`（U+FF09，UTF-8 `\xef\xbc\x89`）当成 identifier 续接，结果实际 expand 的变量名是 `first_ver_line）`（含 3 字节非 ASCII），那是没赋值过的 → set -u abort。

发现路径:mac-release v0.1.0 self-bake 第三次尝试。gitx-release 自己从未触发，因为 self-bake 时顶部版本号始终匹配，走 then 分支（line 261-262），else 分支（含此 echo）从未在 happy path 上执行过。是 **dogfood 必到外项目才暴露的隐式假设**。

### 🛠 修复(`scripts/release.sh / release-audit.sh`)

- `release-audit.sh:265` 把 `$first_ver_line）` 改为 `${first_ver_line}）`，ASCII `{}` 显式 delimit identifier。
- 加 `tests/test_audit_chinese_paren_safe.sh`(11 个 BDD 断言):2 条行为(`${var}）` 形式始终 OK；裸 `$var）` 形式记录 informational/abort 二态),2 条静态 guard 覆盖 5 个 .sh + scripts/lib/ — 任何未来回归会立即 RED。

### 🔧 `3e55e14` 后续整理

- **dual-source 镜像同步**:`skills/gitx-release/VERSION` v1.1.6 → v1.1.7;`skills/gitx-release/scripts/release.sh` 同步 root。`3e55e14` 只动了 root 端，破坏 byte-identical 契约 — 直到本次发版前两道 pre-flight check 都会硬 abort。
- **`scrub-tarball.sh` 加入 `check_dual_source` whitelist**:`3e55e14` 给项目了一个新选项(可选 vendor `scripts/scrub-tarball.sh`),但忘了它会在 dual-source diff 出 root-only 漂移。`scripts/release.sh:check_dual_source()` 和 `scripts/release-audit.sh §9` 各加一条 case 放行。
- **`scrub-tarball.sh` 路径 TDD 覆盖**:`tests/test_release_tarball_scrub_preferred.sh`(10 个 BDD 断言):6 条静态(PROJECT_SCRUB 路径 / 双 guard / dry-run marker / `return 0` 防 fall-through / rsync fallback 保留 / 1by1 历史注释保留),4 条行为(planted scrub fixture / no-scrub fixture 各两面)。

### 🧪 验证

- `bash tests/run_all.sh` → **78 suites / 0 failed**(76 baseline + 2 new tests)。
- `diff -rq scripts/ skills/gitx-release/scripts/` → clean。
- `bash scripts/release-sanitize.sh .` → ✅ Release sanity clean。
- 自发版通过 `gitx-release.sh --version v1.1.7` 端到端 audit。

### 🔗 关联

- Gotcha #32 / #33(HANDOFF 同时新增条目)。
- mac-release v0.1.0 self-bake 是 gitx-release v1.1.6 第一次跑外项目;暴露的 friction 都已闭合到本版本。
- 后续观察:HANDOFF Gotcha #34 占位为 ".sync-conflict-* 文件污染 dual-source check"(本次以 `.gitignore` 加 `*.sync-conflict-*` 规则解决)。

---

## v1.1.6 — 2026-05-05

**Stability rebake validating v1.1.5 sanitizer in production self-test.** No
source code changes vs v1.1.5; this version exists to prove the v1.1.5
sanitizer can pass its own audit gate after the operational hardening
(four UX bugs fixed + IP policy tightened).

Process catch worth recording: the first v1.1.6 attempt was correctly
blocked by the now-installed v1.1.5 sanitizer at audit §7 (post-release
sanity scan) — because the v1.1.5 CHANGELOG entry's prose contained
literal sample-user paths, sample-email, and a literal real-looking
public IP used to describe what the new tests verify. Same root lesson
as Gotcha #31 (CHANGELOG prose containing scanner-bait strings retrips
the scanner), surfaced via a different code path (audit §7 instead of
gitx-release wrapper sentinel detector). Resolved by rewriting the
prose in obscured form across both `Release/CHANGELOG.md` and the
flattened scoped copy in `Release/git_release_skill-v1.1.5/CHANGELOG.md`.

This is empirical proof that the v1.1.5 hardening works end-to-end:
the new sanitizer caught a real category-fail in the project's own
shipped artifacts that the v1.1.4 sanitizer would not have flagged in
the same form (because v1.1.4 reported absolute staging paths, making
the source location of the leak harder to identify; v1.1.5 surfaced
"CHANGELOG.md:54" project-relative on the first try).

- All scripts, tests, and contracts byte-identical to v1.1.5
- `bash tests/run_all.sh` → 76 suites / 0 failed
- Deep Audit inline → 170 PASS / 0 FAIL / 1 SKIP / ⚠️0
- §9 dual-source diff → byte-identical
- §11k install.sh dependency check → all `$SELF_DIR/` resolve
- `shasum -a 256 -c checksums.txt` will verify cleanly on extraction

Artifacts: `Release/git_release_skill-v1.1.6/`

---

## v1.1.5 — 2026-05-05

**Sanity-scan UX hardening + IP policy tightening.** Driven by an operational
audit of six gitx-release logs from four downstream projects (gitx-release v1.1.4,
ClaudeMeX, 1by1, Handoff). Four operator-impacting issues fixed; 31 new TDD
assertions added.

- **Bug A — Credentials report now prefixes file path on EVERY hit.**
  Previously, when `scan-credentials.sh` reported multiple credentials in the
  same file (e.g. an OpenAI key + Anthropic key + GitHub PAT all in one
  `sanitize.test.js`), only the first match line was prefixed with the file
  path; subsequent lines came out as `⚠️ <type> detected (line N)` with no
  file context, forcing operators to visually backtrack. `release-sanitize.sh`
  now reads scan-credentials output line-by-line and prefixes EACH hit with
  `${rel}:`. (Reproducer: ClaudeMeX run 1 log line 60–66.)
- **Bug B — Findings show project-relative paths, not staging mktemp absolute
  paths.** Previously, the ABSOLUTE USER PATHS / EMAIL ADDRESSES / PUBLIC IP
  ADDRESSES / MAC / SSH-GPG categories all printed paths starting with
  `/var/folders/.../tmp.XXX/<project>-vX.Y.Z/`. Operators had to mentally
  strip the staging prefix before locating the offending file in their tree.
  Inconsistent with the CREDENTIAL PATTERNS category, which already used
  project-relative paths. `grep_files()` now post-processes its grep output
  via awk substr-prefix match (avoids regex escaping hazards in mktemp paths)
  to strip `$DIR/`. (Reproducer: ClaudeMeX run 1 log line 79–125, Handoff
  run 1 log line 459–462.)
- **Bug C — `--label <name>` distinguishes the two sanity-scan passes.**
  `release.sh:run_sanity_scans()` calls `release-sanitize.sh` twice — once
  on the staging directory, once on the extracted `.skill` bundle (TKX policy
  v2.3 §6 requires both). Both passes printed identical `✅ Release sanity
  clean` lines, so failed/passed log forensics couldn't tell which pass
  produced which message. `release-sanitize.sh` now accepts an optional
  `--label <name>` flag (POSIX `--label=value` form also accepted) that
  appends the label to both success and failure messages. `release.sh`
  passes `--label staging` and `--label .skill` to make the two passes
  disambiguatable. Backward-compatible: omitting `--label` preserves
  pre-v1.1.5 output exactly.
- **Bug D — Public IPs are HARD FAIL with ❌ icon.** Previously, the
  PUBLIC IP ADDRESSES category was printed with `⚠️` (warning) icon while
  still incrementing `FINDINGS` and triggering exit 1 — a misleading
  severity-vs-behavior mismatch. Per project policy ("肯定是不能出现公网IP的"),
  real public IPs must NEVER appear in releases. Icon corrected to `❌`
  (consistent with all other fail categories). RFC 5737 documentation
  ranges (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24) added to the
  allowlist for legitimate documentation use; existing exemptions (RFC 1918
  private ranges, link-local 169.254/16, 1.1.1.1, 8.8.8.8/4.4, 9.9.9.9 DNS
  placeholders) preserved.

New regression armor: `tests/test_sanitize_output_format.sh` (31 BDD
assertions across the four bugs + cross-cutting clean-dir behavior). Each
fixture-positive test verifies that a real-looking public IP IS flagged
while RFC 5737 documentation ranges are NOT — locking the policy intent
in code, not just docs.

Process notes:
- Discovered during write that the test fixture's intentional sample-user
  `/Users/...` paths, sample-email, and sample-public-IP strings would be
  flagged by the sanitizer scanning the project's own staging tree. Added
  `tests/test_sanitize_output_format.sh` to `.sanitize-ignore` (joining
  the existing convention used by `test_sanitize.sh`,
  `test_credential_patterns.sh`, etc.) so the file is exempt from scanning
  while still being visible to the test runner.
- First self-bake attempt failed at the new test fixture's IP/email/path
  patterns being flagged by the still-installed v1.1.4 sanitizer; resolved
  by the `.sanitize-ignore` addition (Gotcha #17 wrapper-rollback
  successfully restored v1.1.4 VERSION before the retry).
- Second self-bake attempt failed for the symmetric reason on the audit
  side: this very CHANGELOG entry, when flattened into Release/<ver>/,
  contained literal strings that the now-installed v1.1.5 sanitizer
  correctly rejected. Resolved by rewriting the prose to describe the
  fixture content in obscured form (Gotcha #31 — same lesson, different
  surface). The lesson is durable: any CHANGELOG / Dev Log prose that
  describes scanner test fixtures must not include the literal bait
  strings — use semantic equivalents, or quote them inside the test file
  (which is `.sanitize-ignore`'d) and reference the file by path.

Verification:
- `bash tests/run_all.sh` → **76 suites / 0 failed** (+1 = test_sanitize_output_format)
- `bash tests/test_release_pipeline_smoke.sh` → 6/6
- `bash tests/test_sanitize_output_format.sh` → 31/0
- Deep Audit inline → 170 PASS / 0 FAIL / 1 SKIP / ⚠️0
- §11k install.sh dependency check → all `$SELF_DIR/` resolve
- §9 dual-source diff → byte-identical
- `shellcheck -S warning scripts/release-sanitize.sh scripts/release.sh tests/test_sanitize_output_format.sh` → 0 warnings

Artifacts: `Release/git_release_skill-v1.1.5/`

---

## v1.1.4 — 2026-05-05

**Docs-only release.** Two operator-visibility improvements driven by an
external Codex adversarial review and a HANDOFF-drift audit. No source,
test, or contract changes vs v1.1.3 — pipeline byte-stable.

- **GETTING_STARTED.md §8 install split into verified vs dev-clone tiers.**
  Prior wording listed `git clone …/<gitx-release-repo>` next to a stale
  `cd Git_Release_Skill` placeholder, normalizing unverified release-tooling
  installs without surfacing `install.sh`'s existing checksum verification.
  §8 now has two clearly-separated paths:
  - **§8a Recommended** — download `git_release_skill-<ver>-full.tar.gz`,
    verify outer sha256 against an out-of-band published value, extract,
    then `./install.sh` (which auto-verifies `checksums.txt` per Gotcha #30
    before any filesystem write). Documents expected `🔐 checksums.txt
    verified` line; explicit "do not `--force` past a FAILED check."
  - **§8b Developer / contributor** — `git clone … && ./install.sh` with
    explicit ⚠️ that this path bypasses `install.sh`'s integrity check
    (graceful degradation for dev trees) and **must not** be used on
    machines that run `gitx-release` against production code, including
    teammate-clone installs.
  - Cross-references to HANDOFF Gotcha #30 / Decision 2026-05-04 so
    future readers can find the trust-model reasoning.
- **Release/CHANGELOG.md backfilled four placeholder entries** (v1.0.8 /
  v1.0.9 / v1.0.10 / v1.1.1). All four had been auto-generated by the
  Gotcha #29 wrapper sentinel and never replaced with real notes,
  meaning every gitx-release run was firing a publish-blocker ⚠️ for
  historical versions. Real notes derived from git log + HANDOFF Dev
  Log + source-commit messages. Subtle catch during write: the v1.0.8
  prose described the sentinel mechanism by quoting the literal
  literal `gitx-auto-entry` HTML-comment opener, which retripped the wrapper's
  `grep -qF` detector at `scripts/gitx-release.sh:291`. Reworded to
  break the literal substring while preserving meaning.

Two adversarial review passes during prep:
- Round 1 (`git diff --base 0ca0d3a~1`): CodeRabbit found 1 minor
  (placeholder URL in §8); Codex adversarial flagged the same area as
  a high-severity supply-chain gap.
- Round 2 (post-§8 rewrite): Codex adversarial verdict `approve` —
  trust boundary now explicit in docs.

Self-bake (`bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh`):
- `bash tests/run_all.sh` → all suites green
- Deep Audit inline → 170 PASS / 0 FAIL / 1 SKIP (§8 inline `latest`
  expected SKIP — flips to v1.1.4 post-audit per gate-then-ship)
- §11k install.sh dependency check → all `$SELF_DIR/` references resolve
- §9 dual-source diff → byte-identical
- §11 open-source compliance → 43/0
- `shasum -a 256 -c checksums.txt` will verify cleanly on extraction

Artifacts: `Release/git_release_skill-v1.1.4/`

---

## v1.1.3 — 2026-05-04

**Addresses post-v1.1.2 review feedback (Important #1, #2, #3 + Minor #6, #7).**

- **§11k false-positive fix**: audit no longer extracts `$SELF_DIR/...`
  paths from comment lines. A documented example like
  `# cp "$SELF_DIR/example.md"` no longer fails the audit. Implemented
  via a `sed -E 's/[[:space:]]*#.*$//'` strip pass before `grep -oE`.
- **§11k brace-form coverage**: regex extended to catch
  `"${SELF_DIR}/<path>"` in addition to `"$SELF_DIR/<path>"`. Both
  idiomatic bash forms are now equally enforced. Used `sed -E` (ERE)
  for the strip pass so `\?` is the optional-quantifier on macOS BSD sed.
- **GETTING_STARTED.md §5 Option C corrected**: documented `.release-flatten`
  as v1.1.2-shipped (was incorrectly labelled "*planned*"). Includes
  syntax example with whole-line + trailing comments and subdirectory paths.
- **GETTING_STARTED.md §6 dependency-check recipe**: replaced the
  incomplete `grep -E 'cp .*\$SELF_DIR/[A-Z]'` snippet with the
  authoritative `gitx-release.sh --dry-run` invocation that runs §11k.
- **Test fixture comment correction**: `test_flatten_manifest.sh:191`
  no longer claims trailing comments are unsupported (they are).

TDD process:
- Two new BDD cases added to `test_audit_install_dependencies.sh`:
  - case D: `# cp "$SELF_DIR/example.md"` in comment → must NOT fail
  - case E: `cp "${SELF_DIR}/file.md"` brace form → must catch missing dep
- Both written RED first; revealed a `sed` portability bug (BSD vs GNU
  `\?` semantics) that would have shipped silently otherwise.

Audit count unchanged: 170 PASS / 0 FAIL / 1 SKIP. CI rehearsal clean
across shellcheck + dual-source + 75 test suites.

Artifacts: `Release/git_release_skill-v1.1.3/`

---

## v1.1.2 — 2026-05-04

**Closes the "claudemex install.sh" failure mode** — a downstream project
discovered that `install.sh` could reference project-specific files NOT in
the standard 8-doc flatten list, producing a release where `cp $SELF_DIR/<file>`
failed at user install time. Fixed at two layers:

- **Flatten layer**: `flatten_docs()` now reads optional `.release-flatten`
  manifest at `$PROJECT_ROOT/`. One path per line, comments + blank lines
  tolerated. Listed paths are copied into `Release/<ver>/` alongside the
  standard 8 docs. Backward-compatible: missing manifest = unchanged behavior.
- **Audit layer**: new `release-audit.sh §11k` parses `Release/<ver>/install.sh`
  for `"$SELF_DIR/<path>"` references and verifies each resolves. Catches
  any new project's missing-flatten gap BEFORE the user runs install.sh.

Other improvements:
- New top-level `GETTING_STARTED.md` — front-door doc for AI agents and skill
  authors describing project prerequisites BEFORE running gitx-release.
  Covers required layout, install.sh contract, common pitfalls, and the
  generic-software (Mac/Win/Linux) decision tree.
- Removed unused `EPOCH` variable in `test_skill_zip_determinism.sh` (CI shellcheck warning fix).

TDD process:
- `tests/test_flatten_manifest.sh` (8 BDD assertions, 4 scenarios)
- `tests/test_audit_install_dependencies.sh` (5 BDD assertions, 3 cases)
- Both written RED first, applied GREEN second.

Self-bake caught a false-positive in the new §11k gate (our own install.sh
uses `cp "$SELF_DIR/$f"` in a for-loop; the `$f` runtime variable was
mistakenly treated as a literal path). Filtered by adding `grep -v '$'`
on the extracted dependency list — only literal paths are now audited.

Audit count: 169 → 170 (+1 from §11k).

Artifacts: `Release/git_release_skill-v1.1.2/`

---

## v1.1.1 — 2026-05-04

**Addresses post-v1.1.0 5th-pass review feedback (Important #1–#5)**
on the rebrand commit `e3800d6`, plus a test-suite robustness fix.

- **#1 INSTALL.md uninstall block** — bulk sed had collapsed four
  distinct CLI root paths into three identical no-ops. Restored the
  full 10-path uninstall sequence matching `install.sh`'s help block:
  `~/.agents`, `~/.claude` (skills + commands shim), `~/.codex` (all
  three case variants), `~/.config/opencode`, plus the deprecated
  `git-release-pipeline` path under each root.
- **#2 INSTALL.md alias-example sentence** — sed had reduced
  "$gitx-release / $GitX-release / $gitx-release" to a tautology.
  Rewritten to explain the lowercase-canonical reasoning and name the
  deprecated-alias retention contract directly.
- **#3 release.sh `commands/` flattening — generic-pipeline contract
  clarified.** The branch isn't dead code; it's part of the generic
  release pipeline used by ANY downstream skill that ships slash
  commands. Added explanatory comment + updated test description in
  `test_gitx_release_one_command.sh`. No behavior change.
- **#4 Codex codex-commands.txt parser risk** — `agents/codex-commands.txt`
  had `# ...` deprecation notes, but Codex parses the manifest as a
  flat selector list and may reject comments. Moved the deprecation
  contract into a new `agents/README.md` (root + bundle). Manifest
  is now exactly 2 selector lines, zero comments.
- **#5 test_audit_codex_command_selectors.sh** — added an exact-count
  assertion (`==2 selectors`); previously a stray third selector
  could have slipped past. Closes a regression-armor gap.

Test fix: `test_release_pipeline_smoke.sh` BDD VERSION assertion was
too strict against post-bump test runs and would fail when run
against an in-progress release tree (commit `ab3f72e`).

Self-bake: `bash tests/run_all.sh` green; pipeline-stable rebake
(no audit-count change vs v1.1.0).

Artifacts: `Release/git_release_skill-v1.1.1/`

---

## v1.1.0 — 2026-05-04

**BREAKING — canonical name rebrand to collapse the duplicate `/`-menu entry.**

- **Skill renamed**: `git-release-pipeline` → `gitx-release` everywhere
  (folder, SKILL.md `name:`, install paths, test fixtures). Brand text
  "GitX-Release" preserved in human-readable docs and titles.
- **Slash command shim removed**: `commands/GitX-release.md` deleted.
  Claude Code now auto-promotes the renamed skill to `/gitx-release`
  (single canonical entry — fixes the tacit-knowledge tax of having
  both `/GitX-release` and `/git-release-pipeline` visible).
- **Codex aliases**: `$gitx-release` is now primary; `$git-release-pipeline`
  retained as deprecated alias for one minor version (removed in v1.2.0).
- **Migration**: `./install.sh --force` cleans up legacy paths
  (`~/.agents/skills/git-release-pipeline/`, `~/.claude/commands/GitX-release.md`,
  `~/.codex/skills/{git-release-pipeline,GitX-release}/`) automatically.

Why lowercase `gitx-release` and not `GitX-Release` for the canonical
filesystem name: Decision 2026-04-30 + Gotcha #16 — macOS HFS+ is
case-insensitive, so `GitX-Release/` and `gitx-release/` collide on
default macOS filesystems. The brand survives in titles and descriptions;
the filesystem identifier stays lowercase.

Artifacts: `Release/gitx-release-v1.1.0/`

---

## v1.0.10 — 2026-05-04

**No-op stability rebake.** No source code changes vs v1.0.9. Sole
purpose: verify the v1.0.8 hardening + v1.0.9 self-bake remain
deterministic across a fourth consecutive run, and exercise the
release pipeline immediately before the v1.1.0 rebrand cut.

- All scripts, tests, and contracts byte-identical to v1.0.9
- `bash tests/run_all.sh` → 72 suites / 0 failed
- Deep Audit inline → 176 PASS / 0 FAIL / 1 SKIP (§8 inline `latest`
  not yet flipped — expected SKIP)
- `shasum -a 256 -c checksums.txt` → 6/6 OK
- `diff -rq scripts/ skills/git-release-pipeline/scripts/` → clean

Artifacts: `Release/git_release_skill-v1.0.10/`

---

## v1.0.9 — 2026-05-04

**Stability self-bake of v1.0.8 hardening.** No source code changes
vs v1.0.8. Third consecutive self-bake (after v1.0.7 / v1.0.8) to
prove release-to-release determinism of the 5th-pass hardening.

- All scripts, tests, and contracts byte-identical to v1.0.8
- `bash tests/run_all.sh` → 72 suites / 0 failed
- Deep Audit inline → 176 PASS / 0 FAIL / 1 SKIP
- `shasum -a 256 -c checksums.txt` → 6/6 OK
- `gitx-release.sh` sentinel ⚠️ warning fired correctly (Gotcha #29 +
  the new contract from v1.0.8 §11h)

Artifacts: `Release/git_release_skill-v1.0.9/`

---

## v1.0.8 — 2026-05-04

**5th-pass independent review hardening.** Three parallel reviewers
(security / bash / architecture) audited ~2.9K lines of critical core.
0 Critical, 13 Important, 13 Minor — all P0/P1 closed before
multi-project use.

P0 — supply chain
- **install.sh checksums.txt verification** (Gotcha #30): if
  `$SELF_DIR/checksums.txt` exists, every listed file is verified
  with `shasum -a 256 -c` (or `sha256sum -c` fallback) BEFORE any
  filesystem write. Mismatch → exit 1 with details. Dev-tree
  installs (no checksums.txt) graceful-degrade.

P0 — audit integrity
- **release-audit.sh `--inline` provenance** (Gotcha #27): flag now
  requires `_GITX_INTERNAL_INLINE=1` env. release.sh exports it
  before in-pipeline audit calls; standalone callers passing
  `--inline` without the env get stderr warn + strict mode.
  Closes the §8 mismatch FAIL→SKIP bypass.
- **VERSION regex validation**: standalone audit rejects malformed
  inputs (`../../etc`, shell metachars, wildcards) with exit 2.
- **§6 unzip clean fail**: corrupt `.skill` no longer aborts the
  audit script under `set -e`; Per-Section Summary always prints.
- **§5 LIST trap mangle**: function-local `_S5_LIST` + explicit
  `trap - RETURN` to prevent global RETURN trap collisions.

P1 — sanitizer / scanner
- **release-sanitize.sh path anchoring** (Gotcha #28): all `! -name
  'X.sh'` exclusions changed to `! -path '*/scripts/X.sh'`,
  eliminating the basename-collision bypass where same-named files
  in unexpected paths were silently skipped.
- **scan-credentials.sh stream-not-slurp**: file-stream `grep -E
  ... < SRC` instead of variable substitution, avoiding RSS bloat
  on large files; `printf` instead of `echo` to defeat xpg_echo.
- **+7 credential patterns**: AWS ASIA STS, AWS `key=value`,
  GitHub fine-grained PAT, GitHub user-to-server (`ghu_…`), bare
  JWT, GCP service-account JSON marker, Azure storage connection
  string. Test fixtures use string-assembly to avoid self-flagging
  by other secret scanners.

P1 — contract clarity
- **gitx-release.sh sentinel + warn** (Gotcha #29): wrapper injects
  an HTML-comment marker (literal string `gitx-auto-entry: replace
  this section …`) into every auto-generated CHANGELOG entry, then
  prints ⚠️ at end-of-run if any matching marker is detected in the
  root or release-scoped CHANGELOG.
- **release.sh preflight_external_tools()**: probes
  rsync/tar/gzip/unzip/awk/sed/grep/find/diff/sha up front; missing
  binaries → exit 1 BEFORE pipeline starts.
- **release.sh RELEASE_DATE wall-clock guard**: explicit `if [ -z ]`
  block + stderr warn that RELEASE_NOTES.md will not be
  byte-reproducible when wall-clock fallback fires.

Phase D — defensive hardening
- gitx-release.sh:230 residual Gotcha #24 `[ -n "$var" ] && cmd`
  pattern → if-form (would otherwise abort under set -e).
- release.sh:cleanup_on_fail() — three mktemp guards converted to
  if-form (same set -e hazard).
- release.sh:safe_version() — escape set widened from `\.` to
  `[.[*+?(){}\\^$|]` to defend against future VERSION regex
  loosening.
- emit-sbom.sh — new `json_escape()` helper, `VERSION_ESC` /
  `SKILL_NAME_ESC` injected into SBOM JSON via the helper.
- detect-project.sh `_validate_name()` — `[a-zA-Z0-9._-]` charset
  whitelist on PROJECT_NAME / SKILL_NAME; `_detect_skill_name`
  failure now propagates return code to sourcing caller.
- release-sanitize.sh — top-of-file maintenance comment ("set -u
  only — do NOT add set -e without converting all `[ ... ] && cmd`
  to if-form").

Tests: 8 new TDD files (audit_inline_provenance,
audit_unzip_clean_fail, audit_version_validation,
full_tarball_reproducibility, install_checksum_verify,
preflight_external_tools, release_date_hard_fail,
sanitize_basename_anchor, wrapper_changelog_warn) +
credential_patterns expanded to 11 cases. Suite 64 → 72 green.

Verification: `bash tests/run_all.sh` clean; smoke 6/6; Deep Audit
176 PASS / 0 FAIL / 1 SKIP; `shasum -c checksums.txt` 6/6 OK;
`shellcheck -S warning` 0 new warnings; `diff -rq` dual-source
clean.

Artifacts: `Release/git_release_skill-v1.0.8/`

---

## v1.0.7 — 2026-05-04

- Automated GitX release: run full gate suite, package artifacts, generate attestations, and complete deep audit.

Artifacts: `Release/git_release_skill-v1.0.7/`

---

## v1.0.6 — 2026-05-01

- Automated GitX release: run full gate suite, package artifacts, generate attestations, and complete deep audit.

Artifacts: `Release/git_release_skill-v1.0.6/`

---

## v1.0.5 — 2026-05-01

- Automated GitX release: run full gate suite, package artifacts, generate attestations, and complete deep audit.

Artifacts: `Release/git_release_skill-v1.0.5/`

---

## v1.0.4 — 2026-04-30

- Automated GitX release: run full gate suite, package artifacts, generate attestations, and complete deep audit.

Artifacts: `Release/git_release_skill-v1.0.4/`

---

## v1.0.3 — 2026-04-30

- Automated GitX release: run full gate suite, package artifacts, generate attestations, and complete deep audit.

Artifacts: `Release/git_release_skill-v1.0.3/`

---

## v1.0.2 — 2026-04-30

- Automated GitX release: run full gate suite, package artifacts, generate attestations, and complete deep audit.

Artifacts: `Release/git_release_skill-v1.0.2/`

---

> 历史完整累积记录同步到 `Release/CHANGELOG.md`（由 `scripts/release.sh` 自动维护）。

## v1.0.1 — 2026-04-30

### 跨 CLI 安装支持

- **install.sh 重写**: 实体安装到 `~/.agents/skills/`（Agent Skills 开放标准路径），自动创建 symlink 到 `~/.claude/skills/`
- 一条命令覆盖 Claude Code + Codex + OpenCode + Gemini CLI 四家
- rsync 排除 `.omc/` 目录（审查报告不进 release tarball）
- 同步 dual-source: `scripts/lib/`、`README.md`、`sync-dual-source.sh` 补全到 skill bundle
- `sync-dual-source.sh` 加 `chmod +x`（修复 §6b audit 失败）

Artifacts: `Release/git_release_skill-v1.0.1/`

---

## v1.0.0 — 2026-04-29

### 🎉 v1.0.0 — 五专家审查 + 全量 TDD 修复 + 三轮回审

首个正式稳定版。经 5 位专家（Torvalds / Norman / Liskov / Vogels / Feathers）三轮 heuristic evaluation，18+ 项发现全部通过 TDD 迭代修复，三轮代码回审确认零回归。

### 🔴 P0 修复 (3 项)
- **dry-run 契约修复**: `mkdir -p "$RELEASE_DIR"` 及 tar|gzip pipeline 现在正确包在 `run()` 中，dry-run 不再创建任何真实文件或目录
- **dry-run 全链路贯通**: 6 个函数（run_sanity_scans / generate_attestations / generate_release_notes / update_changelog / run_deep_audit / build_skill_package zip fallback）加 DRY_RUN early return，dry-run 模式 exit 0
- **Test 5 断言修复**: 从旧 `ln -sf + mv` 模式更新为当前 `ln -sfn` 便携模式

### 🟠 P1 修复 (6 项)
- **trap 覆写消除**: CHANGELOG scaffold 不再用 `trap` 覆写外层 cleanup，改用 `CLEANUP_EXTRAS` bash 数组累加器，消除 STAGE tmpdir 泄漏
- **安全扫描 +3 pattern**: 经典 OpenAI key `sk-[48]` / npm auth token / PyPI API token
- **安全扫描 +4 扩展名**: `.env` / `.pem` / `.key` / `.p12` 加入 `find_text_files`
- **warn() ADVISORY 计数器**: 失败时增 ADVISORY 计数（非 FAIL），summary 行输出 `⚠️N`
- **E2E pipeline smoke test**: 对最小 fixture 跑完整 release.sh pipeline，6 断言覆盖核心产物
- **dry-run CHANGELOG 不可变**: `Release/` 和 CHANGELOG.md 的 bootstrap 创建包在 DRY_RUN guard 中

### 🔍 三轮回审额外修复
- `CLEANUP_EXTRAS` 从 string 改为 bash 数组（消除 unquoted word-split 安全隐患）
- Test 7 传入 `PROJECT_NAME` 消除 vacuous assertion
- bash 3.2 trap exit code 泄漏修复（`&&` → `if/then`）

### 📊 数据
- **40 test suites / 329 assertions / 0 failed** — 连续 3 轮全绿
- **shellcheck 0 warnings** 全部修改脚本
- **12 credential patterns** 覆盖 11 服务
- **20 种文件扩展名** 纳入扫描

Artifacts: `Release/git_release_skill-v1.0.0/`

---

## v0.9.11 — 2026-04-24

### 🧮 新 artifact: `TOKEN_USAGE.md` — 为终端用户披露运行时 context token 成本

被 release 的 skill 装到用户 Claude Code 后,每次触发会占用 AI 的 context window。之前用户装之前看不到这个开销,装完才发现贵;现在 release 产物里带一份 `TOKEN_USAGE.md`,把**这个具体 skill** 在 runtime 进入 context 的 token 量按三档列出(baseline / typical / full references pull),折算 Sonnet/Haiku/Opus 三价。

### 🆕 新脚本: `scripts/emit-token-usage.sh`

- 独立可测,~180 行,零外部依赖
- **Tier-1** tokenizer: `python3 + tiktoken cl100k_base`(±10% vs Claude tokenizer)
- **Tier-0** 降级: 纯 bash 启发式(保守偏高 20-35%,自动标注"install tiktoken for precision")
- 输出分层:
  - `SKILL.md` → **always loaded**(baseline,每次触发必进 context)
  - `references/**.md` → **on-demand**(SKILL.md 指引 AI 按需读取)
  - `scripts/**` → **NOT LOADED**(执行层,由 Bash tool 跑,源码不入 context)
  - 根目录 docs → **bundle-only**(README/CHANGELOG 等纯人看,Claude Code 不加载)
- 价格可通过 env 覆盖: `CLAUDE_SONNET_INPUT_PER_MTOK` / `CLAUDE_HAIKU_INPUT_PER_MTOK` / `CLAUDE_OPUS_INPUT_PER_MTOK`

### 🔧 流水线接入

- `release.sh §2.7b`: 在 SBOM 之后、checksums 之前调 `emit-token-usage.sh`(仅 skill bundle 跑,非 skill 项目静默 skip)
- `release.sh §2.8`: checksums 覆盖面 4 → **5** 件(加入 `TOKEN_USAGE.md`,防篡改对齐 SBOM/install.sh 级别)
- `release-audit.sh §11j`: 6 项检查(存在 / 标题 / SKILL.md baseline 标注 / tokenizer 披露 / 场景表数字合理 / checksums 覆盖);非 skill 项目 ➖ SKIP

### 🧭 Decision

tokenizer 分层选了 **C(两档并存)** 而非 A(强依赖 tiktoken)或 B(只 bash 启发式);audit 严苛度选了 **Y(非 skill SKIP,skill FAIL)** 而非 X(一律 FAIL)。详见 `HANDOFF.md` Decision Log 2026-04-24。

### 🧪 测试

- 新增 `tests/test_token_usage.sh`(14 用例,TDD 严格 RED→GREEN)
- 测试套件: 25 → 26 suites 全绿
- `tests/run_all.sh` 从硬编码 36 套件 → 自动发现所有 `test_*.sh`(P0-3)
- 新增 `test_audit_version_escape.sh`(6 用例, SAFE_VERSION 全局化验证)
- 新增 `test_release_dry_run_tests_skip.sh`(3 用例, dry-run 无副作用验证)
- 新增 `test_run_all_auto_discovery.sh`(3 用例, 自动发现验证)
- 测试套件: 36 → **38 suites 全绿**

### 🔧 流水线增强 (v0.9.11)

- `release.sh`: CHANGELOG gate dry-run 短路(P0-4, dry-run 不修改文件)
- `release.sh`: run_tests dry-run 跳过(P2-4, 避免执行测试)
- `release.sh`: set -o errtrace 加固 trap 链(B-5)
- `release-audit.sh`: SAFE_VERSION 全局化,消除 `.` 通配符误判风险(P0-2)
- `release-audit.sh`: checksum 失败输出具体不匹配详情(B-4)
- `release-audit.sh`: 每 section 独立统计,输出 Per-Section Summary 表(P3-2)
- `release-sanitize.sh`: grep_files 限流,每文件 10 行/总计 200 行上限(P1-1)
- `emit-sbom.sh`: json_escape 完整化,处理 \t \r \b \f(B-3)
- `sync-dual-source.sh`: 硬编码 project 名 → 自动检测 SKILL_NAME(P0-1)
- `detect-project.sh`: 排除模式配置化(SKILL_EXCLUDE_PATTERNS 环境变量)(P2-1)
- 新增 `scripts/README.md` — 所有脚本的入口索引(P3-4)
- SKILL.md 执行流程从 13 步编号 → 12 函数表(P2-2)

### 📊 对本项目 dogfood 数据(tiktoken 精确)

| 场景 | Input tokens | Sonnet 4.6 |
|---|---:|---:|
| Baseline (trigger only) | 2,015 | $0.006 |
| Typical invocation | 5,015–7,015 | $0.015–$0.021 |
| Full references pull | 24,273 | $0.073 |

Bundle 元数据(README/CHANGELOG/LICENSE 等) 合计 14,275 token — **不进 runtime context**。

---

## v0.9.10 — 2026-04-23

### 🏷 Release 目录带项目名前缀（命名一致化）

之前 `Release/v0.9.9/` 看不出属于哪个项目,在 monorepo / 回审场景下有歧义。改为 `Release/<PROJECT_NAME>-<VERSION>/`,与 artifact 文件名约定(`git_release_skill-v0.9.10.skill` / `-source.tar.gz`)一致。

- `release.sh`: `RELEASE_DIR="$PROJECT_ROOT/Release/${PROJECT_NAME}-${VERSION}"`
- `release.sh`: `ln -sfn "${PROJECT_NAME}-${VERSION}" .../Release/latest`
- `release.sh`: CHANGELOG 脚手架模板同步 `Release/${PROJECT_NAME}-$VERSION/`
- `release-audit.sh`: `DIR` 使用新格式;同时**向后兼容** legacy 布局 — 若新路径不存在但 `Release/$VERSION/` 存在,audit 降级到 legacy 模式,可以审计历史版本
- `release-audit.sh §8`: latest target 期望值按 `LEGACY_LAYOUT` flag 切换(legacy → bare $VERSION;new → `${PROJECT_NAME}-${VERSION}`)

### 🔄 已有 Release/ 目录迁移

原地 `mv`:

```
Release/v0.9.6 → Release/git_release_skill-v0.9.6
Release/v0.9.7 → Release/git_release_skill-v0.9.7
Release/v0.9.8 → Release/git_release_skill-v0.9.8
Release/v0.9.9 → Release/git_release_skill-v0.9.9
Release/latest → git_release_skill-v0.9.9
```

### 🧪 测试

- 新增 `tests/test_release_dir_naming.sh`（5 用例）
  - release.sh `RELEASE_DIR` 包含 `$PROJECT_NAME-$VERSION`
  - release-audit.sh `DIR` 同格式
  - `ln -sfn` 目标参数同格式
  - audit §8 期望值按新格式比对
  - 功能断言: `Release/latest` 指向 `<name>-<version>/` 而非 bare `<version>/`
- 测试套件：24 → **25 suites 全绿**

### 📝 备注

- 向后兼容: standalone `audit v0.9.6` (老版本)仍可工作(自动检测 legacy 布局)
- 产物内容未变(`.skill` / tarball / SBOM / checksums)只有外层目录名改
- `Release/CHANGELOG.md` 的 `Artifacts:` 行从 v0.9.10 开始写新路径

## v0.9.9 — 2026-04-23

### ✨ 新功能 — A + B + D（v0.9.x 产出物质量升级）

#### A. SOURCE_DATE_EPOCH 支持

按 Debian / Nix / SLSA 标准，release.sh 尊重 `$SOURCE_DATE_EPOCH` 环境变量：

- 已设：使用该 epoch 作为 staging mtime（典型用法 `SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)`）
- 未设：沿用 v0.9.8 的默认 `200001010000.00`

跨 BSD `date -r EPOCH` 和 GNU `date -d @EPOCH` 两种风格自动兼容。接入 CI 后可让 tarball hash 与 commit SHA 一一对应。

#### B. RELEASE_NOTES 注入 CHANGELOG 当前版条目

之前的 `RELEASE_NOTES.md` 只列文件清单和三条安装路径，用户要打开 `CHANGELOG.md` 才知道本版改了什么。现在 release.sh 在 RELEASE_NOTES 末尾自动 append 一个 `## What's new in $VERSION` 章节，内容来自 `Release/CHANGELOG.md` 的对应块（awk 按 `## vX.Y.Z` 起始、`---` 结束提取）。

#### D. CycloneDX 1.5 SBOM 生成

新产出物 `Release/<ver>/sbom.cyclonedx.json`，列出 `.skill` / tarball / install.sh 的 name + version + SHA-256 哈希。满足 SLSA L3 / 开源供应链审计最低要求。

- 零外部依赖（纯 bash + 已有的 `shasum`/`sha256sum`）
- 确定性：timestamp 跟随 SOURCE_DATE_EPOCH，serialNumber 由 artifact hashes 派生
- 自身被 checksums.txt 覆盖（tamper-evident）
- Audit 新增 §11i 校验 SBOM 形态：bomFormat / specVersion / metadata.component.version / 各 artifact 入列

### 🧪 测试

- 新增 `tests/test_source_date_epoch.sh`（5 用例）— 含"同 epoch → byte-identical / 异 epoch → 不同"双向功能断言
- 新增 `tests/test_release_notes_changelog_inject.sh`（3 用例）— 含 awk 提取隔离性验证
- 新增 `tests/test_sbom_generation.sh`（5 用例）— 含 JSON 解析 + CycloneDX shape 校验
- 测试套件：21 → **24 suites 全绿**

### 📝 备注

- 无破坏性变更
- checksums.txt 现覆盖 4 件（.skill / tarball / install.sh / sbom.cyclonedx.json）
- RELEASE_NOTES 文本首次真正"自说明"（不用二次跳转）

## v0.9.8 — 2026-04-23

### 🔒 Reproducible source tarball（Gotcha #14）

v0.9.7 幂等重跑时发现：`.skill` 和 `install.sh` hash 稳定，**source tarball hash 每次不同**。用户无法离线验证"我手上的 tarball 是否与官方一致"，违反 SLSA L3 可复现构建。

三个不确定性来源逐一修复：

1. **文件 mtime** 写进 tar header → `find "$STAGE_SUB" -exec touch -t 200001010000.00 {} +` 归一化到固定 epoch
2. **文件系统遍历顺序** 不稳定 → `find | LC_ALL=C sort | tar --no-recursion -T -` 显式排序
3. **gzip header 内嵌时间戳和文件名** → `gzip -n`（strip name + timestamp）

跨 BSD tar (macOS) / GNU tar 兼容。

### 🐛 顺带发现 Gotcha #15 — BSD mv 破坏 latest 软链

自审验证 idempotency 时发现 `mv -f .latest.tmp latest` 在 BSD mv (macOS) 上 follow 目标软链:当 `latest → v0.9.7/` 已存在,`mv -f .latest.tmp latest` 把 `.latest.tmp` 移进了 `v0.9.7/` 目录(BSD mv 解释 `latest` 为目标目录),结果:

- `latest` 软链原地不动,指向旧版本
- `v0.9.7/.latest.tmp` 孤儿文件累积
- standalone audit §8 `❌ Release/latest → v0.9.7(应为 v0.9.8)` 挂

修复: 改用 `ln -sfn "$VERSION" "$PROJECT_ROOT/Release/latest"` — `-n` flag 让 BSD/GNU ln 一致把已存在的 symlink-to-directory 当普通文件替换,跨平台原子 swap。

### 🧪 测试

- 新增 `tests/test_tarball_reproducibility.sh`（4 用例）
  - 静态断言：release.sh 含 `gzip -n` / `touch -t` / `find | sort | tar -T -`
  - 功能断言：两次 build 同一 staging → tarball byte-identical
- 新增 `tests/test_release_latest_swap.sh`（4 用例）
  - 静态断言：release.sh 用 `ln -sfn`（非 `mv -f`）
  - 功能断言：recipe 正确替换 symlink-to-directory
  - 回归守卫：`v0.9.x/.latest.tmp` 孤儿检测
  - 平台诊断：BSD mv 行为探针(记录 macOS/Linux 实际表现)
- 测试套件：19 → **21 suites 全绿**

### 📝 备注

- 无破坏性变更；任何下游项目自动受益（触发条件只在 release.sh 流程中）
- checksums.txt 的 tarball hash 现在是确定的——发版者和下载者可离线比对
- idempotency sanity: 同一 source 两次 `bash scripts/release.sh v0.9.8` → `.skill` / tarball / install.sh 三件 sha256 完全一致

## v0.9.7 — 2026-04-23

### 🔍 自审 sprint — 产物回审迭代

v0.9.6 首次自举成功后，对发版产物（`.skill` / tarball / 平摊文档 / install.sh / checksums）进行深度回审，四轮迭代共发现并修复 5 个隐藏问题：

#### F1 tarball 泄漏内部自发版镜像

- 症状: 用户解压 `*-source.tar.gz` 看到根级 `scripts/` 和 `skills/git-release-pipeline/scripts/` 两份完全相同的文件，困惑
- 根因: flat-layout 项目使用 `skills/<name>/` 作为 self-release 镜像（解决 v0.9.x skill-creator 布局兼容），rsync 未排除
- 修复: `release.sh` rsync 启发式——若 `$PROJECT_ROOT/SKILL.md` 存在，自动 `--exclude='/skills'`；`release-audit.sh §5` 同步改为 flat-aware（校验根级 scripts/ + SKILL.md 而非 skills/）
- 影响面: 仅本项目 + 未来任何采用 flat-bootstrap 的新项目

#### F2 RELEASE_NOTES 方式 B 指示 `cp commands/*.md` 但 bundle 无 commands/

- 症状: 用户跟随 Method B 执行到 `cp ~/.claude/skills/git-release-pipeline/commands/*.md ~/.claude/commands/` 报错（源文件不存在）
- 根因: `release.sh` RELEASE_NOTES 模板硬编码假设 skill 有 slash command shim；本项目（及任何纯逻辑 skill）无 commands/
- 修复: 检测 `$SKILL_SRC_DIR/commands/*.md` 存在时才 emit `mkdir -p ~/.claude/commands` 和 `cp .../commands/*.md ...` 两行；否则只 emit `mkdir -p ~/.claude/skills`

#### F4 install.sh 从 Release 目录运行会 abort（Method A broken）

- 症状: `cd Release/v0.9.7 && ./install.sh` 报 `❌ Missing required file: .../scripts/release.sh`，自此 **任何使用本 release.sh 的项目 Method A 都 broken**
- 根因: `release.sh` 平摊步骤只拷了 docs + install.sh + SKILL.md 到 `Release/<ver>/`，没拷 `scripts/` / `references/` / `assets/`；但 install.sh line 60-66 要求这几个目录在 `$SELF_DIR` 下
- 修复: `release.sh` 平摊步骤新增 `cp -R $SKILL_SRC_DIR/{scripts,references,assets} $RELEASE_DIR/`（条件拷贝），并 `chmod +x scripts/*.sh`

#### F5 README 链 `ROADMAP.md` 但未平摊到 Release/<ver>/

- 症状: Method A 用户在 Release dir 打开 README 点 ROADMAP.md 链接 → 404
- 根因: `release.sh` 平摊白名单遗漏 ROADMAP.md（项目特定文档）
- 修复: 平摊循环加入 ROADMAP.md（存在时才拷，保持 cross-project 兼容）

#### Gotcha #13 audit §8 N+1 发版时 inline audit 误 FAIL

- 症状: 首次自发版 v0.9.7 时，audit §8 `❌ Release/latest → v0.9.6（应为 v0.9.7）`。v0.9.6 的 "latest 缺失→SKIP" 修复没覆盖这个 N+1 场景
- 根因: inline audit 运行时 latest 还指向上一版 v0.9.6（S1-5 故意让 release.sh 在 audit 通过后才原子更新），但 audit §8 mismatch-target 分支硬 FAIL
- 修复: `release-audit.sh` 接受 `--inline` flag；inline 模式下若 `latest_target` 指向的旧版本目录仍存在，§8 emit ➖ SKIP；standalone 调用保留严格 target 校验。`release.sh` 调用 audit 时传 `--inline`
- 新增 `tests/test_audit_inline_flag.sh`（6 用例）防回归

### 📝 备注

- 测试套件从 18 → **19 suites 全绿**（新增 `test_audit_inline_flag.sh`）
- 本次 sprint 未引入破坏性变更；所有修复同时适用于 flat-layout 自发版项目 + 传统 `skills/<name>/` 布局项目
- Method A（`cd Release/<ver> && ./install.sh`） 首次真正可用
- 回审流程: inline audit → unpack .skill → extract tarball → install.sh dry-run → real install → cross-ref scan;每轮问题修好后重包再审

## v0.9.6 — 2026-04-23

### 🔧 自举 sprint — 首次自发版时发现并修复 5 个阻塞

首次尝试用本技能给自己发版时，一口气暴露了 5 个真实 bug。v0.9.6 把它们全部 TDD 修掉，自举 release 终于 119 ✅ / 0 ❌ / 1 ➖。

#### 1. Gotcha #8 `[build]` skill-creator 拒绝顶层 `version:` 字段

- 症状: `release.sh:182` `python -m scripts.package_skill` 静默 abort（stdout → /dev/null），release 停在 "Building .skill via skill-creator..."
- 根因: S3-3 契约在 SKILL.md 顶层声明 `version:`，但 skill-creator 校验器只允许 `{allowed-tools, compatibility, description, license, metadata, name}`
- 修复:
  - `SKILL.md` frontmatter: `version: v0.9.5` → `metadata:\n  version: v0.9.6`
  - `release.sh` S3-3 解析器改 awk 状态机：进入 `metadata:` 块后读取缩进的 `version:`；缺失/不一致仍 abort
  - `test_skill_version_consistency.sh` 扩展到 6 用例（含"顶层不得有 version"防回归 + 解析器嵌套识别）

#### 2. Gotcha #9 `[build]` skill-creator 禁止 `description:` 含 `<` / `>`

- 症状: `❌ Validation failed: Description cannot contain angle brackets (< or >)`
- 根因: SKILL.md description 用 `skills/<name>/`、`release <version>`、`audit <version>`、`scan <dir>` 作占位符
- 修复:
  - SKILL.md: `<name>` → `NAME`、`<version>` → `VERSION`、`<dir>` → `DIR`（语义保持一致）
  - `test_skill_description_word_count.sh`: trigger 断言更新为 uppercase 版本

#### 3. Gotcha #10 `[build]` 空 `assets/` 目录被 skill-creator 剥掉

- 症状: audit §6 `.skill 含 assets/` ❌；`.skill 与 bundle 有差异: Only in bundle: assets` ❌
- 根因: upstream skill-creator zip 剥离空目录，但 audit 要求 `.skill` 解压后含 `assets/`
- 修复: 新增 `assets/README.md` 占位文件，说明"保留目录存在"的意图

#### 4. Gotcha #11 `[build]` `.sanitize-ignore` 未平摊到 Release/<ver>/

- 症状: audit §7 post-release sanity 扫描命中 `SECURITY.md` 的业务联络邮箱（本应由白名单豁免）
- 根因: `release-sanitize.sh` 从 `$DIR/.sanitize-ignore` 加载白名单；pre-release 扫 staging 目录（rsync 带来了 `.sanitize-ignore`），post-release 扫 `Release/<ver>/` 却没有
- 修复: `release.sh` §2.6 平摊步骤新增 `.sanitize-ignore` → `Release/<ver>/`

#### 5. Gotcha #12 `[build]` audit §8 `latest` 缺失硬 FAIL 破坏自身契约

- 症状: 首次发版时 `❌ Release/latest 软链接不存在`
- 根因: S1-5 故意让 release.sh 在 audit 通过后才原子创建 latest（避免"audit 失败却已更新 latest"），但 audit 在 release.sh 中是 inline 调用，此时 latest 确实不存在——audit 反过来 FAIL 自己
- 修复:
  - `release-audit.sh §8`: latest 缺失从 ❌ FAIL → ➖ SKIP（保留"target 错误时仍 FAIL"的关键不变量）
  - 新增 `tests/test_audit_latest_symlink_skip.sh`（5 用例）：断言 SKIP 分支 + 防 target-mismatch 分支回归
  - run_all.sh 加载新套件

#### 附带: `$VAR（` 多字节字符解析 bug

- 症状: release.sh line 401 执行 `echo "...$VERSION（..."` 报 `VERSION�: unbound variable`
- 根因: bash locale 相关，`$VERSION` 后紧跟全角 `（` 时被当作变量名一部分
- 修复: 3 处显式加括号 `${VERSION}` `${latest_target}`（release.sh 1 处、release-audit.sh 2 处）

### 📝 备注

- **v0.9.5 从未发布**: 所有 v0.9.5 的 Sprint 2/3 加固与 GitHub 开源标准补全工作保留在代码中
- 无破坏性变更: 下游项目只需把 SKILL.md 顶层 `version:` 移到 `metadata.version:` 即可
- 测试套件从 17 → **18 suites 全绿**（新增 `test_audit_latest_symlink_skip.sh`）

## v0.9.5 — 2026-04-23 *(yanked — never shipped due to Gotcha #8)*

### 🔧 Sprint 2/3 TDD 加固

- **S2-1 (已先落地)**: `release-sanitize.sh` 改用 `find -print0 | while read -d ''`，支持含空格文件名
- **S2-2**: `release.sh` + `release-audit.sh` §4 使用 `SAFE_VERSION`（dot 转义）+ `grep -F`，杜绝 `v1.0.0` 误匹配 `v1X0Y0` 假阳性
- **S2-3/4/5/6/7 (已先落地)**: 白名单扩展 / evals 缩窄 / §2b §6b warn / trap 统一清理 / install.sh §6.10 接口验证
- **S3-2**: `SKILL.md` description 精简到 66 词（原 118 词），保留三条 trigger 语义
- **S3-3**: `SKILL.md` frontmatter 新增 `version:` 字段，`release.sh` 加一致性校验 gate（不一致即 abort）
- **S3-4**: `release-audit.sh §9` 双源缺失从 ➖ SKIP 升级为 ❌ FAIL，执行 v2.3 byte-identical 政策
- **S3-6**: `release-audit.sh §10` 硬编码 `[0-9]+ KB` 从 ⚠️ 软警告升级为 ❌ FAIL
- **S3-7**: `release.sh` 启用 `set -euo pipefail`

### ✨ GitHub 开源标准补全

- 新增 `README.md` / `LICENSE` (MIT) / `CONTRIBUTING.md` / `CHANGELOG.md`（本文件）

### 🧪 测试

- 测试套件从 8 suites / 31 用例 → **12 suites / 47+ 用例全绿**
- 新增测试文件：`test_skill_version_consistency.sh` / `test_audit_dual_source_required.sh` / `test_audit_kb_hardcode.sh` / `test_skill_description_word_count.sh`

Artifacts: `Release/v0.9.5/`

---

## v0.9.4 — 2026-04-22

### 🔧 Sprint 1 TDD 修复（4 个 CRITICAL）

- **S1-1**: `release-audit.sh` 空 `assets/` 目录从 ❌ FAIL → ➖ SKIP
- **S1-2**: `SKILL.md` 删除无实现的 `check policy` 触发词，替换为 `scan <dir>`
- **S1-3**: audit summary 改为三态 `✅N / ❌N / ➖N`，所有 ➖ 分支计数 SKIP
- **S1-4**: `release.sh` audit 失败消息删除 `<重跑 release>` 占位符，改为可执行命令
- **S1-5**: `release.sh` latest 软链从 Step 4 移到 audit 通过后，原子 `ln -sf + mv`

### 🧪 测试基础建设

- 新建 `tests/run_all.sh` + 7 个测试文件 + fixtures（31 个用例）

Artifacts: `Release/v0.9.4/`

---
