#!/bin/bash
# test_release_pipeline_smoke.sh — Full pipeline smoke test against a minimal fixture project.
# Runs release.sh v0.0.1 end-to-end and asserts key output artifacts exist.
# This test catches regressions anywhere in the release.sh call graph that the
# narrower unit tests cannot reach.
# exit: 0 all pass, 1 any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT_REAL="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== test_release_pipeline_smoke.sh ==="

# ── 1. Create a self-contained fixture project in a temp dir ──────────────────
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
FAKE_HOME="$FIXTURE/home"
mkdir -p "$FAKE_HOME"

VERSION="v0.0.1"
SKILL="my-skill"

# Directory skeleton
mkdir -p \
    "$FIXTURE/skills/$SKILL/agents" \
    "$FIXTURE/skills/$SKILL/scripts/lib" \
    "$FIXTURE/skills/$SKILL/references" \
    "$FIXTURE/skills/$SKILL/assets" \
    "$FIXTURE/scripts/lib" \
    "$FIXTURE/tests" \
    "$FIXTURE/Release"

# zip skips empty directories; place placeholder .md files so references/ and
# assets/ are included in the .skill bundle — required by audit §6.
cat > "$FIXTURE/skills/$SKILL/references/README.md" <<'EOF'
# References

This skill has no external reference documents at this time.

Placeholder reference file to satisfy audit §6b line-count threshold.

Future versions may include additional reference materials.
EOF

cat > "$FIXTURE/skills/$SKILL/assets/README.md" <<'EOF'
# Assets

This skill has no binary assets.
EOF

cat > "$FIXTURE/skills/$SKILL/agents/codex-commands.txt" <<'EOF'
$my-skill
EOF

# --- SKILL.md with valid frontmatter ---
cat > "$FIXTURE/skills/$SKILL/SKILL.md" <<'EOF'
---
name: my-skill
description: Minimal fixture skill for pipeline smoke testing.
---
# My Skill

## When to Trigger

Use this skill for testing the release pipeline.

## Steps / Execution Flow

1. Do thing A
2. Do thing B
3. Verify result

This skill is a minimal fixture for smoke testing the release.sh pipeline.
It has enough content to pass the audit line-count thresholds.
Line 13 of content.
Line 14 of content.
Line 15 of content.
Line 16 of content.
Line 17 of content.
Line 18 of content.
Line 19 of content.
Line 20 of content.
Line 21 of content.
EOF
printf '%s\n' "$VERSION" > "$FIXTURE/skills/$SKILL/VERSION"

# --- tests/run_all.sh — minimal stub that always passes ---
cat > "$FIXTURE/tests/run_all.sh" <<'EOF'
#!/bin/bash
# Minimal test runner stub for fixture project.
echo "Tests: 0 suites (fixture stub)"
exit 0
EOF
chmod +x "$FIXTURE/tests/run_all.sh"

# --- Release/CHANGELOG.md — valid entry, no TODO ---
cat > "$FIXTURE/Release/CHANGELOG.md" <<'EOF'
# My-skill — Release History

记录各版本的关键变化。最新版本在最上面。

## v0.0.1 — 2026-01-01

Initial release of the fixture skill for pipeline smoke testing.

Artifacts: `Release/my-skill-v0.0.1/`

---
EOF

# --- README.md ---
cat > "$FIXTURE/README.md" <<'EOF'
# My-skill

A minimal fixture skill for smoke testing the release pipeline.

## Installation

Run `./install.sh` to install.

## Usage / Quick Start

Trigger the skill via Claude Code.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development guidelines.

## License

MIT
EOF

# --- TEST-SCENARIOS.md ---
cat > "$FIXTURE/TEST-SCENARIOS.md" <<'EOF'
# Test Scenarios

Smoke test scenarios for the fixture skill.

## Scenario 1: Basic Installation

Install the skill and verify it triggers.

## Scenario 2: Version Check

Verify the correct version is installed.
EOF

# --- INSTALL.md ---
cat > "$FIXTURE/INSTALL.md" <<'EOF'
# Install

## Requirements

- Claude Code

## Install steps

```bash
./install.sh
```

## Uninstall

Remove the skill directory.

## Upgrade / Update

Re-run install.sh with --force.
EOF

# --- install.sh — must support --dry-run, --force, --help (§6.10 interface contract) ---
cat > "$FIXTURE/install.sh" <<'EOF'
#!/bin/bash
# install.sh — fixture install stub
# usage: ./install.sh [--dry-run] [--force] [--help]
# exit: 0 success, 1 failure
set -euo pipefail
DRY_RUN=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
        --help)    echo "Usage: $0 [--dry-run] [--force] [--help]"; exit 0 ;;
    esac
done
[ "$DRY_RUN" = "1" ] && echo "[dry-run] would install" && exit 0
mkdir -p "$HOME/.claude/skills"
echo "Fixture install.sh executed."
EOF
chmod +x "$FIXTURE/install.sh"

# --- LICENSE ---
cat > "$FIXTURE/LICENSE" <<'EOF'
MIT License

Copyright (c) 2026 Fixture Author

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so.
EOF

# --- CONTRIBUTING.md ---
cat > "$FIXTURE/CONTRIBUTING.md" <<'EOF'
# Contributing

## Development

1. Clone the repo
2. Run tests: `bash tests/run_all.sh`
3. Build: no build step required

## Pull Request / Commit Conventions

- Use conventional commits: `feat:`, `fix:`, `docs:`, `chore:`
- Submit changes via PR against main
- All tests must pass before merging
EOF

# --- Copy scripts from real project (the release pipeline itself) ---
# These are the helpers that release.sh calls at runtime.
cp "$PROJECT_ROOT_REAL/scripts/release-sanitize.sh"  "$FIXTURE/scripts/"
cp "$PROJECT_ROOT_REAL/scripts/scan-credentials.sh"  "$FIXTURE/scripts/"
cp "$PROJECT_ROOT_REAL/scripts/release-audit.sh"     "$FIXTURE/scripts/"
cp "$PROJECT_ROOT_REAL/scripts/emit-sbom.sh"         "$FIXTURE/scripts/"
cp "$PROJECT_ROOT_REAL/scripts/emit-token-usage.sh"  "$FIXTURE/scripts/"
cp "$PROJECT_ROOT_REAL/scripts/lib/detect-project.sh" "$FIXTURE/scripts/lib/"
chmod +x "$FIXTURE/scripts/"*.sh

# Dual-source: skills/<name>/scripts/ must be byte-identical to scripts/
# (release.sh §check_dual_source and release-audit.sh §9 both enforce this).
# The diff is rooted at scripts/ vs skills/<name>/scripts/ so the lib/
# subdirectory must mirror exactly — including the lib/ sub-path.
mkdir -p "$FIXTURE/skills/$SKILL/scripts/lib"
cp "$FIXTURE/scripts/release-sanitize.sh"   "$FIXTURE/skills/$SKILL/scripts/"
cp "$FIXTURE/scripts/scan-credentials.sh"   "$FIXTURE/skills/$SKILL/scripts/"
cp "$FIXTURE/scripts/emit-sbom.sh"          "$FIXTURE/skills/$SKILL/scripts/"
cp "$FIXTURE/scripts/emit-token-usage.sh"   "$FIXTURE/skills/$SKILL/scripts/"
cp "$FIXTURE/scripts/lib/detect-project.sh" "$FIXTURE/skills/$SKILL/scripts/lib/"
chmod +x "$FIXTURE/skills/$SKILL/scripts/"*.sh

# ── 2. Run release.sh against the fixture ─────────────────────────────────────
# Set PROJECT_NAME explicitly so artifact names are stable and predictable
# regardless of the mktemp basename (which varies per run).
PROJ_NAME="fixture-proj"
RELEASE_SH="$PROJECT_ROOT_REAL/scripts/release.sh"

set +e
output=$(HOME="$FAKE_HOME" PROJECT_ROOT="$FIXTURE" PROJECT_NAME="$PROJ_NAME" SKILL_NAME="$SKILL" bash "$RELEASE_SH" "$VERSION" 2>&1)
rc=$?
set -e

# ── 3. Assertions ──────────────────────────────────────────────────────────────

# 3a. Exit code 0
if [ "$rc" -eq 0 ]; then
    ok "release.sh exits 0"
else
    fail "release.sh exited $rc"
    echo ""
    echo "--- release.sh output (first 120 lines) ---"
    echo "$output" | head -120
    echo "---"
fi

RELEASE_DIR="$FIXTURE/Release/${PROJ_NAME}-${VERSION}"

# 3b. Release directory exists
if [ -d "$RELEASE_DIR" ]; then
    ok "Release dir exists: ${PROJ_NAME}-${VERSION}/"
else
    fail "Release dir missing: $RELEASE_DIR"
fi

# 3c. Source tarball exists
TAR_FILE="$RELEASE_DIR/${PROJ_NAME}-${VERSION}-source.tar.gz"
if [ -f "$TAR_FILE" ]; then
    ok "Source tarball exists: ${PROJ_NAME}-${VERSION}-source.tar.gz"
else
    fail "Source tarball missing: $TAR_FILE"
fi

# 3d. checksums.txt exists
if [ -f "$RELEASE_DIR/checksums.txt" ]; then
    ok "checksums.txt exists"
else
    fail "checksums.txt missing"
fi

# 3e. RELEASE_NOTES.md exists
if [ -f "$RELEASE_DIR/RELEASE_NOTES.md" ]; then
    ok "RELEASE_NOTES.md exists"
else
    fail "RELEASE_NOTES.md missing"
fi

# 3f. Release/latest symlink exists and points to the right target
LATEST_LINK="$FIXTURE/Release/latest"
if [ -L "$LATEST_LINK" ]; then
    target="$(readlink "$LATEST_LINK")"
    if [ "$target" = "${PROJ_NAME}-${VERSION}" ]; then
        ok "Release/latest symlink → ${PROJ_NAME}-${VERSION}"
    else
        fail "Release/latest points to '$target' (expected '${PROJ_NAME}-${VERSION}')"
    fi
else
    fail "Release/latest symlink missing"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Smoke Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
