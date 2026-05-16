<div align="center">

# 🚀 GitX

**A cross-project release pipeline that treats shipping as an engineering discipline, not a chore.**

[English](README.md) · [中文](README_CN.md)

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-95%2B%20suites%20%2F%200%20fail-brightgreen.svg)](tests/run_all.sh)
[![Deep Audit](https://img.shields.io/badge/deep%20audit-227%2F0%2F1-brightgreen.svg)](scripts/release-audit.sh)
[![CLIs](https://img.shields.io/badge/CLI-Claude%20Code%20%C2%B7%20Codex%20%C2%B7%20OpenCode%20%C2%B7%20Gemini-blue.svg)](#quick-start)
[![Shell](https://img.shields.io/badge/bash-3.2%2B%20POSIX-orange.svg)](SKILL.md)

</div>

> One command turns the scattered, error-prone ritual of cutting a release —
> version bump, tests, packaging, secret scanning, doc flattening, integrity
> attestation, deep audit — into a single fail-closed pipeline. Every policy
> is enforced as a shell assertion, not a wiki page nobody reads.

**Version**: see [`VERSION`](VERSION) / [`Release/CHANGELOG.md`](Release/CHANGELOG.md) ·
**Runtime**: pure Bash 3.2+ (POSIX), git 2.x, optional `python3 + venv` ·
**Scope**: any `skills/<name>/SKILL.md`-layout project, four CLI install surfaces.

---

## What's New

| Version | Highlight |
|---------|-----------|
| v1.9.x | `/gitx:*` plugin namespace + central `tkxlab-ai/marketplace` + gitx-init auto-provision |
| v1.8.x | Claude Code plugin distribution + community-file standard |
| v1.7.5 | Slash shims install to `~/.claude/commands/` (Claude Code discovery fix) |
| v1.7.4 | `gitx-sop` hardened for use by *other* skills (portable redaction + completeness gate) |
| v1.7.2–1.7.3 | Doc version-rot killed + `§0e` audit guard + README command-completeness guard |
| v1.7.0–1.7.1 | `gitx-sop` subcommand (GitHub-publish runbook) + `commands/` distribution fix |
| v1.6.0 | `gitx-init` subcommand — projects teach themselves to release |
| v1.0–1.5 | Vendored Anthropic skill-creator, reproducible builds, 5-skill install standard |

---

## 📊 Live build metrics

**Version**: v1.9.6 · **Released**: 2026-05-16 · **Models**: Claude / Codex (development + adversarial review) · **Cumulative AI tokens (project to date, est.)**: ~500M+ I/O + ~6B+ cache, across hundreds of sessions · **By the numbers**: 95+ BDD suites / 0 fail · Deep Audit all-green · 20+ shipped releases · one GitHub Release per tag.

> **Install any TKX skill** — one marketplace add, then any skill by name:
> ```
> /plugin marketplace add tkxlab-ai/marketplace
> /plugin install gitx@tkx-skills
> ```
> `install.sh` (see [Quick Start](#quick-start)) remains available for direct multi-CLI installs.

---

## Table of Contents

- [Why GitX?](#why-gitx)
- [Philosophy](#philosophy)
- [命令矩阵 Commands](#命令矩阵-commands)
- [Methodology](#methodology)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Testing](#testing)
- [Security Model](#security-model)
- [References & Citations](#references--citations)
- [Compatibility](#compatibility)
- [Contributing](#contributing)
- [License](#license)

---

## Why GitX?

Releasing software by hand fails in predictable, expensive ways:

- **Silent secret leaks** — an absolute path, a private Git host, a token in a
  CHANGELOG line ships to a public mirror and cannot be un-published.
- **Unreproducible artifacts** — `tar` embeds mtimes, `gzip` embeds filenames;
  the same source produces a different tarball every run, so nobody can verify
  "is the file I downloaded the one you released?"
- **Aspirational policy** — "always run the tests first" lives in a wiki the
  releaser skips under deadline pressure. Documentation is not enforcement.
- **Drift** — root scripts and the packaged bundle diverge; docs claim `v0.9`
  while the code is `v1.7`; a slash command ships to a directory the host
  never scans.

GitX exists because **every one of those failure modes is a computable
predicate**. If a rule can be checked by a script, it should fail the build —
not a code review comment six months later. This project is the accumulation
of 30+ real incidents (each a hardened regression test or audit gate) each
converted from "lesson learned" into a regression test or an audit gate.

It helps you:

- Ship a skill/project with **one command** and a fail-closed gate chain.
- Produce **byte-reproducible** source tarballs (SLSA-style provenance).
- Emit a **CycloneDX SBOM** + SHA-256 `checksums.txt` for every release.
- Publish to a **public GitHub mirror** without leaking the private dev tree
  (`/gitx-sop`), and teach any project its own release policy (`/gitx-init`).

---

## Philosophy

GitX is built on four load-bearing principles, each traceable to a named idea:

1. **Policy as Code.** Every release rule is a shell assertion that aborts the
   pipeline, never prose advice. v2.2/v2.3 of the internal policy converted 7
   "aspirational" rules into code-enforced gates. Lineage: the
   *infrastructure-as-code* / *executable specification* tradition.

2. **Invariants over conventions** — *E. W. Dijkstra*. Replace fuzzy human
   judgment with computable predicates: `diff -rq` for dual-source identity,
   anchored `grep` for credential classes, exit-code gates for tests. A
   convention you *hope* holds is replaced by an invariant the machine
   *proves* holds. See Dijkstra, *A Discipline of Programming* (1976).

3. **Close the Gulf of Evaluation** — *Donald A. Norman*. Every pipeline step
   emits an explicit `✅ / ❌ / ➖` marker so the operator never has to infer
   system state. From Norman, *The Design of Everyday Things* (1988) — the
   "gulf of evaluation" is the gap between system state and the user's
   perception of it; GitX narrows it to zero per step.

4. **Zero hardcode, cross-project.** `PROJECT_NAME` / `SKILL_NAME` /
   `PROJECT_ROOT` are environment-derived; there is no project-specific
   literal in the pipeline. The same scripts that release GitX itself release
   any sibling skill — proven in production across multiple projects.

A fifth, operational principle governs how the project itself is maintained:
**every defect becomes a guard.** Test-Driven Development (*Kent Beck*, *Test-
Driven Development: By Example*, 2002) is applied red→green→refactor to every
behavior; tacit operational knowledge is externalized into the project's internal dev log following *Nonaka & Takeuchi*'s SECI model of knowledge conversion (*The
Knowledge-Creating Company*, 1995).

---

## 命令矩阵 Commands

| Action | Trigger | Script | Behavior |
|--------|---------|--------|----------|
| One-command release | `/gitx-release` | `scripts/gitx-release.sh` | Auto patch bump → sync SKILL.md + CHANGELOG → full gate chain; no auto git push |
| Release (explicit) | `release <version>` | `scripts/release.sh` | 12-function pipeline: tests → package → tarball → sanitize → flatten → attest → Deep Audit |
| Re-audit | `audit <version>` | `scripts/release-audit.sh` | 40+ static checks over an existing `Release/<ver>/` (offline-capable) |
| Sanity scan | `scan <dir>` | `scripts/release-sanitize.sh` | 6 secret classes: credentials / abs user paths / real emails / public IPs / MAC / SSH-GPG fingerprints |
| Project init | `/gitx-init` | `scripts/gitx-init.sh` | Generate `.gitx/` policy pack + `RELEASE_GUIDELINE.md` (auto-detect skill/mac/both/empty) |
| GitHub publish SOP | `/gitx-sop` | `scripts/gitx-sop.sh` | Generate `.gitx/GITHUB_RELEASE_SOP.md` — placeholder-rendered public-mirror runbook, **generate-only, never executes git/gh** |

> **Hard constraint**: `git tag` / `git push` / `gh release` are never
> automated by the pipeline (TKX policy §10.10). GitX produces local
> `Release/<version>/` artifacts; pushing upstream is always a human action.

---

## Methodology

### The release pipeline (`release.sh`, 12 named functions)

Executed in strict order; any non-zero step aborts (no `FORCE=1` bypass —
the silent-ghost-release moat):

| # | Function | Guarantee |
|---|----------|-----------|
| 1 | `preflight_checks` | version syntax + SKILL.md consistency + CHANGELOG gate |
| 2 | `run_tests` | `tests/run_all.sh` green or abort |
| 3 | `check_dual_source` | root `scripts/` ≡ bundle `scripts/` (`diff -rq`) |
| 4 | `build_skill_package` | `.skill` via vendored Anthropic skill-creator (zip fallback) |
| 5 | `build_source_tarball` | reproducible tarball (mtime-normalized + sorted) |
| 6 | `run_sanity_scans` | staging + extracted `.skill` scanned for 6 secret classes |
| 7 | `flatten_docs` | 9 docs + scripts/ + references/ + commands/ + install.sh |
| 8 | `generate_attestations` | CycloneDX SBOM + token usage + `checksums.txt` |
| 9 | `generate_release_notes` | 3 install paths + CHANGELOG inject |
| 10 | `update_changelog` | flatten `Release/CHANGELOG.md` |
| 11 | `run_deep_audit` | `release-audit.sh --inline`, 40+ checks green or abort |
| 12 | `update_latest_symlink` | atomic `ln -sfn` **only after audit passes** |

The ordering encodes the **gate-then-ship invariant**: `Release/latest`
never points at an unverified artifact (steps 11 → 12 are not reorderable).

### Reproducible builds (SLSA-style provenance)

`build_source_tarball` neutralizes the three sources of tar non-determinism:
(a) `touch -t $SOURCE_DATE_EPOCH` normalizes mtimes, (b)
`find | LC_ALL=C sort | tar --no-recursion -T -` fixes traversal order, (c)
`gzip -n` drops the embedded filename/timestamp. Result: identical source →
byte-identical tarball → `shasum -a 256 -c checksums.txt` lets anyone verify
their copy offline. This follows the **SLSA** build-provenance model
([slsa.dev](https://slsa.dev)) and *reproducible-builds.org* practice.

### Deep Audit

`release-audit.sh` runs ~14 sections / 227 checks as pure static analysis
(network-free): spec conformance, install standard, `gitx-init`/`gitx-sop`
template integrity (`§0c`/`§0d`), doc version-rot (`§0e`), dual-source
identity, CHANGELOG authenticity, reproducibility, sanitize re-scan. Output
is three-state (`✅ PASS / ❌ FAIL / ➖ SKIP`) — Norman's principle applied.

### Defense in depth

Secrets are scanned at **three independent boundaries**: pre-release staging,
extracted `.skill` bundle, and (for `/gitx-sop`) the public worktree with a
*mandatory post-redaction verification grep* that runs fail-closed regardless
of which redaction path executed.

---

## Quick Start

### Option A — Claude Code plugin (recommended for Claude Code users)

```text
/plugin marketplace add tkxlab-ai/marketplace
/plugin install gitx@tkx-skills
```

Plugin commands are **namespaced** (Claude Code policy) under the `gitx`
plugin: `/gitx:release` `/gitx:sop` `/gitx:init` `/gitx:audit` `/gitx:scan`
(not the flat `/gitx-sop`). Updates: `/plugin marketplace update tkx-skills`.

### Option B — `install.sh` (multi-CLI: Claude Code · Codex · OpenCode · Gemini, flat `/gitx-sop`)

```bash
# Install (clone the public mirror)
git clone https://github.com/tkxlab-ai/GitX.git
cd GitX
./install.sh --dry-run        # preview
./install.sh                  # install to ~/.agents/skills/gitx-release/ (+ Claude/OpenCode symlinks + ~/.claude/commands/ shims)
./install.sh --force          # reinstall when an existing install is already present (overwrites in place)
```

Both paths coexist; pick one. Plugin = namespaced, marketplace-updatable,
Claude-Code-only. `install.sh` = flat command names, four CLIs.

```bash
# Use inside any skills/<name>/SKILL.md project
/gitx-release                 # one-command release (auto patch bump)
release v1.2.0                # explicit version
audit v1.2.0                  # re-audit an existing release
scan ./some-dir               # standalone secret scan
/gitx-init                    # drop a .gitx/ policy pack into the project
/gitx-sop                     # generate the GitHub-publish runbook
```

Codex CLI: open the skill list with `/skills`, or type `$` and pick **GitX**
(selector `$gitx-release`). OpenCode / Gemini: say "gitx release". Slash
subcommands (`/gitx-init`, `/gitx-sop`) require a fresh Claude Code session
after install (commands load at startup).

---

## Architecture

```
gitx-release/
├── SKILL.md                  # skill manifest (name: gitx-release, brand: GitX)
├── install.sh                # 4-CLI installer + ~/.claude/commands/ shims
├── scripts/                  # dual-sourced (root ≡ skills/gitx-release/scripts/)
│   ├── gitx-release.sh       # wrapper: VERSION bump + CHANGELOG + orchestration
│   ├── release.sh            # 12-function pipeline
│   ├── release-audit.sh      # Deep Audit (§0–§11)
│   ├── release-sanitize.sh   # 6-class secret scanner
│   ├── gitx-init.sh          # .gitx/ policy generator
│   ├── gitx-sop.sh           # GitHub-publish SOP renderer
│   ├── lib/                  # detect-project, skill-creator-version, install-style
│   └── vendored/skill-creator/  # Anthropic skill-creator (Apache-2.0, pinned)
├── commands/                 # slash shims (dual-sourced) → ~/.claude/commands/
├── references/               # TKX policy v2.3, gitx-init/, gitx-sop/ templates
├── tests/                    # 94 BDD suites (run_all.sh)
└── Release/                  # generated artifacts + CHANGELOG (not in git)
```

**Dual-source contract**: `scripts/` and `commands/` exist identically at
repo root and inside `skills/gitx-release/`; `check_dual_source` + audit `§9`
abort on any drift. The root layout is what `install.sh` reads; the bundle is
what packages into `.skill`.

---

## Testing

| Layer | What | Count |
|-------|------|-------|
| BDD suites | `tests/run_all.sh` (red→green TDD, one assertion per cycle) | **94 / 0 fail** |
| Deep Audit | `release-audit.sh` static gates (offline) | **227 PASS / 0 FAIL / 1 SKIP / ⚠️0** |
| Reproducibility | byte-identical tarball across runs | enforced (`§5` + dedicated tests) |
| Dual-source | root ≡ bundle | enforced (`§9` + `check_dual_source`) |
| Independent review | Codex adversarial + review gate (authoring/review separation) | clean |

Every known pitfall (37+) maps to a regression test or an audit gate — defects do not recur silently.

---

## Security Model

- **No upstream automation**: the pipeline never runs `git push`/`gh release`.
- **Fail-closed gates**: tests, sanitize, dual-source, Deep Audit, redaction
  verification — any failure aborts before artifacts are blessed.
- **Public-mirror isolation** (`/gitx-sop`): publishes only the sanitized,
  version-pinned release tarball into an isolated per-release worktree with
  its own `.git`; the private remote is never added; tokens are env-only and
  scrubbed from the remote URL after push.
- **Supply chain**: `install.sh` verifies `checksums.txt`; vendored
  skill-creator is pinned by upstream commit; SBOM ships per release.

---

## References & Citations

### Methodology & academic lineage

| Idea | Used for | Reference |
|------|----------|-----------|
| Invariants over conventions | `diff -rq` dual-source, predicate gates | Dijkstra, *A Discipline of Programming*, 1976 |
| Gulf of Evaluation | per-step `✅/❌/➖` output | Norman, *The Design of Everyday Things*, 1988 |
| Test-Driven Development | every behavior red→green→refactor | Beck, *TDD: By Example*, 2002 |
| SECI / tacit knowledge | internal dev-log design | Nonaka & Takeuchi, *The Knowledge-Creating Company*, 1995 |
| Semantic Versioning | version contract | [semver.org](https://semver.org) (Preston-Werner) |
| Build provenance | reproducible tarballs | [slsa.dev](https://slsa.dev), [reproducible-builds.org](https://reproducible-builds.org) |
| SBOM | dependency attestation | [CycloneDX](https://cyclonedx.org) 1.5 spec (OWASP) |

### Software & attributions

- **[Anthropic skill-creator](https://github.com/anthropics/skills)** —
  Apache-2.0; vendored under `scripts/vendored/skill-creator/` (pinned by
  upstream commit) so `.skill` packaging is self-contained and reproducible
  without a network or plugin marketplace. License preserved verbatim.
- **superpowers `test-driven-development`** skill — the red→green discipline
  applied to every cycle in this project's own development.
- **Codex CLI** (OpenAI) — independent adversarial review, used to keep
  authoring and review in separate contexts.

### Internal documents

| Document | Purpose |
|----------|---------|
| [`references/TKX_Git_Release_policy_and_process.md`](references/TKX_Git_Release_policy_and_process.md) | Full release policy v2.3 (lifecycle, pre-release gate, sanitize, Deep Audit, low-level-error catalog) |
| [`docs/SKILL_CROSS_CLI_GUIDELINE.md`](docs/SKILL_CROSS_CLI_GUIDELINE.md) | Cross-CLI skill authoring guideline |
| [`ROADMAP.md`](ROADMAP.md) | Universalization roadmap (non-skill source packages) |

---

## Compatibility

| Requirement | Support |
|-------------|---------|
| OS | macOS / Linux |
| Shell | Bash 3.2+ (POSIX); BSD & GNU coreutils both handled |
| git | 2.x |
| Python | optional — `python3 + venv` for vendored skill-creator; deterministic zip fallback when absent |
| CLIs | Claude Code · Codex · OpenCode · Gemini |

---

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). The bar: every change is TDD'd
(failing test first), dual-source stays byte-identical, Deep Audit stays
green, and authoring/review run in separate contexts.

## License

MIT — Copyright (c) 2026 TKXLAB.AI — <https://github.com/tkxlab-ai>
Vendored `scripts/vendored/skill-creator/` is Apache-2.0 (Anthropic),
license retained in place.

<div align="center">

**GitX** · TKX universal release pipeline · <https://github.com/tkxlab-ai/GitX>

</div>
