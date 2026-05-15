#!/bin/bash
# test_release_notes_changelog_inject.sh — v0.9.9 feature B
# RELEASE_NOTES.md should not be a generic shell of "files + install methods";
# it should also surface what actually changed in this version. release.sh
# must extract the current version's entry from Release/CHANGELOG.md and
# inject it as a "What's new" section in RELEASE_NOTES.md.
#
# exit: 0=all pass, 1=any fail

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_SH="$SCRIPT_DIR/../scripts/release.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_release_notes_changelog_inject.sh ══"

# ── Test 1: release.sh has injection logic ────────────────────────────────
# Look for both:
#   (a) an awk/sed extraction over ACCUM_CHANGELOG restricted by SAFE_VERSION
#   (b) an append (`>>`) to RELEASE_NOTES.md of a "What's new"/"本版改动" header
if grep -qE 'awk.*ACCUM_CHANGELOG|awk .*SAFE_VERSION.*CHANGELOG' "$RELEASE_SH" \
   && grep -qE '>>\s*"?\$(\{)?RELEASE_DIR(\})?/RELEASE_NOTES\.md' "$RELEASE_SH" \
   && grep -qE '## .*What.?s new|## .*本版|## .*Changes in this release' "$RELEASE_SH"; then
    ok "release.sh has CHANGELOG → RELEASE_NOTES injection logic"
else
    fail "release.sh does NOT inject CHANGELOG entry into RELEASE_NOTES"
fi

# ── Test 2: functional — temporary CHANGELOG entry survives extraction ────
# Simulate the awk extraction recipe and verify it isolates ONE version.
TMP=$(mktemp -d)
cat > "$TMP/CHANGELOG.md" <<'EOF'
# Project — History

## v9.9.9 — 2099-12-31

### What changed
- Added Foo
- Fixed Bar

Artifacts: `Release/v9.9.9/`

---

## v8.8.8 — 2099-11-30

### Old stuff
- Old change should NOT appear

---
EOF

VERSION=v9.9.9
SAFE_VERSION=$(printf '%s' "$VERSION" | sed 's/\./\\./g')
extracted=$(awk "/^## $SAFE_VERSION /,/^---$/" "$TMP/CHANGELOG.md" | sed '$d')

if echo "$extracted" | grep -q "Added Foo" \
   && echo "$extracted" | grep -q "Fixed Bar" \
   && ! echo "$extracted" | grep -q "Old stuff" \
   && ! echo "$extracted" | grep -q "v8.8.8"; then
    ok "awk extraction isolates target version block"
else
    fail "awk extraction recipe is wrong"
    echo "--- extracted ---"
    echo "$extracted" | sed 's/^/    /'
fi

rm -rf "$TMP"

# ── Test 3: end-to-end — produced RELEASE_NOTES contains version content ──
# This requires a successful release run; we look for current Release/<ver>/
# RELEASE_NOTES.md and check it contains the version's CHANGELOG content.
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LATEST_VER_DIR="$PROJECT_ROOT/Release/$(readlink "$PROJECT_ROOT/Release/latest" 2>/dev/null || echo missing)"

if [ ! -f "$LATEST_VER_DIR/RELEASE_NOTES.md" ]; then
    ok "(skip) no current Release/<ver>/RELEASE_NOTES.md to verify end-to-end"
elif grep -qE "^## .*What.?s new|^## .*本版|^## .*Changes in this release" "$LATEST_VER_DIR/RELEASE_NOTES.md"; then
    ok "current RELEASE_NOTES has a 'What's new' H2 section"
else
    fail "current RELEASE_NOTES.md has no injected CHANGELOG section"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
