#!/bin/bash
# test_checksums.sh — checksums.txt generation + audit contract
# Asserts:
#   - release.sh emits checksums.txt after building .skill + tarball
#   - release-audit.sh §11h verifies checksums.txt presence + sha256 match
# exit: 0=all pass, 1=any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
RELEASE_SH="$ROOT/scripts/release.sh"
AUDIT_SH="$ROOT/scripts/release-audit.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_checksums.sh ══"

# ── Test 1: release.sh writes checksums.txt ──────────────────────────────
if grep -qE 'checksums\.txt' "$RELEASE_SH"; then
    ok "release.sh references checksums.txt"
else
    fail "release.sh MISSING checksums.txt emission"
fi

# ── Test 2: release.sh uses shasum or sha256sum ──────────────────────────
if grep -qE 'shasum|sha256sum' "$RELEASE_SH"; then
    ok "release.sh uses shasum / sha256sum for hashing"
else
    fail "release.sh MISSING sha256 hashing tool"
fi

# ── Test 3: checksums include .skill, tarball, install.sh ────────────────
# Look at the 30 lines following the first `checksums.txt` mention for all three artifacts.
WINDOW=$(grep -A 30 'checksums\.txt' "$RELEASE_SH" | head -40)
if echo "$WINDOW" | grep -q '\.skill' \
   && echo "$WINDOW" | grep -qE 'tar\.gz|TAR_OUT' \
   && echo "$WINDOW" | grep -q 'install\.sh'; then
    ok "release.sh hashes .skill + tarball + install.sh"
else
    fail "release.sh checksums.txt does not cover all three artifacts"
fi

# ── Test 4: audit.sh checks for checksums.txt presence ───────────────────
if grep -qE 'checksums\.txt' "$AUDIT_SH"; then
    ok "release-audit.sh references checksums.txt"
else
    fail "release-audit.sh MISSING checksums.txt check"
fi

# ── Test 5: audit.sh verifies hash (not just existence) ──────────────────
if grep -qE 'shasum -c|sha256sum -c|shasum.*--check|sha256sum.*--check' "$AUDIT_SH"; then
    ok "release-audit.sh verifies sha256 digests (shasum -c / sha256sum -c)"
else
    fail "release-audit.sh does NOT verify checksum digests"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
