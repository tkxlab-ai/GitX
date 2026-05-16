#!/bin/bash
# test_no_force_bypass.sh — S3-1 policy: FORCE=1 bypass removed; use .sanitize-ignore instead
# Asserts:
#   - release.sh no longer has FORCE=1 bypass branches for sanitize failure
#   - release-sanitize.sh honors a `.sanitize-ignore` whitelist file
#   - Sanitize help text / references mention .sanitize-ignore
# exit: 0=all pass, 1=any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
RELEASE_SH="$ROOT/scripts/release.sh"
SANITIZE_SH="$ROOT/scripts/release-sanitize.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_no_force_bypass.sh ══"

# ── Test 1: release.sh has NO "FORCE=1" bypass branch ────────────────────
# The old pattern looked like `if [ "${FORCE:-0}" != "1" ]; then exit 1; fi`
if grep -qE 'FORCE:-0|FORCE=1 设置' "$RELEASE_SH"; then
    fail "release.sh still contains FORCE bypass logic (S3-1 violation)"
else
    ok "release.sh has no FORCE=1 bypass (S3-1 compliant)"
fi

# ── Test 2: release.sh header comment no longer advertises FORCE env ─────
if grep -qE '^#.*FORCE[[:space:]]+default' "$RELEASE_SH"; then
    fail "release.sh header still documents FORCE env var"
else
    ok "release.sh header no longer documents FORCE env var"
fi

# ── Test 3: release-sanitize.sh reads .sanitize-ignore ───────────────────
if grep -qE '\.sanitize-ignore' "$SANITIZE_SH"; then
    ok "release-sanitize.sh references .sanitize-ignore"
else
    fail "release-sanitize.sh does NOT reference .sanitize-ignore"
fi

# ── Test 4: Functional — .sanitize-ignore actually filters findings ──────
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Seed a deliberate finding: a real-looking email in a .md file
mkdir -p "$TMP/docs"
cat > "$TMP/docs/leak.md" <<EOF
Contact: realperson@gmail.com
EOF
# Without ignore file, sanitize should flag it
if bash "$SANITIZE_SH" "$TMP" >/dev/null 2>&1; then
    fail "baseline: sanitize missed planted email (test fixture broken)"
else
    ok "baseline: sanitize catches planted email without ignore file"
fi
# With .sanitize-ignore whitelisting the offending path, sanitize should pass
cat > "$TMP/.sanitize-ignore" <<EOF
# Whitelist test fixture
docs/leak.md
EOF
if bash "$SANITIZE_SH" "$TMP" >/dev/null 2>&1; then
    ok ".sanitize-ignore whitelisting filters the finding"
else
    fail ".sanitize-ignore did NOT filter the whitelisted path"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
