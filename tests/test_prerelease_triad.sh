#!/bin/bash
# test_prerelease_triad.sh — RED→GREEN: release.sh preflight_checks must
# implement §2.1 pre-release triad: scan source for blocking TODO/FIXME/HACK/XXX.
# TDD P1-8
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"
echo "=== test_prerelease_triad: §2.1 blocking TODO scan ==="
# preflight_checks must run a recursive grep for FIXME/HACK in source .sh files
_BLK=$(awk '/^preflight_checks/,/^}/' "$RELEASE_SH")
if echo "$_BLK" | grep -qE 'grep.*rE?.*FIXME|grep.*rn?.*FIXME'; then
    ok "release.sh preflight_checks: recursive FIXME/HACK source scan present"
else
    fail "release.sh preflight_checks: missing §2.1 recursive FIXME/HACK scan"
fi
# Scan must exclude scripts/ specifically (prevents self-referencing variable names)
if echo "$_BLK" | grep -qF 'exclude-dir=scripts' && echo "$_BLK" | grep -qF 'FIXME'; then
    ok "release.sh preflight_checks: --exclude-dir=scripts guards against self-reference"
else
    fail "release.sh preflight_checks: FIXME scan missing --exclude-dir=scripts guard"
fi
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
