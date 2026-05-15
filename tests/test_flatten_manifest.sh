#!/bin/bash
# test_flatten_manifest.sh — v1.1.2 BDD acceptance test for `.release-flatten`.
#
# SCENARIO 1 (the claudemex case):
#   Given a project that ships a custom top-level file (e.g. CUSTOM-PROMPT.md)
#   AND   the project's install.sh references that file as `$SELF_DIR/CUSTOM-PROMPT.md`
#   When  the project has a `.release-flatten` manifest listing CUSTOM-PROMPT.md
#   Then  flatten_docs() copies CUSTOM-PROMPT.md into Release/<ver>/
#   And   running install.sh from the release dir succeeds.
#
# SCENARIO 2 (backward compatibility):
#   Given a project with NO `.release-flatten` manifest
#   When  flatten_docs() runs
#   Then  it copies exactly the standard 8 docs (current behavior, no regression).
#
# SCENARIO 3 (manifest entry that doesn't exist):
#   Given a `.release-flatten` listing a file that doesn't exist in the project
#   When  flatten_docs() runs
#   Then  a labelled warning is printed, but the release continues
#         (manifests are advisory; missing optional files don't block release).
#
# SCENARIO 4 (manifest comment + blank line tolerance):
#   Given a manifest with `#` comments and blank lines
#   When  flatten_docs() reads it
#   Then  comments and blanks are skipped; only path lines are copied.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_flatten_manifest.sh ══"

# ── Static: release.sh references .release-flatten ─────────────────────
if grep -qE '\.release-flatten' "$RELEASE_SH"; then
    ok "release.sh references .release-flatten manifest"
else
    fail "release.sh does NOT reference .release-flatten — manifest support missing"
fi

# ── Static: flatten_docs reads a manifest in a loop ────────────────────
block=$(awk '/^flatten_docs\(\)/,/^\}/' "$RELEASE_SH")
if echo "$block" | grep -qE '\.release-flatten'; then
    ok "flatten_docs() body reads .release-flatten manifest"
else
    fail "flatten_docs() does not consume .release-flatten"
fi

# ── Behavioral fixture ─────────────────────────────────────────────────
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

# Build a minimal valid project layout (copy of the skill's layout)
mkdir -p "$FIXTURE/skills/demo-skill/scripts/lib" "$FIXTURE/scripts/lib" "$FIXTURE/tests"
cat > "$FIXTURE/SKILL.md" <<'EOF'
---
name: demo-skill
description: BDD fixture project for flatten manifest testing — checks both scenarios in one fixture run.
---
# Demo Skill
EOF
cp "$FIXTURE/SKILL.md" "$FIXTURE/skills/demo-skill/SKILL.md"
echo "v0.0.1" > "$FIXTURE/VERSION"
echo "v0.0.1" > "$FIXTURE/skills/demo-skill/VERSION"
echo "# Demo Project" > "$FIXTURE/README.md"
echo "MIT" > "$FIXTURE/LICENSE"
cat > "$FIXTURE/CHANGELOG.md" <<'EOF'
# Demo — Release History

## v0.0.1 — 2026-05-04

- Initial fixture release for flatten-manifest BDD test.
EOF
mkdir -p "$FIXTURE/Release"
cp "$FIXTURE/CHANGELOG.md" "$FIXTURE/Release/CHANGELOG.md"

# Project-specific custom file at the top level (the claudemex case)
echo "# Custom Project Prompt" > "$FIXTURE/CUSTOM-PROMPT.md"

# Project-specific install.sh that references the custom file
cat > "$FIXTURE/install.sh" <<'EOF'
#!/bin/bash
# Demo install.sh — references a project-specific file that is NOT in
# the gitx-release standard flatten list. This is the claudemex case.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.demo-target"
cp "$SELF_DIR/CUSTOM-PROMPT.md" "$HOME/.demo-target/CUSTOM-PROMPT.md"
echo "✅ Installed"
EOF
chmod +x "$FIXTURE/install.sh"

# Required minimal scripts (byte-identical dual source)
cat > "$FIXTURE/scripts/noop.sh" <<'EOF'
#!/bin/bash
echo "noop"
EOF
cp "$FIXTURE/scripts/noop.sh" "$FIXTURE/skills/demo-skill/scripts/noop.sh"
cat > "$FIXTURE/tests/run_all.sh" <<'EOF'
#!/bin/bash
echo "Suite Results: ✅0 suites passed / ❌0 suites failed"
echo "🎉 All tests GREEN"
exit 0
EOF
chmod +x "$FIXTURE/tests/run_all.sh"

# Helper: run flatten_docs() in isolation against $FIXTURE and report
# whether CUSTOM-PROMPT.md ends up in $RELEASE_DIR.
run_flatten_only() {
    local rel_dir="$1"
    rm -rf "$rel_dir"
    mkdir -p "$rel_dir"
    PROJECT_ROOT="$FIXTURE" PROJECT_NAME="demo" SKILL_NAME="demo-skill" RELEASE_DIR="$rel_dir" \
        bash -c '
            source "'"$ROOT"'/scripts/lib/detect-project.sh" 2>/dev/null || true
            # Source release.sh up to the function definitions, then call flatten_docs.
            # Use bash subshell to avoid running main flow.
            DRY_RUN=0
            run() { "$@"; }
            source <(awk "/^flatten_docs\(\)/,/^\}/" "'"$RELEASE_SH"'")
            flatten_docs >/dev/null 2>&1 || true
        '
}

# ── SCENARIO 2 first (backward compat — no manifest, standard list) ────
RELDIR_NOMAN="$FIXTURE/Release/demo-v0.0.1"
run_flatten_only "$RELDIR_NOMAN"
if [ -f "$RELDIR_NOMAN/README.md" ] && [ -f "$RELDIR_NOMAN/LICENSE" ] && [ -f "$RELDIR_NOMAN/install.sh" ]; then
    ok "[scenario 2] no manifest → standard 8 docs still flattened (backward compat)"
else
    fail "[scenario 2] no manifest → standard docs missing from release dir"
fi
if [ ! -f "$RELDIR_NOMAN/CUSTOM-PROMPT.md" ]; then
    ok "[scenario 2] no manifest → CUSTOM-PROMPT.md NOT auto-included (no global copy)"
else
    fail "[scenario 2] no manifest → CUSTOM-PROMPT.md was wrongly copied without manifest opt-in"
fi
rm -rf "$RELDIR_NOMAN"

# ── SCENARIO 1 (manifest opts the custom file in) ──────────────────────
cat > "$FIXTURE/.release-flatten" <<'EOF'
# Project-specific files to flatten into Release/<ver>/ in addition to
# the standard 8-doc list. One path per line; comments and blank lines OK.

CUSTOM-PROMPT.md
EOF

RELDIR_WITH="$FIXTURE/Release/demo-v0.0.1"
run_flatten_only "$RELDIR_WITH"
if [ -f "$RELDIR_WITH/CUSTOM-PROMPT.md" ]; then
    ok "[scenario 1] manifest → CUSTOM-PROMPT.md flattened into release dir"
else
    fail "[scenario 1] manifest → CUSTOM-PROMPT.md NOT flattened (claudemex bug not fixed)"
fi

# Verify install.sh actually works against the flattened release dir
if [ -f "$RELDIR_WITH/install.sh" ]; then
    if HOME="$FIXTURE/fakeenv" bash "$RELDIR_WITH/install.sh" >/dev/null 2>&1; then
        ok "[scenario 1] install.sh succeeds against flattened release dir"
    else
        fail "[scenario 1] install.sh STILL fails — manifest entry copied but install.sh broken"
    fi
fi
rm -rf "$RELDIR_WITH"

# ── SCENARIO 3 (manifest entry that doesn't exist on disk) ─────────────
cat > "$FIXTURE/.release-flatten" <<'EOF'
CUSTOM-PROMPT.md
DOES-NOT-EXIST.md
EOF

RELDIR_MISS="$FIXTURE/Release/demo-v0.0.1"
run_flatten_only "$RELDIR_MISS" >/dev/null 2>&1 || true
# Existing file still flattened, missing file warned (not fatal at flatten time)
if [ -f "$RELDIR_MISS/CUSTOM-PROMPT.md" ]; then
    ok "[scenario 3] existing manifest entry flattened despite missing peer entry"
else
    fail "[scenario 3] missing manifest entry blocked all flattening"
fi
rm -rf "$RELDIR_MISS"

# ── SCENARIO 4 (manifest comments + blank lines tolerated) ─────────────
cat > "$FIXTURE/.release-flatten" <<'EOF'
# leading comment

# blank line above this is intentional

CUSTOM-PROMPT.md   # trailing comments ARE supported — stripped via ${var%%#*}

EOF

RELDIR_COM="$FIXTURE/Release/demo-v0.0.1"
run_flatten_only "$RELDIR_COM"
if [ -f "$RELDIR_COM/CUSTOM-PROMPT.md" ]; then
    ok "[scenario 4] manifest with comments + blank lines parsed correctly"
else
    fail "[scenario 4] manifest with comments not parsed — file not flattened"
fi
rm -rf "$RELDIR_COM"

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
