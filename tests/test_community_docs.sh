#!/bin/bash
# test_community_docs.sh — GitHub community health files + flatten contract
# Asserts:
#   - CODE_OF_CONDUCT.md and SECURITY.md exist at project root
#   - Each file has required sections (Covenant pledge / reporting channel)
#   - release.sh flatten loop includes both files
# exit: 0=all pass, 1=any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_community_docs.sh ══"

# ── Test 1: CODE_OF_CONDUCT.md exists ─────────────────────────────────────
if [ -f "$ROOT/CODE_OF_CONDUCT.md" ]; then
    ok "CODE_OF_CONDUCT.md exists at project root"
else
    fail "CODE_OF_CONDUCT.md missing at project root"
fi

# ── Test 2: CODE_OF_CONDUCT.md references Contributor Covenant ────────────
if [ -f "$ROOT/CODE_OF_CONDUCT.md" ] && grep -qiE 'contributor covenant|行为准则' "$ROOT/CODE_OF_CONDUCT.md"; then
    ok "CODE_OF_CONDUCT.md references Contributor Covenant / 行为准则"
else
    fail "CODE_OF_CONDUCT.md missing Contributor Covenant / 行为准则 reference"
fi

# ── Test 3: SECURITY.md exists ────────────────────────────────────────────
if [ -f "$ROOT/SECURITY.md" ]; then
    ok "SECURITY.md exists at project root"
else
    fail "SECURITY.md missing at project root"
fi

# ── Test 4: SECURITY.md has a reporting channel ───────────────────────────
if [ -f "$ROOT/SECURITY.md" ] && grep -qiE 'report|邮箱|contact|email|@' "$ROOT/SECURITY.md"; then
    ok "SECURITY.md contains a reporting channel"
else
    fail "SECURITY.md missing reporting channel"
fi

# ── Test 5: release.sh flatten loop includes CODE_OF_CONDUCT.md ───────────
if grep -qE 'CODE_OF_CONDUCT\.md' "$ROOT/scripts/release.sh"; then
    ok "release.sh flatten includes CODE_OF_CONDUCT.md"
else
    fail "release.sh flatten MISSING CODE_OF_CONDUCT.md"
fi

# ── Test 6: release.sh flatten loop includes SECURITY.md ──────────────────
if grep -qE 'SECURITY\.md' "$ROOT/scripts/release.sh"; then
    ok "release.sh flatten includes SECURITY.md"
else
    fail "release.sh flatten MISSING SECURITY.md"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
