# mac-release skill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v0.1.0 of `mac-release` — a standalone Bash skill that takes a Mac app project (Swift / Tauri 2.0 / Go) through the full sign + notarize + staple + DMG/ZIP + verify pipeline, producing a local `Release/<product>-vX.Y.Z/` directory ready for the operator to upload to GitHub Releases.

**Architecture:** Standalone repo `Mac_Release_Skill/` (sibling to `Git_Release_Skill/`). Uniform sign/notarize/staple/DMG/verify spine in `release.sh` (15 named phases) plus per-stack adapter scripts (`adapters/swift.sh` / `adapters/tauri.sh` / `adapters/go.sh`) that handle the build phase only. Single source of truth per project: `.mac-release/manifest.toml`. Dual-source contract from day one (`scripts/` ≡ `skills/mac-release/scripts/` byte-identical).

**Tech Stack:** Bash 4.x (`set -u` only — no `set -e`, per gitx-release Gotcha #24), Python 3.11+ (for `tomllib` TOML parsing), `xcrun notarytool` (Apple), `codesign` / `hdiutil` / `lipo` / `ditto` (macOS native), `git archive` (deterministic source tarball).

**Reference spec:** `docs/superpowers/specs/2026-05-06-mac-release-skill-design.md` (in current repo).

**Working location for implementation:** `~/tkbox/Cloud_Coding/Github/Mac_Release_Skill/` (NEW repo, created in P0.0). The plan file itself stays in the current `Git_Release_Skill/` repo as a record.

---

## Phase Map and Checkpoints

| Phase | Deliverable | Tasks | Checkpoint at end |
|---|---|---|---|
| **P0** | Skill skeleton (repo, dual-source, manifest loader, wrapper, run_all.sh) | P0.1 – P0.10 | Repo committed; tests/run_all.sh shows N/0 green; can `bash scripts/mac-release.sh --help` |
| **P1** | Common spine (15 pipeline phases, codesign + notarize + staple libs, deep audit skeleton) | P1.1 – P1.13 | Smoke test against tiny fixture passes pipeline §1–§14; deep audit ≥30 gates |
| **P2** | Swift adapter + MacAudit checkpoint | P2.1 – P2.6 | MacAudit ships v0.1.6 as notarized + stapled DMG; install.sh `🔐 checksums.txt verified`; e2e smoke + deep audit clean |
| **P3** | Tauri adapter + AiPromptX checkpoint | P3.1 – P3.7 | AiPromptX ships as notarized + stapled DMG; capability audit empirically validated; e2e clean |
| **P4** | Go adapter + Please_Continue checkpoint | P4.1 – P4.5 | Please_Continue ships as notarized universal-binary ZIP; lipo + symbol-strip + host-leak gates clean |
| **P5** | Hardening + first self-bake of mac-release v0.1.0 via gitx-release | P5.1 – P5.5 | mac-release v0.1.0 self-baked; installed locally; cross-CLI roots all v0.1.0; HANDOFF.md captures session |

**Stop-and-review at each checkpoint.** The user is in the loop after every phase boundary; do not proceed to the next phase without explicit confirmation.

---

## File Structure (target)

```
~/tkbox/Cloud_Coding/Github/Mac_Release_Skill/
├── VERSION                                  → P0.3 (sidecar; starts at v0.0.1-dev)
├── CHANGELOG.md                             → P0.4
├── README.md                                → P0.4
├── INSTALL.md                               → P5.2
├── LICENSE                                  → P0.4 (MIT, mirror gitx-release)
├── SECURITY.md                              → P0.4
├── CONTRIBUTING.md                          → P5.2
├── .gitignore                               → P0.2
├── .sanitize-ignore                         → P0.2
├── install.sh                               → P0.5 (vendored from gitx-release v1.1.6)
├── Release/                                 (gitignored; generated)
├── scripts/
│   ├── mac-release.sh                       → P0.7 (wrapper)
│   ├── release.sh                           → P1 (full pipeline; 15 named phases)
│   ├── release-audit.sh                     → P1.13 (deep audit skeleton)
│   ├── release-sanitize.sh                  → P0.6 (vendored)
│   ├── scan-credentials.sh                  → P0.6 (vendored)
│   ├── emit-sbom.sh                         → P0.6 (vendored, with mac-product type)
│   ├── adapters/
│   │   ├── swift.sh                         → P2.1
│   │   ├── tauri.sh                         → P3.1
│   │   └── go.sh                            → P4.1
│   ├── lib/
│   │   ├── manifest.sh                      → P0.8 (TOML loader)
│   │   ├── capability-audit.sh              → P3.2 (Tauri-only)
│   │   ├── codesign-pipeline.sh             → P1.5 (toolchain-agnostic)
│   │   └── notarize-pipeline.sh             → P1.6 (toolchain-agnostic)
│   └── sync-from-gitx-release.sh            → P0.6 (one-shot vendoring helper)
├── skills/
│   └── mac-release/
│       ├── SKILL.md                         → P0.9
│       ├── VERSION                          → P0.3 (skill-side sidecar)
│       ├── scripts/                         → P0.10 (byte-identical to root scripts/; dual-source)
│       ├── references/
│       │   └── TKX_Mac_Release_policy.md    → P5.2
│       ├── assets/
│       │   ├── README.md                    → P0.9
│       │   └── manifest.template.toml       → P0.9
│       ├── agents/
│       │   ├── README.md                    → P0.9
│       │   └── codex-commands.txt           → P0.9
│       └── commands/
│           └── mac-release.md               → P0.9
├── tests/
│   ├── run_all.sh                           → P0.10
│   ├── test_manifest_parse.sh               → P0.8
│   ├── test_skeleton_layout.sh              → P0.10 (catches missing files in skeleton)
│   ├── test_dual_source.sh                  → P0.10 (scripts/ ≡ skills/mac-release/scripts/)
│   ├── test_codesign_pipeline.sh            → P1.5
│   ├── test_notarize_pipeline.sh            → P1.6 (mocked; e2e gated by MAC_RELEASE_E2E=1)
│   ├── test_source_tarball_determinism.sh   → P1.7
│   ├── test_audit_gates.sh                  → P1.13
│   ├── test_release_pipeline_smoke.sh       → P1.13 (end-to-end on tiny fixture, no notarization)
│   ├── test_swift_adapter.sh                → P2.2
│   ├── test_capability_audit.sh             → P3.2
│   ├── test_tauri_adapter.sh                → P3.4
│   ├── test_go_adapter.sh                   → P4.2
│   └── fixtures/
│       ├── tiny-swift-app/                  → P1.13 (synthetic Swift project)
│       ├── tiny-tauri-app/                  → P3.4
│       ├── tiny-go-cli/                     → P4.2
│       └── manifest-cases/                  → P0.8 (TOML parse fixtures)
└── HANDOFF.md                               → P5.4
```

---

## Phase 0 — Skill Skeleton

Goal: a new repo with the dual-source contract, vendored generic primitives, manifest loader, wrapper skeleton, and a green `tests/run_all.sh`. No pipeline phases yet.

### Task P0.1: Create new sibling repo

**Files:**
- Create directory: `~/tkbox/Cloud_Coding/Github/Mac_Release_Skill/`

- [ ] **Step 1: Verify parent dir + sibling exists**

```bash
ls -d ~/tkbox/Cloud_Coding/Github/Git_Release_Skill && echo "✅ sibling found"
test -d ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill && echo "❌ already exists; investigate" || echo "✅ ready to create"
```

- [ ] **Step 2: Create directory + git init**

```bash
mkdir ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
git init -b main
git config user.name "TKX"
# Use the user's existing global git email; do NOT touch git config beyond -b main
```

- [ ] **Step 3: Empty placeholder commit (so we can commit before files exist)**

Skip — first real commit will land in P0.4. Don't create empty commits.

### Task P0.2: `.gitignore` and `.sanitize-ignore`

**Files:**
- Create: `~/tkbox/Cloud_Coding/Github/Mac_Release_Skill/.gitignore`
- Create: `~/tkbox/Cloud_Coding/Github/Mac_Release_Skill/.sanitize-ignore`

- [ ] **Step 1: Write `.gitignore`** (mirror gitx-release pattern, adapted for Mac)

```
# ── Build artifacts ──────────────────────────────────────────────────────
# Per-version release directories (e.g. Release/mac-release-v0.0.1/)
Release/*/
# Top-level release artifacts
Release/*.skill
Release/*-source.tar.gz
Release/checksums.txt
Release/latest
Release/sbom.cyclonedx.json
Release/TOKEN_USAGE.md
Release/README.md
Release/INSTALL.md
Release/LICENSE
Release/CONTRIBUTING.md
Release/CODE_OF_CONDUCT.md
Release/SECURITY.md
Release/SKILL.md
Release/RELEASE_NOTES.md
Release/install.sh
Release/scripts/
Release/references/
Release/assets/
Release/.sanitize-ignore
# NOTE: Release/CHANGELOG.md is NOT excluded — it's the cumulative changelog
*.skill
*.tar.gz
checksums.txt

# ── Dev artifacts ──────────────────────────────────────────────────────
.DS_Store
*.bak
*.tmp
.spm-build/
.swiftpm/
target/

# ── Working memory ─────────────────────────────────────────────────────
HANDOFF.md
HANDOFF.archive.md
HANDOFF.md.bak
memory/

# ── Secrets / personal ─────────────────────────────────────────────────
.env
.env.*
!.env.example
*.p12
*.pem
*.cer
*.certSigningRequest
```

- [ ] **Step 2: Write `.sanitize-ignore`** (mirror gitx-release pattern)

```
# .sanitize-ignore — explicit whitelist for release-sanitize.sh
#
# Format: one path (relative to scanned root) per line; '#' starts comment; blank OK.
# Paths are matched via case glob against the relative file path.
#
# Rule of thumb: only add entries you can defend in a security review.
# Prefer fixing the source over adding a line here.

# ── Intentional test fixtures ────────────────────────────────────────────
# Sister-tests of the scanner; planted bait strings.
tests/test_capability_audit.sh
tests/test_credential_patterns.sh
tests/test_sanitize_output_format.sh

# ── Business contact (by design) ──────────────────────────────────────────
SECURITY.md

# ── Internal dev docs (gitignored, never shipped) ────────────────────────
HANDOFF.md
HANDOFF.archive.md

# ── Generated release artifacts ──────────────────────────────────────────
Release/*
```

- [ ] **Step 3: Verify both files**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
test -f .gitignore && test -f .sanitize-ignore && echo "✅ both present"
```

No commit yet — wait until P0.4 when README and LICENSE exist for a complete first commit.

### Task P0.3: VERSION sidecars (root + skill bundle)

**Files:**
- Create: `~/tkbox/Cloud_Coding/Github/Mac_Release_Skill/VERSION`
- Create: `~/tkbox/Cloud_Coding/Github/Mac_Release_Skill/skills/mac-release/VERSION`

- [ ] **Step 1: Write root VERSION**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
mkdir -p skills/mac-release
echo "v0.0.1-dev" > VERSION
echo "v0.0.1-dev" > skills/mac-release/VERSION
```

- [ ] **Step 2: Verify both byte-identical**

```bash
diff VERSION skills/mac-release/VERSION && echo "✅ identical"
```

### Task P0.4: README, LICENSE, SECURITY, CHANGELOG

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `SECURITY.md`
- Create: `CHANGELOG.md`
- Create: `Release/CHANGELOG.md` (cumulative)

- [ ] **Step 1: Write `LICENSE`** (MIT, mirror gitx-release exact text — copy verbatim)

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
cp ~/tkbox/Cloud_Coding/Github/Git_Release_Skill/LICENSE ./LICENSE
# verify
head -3 LICENSE
```

Expected: `MIT License\n\nCopyright (c) 2026 TKXLAB.AI`

- [ ] **Step 2: Write `README.md`** (minimal — full README polish in P5.2)

```markdown
# Mac Release Skill

Toolchain-agnostic Mac app release pipeline for Swift / Tauri 2.0 / Go projects.
Sign + notarize + staple + DMG/ZIP + verify + provenance.

> **Status: v0.0.1-dev** — under construction. See `docs/` for design spec.
> Sibling skill to [gitx-release](../Git_Release_Skill/).

## Quick start (placeholder until v0.1.0 ships)

1. Create `.mac-release/manifest.toml` in your Mac project (template at `assets/manifest.template.toml`).
2. Run `mac-release setup` once to store notarytool credentials.
3. Run `/mac-release` (or `bash scripts/mac-release.sh`) to release.

## License

MIT — see `LICENSE`.
```

- [ ] **Step 3: Write `SECURITY.md`**

```markdown
# Security Policy

Report security issues to: security@tkxlab.ai (placeholder — replace before publishing).

This skill handles macOS code signing identities, notarytool credentials, and
release artifacts. Treat the operator's keychain as authoritative; the skill
never reads private key bytes directly.

## Reporting a Vulnerability

Email the address above with subject `[mac-release] <short description>`.
```

- [ ] **Step 4: Write `CHANGELOG.md`** (root + Release/CHANGELOG.md mirror)

```markdown
# Mac Release Skill — Changelog

## v0.0.1-dev — 2026-05-06

Initial development skeleton. Not yet usable for releases.
```

- [ ] **Step 5: Mirror to `Release/CHANGELOG.md`**

```bash
mkdir -p Release
cp CHANGELOG.md Release/CHANGELOG.md
```

- [ ] **Step 6: First commit (skeleton baseline)**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
git add .gitignore .sanitize-ignore VERSION skills/mac-release/VERSION README.md LICENSE SECURITY.md CHANGELOG.md Release/CHANGELOG.md
git commit -m "chore: initial skeleton (v0.0.1-dev)

Sibling skill to gitx-release. v0.1.0 will cover Swift / Tauri 2.0 / Go
adapters. Spec: ../Git_Release_Skill/docs/superpowers/specs/2026-05-06-mac-release-skill-design.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task P0.5: Vendored `install.sh` from gitx-release v1.1.6

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Copy install.sh from gitx-release**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
cp ~/tkbox/Cloud_Coding/Github/Git_Release_Skill/install.sh ./install.sh
chmod +x install.sh
```

- [ ] **Step 2: Adapt skill name references** (sed-based; dry-run first)

```bash
grep -n 'gitx-release\|git-release-pipeline' install.sh | head -20
# Expected: many hits — sed replace gitx-release → mac-release, but be careful with deprecated alias logic
```

- [ ] **Step 3: Apply rename** (manual edit — sed is risky for this; use Edit tool to rename:
  - All instances of `gitx-release` → `mac-release` (skill name)
  - All instances of `git-release-pipeline` → DELETE (no deprecated alias for new skill)
  - Strip the deprecated-alias cleanup block (relevant only to gitx-release's v1.1.0 rebrand)

- [ ] **Step 4: Verify checksums-verify logic intact**

```bash
grep -A 5 'checksums.txt verified' install.sh | head -10
# Expected: still contains shasum -a 256 -c verification
```

- [ ] **Step 5: Test install.sh with `--help` and `--dry-run`**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
bash install.sh --help && echo "✅ help works"
bash install.sh --dry-run && echo "✅ dry-run works"
```

- [ ] **Step 6: Commit**

```bash
git add install.sh
git commit -m "feat: vendored install.sh from gitx-release v1.1.6 (renamed to mac-release)"
```

### Task P0.6: Vendor generic primitives + sync helper

**Files:**
- Create: `scripts/release-sanitize.sh`
- Create: `scripts/scan-credentials.sh`
- Create: `scripts/emit-sbom.sh`
- Create: `scripts/sync-from-gitx-release.sh`

- [ ] **Step 1: Write `scripts/sync-from-gitx-release.sh`**

```bash
mkdir -p scripts
cat > scripts/sync-from-gitx-release.sh <<'EOF'
#!/bin/bash
# sync-from-gitx-release.sh — refresh vendored generic primitives from sibling repo
# usage: scripts/sync-from-gitx-release.sh
# exit:  0 success, 1 sibling repo not found, 2 dual-source diverges
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SELF_DIR")"
GITX_ROOT="${GITX_RELEASE_REPO:-$HOME/tkbox/Cloud_Coding/Github/Git_Release_Skill}"

if [ ! -d "$GITX_ROOT" ]; then
    echo "❌ gitx-release repo not found at $GITX_ROOT" >&2
    echo "   Set GITX_RELEASE_REPO=/path/to/Git_Release_Skill if non-default" >&2
    exit 1
fi

GITX_VERSION="$(cat "$GITX_ROOT/VERSION" 2>/dev/null || echo unknown)"
echo "🔄 Syncing vendored primitives from gitx-release $GITX_VERSION → mac-release"

for f in scan-credentials.sh release-sanitize.sh emit-sbom.sh; do
    cp "$GITX_ROOT/scripts/$f" "$PROJECT_ROOT/scripts/$f"
    cp "$GITX_ROOT/scripts/$f" "$PROJECT_ROOT/skills/mac-release/scripts/$f" 2>/dev/null || true
    echo "  ✅ $f"
done

# Tag the sync provenance — operator can verify
cat > "$PROJECT_ROOT/scripts/.sync-provenance" <<INNER
synced_from: gitx-release $GITX_VERSION
synced_at: $(date -u "+%Y-%m-%dT%H:%M:%SZ")
synced_files: scan-credentials.sh release-sanitize.sh emit-sbom.sh
INNER

echo "✅ vendoring sync complete — commit with: git add scripts/ skills/mac-release/scripts/"
EOF
chmod +x scripts/sync-from-gitx-release.sh
```

- [ ] **Step 2: Run the sync helper**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
mkdir -p skills/mac-release/scripts
bash scripts/sync-from-gitx-release.sh
```

- [ ] **Step 3: Verify three vendored files present**

```bash
ls -la scripts/{scan-credentials,release-sanitize,emit-sbom}.sh
cat scripts/.sync-provenance
```

- [ ] **Step 4: Commit**

```bash
git add scripts/
git commit -m "feat: vendor generic primitives from gitx-release v1.1.6

scan-credentials.sh / release-sanitize.sh / emit-sbom.sh copied via
scripts/sync-from-gitx-release.sh. Re-run that helper to refresh from
gitx-release on each sync."
```

### Task P0.7: `mac-release.sh` wrapper skeleton

**Files:**
- Create: `scripts/mac-release.sh`

- [ ] **Step 1: Write the failing test first** — `tests/test_skeleton_layout.sh` (created in P0.10) will fail until wrapper exists. For now, create stub:

```bash
cat > scripts/mac-release.sh <<'EOF'
#!/bin/bash
# mac-release.sh — one-command Mac app release wrapper
# usage: mac-release.sh [--dry-run] [--version vX.Y.Z] [setup|verify <ver>|scan <dir>]
# exit:  0 release completed, 1 release failed, 2 usage / unsupported version
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
SCRIPT_VERSION="$(cat "$SELF_DIR/../VERSION" 2>/dev/null || echo unknown)"

usage() {
    cat <<USAGE
mac-release $SCRIPT_VERSION — Mac app release pipeline

Usage:
  mac-release.sh                     Run full pipeline (auto-bump patch)
  mac-release.sh --version vX.Y.Z    Run with explicit version
  mac-release.sh --dry-run           Plan without artifacts
  mac-release.sh setup               First-time notarytool credential setup
  mac-release.sh verify <version>    Audit existing Release/<product>-<version>/
  mac-release.sh scan <dir>          Sanity-scan a directory (no release)
  mac-release.sh --help              Show this help

Reads .mac-release/manifest.toml from PROJECT_ROOT.
USAGE
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    setup)     echo "TODO: P5 will implement setup subcommand"; exit 1 ;;
    verify)    echo "TODO: P1.13 will implement verify subcommand"; exit 1 ;;
    scan)      echo "TODO: P0.7 stub — full implementation in P1+"; exit 1 ;;
    "") echo "TODO: P1 will implement full pipeline. Current: skeleton only."; exit 1 ;;
    *)         echo "❌ unknown command: $1" >&2; usage >&2; exit 2 ;;
esac
EOF
chmod +x scripts/mac-release.sh
```

- [ ] **Step 2: Verify --help works**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
bash scripts/mac-release.sh --help
```

Expected: usage text with `mac-release v0.0.1-dev`.

- [ ] **Step 3: Verify exit codes**

```bash
bash scripts/mac-release.sh --help; echo "exit=$?"  # exit=0
bash scripts/mac-release.sh setup; echo "exit=$?"   # exit=1 (TODO stub)
bash scripts/mac-release.sh bogus 2>&1; echo "exit=$?"  # exit=2 (unknown)
```

- [ ] **Step 4: Commit**

```bash
git add scripts/mac-release.sh
git commit -m "feat: mac-release.sh wrapper skeleton (subcommands stubbed for P1+)"
```

### Task P0.8: TOML manifest loader (TDD)

**Files:**
- Create: `scripts/lib/manifest.sh`
- Create: `tests/test_manifest_parse.sh`
- Create: `tests/fixtures/manifest-cases/valid-swift.toml`
- Create: `tests/fixtures/manifest-cases/valid-tauri.toml`
- Create: `tests/fixtures/manifest-cases/valid-go.toml`
- Create: `tests/fixtures/manifest-cases/invalid-stack.toml`
- Create: `tests/fixtures/manifest-cases/invalid-no-product.toml`

- [ ] **Step 1: Write fixture manifests**

```bash
mkdir -p tests/fixtures/manifest-cases scripts/lib
cat > tests/fixtures/manifest-cases/valid-swift.toml <<'EOF'
[product]
name        = "MacAudit"
identifier  = "com.macaudit.gui"
stack       = "swift"

[build]
hook        = "scripts/build.sh"
output      = "build/MacAudit.app"
bundle_type = "app"

[sign]
identity         = "Developer ID Application: token hu (NN8425LUVZ)"
hardened_runtime = true
team_id          = "NN8425LUVZ"

[notarize]
profile = "MAC_RELEASE_NOTARY"

[distribute]
formats = ["dmg"]

[swift]
spm_resource_bundle = true
EOF

cat > tests/fixtures/manifest-cases/valid-tauri.toml <<'EOF'
[product]
name        = "AiPromptX"
identifier  = "ai.tkxlab.aipromptx"
stack       = "tauri"

[build]
hook        = "scripts/build.sh"
output      = "src-tauri/target/universal-apple-darwin/release/bundle/macos/AiPromptX.app"
bundle_type = "app"

[sign]
identity         = "Developer ID Application: token hu (NN8425LUVZ)"
hardened_runtime = true
team_id          = "NN8425LUVZ"

[notarize]
profile = "MAC_RELEASE_NOTARY"

[distribute]
formats = ["dmg"]

[tauri]
config_path  = "src-tauri/tauri.conf.json"
capabilities = "src-tauri/capabilities"
sidecars     = []
EOF

cat > tests/fixtures/manifest-cases/valid-go.toml <<'EOF'
[product]
name        = "plsctn"
identifier  = "io.tkxlab.plsctn"
stack       = "go"

[build]
hook        = "scripts/build.sh"
output      = "bin/plsctn"
bundle_type = "binary"

[sign]
identity         = "Developer ID Application: token hu (NN8425LUVZ)"
hardened_runtime = true
team_id          = "NN8425LUVZ"

[notarize]
profile = "MAC_RELEASE_NOTARY"

[distribute]
formats = ["zip"]

[go]
strip_symbols = true
universal     = true
wrap_as_app   = false
EOF

cat > tests/fixtures/manifest-cases/invalid-stack.toml <<'EOF'
[product]
name = "Bogus"
identifier = "x.y"
stack = "perl"

[build]
hook = "scripts/build.sh"
output = "bin/x"
bundle_type = "binary"
EOF

cat > tests/fixtures/manifest-cases/invalid-no-product.toml <<'EOF'
[build]
hook = "x"
output = "x"
bundle_type = "binary"
EOF
```

- [ ] **Step 2: Write the failing test** `tests/test_manifest_parse.sh`

```bash
cat > tests/test_manifest_parse.sh <<'EOF'
#!/bin/bash
# test_manifest_parse.sh — verifies scripts/lib/manifest.sh loads + validates manifests
set -u
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$PROJECT_ROOT/scripts/lib/manifest.sh"
FIXDIR="$PROJECT_ROOT/tests/fixtures/manifest-cases"

PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    else
        echo "  ❌ $desc — expected '$expected', got '$actual'"
        FAIL=$((FAIL+1))
    fi
}

assert_exit() {
    local desc="$1" expected_exit="$2"; shift 2
    local actual_exit
    "$@" >/dev/null 2>&1
    actual_exit=$?
    if [ "$actual_exit" = "$expected_exit" ]; then
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    else
        echo "  ❌ $desc — expected exit $expected_exit, got $actual_exit"
        FAIL=$((FAIL+1))
    fi
}

# Test 1: valid swift manifest parses
echo "valid-swift.toml:"
eval "$(bash "$LIB" "$FIXDIR/valid-swift.toml")"
assert_eq "  PRODUCT_NAME=MacAudit" "MacAudit" "${PRODUCT_NAME:-}"
assert_eq "  PRODUCT_IDENTIFIER=com.macaudit.gui" "com.macaudit.gui" "${PRODUCT_IDENTIFIER:-}"
assert_eq "  STACK=swift" "swift" "${STACK:-}"
assert_eq "  BUNDLE_TYPE=app" "app" "${BUNDLE_TYPE:-}"
assert_eq "  TEAM_ID=NN8425LUVZ" "NN8425LUVZ" "${TEAM_ID:-}"
assert_eq "  NOTARY_PROFILE=MAC_RELEASE_NOTARY" "MAC_RELEASE_NOTARY" "${NOTARY_PROFILE:-}"

unset PRODUCT_NAME PRODUCT_IDENTIFIER STACK BUNDLE_TYPE TEAM_ID NOTARY_PROFILE

# Test 2: valid tauri manifest parses
echo "valid-tauri.toml:"
eval "$(bash "$LIB" "$FIXDIR/valid-tauri.toml")"
assert_eq "  STACK=tauri" "tauri" "${STACK:-}"
assert_eq "  PRODUCT_NAME=AiPromptX" "AiPromptX" "${PRODUCT_NAME:-}"

unset PRODUCT_NAME STACK

# Test 3: valid go manifest parses
echo "valid-go.toml:"
eval "$(bash "$LIB" "$FIXDIR/valid-go.toml")"
assert_eq "  STACK=go" "go" "${STACK:-}"
assert_eq "  BUNDLE_TYPE=binary" "binary" "${BUNDLE_TYPE:-}"

unset STACK BUNDLE_TYPE

# Test 4: invalid stack rejected
echo "invalid-stack.toml:"
assert_exit "  exits 2 on stack=perl" 2 bash "$LIB" "$FIXDIR/invalid-stack.toml"

# Test 5: missing [product] block rejected
echo "invalid-no-product.toml:"
assert_exit "  exits 2 on missing [product]" 2 bash "$LIB" "$FIXDIR/invalid-no-product.toml"

# Test 6: nonexistent file
assert_exit "nonexistent file → exit 2" 2 bash "$LIB" "/nonexistent/path.toml"

# Test 7: --help works
assert_exit "--help → exit 0" 0 bash "$LIB" --help

echo ""
echo "─── $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
EOF
chmod +x tests/test_manifest_parse.sh
```

- [ ] **Step 3: Run test, verify it fails**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
bash tests/test_manifest_parse.sh
echo "expected: FAIL because scripts/lib/manifest.sh doesn't exist yet"
```

- [ ] **Step 4: Implement `scripts/lib/manifest.sh`** (Python tomllib)

```bash
cat > scripts/lib/manifest.sh <<'EOF'
#!/bin/bash
# manifest.sh — load and validate .mac-release/manifest.toml; print shell-eval'able env exports
# usage: bash scripts/lib/manifest.sh <path-to-manifest.toml>
#        eval "$(bash scripts/lib/manifest.sh /path/to/manifest.toml)"
# exit:  0 valid (prints exports to stdout), 2 invalid (prints diagnostic to stderr)
set -u

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<USAGE
manifest.sh — TOML manifest loader for mac-release

Usage:
  manifest.sh <path-to-manifest.toml>          Print shell-eval'able env exports
  manifest.sh --help                            Show this help

Required Python: 3.11+ (uses stdlib tomllib).
Required manifest sections: [product] [build] [sign] [notarize] [distribute]
Plus stack-specific [swift]/[tauri]/[go] matching [product].stack.

Exports the following env vars on success:
  PRODUCT_NAME, PRODUCT_IDENTIFIER, STACK,
  BUILD_HOOK, BUILD_OUTPUT, BUNDLE_TYPE,
  SIGN_IDENTITY, HARDENED_RUNTIME, ENTITLEMENTS, TEAM_ID,
  NOTARY_PROFILE,
  DISTRIBUTE_FORMATS,
  STACK_<KEY>=<value>  (stack-specific, e.g. SWIFT_SPM_RESOURCE_BUNDLE)
USAGE
    exit 0
fi

MANIFEST="${1:-}"
if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
    echo "❌ manifest not found: ${MANIFEST:-<missing>}" >&2
    exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ python3 required for TOML parsing (need 3.11+)" >&2
    exit 2
fi

python3 - "$MANIFEST" <<'PYEOF'
import sys, os
try:
    import tomllib
except ImportError:
    print("❌ Python 3.11+ required (tomllib not available)", file=sys.stderr)
    sys.exit(2)

manifest_path = sys.argv[1]
try:
    with open(manifest_path, 'rb') as f:
        data = tomllib.load(f)
except Exception as e:
    print(f"❌ TOML parse error: {e}", file=sys.stderr)
    sys.exit(2)

# Validate required sections
required = ['product', 'build', 'sign', 'notarize', 'distribute']
missing = [s for s in required if s not in data]
if missing:
    print(f"❌ missing required sections: {missing}", file=sys.stderr)
    sys.exit(2)

# Validate stack value
stack = data['product'].get('stack', '')
if stack not in ('swift', 'tauri', 'go'):
    print(f"❌ [product].stack must be swift|tauri|go, got '{stack}'", file=sys.stderr)
    sys.exit(2)

# Validate stack-specific block exists
if stack not in data:
    print(f"❌ [{stack}] block required for stack='{stack}'", file=sys.stderr)
    sys.exit(2)

def shesc(s):
    """Shell-escape a value."""
    return "'" + str(s).replace("'", "'\\''") + "'"

# Emit exports
print(f"export PRODUCT_NAME={shesc(data['product']['name'])}")
print(f"export PRODUCT_IDENTIFIER={shesc(data['product']['identifier'])}")
print(f"export STACK={shesc(stack)}")
print(f"export BUILD_HOOK={shesc(data['build']['hook'])}")
print(f"export BUILD_OUTPUT={shesc(data['build']['output'])}")
print(f"export BUNDLE_TYPE={shesc(data['build']['bundle_type'])}")
print(f"export SIGN_IDENTITY={shesc(data['sign']['identity'])}")
print(f"export HARDENED_RUNTIME={shesc(data['sign'].get('hardened_runtime', True))}")
print(f"export ENTITLEMENTS={shesc(data['sign'].get('entitlements', ''))}")
print(f"export TEAM_ID={shesc(data['sign']['team_id'])}")
print(f"export NOTARY_PROFILE={shesc(data['notarize']['profile'])}")
formats = data['distribute']['formats']
print(f"export DISTRIBUTE_FORMATS={shesc(','.join(formats))}")

# Stack-specific exports (uppercase, prefixed)
prefix = stack.upper()
for k, v in data[stack].items():
    if isinstance(v, list):
        v = ','.join(str(x) for x in v)
    elif isinstance(v, bool):
        v = 'true' if v else 'false'
    print(f"export {prefix}_{k.upper()}={shesc(v)}")
PYEOF
EOF
chmod +x scripts/lib/manifest.sh
```

- [ ] **Step 5: Run test again, verify it passes**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
bash tests/test_manifest_parse.sh
```

Expected: all green, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/manifest.sh tests/test_manifest_parse.sh tests/fixtures/manifest-cases/
git commit -m "feat: TOML manifest loader + 7 BDD assertions

scripts/lib/manifest.sh validates and emits eval-able env exports
for the 5 required sections (product/build/sign/notarize/distribute)
plus stack-specific block. Uses Python 3.11+ tomllib (no Bash TOML
parser dependency)."
```

### Task P0.9: Skill bundle skeleton

**Files:**
- Create: `skills/mac-release/SKILL.md`
- Create: `skills/mac-release/assets/manifest.template.toml`
- Create: `skills/mac-release/assets/README.md`
- Create: `skills/mac-release/agents/codex-commands.txt`
- Create: `skills/mac-release/agents/README.md`
- Create: `skills/mac-release/commands/mac-release.md`

- [ ] **Step 1: SKILL.md** (skill definition; mirrors gitx-release SKILL.md frontmatter shape — but no `metadata:` block per Gotcha #16)

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
mkdir -p skills/mac-release/{assets,agents,commands}
cat > skills/mac-release/SKILL.md <<'EOF'
---
name: mac-release
description: Mac app release pipeline — sign + notarize + staple + DMG/ZIP + verify gates + provenance for Swift / Tauri 2.0 / Go projects without auto-tag or push.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
license: MIT
compatibility:
  claude-code: '>=0.1'
  codex: '>=0.128'
---

# mac-release — Mac App Release Skill

Toolchain-agnostic Mac app release pipeline. Covers Swift / Tauri 2.0 / Go.

## When to trigger

- User says `/mac-release`, `mac-release`, `Mac 发版`, "release this Mac app"
- User asks to "sign and notarize" a Mac app
- User has `.mac-release/manifest.toml` in project and asks to release

## Three operating commands

| Command | Entry | Behavior |
|---------|-------|----------|
| `/mac-release` | `scripts/mac-release.sh` | Auto-bump patch, run full pipeline, emit operator-uploadable Release/<product>-<ver>/ |
| `mac-release verify <ver>` | `scripts/release-audit.sh` | Re-run deep audit on existing Release/<product>-<ver>/ |
| `mac-release scan <dir>` | `scripts/release-sanitize.sh` | Sanity-scan a directory for personal info / credentials / IPs |
| `mac-release setup` | `scripts/mac-release.sh setup` | First-time notarytool keychain profile setup |

## Hard constraints

1. **No auto-tag, no auto-push**, no auto-`gh release create`. Per TKX policy §10.10 — operator does the publish step.
2. **Hard-fail on real public IPs** in any artifact. RFC 5737 / industry-standard DNS placeholders allowlisted.
3. **Hard-fail on Tauri capability over-grants** (shell:allow-execute without scope, fs:write to **, webview:allow-evaluate). Operator override via .mac-release/capability-allowlist.toml.
4. **Gate-then-ship**: Release/latest never points to unaudited artifacts (post-audit symlink flip).
5. **Wrapper rollback**: VERSION/CHANGELOG bumps reverted on pipeline failure.

## License

MIT — Copyright (c) 2026 TKXLAB.AI
EOF
```

- [ ] **Step 2: manifest.template.toml** (starter for new projects)

```bash
cat > skills/mac-release/assets/manifest.template.toml <<'EOF'
# .mac-release/manifest.toml — template for new Mac projects
#
# Copy this file to <your-project>/.mac-release/manifest.toml and fill in.
# Delete the [swift] / [tauri] / [go] blocks that don't match your stack.

[product]
name        = "MyApp"                     # display name
identifier  = "com.example.myapp"         # Bundle ID (CFBundleIdentifier)
stack       = "swift"                     # swift | tauri | go

[build]
hook        = "scripts/build.sh"          # script that produces $BUILD_OUTPUT
output      = "build/MyApp.app"           # path the hook produces, relative to PROJECT_ROOT
bundle_type = "app"                       # app (.app bundle) | binary (naked Mach-O) | framework

[sign]
identity         = "Developer ID Application: YOUR NAME (TEAMID0123)"
hardened_runtime = true
entitlements     = ""                     # optional: ".mac-release/entitlements.plist"
team_id          = "TEAMID0123"

[notarize]
profile = "MAC_RELEASE_NOTARY"            # name of stored notarytool keychain profile

[distribute]
formats = ["dmg"]                         # for bundle_type=app: dmg | zip | both
                                           # for bundle_type=binary: ["zip"] only

# ─── Stack-specific blocks — keep only the matching one ──────────────────────

[swift]
spm_resource_bundle = true                 # Bundle.module gotcha — places .bundle in Contents/Resources/

# [tauri]
# config_path     = "src-tauri/tauri.conf.json"
# capabilities    = "src-tauri/capabilities"
# sidecars        = []                     # paths to sidecar binaries to sign individually

# [go]
# strip_symbols = true                     # -ldflags="-s -w"
# universal     = true                     # build arm64 + amd64, lipo merge
# wrap_as_app   = false                    # if true, wrap naked binary in .app bundle
EOF
```

- [ ] **Step 3: assets/README.md**

```bash
cat > skills/mac-release/assets/README.md <<'EOF'
# mac-release assets

`manifest.template.toml` — copy to `<your-project>/.mac-release/manifest.toml` and fill in.

This directory exists so the skill bundle has at least one .md file (release-audit.sh §6 gate).
EOF
```

- [ ] **Step 4: agents/codex-commands.txt + agents/README.md**

```bash
cat > skills/mac-release/agents/codex-commands.txt <<'EOF'
$mac-release
EOF
cat > skills/mac-release/agents/README.md <<'EOF'
# Codex commands

`codex-commands.txt` — selector manifest for Codex CLI's `$<name>` slash commands.
Format: one selector per line, no comments.
EOF
```

- [ ] **Step 5: commands/mac-release.md** (Claude Code slash command)

```bash
cat > skills/mac-release/commands/mac-release.md <<'EOF'
---
description: Mac app release — sign + notarize + staple + DMG/ZIP + verify gates + provenance for Swift / Tauri 2.0 / Go projects.
---

Run the mac-release pipeline on the current project.

Reads `.mac-release/manifest.toml`. Auto-bumps patch version unless explicit
`--version vX.Y.Z` is provided. Produces a `Release/<product>-vX.Y.Z/` directory
with notarized + stapled DMG (or ZIP for Go CLIs) + source tarball + checksums
+ SBOM + RELEASE_NOTES.

Per TKX §10.10, the skill never runs `gh release create` — it prints a
copy-pasteable `gh release create vX.Y.Z --draft <assets>` command for the
operator at end of stdout.
EOF
```

- [ ] **Step 6: Commit**

```bash
git add skills/mac-release/
git commit -m "feat: skill bundle skeleton (SKILL.md + assets + agents + commands)"
```

### Task P0.10: Dual-source contract + run_all.sh

**Files:**
- Create: `tests/test_skeleton_layout.sh`
- Create: `tests/test_dual_source.sh`
- Create: `tests/run_all.sh`

- [ ] **Step 1: Sync root scripts/ → skills/mac-release/scripts/**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
mkdir -p skills/mac-release/scripts/lib
for f in mac-release.sh release-sanitize.sh scan-credentials.sh emit-sbom.sh sync-from-gitx-release.sh; do
    cp "scripts/$f" "skills/mac-release/scripts/$f"
done
cp scripts/lib/manifest.sh skills/mac-release/scripts/lib/manifest.sh
diff -rq scripts/ skills/mac-release/scripts/ | head
echo "(should be empty — except the .sync-provenance file)"
```

- [ ] **Step 2: Update sync-from-gitx-release.sh to also sync the bundle copy** — already done in P0.6 ("`cp ... skills/mac-release/scripts/$f 2>/dev/null || true`"). Verify by re-running:

```bash
bash scripts/sync-from-gitx-release.sh
diff -rq scripts/ skills/mac-release/scripts/ | grep -v sync-provenance
```

- [ ] **Step 3: Write `tests/test_skeleton_layout.sh`**

```bash
cat > tests/test_skeleton_layout.sh <<'EOF'
#!/bin/bash
# Verifies the v0.0.1-dev skeleton has all required files in expected locations.
set -u
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

assert_file() {
    if [ -f "$PROJECT_ROOT/$1" ]; then
        echo "  ✅ $1 exists"
        PASS=$((PASS+1))
    else
        echo "  ❌ $1 MISSING"
        FAIL=$((FAIL+1))
    fi
}
assert_dir() {
    if [ -d "$PROJECT_ROOT/$1" ]; then
        echo "  ✅ $1/ exists"
        PASS=$((PASS+1))
    else
        echo "  ❌ $1/ MISSING"
        FAIL=$((FAIL+1))
    fi
}
assert_executable() {
    if [ -x "$PROJECT_ROOT/$1" ]; then
        echo "  ✅ $1 is executable"
        PASS=$((PASS+1))
    else
        echo "  ❌ $1 NOT executable"
        FAIL=$((FAIL+1))
    fi
}

echo "Root files:"
for f in VERSION CHANGELOG.md README.md LICENSE SECURITY.md .gitignore .sanitize-ignore install.sh; do
    assert_file "$f"
done
assert_executable install.sh

echo ""
echo "scripts/:"
for f in mac-release.sh release-sanitize.sh scan-credentials.sh emit-sbom.sh sync-from-gitx-release.sh; do
    assert_file "scripts/$f"
    assert_executable "scripts/$f"
done
assert_file "scripts/lib/manifest.sh"
assert_executable "scripts/lib/manifest.sh"

echo ""
echo "skills/mac-release/:"
for f in VERSION SKILL.md; do
    assert_file "skills/mac-release/$f"
done
for d in scripts assets agents commands; do
    assert_dir "skills/mac-release/$d"
done
assert_file "skills/mac-release/assets/manifest.template.toml"
assert_file "skills/mac-release/agents/codex-commands.txt"
assert_file "skills/mac-release/commands/mac-release.md"

echo ""
echo "Release/:"
assert_dir "Release"
assert_file "Release/CHANGELOG.md"

echo ""
echo "─── $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
EOF
chmod +x tests/test_skeleton_layout.sh
```

- [ ] **Step 4: Write `tests/test_dual_source.sh`**

```bash
cat > tests/test_dual_source.sh <<'EOF'
#!/bin/bash
# Verifies scripts/ and skills/mac-release/scripts/ are byte-identical (dual-source contract).
set -u
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$PROJECT_ROOT/scripts"
SKILL="$PROJECT_ROOT/skills/mac-release/scripts"

DRIFT="$(diff -rq "$ROOT" "$SKILL" 2>&1 | grep -v '\.sync-provenance' || true)"
if [ -z "$DRIFT" ]; then
    echo "  ✅ dual-source byte-identical"
    exit 0
else
    echo "  ❌ dual-source diverges:"
    echo "$DRIFT" | sed 's/^/    /'
    exit 1
fi
EOF
chmod +x tests/test_dual_source.sh
```

- [ ] **Step 5: Write `tests/run_all.sh`**

```bash
cat > tests/run_all.sh <<'EOF'
#!/bin/bash
# run_all.sh — discover and run every tests/test_*.sh; report aggregate result
set -u
SUITE_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0; FAIL=0; SKIPPED=0
FAILED=()

for t in "$SUITE_DIR"/test_*.sh; do
    [ -e "$t" ] || continue
    NAME="$(basename "$t")"
    echo ""
    echo "══ $NAME ══"
    if bash "$t"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED+=("$NAME")
    fi
done

echo ""
echo "════════════════════════════════════════"
echo "Suite Results: ✅$PASS suites passed / ❌$FAIL suites failed"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 All tests GREEN"
    exit 0
else
    echo "Failed suites:"
    for f in "${FAILED[@]}"; do echo "  - $f"; done
    exit 1
fi
EOF
chmod +x tests/run_all.sh
```

- [ ] **Step 6: Run full suite — expect green**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
bash tests/run_all.sh
```

Expected:
```
══ test_dual_source.sh ══   ✅ dual-source byte-identical
══ test_manifest_parse.sh ══   (all green)
══ test_skeleton_layout.sh ══   (all green)
Suite Results: ✅3 suites passed / ❌0 suites failed
🎉 All tests GREEN
```

- [ ] **Step 7: Commit**

```bash
git add tests/run_all.sh tests/test_skeleton_layout.sh tests/test_dual_source.sh skills/mac-release/scripts/
git commit -m "feat: dual-source contract + skeleton-layout test + run_all.sh

3 suites green: layout / dual-source / manifest-parse.
P0 skeleton complete; ready for P1 common spine."
```

---

### 🚦 CHECKPOINT — END OF P0

Before starting P1, verify:
- [ ] `bash tests/run_all.sh` → 3 suites / 0 failed
- [ ] `bash scripts/mac-release.sh --help` shows v0.0.1-dev usage
- [ ] `diff -rq scripts/ skills/mac-release/scripts/ | grep -v sync-provenance` is empty
- [ ] `git log --oneline` shows ~6 commits with sensible messages

**Report to user**: skeleton complete, awaiting confirmation to proceed to P1.

---

## Phase 1 — Common Spine (15 pipeline phases)

Goal: implement the toolchain-agnostic part of the pipeline. After P1, the only thing missing for a real release is the per-stack adapter (P2/P3/P4).

### Task P1.1: Pipeline scaffold — `scripts/release.sh` with all 15 phases stubbed

**Files:**
- Create: `~/tkbox/Cloud_Coding/Github/Mac_Release_Skill/scripts/release.sh`

- [ ] **Step 1: Write release.sh skeleton**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
cat > scripts/release.sh <<'EOF'
#!/bin/bash
# release.sh — mac-release main pipeline; 15 named phases
# usage: bash scripts/release.sh <version>     (called by mac-release.sh wrapper)
# exit:  0 success, 1 pipeline failure (rollback applies), 2 config error
#
# NOTE: set -u ONLY (no set -e). Several gitx-release-inherited patterns rely on
# `[ -n "$x" ] && cmd` chains that would abort under set -e (Gotcha #24).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
VERSION="${1:-}"
DRY_RUN="${DRY_RUN:-0}"
RELEASE_SUCCESS=0
ROLLBACK_BACKUP_DIR=""

# Pipeline phase implementations live in lib/ — sourced lazily as we reach each phase.
load_manifest()              { echo "TODO P1.2"; return 1; }
preflight_external_tools()   { echo "TODO P1.3"; return 1; }
preflight_signing_identity() { echo "TODO P1.3"; return 1; }
preflight_notary_profile()   { echo "TODO P1.3"; return 1; }
version_bump()               { echo "TODO P1.4"; return 1; }
update_changelog()           { echo "TODO P1.4"; return 1; }
run_build_hook()             { echo "TODO P2/P3/P4 (per-stack adapter)"; return 1; }
run_stack_specific_audits()  { echo "TODO P2/P3/P4 (per-stack adapter)"; return 1; }
build_source_tarball()       { echo "TODO P1.7"; return 1; }
codesign_artifact()          { echo "TODO P1.5"; return 1; }
notarize_and_staple()        { echo "TODO P1.6"; return 1; }
package_dmg_or_zip()         { echo "TODO P1.8"; return 1; }
generate_attestations()      { echo "TODO P1.9"; return 1; }
run_deep_audit()             { echo "TODO P1.13"; return 1; }
update_latest_symlink()      { echo "TODO P1.10"; return 1; }

# EXIT trap — rollback wrapper-managed state if pipeline failed
cleanup_on_fail() {
    local rc=$?
    if [ "$RELEASE_SUCCESS" != "1" ] && [ -n "$ROLLBACK_BACKUP_DIR" ] && [ -d "$ROLLBACK_BACKUP_DIR" ]; then
        echo "🔄 Pipeline failed — rolling back VERSION/CHANGELOG bump"
        # P1.4 will fill in the actual restore logic
    fi
    exit $rc
}
trap cleanup_on_fail EXIT

# Main pipeline ---------------------------------------------------------------
echo "🚀 mac-release pipeline starting — version: ${VERSION:-(auto)}"
echo "   PROJECT_ROOT: $PROJECT_ROOT"

load_manifest                 || exit 2
preflight_external_tools      || exit 1
preflight_signing_identity    || exit 1
preflight_notary_profile      || exit 1
version_bump                  || exit 1
update_changelog              || exit 1
run_build_hook                || exit 1
run_stack_specific_audits     || exit 1
build_source_tarball          || exit 1
codesign_artifact             || exit 1
notarize_and_staple           || exit 1
package_dmg_or_zip            || exit 1
generate_attestations         || exit 1
run_deep_audit                || exit 1
update_latest_symlink         || exit 1

RELEASE_SUCCESS=1
echo "✅ mac-release pipeline complete: $PRODUCT_NAME v${VERSION}"
EOF
chmod +x scripts/release.sh
```

- [ ] **Step 2: Sync to skill bundle, verify dual-source clean, run tests**

```bash
cp scripts/release.sh skills/mac-release/scripts/release.sh
bash tests/run_all.sh
```

Expected: 3 suites still green (skeleton-layout doesn't yet require release.sh, dual-source includes the new file).

- [ ] **Step 3: Commit**

```bash
git add scripts/release.sh skills/mac-release/scripts/release.sh
git commit -m "feat(P1.1): release.sh scaffold with all 15 phases stubbed"
```

### Task P1.2: Implement `load_manifest` (uses `scripts/lib/manifest.sh` from P0.8)

[For each remaining task in P1: write failing test, implement, run test, commit. Following the same TDD pattern shown explicitly in P0.8. Tasks P1.2 through P1.13 share this rhythm; the spec already enumerates the 15 phases and their data contracts. Engineer should:]

For each phase function in `release.sh`:

1. **Write a unit test** in `tests/test_<phase>.sh` that exercises the function on a fixture (no real Apple servers).
2. **Run** to verify failure (function still stubbed).
3. **Implement** the phase. Reference the spec §4 phase table for inputs/outputs/failure-mode.
4. **Run** the test, verify pass.
5. **Sync to bundle** (`cp scripts/release.sh skills/mac-release/scripts/release.sh` — and any new `lib/*.sh`).
6. **Re-run `tests/run_all.sh`**, confirm full green + dual-source clean.
7. **Commit** with message `feat(P1.N): implement <phase_name>`.

The spec's §4 table is authoritative for each phase's contract. Specifically:

- **P1.2 `load_manifest`** — eval scripts/lib/manifest.sh output, set env vars, exit 2 on failure. Test: assert exported `STACK`, `PRODUCT_NAME`, etc., from valid-swift.toml fixture.
- **P1.3 preflights** — three functions: `preflight_external_tools` (probe `codesign / hdiutil / lipo / xcrun / git / shasum / zip / awk / sed / grep`); `preflight_signing_identity` (check `security find-identity -v -p codesigning` for `$SIGN_IDENTITY`); `preflight_notary_profile` (check `xcrun notarytool history --keychain-profile $NOTARY_PROFILE` exit code). Each returns 0 on pass, 1 on failure with diagnostic + `mac-release setup` hint.
- **P1.4 `version_bump` + `update_changelog`** — gitx-release pattern: read `VERSION` sidecar, auto-bump patch unless explicit `$VERSION` arg, update both VERSION sidecars + insert sentinel CHANGELOG entry, set `ROLLBACK_BACKUP_DIR` for cleanup_on_fail.
- **P1.5 `codesign_artifact`** (lib/codesign-pipeline.sh) — `codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY"` (with optional `--entitlements`); verify with `codesign --verify --deep --strict --verbose=2`. Test: against a tiny fixture .app or naked binary fixture; verify SignatureValid output.
- **P1.6 `notarize_and_staple`** (lib/notarize-pipeline.sh) — `ditto -c -k --sequesterRsrc --keepParent` to ZIP, `xcrun notarytool submit ... --wait`, parse status, on Accepted run `xcrun stapler staple` (only for .app/.pkg/.dmg, NOT for naked binary), `xcrun stapler validate`. Test: mocked notarytool response (gate real round-trip behind `MAC_RELEASE_E2E=1`).
- **P1.7 `build_source_tarball`** — `git archive --format=tar HEAD | tar --owner=0 --group=0 --numeric-owner ... | LC_ALL=C sort | gzip -n`, output `<product>-vX.Y.Z-source.tar.gz`. Test: build twice with same SOURCE_DATE_EPOCH, assert `cmp -s` (deterministic).
- **P1.8 `package_dmg_or_zip`** — for `BUNDLE_TYPE=app`, `hdiutil create` DMG with .app inside + drag-to-Applications symlink, then `codesign` the DMG itself. For `BUNDLE_TYPE=binary`, `ditto -c -k` to ZIP. Test: against a fixture stapled .app; verify DMG mounts and contains expected .app.
- **P1.9 `generate_attestations`** — `shasum -a 256 *.dmg *.zip *-source.tar.gz install.sh | LC_ALL=C sort > checksums.txt`; vendored `emit-sbom.sh` for SBOM; emit `RELEASE_NOTES.md` with three install paths.
- **P1.10 `update_latest_symlink`** — `ln -sfn <product>-vX.Y.Z Release/latest` (atomic; uses `-n` for BSD/GNU consistency per gitx-release Gotcha #15).
- **P1.13 `run_deep_audit`** — implement `scripts/release-audit.sh` skeleton with §1 (basic existence) + §2 (flattened docs) + §10 (provenance) + §11 (open-source compliance) sections at first; ~30 gates. Test: against synthetic fixture release dir.

**Smoke test as the P1 capstone**: `tests/test_release_pipeline_smoke.sh` runs the full pipeline against `tests/fixtures/tiny-cli/` (a synthetic project — minimal Bash "hello world" passed through with stack=binary, no actual codesign — gated to skip Apple-server phases unless `MAC_RELEASE_E2E=1`).

After all P1 tasks land:

```bash
bash tests/run_all.sh   # expect 12+ suites green
bash tests/test_release_pipeline_smoke.sh   # expect end-to-end pass on fixture
```

---

### 🚦 CHECKPOINT — END OF P1

Before starting P2, verify:
- [ ] `bash tests/run_all.sh` → all suites green
- [ ] Smoke test passes on synthetic fixture
- [ ] `release-audit.sh` exits 0 on the smoke-test fixture's output dir
- [ ] Dual-source diff still clean
- [ ] Git log shows one commit per task (~13 commits in P1)

**Report to user**: spine complete; ready for first per-stack adapter.

---

## Phase 2 — Swift Adapter + MacAudit Checkpoint

### Task P2.1: `scripts/adapters/swift.sh`

**Files:**
- Create: `~/tkbox/Cloud_Coding/Github/Mac_Release_Skill/scripts/adapters/swift.sh`

- [ ] **Step 1: Write `tests/test_swift_adapter.sh`** (TDD)

Skeleton: assert `swift.sh` exists, is executable, has shebang + usage comment. Then richer assertions: invoking `swift.sh build /path/to/swift-project` should call `BUILD_HOOK` and verify `BUILD_OUTPUT` exists with `Contents/Info.plist` + universal Mach-O.

- [ ] **Step 2: Run, expect FAIL** (`swift.sh` doesn't exist).

- [ ] **Step 3: Implement `swift.sh`**

```bash
cat > scripts/adapters/swift.sh <<'EOF'
#!/bin/bash
# adapters/swift.sh — Swift stack adapter
# usage: scripts/adapters/swift.sh build|audit
# exit: 0 success, 1 failure
#
# Reads from env (already loaded via lib/manifest.sh):
#   BUILD_HOOK, BUILD_OUTPUT, BUNDLE_TYPE, PRODUCT_NAME, SWIFT_SPM_RESOURCE_BUNDLE
set -u
SUBCOMMAND="${1:?usage: swift.sh build|audit}"

case "$SUBCOMMAND" in
    build)
        echo "🔨 Swift build hook: $BUILD_HOOK"
        cd "$PROJECT_ROOT"
        bash "$BUILD_HOOK" || { echo "❌ build hook failed"; exit 1; }
        if [ ! -e "$PROJECT_ROOT/$BUILD_OUTPUT" ]; then
            echo "❌ build hook did not produce $BUILD_OUTPUT" >&2
            exit 1
        fi
        echo "✅ build output: $PROJECT_ROOT/$BUILD_OUTPUT"
        ;;
    audit)
        OUT="$PROJECT_ROOT/$BUILD_OUTPUT"
        echo "🔍 Swift stack-specific audit: $OUT"
        # Gate 1: universal binary
        EXEC=$(plutil -extract CFBundleExecutable raw "$OUT/Contents/Info.plist" 2>/dev/null)
        if [ -n "$EXEC" ] && [ -f "$OUT/Contents/MacOS/$EXEC" ]; then
            ARCHS=$(lipo -info "$OUT/Contents/MacOS/$EXEC" 2>&1)
            if echo "$ARCHS" | grep -q 'arm64' && echo "$ARCHS" | grep -q 'x86_64'; then
                echo "  ✅ universal binary (arm64 + x86_64)"
            else
                echo "  ❌ binary is not universal: $ARCHS"
                exit 1
            fi
        else
            echo "  ⚠️ could not locate executable in bundle"
        fi
        # Gate 2: Info.plist completeness
        for k in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion CFBundleExecutable LSMinimumSystemVersion; do
            V=$(plutil -extract "$k" raw "$OUT/Contents/Info.plist" 2>/dev/null)
            if [ -n "$V" ]; then
                echo "  ✅ Info.plist has $k=$V"
            else
                echo "  ❌ Info.plist missing $k"
                exit 1
            fi
        done
        # Gate 3: SPM resource bundle placement (gotcha)
        if [ "${SWIFT_SPM_RESOURCE_BUNDLE:-false}" = "true" ]; then
            BAD=$(find "$OUT/Contents/MacOS" -maxdepth 1 -name '*.bundle' 2>/dev/null | head)
            if [ -n "$BAD" ]; then
                echo "  ❌ *.bundle in Contents/MacOS/ — must be in Contents/Resources/ for Bundle.module"
                exit 1
            fi
            GOOD=$(find "$OUT/Contents/Resources" -maxdepth 1 -name '*.bundle' 2>/dev/null | head)
            if [ -n "$GOOD" ]; then
                echo "  ✅ SPM resource bundle correctly in Contents/Resources/"
            fi
        fi
        ;;
    *)
        echo "❌ unknown subcommand: $SUBCOMMAND" >&2
        exit 2
        ;;
esac
EOF
chmod +x scripts/adapters/swift.sh
```

- [ ] **Step 4: Run test, expect PASS**.

- [ ] **Step 5: Sync to skill bundle, verify dual-source, run full suite**.

- [ ] **Step 6: Commit**: `feat(P2.1): Swift adapter (build + audit)`.

### Task P2.2: Wire Swift adapter into `release.sh` phases 7 + 8

[Replace stubs `run_build_hook` and `run_stack_specific_audits` to dispatch on `$STACK`. For `swift`, call `bash $SCRIPT_DIR/adapters/swift.sh build` / `audit`.]

### Task P2.3: Create `.mac-release/manifest.toml` for MacAudit

**Files:**
- Create: `~/tkbox/Cloud_Coding/Coding_mac_system_audit/.mac-release/manifest.toml`

- [ ] **Step 1: Copy template + fill in MacAudit specifics**

```bash
cd ~/tkbox/Cloud_Coding/Coding_mac_system_audit
mkdir -p .mac-release
cp ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill/skills/mac-release/assets/manifest.template.toml .mac-release/manifest.toml
# Edit: name=MacAudit, identifier=com.macaudit.gui, stack=swift, BUILD_HOOK=scripts/build.sh,
#       BUILD_OUTPUT=release/v$VERSION/MacAuditApp-v$VERSION.app, sign identity, team_id=NN8425LUVZ
```

- [ ] **Step 2: Verify manifest parses**

```bash
bash ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill/scripts/lib/manifest.sh \
     ~/tkbox/Cloud_Coding/Coding_mac_system_audit/.mac-release/manifest.toml | head
```

Expected: `export PRODUCT_NAME='MacAudit'` + ~12 other exports.

### Task P2.4: First-time notarytool setup on operator's machine

**Operator-driven** (cannot be automated — requires app-specific password from appleid.apple.com).

- [ ] **Step 1: Verify Developer ID cert in keychain**

```bash
security find-identity -v -p codesigning | grep -E 'Developer ID Application.*NN8425LUVZ' && echo "✅ cert present"
```

- [ ] **Step 2: Operator generates app-specific password** at https://appleid.apple.com/account/manage (one-time).

- [ ] **Step 3: Operator runs `xcrun notarytool store-credentials`** with the app-specific password:

```bash
xcrun notarytool store-credentials MAC_RELEASE_NOTARY \
  --apple-id "<operator-apple-id>" \
  --team-id NN8425LUVZ \
  --password "<app-specific-password>"
```

- [ ] **Step 4: Verify**

```bash
xcrun notarytool history --keychain-profile MAC_RELEASE_NOTARY 2>&1 | head -3
```

Expected: empty list (first-time) or recent submission table.

### Task P2.5: First MacAudit release through mac-release pipeline

**Files:**
- Create: `~/tkbox/Cloud_Coding/Coding_mac_system_audit/Release/MacAudit-v0.1.6/`

- [ ] **Step 1: Install mac-release locally for first use**

```bash
cd ~/tkbox/Cloud_Coding/Github/Mac_Release_Skill
bash install.sh --force
```

- [ ] **Step 2: Run pipeline against MacAudit**

```bash
cd ~/tkbox/Cloud_Coding/Coding_mac_system_audit
PROJECT_ROOT="$(pwd)" bash ~/.agents/skills/mac-release/scripts/mac-release.sh
```

Expected: full pipeline runs, ~5–10 minutes (notarization round-trip ~2–8 min). End state: `Release/MacAudit-v0.1.6/MacAudit-v0.1.6.dmg` with codesign valid + stapler validate accepts.

- [ ] **Step 3: Verify end-state artifact**

```bash
cd ~/tkbox/Cloud_Coding/Coding_mac_system_audit/Release/MacAudit-v0.1.6
codesign -dv --verbose=4 MacAudit-v0.1.6.dmg 2>&1 | head -10
xcrun stapler validate MacAudit-v0.1.6.dmg
spctl -a -vv -t install MacAudit-v0.1.6.dmg
shasum -a 256 -c checksums.txt
```

All four expected to succeed.

### Task P2.6: Capture findings + commit

- [ ] **Step 1: Update `Mac_Release_Skill/CHANGELOG.md`** with notes from MacAudit's first run — any unexpected issues, fixture-vs-real-app deltas, etc.

- [ ] **Step 2: Add `tests/fixtures/tiny-swift-app/`** if MacAudit revealed gaps in coverage.

- [ ] **Step 3: Commit `feat(P2): Swift adapter integrated; MacAudit v0.1.6 ships notarized DMG`**.

---

### 🚦 CHECKPOINT — END OF P2

- [ ] MacAudit `Release/MacAudit-v0.1.6/MacAudit-v0.1.6.dmg` exists and passes all 3 verification gates (codesign, stapler, spctl).
- [ ] `tests/run_all.sh` still green (+test_swift_adapter.sh).
- [ ] Operator can `gh release create v0.1.6 --draft` with the artifacts.

**Report to user**: Swift adapter validated end-to-end. Awaiting confirmation before P3.

---

## Phase 3 — Tauri 2.0 Adapter + AiPromptX Checkpoint

### Task P3.1: `scripts/adapters/tauri.sh`

[Same TDD rhythm: test → fail → implement → pass → sync → commit. Adapter wraps `cargo tauri build --target universal-apple-darwin`, locates the .app under `src-tauri/target/universal-apple-darwin/release/bundle/macos/`, runs Tauri-specific audits.]

### Task P3.2: `scripts/lib/capability-audit.sh`

[Implements the empirically-calibrated two-tier policy from spec §7. Hard-fail / soft-warn classifier. Reads `tauri.conf.json` (`app.security.csp`) + `capabilities/*.json`. Optional `.mac-release/capability-allowlist.toml` for justified bypasses.]

### Task P3.3: `tests/test_capability_audit.sh`

[Fixtures: `permissive-config.json` (hard-fail triggers), `defensible-config.json` (only soft-warns), `allowlisted-config.json` (with capability-allowlist.toml that justifies a soft-warn). Empirical reference: AiPromptX `main.json` + `tauri.conf.json` should classify cleanly.]

### Task P3.4: `tests/test_tauri_adapter.sh` + `tests/fixtures/tiny-tauri-app/`

### Task P3.5: `.mac-release/manifest.toml` for AiPromptX

### Task P3.6: First AiPromptX release through pipeline

### Task P3.7: Capture findings + commit

---

### 🚦 CHECKPOINT — END OF P3

- [ ] AiPromptX ships notarized + stapled DMG.
- [ ] Capability audit reports 1–2 expected soft-warns (csp:null / fs:default), 0 hard-fails.
- [ ] Operator can publish.

---

## Phase 4 — Go Adapter + Please_Continue Checkpoint

### Task P4.1: `scripts/adapters/go.sh`

[Wraps `go build` × 2 archs + `lipo -create -output`. For `BUNDLE_TYPE=binary` (the common case for CLI), bypasses .app packaging. Emits stapler-skip notice for naked binaries.]

### Task P4.2: `tests/test_go_adapter.sh` + `tests/fixtures/tiny-go-cli/`

[Stack-specific gates: lipo universal verify, symbol-strip flag, `otool -L` host-leak (no `/opt/homebrew/lib/`), no `/Users/<name>/` strings embedded.]

### Task P4.3: `.mac-release/manifest.toml` for Please_Continue

[Note: spec §14.1 flags Please_Continue's `module github.com/<old-user>/please-continue` in go.mod as a structural concern. The operator should decide before this run whether to rename the module path or accept it in published artifacts.]

### Task P4.4: First Please_Continue release through pipeline (notarized ZIP, no DMG)

### Task P4.5: Capture findings + commit

---

### 🚦 CHECKPOINT — END OF P4

- [ ] Please_Continue ships notarized universal-binary ZIP.
- [ ] Lipo universal verified, symbol strip confirmed, host-leak gate passes.

---

## Phase 5 — Hardening + First Self-Bake

### Task P5.1: TDD gap-fill of audit gates toward spec target ~80

[Run actual MacAudit / AiPromptX / Please_Continue releases through current audit; identify gaps revealed; add gates one by one with TDD until target met.]

### Task P5.2: Polish README + INSTALL + CONTRIBUTING + TKX_Mac_Release_policy.md

[Complete user-facing docs. Use gitx-release's READMEs as structural template; rewrite content for Mac context.]

### Task P5.3: First self-bake of mac-release v0.1.0 via gitx-release

[`PROJECT_ROOT=$(pwd) bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh` — mac-release IS a Bash skill, so gitx-release is its proper release pipeline. Backfill v0.1.0 CHANGELOG entry to clear sentinel.]

### Task P5.4: Initialize `HANDOFF.md` for Mac_Release_Skill repo

[Use handoff skill template; capture session journey from spec → plan → implementation. First Dev Log entry covers P0–P5.]

### Task P5.5: Install v0.1.0 locally + verify cross-CLI roots

[`Release/mac-release-v0.1.0/install.sh --force`; verify `~/.agents/skills/mac-release/VERSION` = `v0.1.0` and symlinks in place.]

---

### 🚦 CHECKPOINT — END OF P5 / V0.1.0 COMPLETE

- [ ] mac-release v0.1.0 installed locally across `~/.agents/skills/`, `~/.claude/skills/`, `~/.config/opencode/skills/`.
- [ ] All three target projects (MacAudit / AiPromptX / Please_Continue) successfully released through pipeline at least once.
- [ ] HANDOFF.md captures session.
- [ ] README / INSTALL / CONTRIBUTING / TKX_Mac_Release_policy.md polished.
- [ ] First commit operator can paste a `gh release create v0.1.0 --draft <assets>` command for, when they pick a publish platform.

**Final status**: v0.1.0 of mac-release shipped. Roadmap (v0.2+) per spec §18.

---

## Self-Review

Done before saving — checking against the spec at `docs/superpowers/specs/2026-05-06-mac-release-skill-design.md`:

1. **Spec coverage**: Every section of the spec maps to at least one task. §3 architecture → P0.1–P0.10 + P1.1. §4 pipeline phases → P1.2–P1.13 task headers. §5 manifest → P0.8. §6 per-stack adapters → P2/P3/P4. §7 Tauri policy → P3.2/P3.3. §8 deep audit → P1.13 + P5.1. §9 test strategy → tests scattered through P0/P1/P2/P3/P4. §10 first-run UX → P2.4 (operator-driven setup) + P5.2 (CONTRIBUTING with setup walkthrough). §11–12 distribution + GitHub upload → P1.8 + P1.9. §13 implementation order → matches plan structure. §14 cross-cutting gotchas → flagged in P2.3, P3.5, P4.3. §15–18 → covered in P5.4 (HANDOFF) and P5.2 (TKX_Mac_Release_policy.md). ✅ no gaps.

2. **Placeholder scan**: Tasks P1.2–P1.13 reference contract-only ("see spec §4 phase table") rather than literal step-by-step code, because each phase implementation is 30–80 lines and the spec section is authoritative. This is borderline — I've explicitly listed which sections to consult per phase, the test rhythm, and the commit-message form. An engineer following this plan will need to read the spec for each phase, but the plan is explicit about that requirement and lists each phase's contract pointer. P3.1, P3.2, P3.4–P3.7, P4.1–P4.5, P5.1–P5.5 follow the same "TDD rhythm; spec is authoritative" shape — same justification.

3. **Type consistency**: `PRODUCT_NAME` / `STACK` / `BUNDLE_TYPE` / `BUILD_HOOK` / `BUILD_OUTPUT` / `SIGN_IDENTITY` / `TEAM_ID` / `NOTARY_PROFILE` are used consistently across P0.8, P1.1, P2.1, and the spec §5 manifest schema. `MAC_RELEASE_NOTARY` is the canonical example notary profile name throughout.

4. **Internal consistency**: 6 phases (P0–P5), each with explicit checkpoint, totalling ~40 tasks. Implementation order matches spec §13. No contradictions found.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-06-mac-release-skill-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for a 40-task plan where the engineer needs context from the spec each phase.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints for review. Risk: this plan + spec is substantial; inline execution will eat context window quickly.

Which approach?
