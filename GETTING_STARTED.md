# Getting Started with GitX-Release

> **Read this first.** Designed for AI agents (Claude, Codex, Gemini, etc.)
> and human skill authors who plan to use GitX-Release to package and release
> a project. Following this guide before you write code prevents the
> ~80% of release failures that come from preventable layout mistakes.

---

## 1. What GitX-Release does

GitX-Release is a **policy-as-code** release pipeline. One command
(`/gitx-release`) takes your project at any version and produces:

```
Release/<project>-<vX.Y.Z>/
├── <project>-<vX.Y.Z>.skill                  ← single-file skill bundle (zip)
├── <project>-<vX.Y.Z>-source.tar.gz          ← deterministic source archive
├── <project>-<vX.Y.Z>-full.tar.gz            ← full release dir tarball
├── install.sh                                ← user-facing installer
├── checksums.txt                             ← sha256 of every artifact
├── sbom.cyclonedx.json                       ← supply-chain SBOM
├── TOKEN_USAGE.md                            ← runtime token disclosure
├── RELEASE_NOTES.md                          ← human-readable summary
├── README.md / LICENSE / CHANGELOG.md / ...  ← flattened standard docs
└── (your SKILL bundle's references/ assets/ scripts/ commands/ agents/)
```

It runs ~170 audit checks before declaring success. It **never** auto-tags,
auto-pushes, or contacts an upstream — TKX policy §10.10. You manually
publish to whatever host you choose (GitHub, GitLab, Gitea, raw remote).

## 2. Decision tree — is GitX-Release a fit for your project?

Answer these in order:

1. **Is this a Claude / Codex / Gemini skill?** → Yes: continue. No: jump to §7.
2. **Is your project layout `<root>/skills/<name>/SKILL.md`?** → Yes: continue. No: read §3 and migrate first.
3. **Will you accept the constraints?** (no auto-push, fixed file layout, etc.) → Yes: continue. No: pick a different release tool.
4. **You're ready.** Read §3–§6 before writing any code.

## 3. Required project layout (skills)

GitX-Release is **layout-strict**. The pipeline auto-detects names by
walking these paths, so deviation breaks discovery.

```
<your-project-root>/
├── VERSION                              ← REQUIRED. exactly one line: vX.Y.Z
├── SKILL.md                             ← REQUIRED. frontmatter + body (root copy)
├── install.sh                           ← REQUIRED. user-facing installer
├── README.md                            ← REQUIRED for §11 compliance audit
├── LICENSE                              ← REQUIRED for §11 compliance audit
├── CHANGELOG.md                         ← REQUIRED. Keep-a-Changelog style
├── INSTALL.md                           ← STRONGLY RECOMMENDED
├── CONTRIBUTING.md                      ← RECOMMENDED for §11 compliance audit
├── CODE_OF_CONDUCT.md                   ← OPTIONAL (auto-flattened if present)
├── SECURITY.md                          ← OPTIONAL (auto-flattened if present)
├── ROADMAP.md                           ← OPTIONAL (auto-flattened if present)
├── TEST-SCENARIOS.md                    ← OPTIONAL (auto-flattened if present)
│
├── scripts/                             ← REQUIRED. shell scripts (any *.sh)
│   ├── *.sh                             ← byte-identical with skills/<name>/scripts/
│   └── lib/*.sh                         ← optional shared libraries
│
├── skills/
│   └── <name>/                          ← REQUIRED — name MUST be lowercase-hyphenated
│       ├── SKILL.md                     ← byte-identical to root SKILL.md
│       ├── VERSION                      ← byte-identical to root VERSION
│       ├── scripts/                     ← byte-identical mirror of root scripts/
│       ├── commands/*.md                ← OPTIONAL slash-command shims
│       ├── references/*.md              ← OPTIONAL policy / process docs
│       ├── assets/                      ← OPTIONAL static assets
│       └── agents/                      ← OPTIONAL CLI metadata (codex-commands.txt, openai.yaml)
│
└── tests/
    ├── run_all.sh                       ← REQUIRED. fail if any *_*.sh fails
    └── test_*.sh                        ← REQUIRED. at least 1 (smoke/static OK)
```

### The dual-source byte-identity rule

`scripts/` (root) and `skills/<name>/scripts/` MUST be byte-identical.
The pipeline runs `diff -rq` between them and refuses to release on drift.
Use `scripts/sync-dual-source.sh` (provided by GitX-Release once installed)
to keep them aligned, or copy manually after every change to either side.

## 4. Required `SKILL.md` frontmatter

```yaml
---
name: my-skill-name        # lowercase-hyphenated, matches skills/<name>/ folder
description: <≤220 chars>  # MUST mention every trigger your skill has
---

# Body content here...
```

Hard rules:
- `name:` = exactly the folder name under `skills/`
- No `metadata:` block. **Codex rejects it.** Version lives in `VERSION` sidecar only.
- `description:` is loaded into the agent's context budget on every invocation.
  Keep it < 80 words / < 220 chars; mention every slash command and trigger phrase.
- Body has no length cap, but is loaded only when the skill is actually invoked.

## 5. The `install.sh` contract — read this carefully

This is the **#1 source of release-time failures** for downstream projects.
Your `install.sh` runs from inside the extracted `Release/<ver>/` directory.
It can ONLY reference files that GitX-Release flattens into that directory:

### Files that ARE flattened (you can `cp $SELF_DIR/<file>` these)

| File / dir | Source |
|---|---|
| `README.md`, `INSTALL.md`, `TEST-SCENARIOS.md`, `LICENSE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `ROADMAP.md` | `$PROJECT_ROOT/<file>` |
| `SKILL.md`, `VERSION` | `skills/<name>/<file>` |
| `install.sh` (this file itself) | `$PROJECT_ROOT/install.sh` |
| `scripts/`, `commands/`, `references/`, `assets/`, `agents/` | `skills/<name>/<dir>` |
| `*.skill`, `*-source.tar.gz`, `*-full.tar.gz`, `checksums.txt`, `sbom.cyclonedx.json`, `TOKEN_USAGE.md`, `RELEASE_NOTES.md`, `CHANGELOG.md` | generated by pipeline |

### Files that are NOT flattened — DO NOT reference these from install.sh

- Any project-specific markdown at `$PROJECT_ROOT/` outside the standard 8 docs
  above (e.g., `MY-CUSTOM-PROMPT.md`, `INTERNAL-NOTES.md`).
- Any directory at `$PROJECT_ROOT/` other than `scripts/` and `skills/`.
- Files inside `.gitignore` (Release/, HANDOFF.md, .omc/, etc.)
- Anything in `tests/` (intentionally excluded from release)

### Concrete pitfall — real case from claudemex

A project's `install.sh` contained:
```bash
cp "$SELF_DIR/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md" "$HOME/.claude/..."
```

`TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md` lived at the project root but is
NOT in the flatten list. `gitx-release` produced a release where
`install.sh` references a file that isn't in the release dir. End-user
ran `./install.sh` from the extracted release tarball → `cp: ... No such
file or directory` → install fails.

### How to fix this in YOUR project

Pick ONE of:

**Option A — move the file into a flattened directory**
- Put the file in `skills/<name>/references/` or `skills/<name>/assets/`
- Update `install.sh` to reference `$SELF_DIR/references/<file>` etc.

**Option B — give the file a standard-list name**
- If it's a pre-install README, name it `INSTALL.md` (already flattened).
- If it's a security policy, name it `SECURITY.md`.

**Option C — use the `.release-flatten` manifest** *(v1.1.2+)*
- Drop a file named `.release-flatten` at your `$PROJECT_ROOT/`. One path
  per line, relative to `$PROJECT_ROOT/`. Whole-line `#` comments and
  trailing `# ...` comments are tolerated. Blank lines are skipped.
- Listed paths are flattened into `Release/<ver>/` alongside the standard
  8-doc list at release time.
- Missing entries print a stderr warning but don't block release —
  `release-audit.sh §11k` will still FAIL the release if any path your
  `install.sh` references via `"$SELF_DIR/<path>"` or `"${SELF_DIR}/<path>"`
  isn't in the release dir, so a typo in `.release-flatten` is caught
  before users see it.

```
# .release-flatten — v1.1.2+ manifest format

# Whole-line comments are stripped.
TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md     # trailing comments also OK
docs/policy.md                            # subdirectory paths supported
```

## 6. Pre-release checklist

Run all of these BEFORE you invoke `/gitx-release` for the first time.

```bash
# 1. Layout sanity
test -f VERSION && grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$' VERSION
test -f SKILL.md && head -1 SKILL.md | grep -q '^---$'
test -f skills/*/SKILL.md
diff -q SKILL.md skills/*/SKILL.md            # MUST be identical
diff -q VERSION skills/*/VERSION              # MUST be identical
test -f install.sh -a -x install.sh

# 2. Dual-source byte-identity
diff -rq scripts/ skills/*/scripts/           # MUST be empty (rogue fixtures excepted)

# 3. Test harness
test -f tests/run_all.sh && bash tests/run_all.sh

# 4. install.sh dependency check — run a dry-run release and let
#    audit §11k validate. It catches both `"$SELF_DIR/..."` and
#    `"${SELF_DIR}/..."` forms, plus skips commented-out examples and
#    runtime variables (e.g. `"$SELF_DIR/$f"` in for-loops).
PROJECT_ROOT="$(pwd)" bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh --dry-run

# 5. Sanity scan (no secrets in source)
bash scripts/release-sanitize.sh .            # available after gitx-release install

# 6. CHANGELOG has an entry for the version you're about to release
grep -qE '^## v[0-9]+\.[0-9]+\.[0-9]+ ' CHANGELOG.md

# 7. shellcheck clean
shellcheck -S warning install.sh scripts/*.sh skills/*/scripts/*.sh tests/*.sh
```

## 7. For generic software (Mac/Windows/Linux apps)

GitX-Release is **skill-focused**. It produces a skill bundle (.skill zip),
source tarball, full tarball, install.sh, SBOM, checksums. It does **not**:

- Build platform binaries (.dmg, .exe, .deb, .rpm, .pkg)
- Code-sign for Apple notarization, Windows Authenticode, Microsoft Store
- Push to package registries (Homebrew, apt, npm, PyPI, etc.)
- Generate platform-specific installers

If you're shipping a Mac/Windows/Linux desktop or CLI app **that is not a
Claude/Codex/Gemini skill**, you should NOT use GitX-Release directly.
Use a platform-appropriate tool:

| Platform | Recommended tool |
|---|---|
| macOS app | `xcodebuild archive` + `notarytool` |
| Windows app | MSIX / Squirrel / electron-builder |
| Linux distro | `cargo-deb`, `fpm`, native packaging |
| Cross-platform CLI | `goreleaser`, `cargo-dist` |
| npm package | `npm publish` |
| Python package | `python -m build` + `twine` |
| Container | `docker buildx` + multi-arch |

That said, **the discipline GitX-Release encodes** is portable to any
project:

- Reproducible builds (`SOURCE_DATE_EPOCH`, sorted file lists, normalized mtimes)
- SBOM at every release
- `checksums.txt` covering every artifact, verified by installer before write
- Pre-release sanity scan for secrets / PII / fingerprints
- Post-release deep audit (40+ checks) before tag/push
- "Policy as code" — automate the rules, don't trust humans to remember them
- Never auto-push (TKX §10.10) — keep one human in the loop

You can borrow these patterns into your platform-specific build script.
Read `references/TKX_Git_Release_policy_and_process.md` for the full policy.

## 8. First release walkthrough

After your project meets §3–§6, install GitX-Release once.

> **Trust model**: GitX-Release is itself the release-gate / packaging / audit
> tooling for downstream projects, so the install path matters. Every release
> tarball ships a `checksums.txt`, and `install.sh` verifies every listed file
> against it **before** any filesystem write — any mismatch aborts the install
> with non-zero exit. The two paths below differ in whether that integrity
> check fires.

### 8a. Recommended install — verified release tarball

This is the only path with end-to-end integrity verification. Use it for any
machine that runs `gitx-release` against production code.

```bash
# 1) Obtain the release bundle from the authoritative source you have been
#    given (release page, signed mirror, vendored release artifacts, etc.).
#    Replace <ver> with the exact version, e.g. v1.1.3.
#    The bundle is named: git_release_skill-<ver>-full.tar.gz
curl -fLO 'https://<authoritative-source>/git_release_skill-<ver>-full.tar.gz'

# 2) Verify the tarball sha256 matches the value the source published
#    out-of-band (release notes, signed manifest, etc.). Reject on mismatch.
shasum -a 256 git_release_skill-<ver>-full.tar.gz   # compare to published value

# 3) Extract and install. install.sh will re-verify every bundled file
#    against the embedded checksums.txt before writing to ~/.agents/skills/.
mkdir -p gitx-release && tar -xzf git_release_skill-<ver>-full.tar.gz -C gitx-release
cd gitx-release
./install.sh
# Expect to see: 🔐 checksums.txt verified (...)
```

If `install.sh` reports `❌ Integrity check FAILED`, **do not** rerun with
`--force`; obtain a fresh copy from the authoritative source instead.

### 8b. Developer / contributor install — source clone (unverified)

Use **only** when you are working on GitX-Release itself or have explicit
permission to run unverified release tooling. A `git clone` ships no
`checksums.txt`, so `install.sh` skips the integrity check (graceful
degradation for dev trees — see HANDOFF Gotcha #30 / Decision 2026-05-04).

> ⚠️ This path bypasses checksum verification. Do **not** use it on machines
> that run `gitx-release` against production code, and do **not** install
> from a teammate's clone unless you have personally audited the diff against
> a verified release.

```bash
# Replace <your-host>/<owner>/<repo> with the actual source location
git clone https://<your-host>/<owner>/<repo>.git gitx-release
cd gitx-release
./install.sh
```

Then in your project:

```bash
cd /path/to/your-project
# DRY RUN first — produces no artifacts, validates layout
PROJECT_ROOT="$(pwd)" bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh --dry-run

# If dry-run passes, do a real release (auto-bumps patch version)
PROJECT_ROOT="$(pwd)" bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh
```

Or in Claude Code, just type:

```
/gitx-release
```

After it succeeds:

1. Inspect `Release/<project>-<vX.Y.Z>/RELEASE_NOTES.md`
2. Edit `Release/CHANGELOG.md` to replace the auto-generated placeholder
   (look for `<!-- gitx-auto-entry -->` sentinel) with real release notes
3. Commit `Release/CHANGELOG.md` + `VERSION` bumps
4. Manual `git tag -a vX.Y.Z` + `git push --tags` to your chosen host

## 9. Common pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| install.sh references non-flattened file | `cp: <file>: No such file or directory` at install time | §5 — move file or rename to standard list |
| `SKILL.md` has `metadata:` block | Codex rejects skill with `invalid YAML` | Move version to `VERSION` sidecar; remove `metadata:` |
| Skill folder name has uppercase | macOS HFS+ collisions, Codex auto-discovery fails | Rename to lowercase-hyphenated |
| `scripts/` and `skills/<name>/scripts/` drift | `diff -rq` fails, audit refuses release | Use `sync-dual-source.sh` after every script change |
| `tests/run_all.sh` missing | Pipeline aborts at step 1 | Create at minimum: `bash -c 'echo "no tests yet"; exit 0'` (placeholder); replace with real tests later |
| `VERSION` not in `vX.Y.Z` form | Pipeline aborts at preflight | Match regex `^v[0-9]+\.[0-9]+(\.[0-9]+)?(-(alpha\|beta\|rc)\.?[0-9]*)?$` |
| `description:` mentions a slash command not in `commands/` | Audit FAIL: §11 Codex selector coverage | Either add the `commands/<name>.md` shim OR remove the trigger from description |
| Sensitive data in source | sanity scan blocks release | Add to `.sanitize-ignore` if false positive; otherwise remove the secret |
| HANDOFF.md committed to git | Sanity scan flags it | Add to `.gitignore`; HANDOFF is private working memory per the handoff skill |
| Release dir already exists | "Refusing duplicate release" | Move existing dir aside or bump version |

## 10. What this guideline does NOT cover

- The TKX policy itself (1091 lines): see
  `references/TKX_Git_Release_policy_and_process.md`
- The 40+ audit checks (§1–§11 of the deep audit): see
  `scripts/release-audit.sh` source
- Specific test patterns to write: see `tests/` for examples
- Codex / OpenCode / Gemini metadata format: see `agents/openai.yaml` and
  `agents/codex-commands.txt`
- Reproducible build mechanics (`SOURCE_DATE_EPOCH`, BSD/GNU portability):
  see `scripts/release.sh:build_*` functions
- HANDOFF.md / project memory conventions: see the `handoff` skill

## 11. When you get stuck

1. **Run `--dry-run`** — fastest feedback loop, no destructive side effects.
2. **Read the diagnostic log** — `Release/logs/gitx-release-<timestamp>-<ver>.log`
   captures every step.
3. **Check `HANDOFF.md` Known Gotchas** — 30+ documented production lessons.
4. **`scripts/release-audit.sh <ver>`** — run audit standalone against a
   release dir to see exact failure section.
5. **shellcheck everything** — `shellcheck -S warning scripts/*.sh tests/*.sh`
   catches most static issues before runtime.

---

## Quick reference card (print this)

```
PROJECT MUST HAVE:
  ✓ VERSION (vX.Y.Z)
  ✓ SKILL.md (with frontmatter, no metadata: block)
  ✓ install.sh (executable, only references flattened files)
  ✓ README.md, LICENSE, CHANGELOG.md
  ✓ scripts/*.sh (root)
  ✓ skills/<name>/SKILL.md (byte-identical to root)
  ✓ skills/<name>/scripts/*.sh (byte-identical to root scripts/)
  ✓ tests/run_all.sh (executable, exit 0 on pass)
  ✓ <name>: lowercase-hyphenated, no spaces, no caps

PROJECT MUST NOT HAVE:
  ✗ metadata: block in SKILL.md
  ✗ Drift between scripts/ and skills/<name>/scripts/
  ✗ install.sh referencing non-flattened files
  ✗ Plaintext secrets in source
  ✗ HANDOFF.md committed to git

GITX-RELEASE WILL NOT:
  ✗ Auto-tag
  ✗ Auto-push
  ✗ Contact any upstream
  ✗ Build platform binaries
```

---

*This guide reflects GitX-Release v1.1.1+. For older versions, check the
`Release/CHANGELOG.md` for breaking changes since your version.*
