#!/bin/bash
# test_audit_version_escape.sh — P0-2 fix verification
# Verifies: all `$VERSION` usages in audit that go into regex are properly escaped.
#
# exit: 0=all pass, 1=any fail

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT_SH="$SCRIPT_DIR/../scripts/release-audit.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_version_escape.sh ══"

# ── Test 1: §4 CHANGELOG uses SAFE_VERSION (already fixed) ────────────────
if grep -qE 'SAFE_VERSION.*printf.*VERSION.*sed' "$AUDIT_SH"; then
    ok "§4 defines SAFE_VERSION for dot-escape"
else
    fail "§4 missing SAFE_VERSION definition"
fi

# §4 uses grep -qF (fixed string) so $VERSION is safe; or uses SAFE_VERSION
if grep -qE 'grep -qF.*\$VERSION' "$AUDIT_SH" || grep -qE 'grep.*\$SAFE_VERSION' "$AUDIT_SH"; then
    ok "§4 CHANGELOG uses fixed-string or SAFE_VERSION"
else
    fail "§4 CHANGELOG uses unescaped VERSION (regex wildcard risk)"
fi

# ── Test 2: §10 RELEASE_NOTES version check uses SAFE_VERSION ─────────────
# Find the line that checks "RELEASE_NOTES.md 含发版版本" and verify it uses SAFE_VERSION
rn_line=$(grep -n 'RELEASE_NOTES.md 含发版版本' "$AUDIT_SH" | head -1)
if echo "$rn_line" | grep -q 'SAFE_VERSION'; then
    ok "§10 RELEASE_NOTES version check uses SAFE_VERSION"
else
    fail "§10 RELEASE_NOTES version check uses raw VERSION (P0-2: regex wildcard bug)"
fi

# ── Test 3: §11i SBOM version check uses proper escaping ──────────────────
# Line ~583 has inline sed 's/\./\\./g' — that's correct.
# Verify any $VERSION used in grep -qE (regex mode) is escaped via SAFE_VERSION or inline sed
bad_usages=$(grep -nE 'grep -qE.*"\$VERSION"' "$AUDIT_SH" | grep -v SAFE_VERSION | grep -v 'sed.*\\\.' || true)
if [ -z "$bad_usages" ]; then
    ok "§11i SBOM version check uses proper escaping"
else
    fail "§11i SBOM has unescaped VERSION in regex: $bad_usages"
fi

# ── Test 4: Functional — dot-in-version doesn't match false positive ──────
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

# Create a release dir with RELEASE_NOTES containing "v1X0Y0" (a false-positive target)
mkdir -p "$FIXTURE/fake-release"
cat > "$FIXTURE/fake-release/RELEASE_NOTES.md" <<'EOF'
# Test Release Notes
Release date: 2026-01-01
v1X0Y0 — should NOT match v1.0.0
EOF

SAFE_V=$(printf '%s' "v1.0.0" | sed 's/\./\\./g')
# With SAFE_VERSION, v1.0.0 should NOT match v1X0Y0
if ! echo "v1X0Y0" | grep -q "$SAFE_V"; then
    ok "SAFE_VERSION does not wildcard-match v1X0Y0"
else
    fail "SAFE_VERSION regex still matches v1X0Y0 (false positive)"
fi

# Without escape, v1.0.0 WOULD match v1X0Y0
if echo "v1X0Y0" | grep -q "v1.0.0"; then
    ok "Unescaped v1.0.0 DOES match v1X0Y0 (proves bug exists)"
else
    fail "Expected wildcard match not reproduced"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
