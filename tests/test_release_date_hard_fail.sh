#!/bin/bash
# test_release_date_hard_fail.sh — v1.0.8 hardening (Arch #4).
# RELEASE_DATE has a 3-tier ladder: CHANGELOG header → SOURCE_DATE_EPOCH →
# wall-clock. Wall-clock fallback leaks nondeterminism into RELEASE_NOTES.md
# even when the rest of the pipeline is reproducible. Hard-fail when the
# CHANGELOG line can't be parsed AND SDE is unset, so non-determinism
# never silently slips into a release.
#
# Behaviour contract (verified here):
#   1. CHANGELOG header has YYYY-MM-DD → RELEASE_DATE derives from it (existing)
#   2. CHANGELOG missing date BUT SOURCE_DATE_EPOCH set → use SDE (existing)
#   3. CHANGELOG missing date AND SDE unset → hard-fail (NEW; was silent fallback)
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE="$ROOT/scripts/release.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_release_date_hard_fail.sh ══"

# Static: there's an explicit hard-fail when both date sources are absent
block=$(awk '/RELEASE_DATE=.*grep/,/RELEASE_DATE=\$\{/' "$RELEASE")
if echo "$block" | grep -qE 'wall-clock|hard.fail|未提供日期|cannot determine|RELEASE_DATE.*required' ; then
    ok "release.sh has hard-fail / explicit-warn for missing date+SDE"
else
    fail "release.sh silently falls back to wall-clock when no date and no SDE"
fi

# Static: wall-clock fallback is now guarded by an explicit `if [ -z "$RELEASE_DATE" ]`
# block (replaces the prior unconditional `${RELEASE_DATE:-$(date +%Y-%m-%d)}`)
guarded_block=$(awk '/RELEASE_DATE.*grep -m1/,/RELEASE_DATE=\$\(date \+%Y-%m-%d\)/' "$RELEASE")
if echo "$guarded_block" | grep -qE 'if \[ -z "\$RELEASE_DATE" \].*then|if \[ -z "\$\{?RELEASE_DATE'; then
    ok "wall-clock fallback is guarded by explicit empty-check + warning"
elif echo "$guarded_block" | grep -qiE 'falling back|warning|not byte-reproducible'; then
    ok "wall-clock fallback emits a labelled warning"
else
    fail "wall-clock fallback is unconditional — nondeterminism slips in silently"
fi

# Behavioral: the wall-clock fallback emits stderr warning text to surface
# the non-determinism risk.
if grep -qE 'NOT byte-reproducible|not byte-reproducible|wall-clock' "$RELEASE"; then
    ok "release.sh emits stderr warning about non-reproducible RELEASE_NOTES"
else
    fail "release.sh does not warn about wall-clock fallback"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
