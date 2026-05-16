#!/bin/bash
# test_checksums_sorted.sh — RED→GREEN: checksums.txt must be LC_ALL=C sorted
# for reproducible artifact ordering across different build configurations.
# TDD P1-5
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"
echo "=== test_checksums_sorted: checksums.txt sorted output ==="
# Direct check: the checksums generation line must pipe through LC_ALL=C sort
if grep -qE '\$\{?SHA_CMD\}?[^|]*\|[^|]*LC_ALL=C sort' "$RELEASE_SH"; then
    ok "release.sh: checksums.txt piped through LC_ALL=C sort"
else
    fail "release.sh: checksums.txt not sorted (non-deterministic ordering)"
fi
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
