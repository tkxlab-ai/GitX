#!/bin/bash
# test_release_notes_determinism.sh — RED→GREEN: RELEASE_NOTES.md "Release date:"
# must be derived from CHANGELOG header, not wall-clock date.
# TDD P0-2: date +%Y-%m-%d → grep CHANGELOG | SOURCE_DATE_EPOCH | wall-clock ladder
set -euo pipefail

PASS=0; FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"

echo "══ test_release_notes_determinism.sh ══"

# ── Test 1: wall-clock RELEASE_DATE only used as guarded last-resort fallback ─
# v1.0.7: ${RELEASE_DATE:-$(date +%Y-%m-%d)} unconditional fallback
# v1.0.8 (Arch #4): replaced with explicit `if [ -z "$RELEASE_DATE" ]; then ... fi`
# block that prints a stderr warning before falling back. Either form is
# acceptable as long as the wall-clock date is NOT the first/unconditional
# assignment to RELEASE_DATE.
if grep -qF 'RELEASE_DATE=$(date +%Y-%m-%d)' "$RELEASE_SH"; then
    # Bare assignment exists — verify it's inside an if-block (guarded fallback)
    _block=$(awk '/^[[:space:]]*if \[ -z "?\$\{?RELEASE_DATE/,/^[[:space:]]*fi/' "$RELEASE_SH")
    if echo "$_block" | grep -qF 'RELEASE_DATE=$(date +%Y-%m-%d)'; then
        ok "release.sh: bare wall-clock fallback is guarded by if [ -z \"\$RELEASE_DATE\" ]"
    else
        fail "release.sh: bare RELEASE_DATE=\$(date +%Y-%m-%d) is unconditional"
    fi
else
    ok "release.sh: no bare RELEASE_DATE=\$(date +%Y-%m-%d) direct assignment"
fi

# ── Test 2: RELEASE_DATE derived from root CHANGELOG.md grep ──────────────
if grep -qF 'CHANGELOG.md' "$RELEASE_SH" && \
   grep -qE 'RELEASE_DATE=.*grep|grep.*oE.*[0-9]\{4\}.*CHANGELOG' "$RELEASE_SH"; then
    ok "release.sh: RELEASE_DATE extracted from root CHANGELOG.md via grep"
else
    fail "release.sh: RELEASE_DATE not extracted from root CHANGELOG.md"
fi

# ── Test 3: SOURCE_DATE_EPOCH appears as RELEASE_DATE fallback ─────────────
# Capture awk output first to avoid SIGPIPE with set -o pipefail.
_EPOCH_BLOCK=$(awk '/RELEASE_DATE/,/PROJECT_TITLE/' "$RELEASE_SH")
if echo "$_EPOCH_BLOCK" | grep -qE 'SOURCE_DATE_EPOCH'; then
    ok "release.sh: SOURCE_DATE_EPOCH used as RELEASE_DATE fallback"
else
    fail "release.sh: SOURCE_DATE_EPOCH not near RELEASE_DATE assignment"
fi

echo ""
echo "──────────────────────────────────────────"
echo "Results: ✅$PASS passed / ❌$FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 test_release_notes_determinism.sh — ALL GREEN"
    exit 0
else
    echo "💥 test_release_notes_determinism.sh — FAILURES"
    exit 1
fi
