#!/bin/bash
# test_sanitize_ignore_hardening.sh — RED→GREEN:
# 1) release-sanitize.sh must reject bare wildcard patterns in .sanitize-ignore
# 2) release.sh must NOT bundle .sanitize-ignore into the release artifact
# TDD P0-3
set -euo pipefail

PASS=0; FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANITIZE_SH="$ROOT/scripts/release-sanitize.sh"
RELEASE_SH="$ROOT/scripts/release.sh"

echo "══ test_sanitize_ignore_hardening.sh ══"

# ── Test 1: bare `*` in .sanitize-ignore causes sanitize to abort ──────────
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

# Create a file with an AWS key pattern (detected by scan-credentials.sh AKIA pattern)
echo "AWS_KEY=AKIAIOSFODNN7EXAMPLE" > "$FIXTURE/config.txt"
# Place a bare wildcard allow-list — this should be REJECTED
printf '*\n' > "$FIXTURE/.sanitize-ignore"

if ! "$SANITIZE_SH" "$FIXTURE" >/dev/null 2>&1; then
    ok "release-sanitize.sh: bare '*' in .sanitize-ignore causes abort (exit non-zero)"
else
    fail "release-sanitize.sh: accepted bare '*' in .sanitize-ignore — security bypass possible"
fi

# ── Test 2: bare `**` in .sanitize-ignore also causes abort ─────────────────
printf '**\n' > "$FIXTURE/.sanitize-ignore"
if ! "$SANITIZE_SH" "$FIXTURE" >/dev/null 2>&1; then
    ok "release-sanitize.sh: bare '**' in .sanitize-ignore causes abort"
else
    fail "release-sanitize.sh: accepted bare '**' in .sanitize-ignore — security bypass possible"
fi

# ── Test 2b: near-total bypass patterns also rejected ────────────────────────
for pat in '?*' '?' '*.*' '**/*' '[!x]*'; do
    printf '%s\n' "$pat" > "$FIXTURE/.sanitize-ignore"
    if ! "$SANITIZE_SH" "$FIXTURE" >/dev/null 2>&1; then
        ok "release-sanitize.sh: broad pattern '$pat' rejected"
    else
        fail "release-sanitize.sh: broad pattern '$pat' accepted — near-total bypass possible"
    fi
done

# ── Test 3: valid .sanitize-ignore (specific glob) still works ───────────────
printf 'tests/fixtures/fake_credentials.txt\n' > "$FIXTURE/.sanitize-ignore"
# No credential hits in $FIXTURE (only config.txt which is NOT whitelisted)
if "$SANITIZE_SH" "$FIXTURE" >/dev/null 2>&1; then
    # sanitize should still abort because config.txt is NOT in the ignore list
    fail "release-sanitize.sh: config.txt with credential should have been flagged"
else
    ok "release-sanitize.sh: valid specific-path ignore still flags non-whitelisted files"
fi

# ── Test 4: release.sh must NOT bundle .sanitize-ignore into release dir ─────
# v1.2 A4 refinement (Gotcha #11 surface 3): the original guard was overly
# broad — it flagged ANY `cp .sanitize-ignore` line as a leak risk. But A4
# legitimately copies .sanitize-ignore into the SKILL_STAGE mktemp dir for
# the bundle scan, then rm's it after. mktemp staging is NOT a persistent
# release artifact, so this is safe. Refined check: only flag cp's that
# target a path NOT containing SKILL_STAGE / mktemp / staging / temp.
SUSPECT_CPS=$(grep -E 'cp[^|]*\.sanitize-ignore' "$RELEASE_SH" \
              | grep -vE 'SKILL_STAGE|mktemp|staging|/tmp' || true)
if [ -z "$SUSPECT_CPS" ]; then
    ok "release.sh: cp's .sanitize-ignore only into mktemp staging (Gotcha #11 contract preserved)"
else
    fail "release.sh: copies .sanitize-ignore into a non-temporary path (audit bypass risk)"
    echo "$SUSPECT_CPS" | sed 's/^/    /'
fi

echo ""
echo "──────────────────────────────────────────"
echo "Results: ✅$PASS passed / ❌$FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 test_sanitize_ignore_hardening.sh — ALL GREEN"
    exit 0
else
    echo "💥 test_sanitize_ignore_hardening.sh — FAILURES"
    exit 1
fi
