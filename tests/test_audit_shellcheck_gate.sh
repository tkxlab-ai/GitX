#!/bin/bash
# test_audit_shellcheck_gate.sh — TDD test for §0j: shellcheck CI-parity meta-gate
# Asserts: §0j present, uses -S warning, targets CI triple, non-counting, generic-safe
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT="$SCRIPT_DIR/../scripts/release-audit.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_shellcheck_gate.sh ══"

# --- Test 1: §0j section header present in release-audit.sh ---
if grep -q '§0j' "$AUDIT"; then
    ok "§0j section present in release-audit.sh"
else
    fail "§0j section MISSING in release-audit.sh"
fi

# --- Test 2: uses shellcheck -S warning (CI-exact severity flag) ---
if grep -A 20 '§0j' "$AUDIT" | grep -q 'shellcheck -S warning'; then
    ok "§0j uses 'shellcheck -S warning' (CI-exact)"
else
    fail "§0j does NOT use 'shellcheck -S warning' — severity mismatch vs CI"
fi

# --- Test 3: references the CI triple targets (install.sh + scripts/ + tests/) ---
_sec=$(awk '/§0j/,/^# ---/' "$AUDIT" 2>/dev/null || grep -A 40 '§0j' "$AUDIT")
if echo "$_sec" | grep -q 'install\.sh'; then
    ok "§0j references install.sh (CI target 1)"
else
    fail "§0j does NOT reference install.sh"
fi
if echo "$_sec" | grep -q 'scripts/\*\.sh\|scripts/\\\*\.sh\|scripts/\*.sh'; then
    ok "§0j references scripts/*.sh (CI target 2)"
else
    fail "§0j does NOT reference scripts/*.sh"
fi
if echo "$_sec" | grep -q 'tests/\*\.sh\|tests/\\\*\.sh\|tests/\*.sh'; then
    ok "§0j references tests/*.sh (CI target 3)"
else
    fail "§0j does NOT reference tests/*.sh"
fi

# --- Test 4: NON-counting — §0j must NOT call _track_start with §0j label ---
# The non-counting invariant (Gotcha #62): §0j is a meta-gate like §0i;
# it must not pass through _track_start/_track_end so TOTAL stays unchanged.
if grep -q '_track_start.*§0j\|_track_start "§0j"' "$AUDIT"; then
    fail "§0j calls _track_start — violates non-counting invariant (Gotcha #62)"
else
    ok "§0j is non-counting (no _track_start for §0j)"
fi

# --- Test 5: generic-safe absent-shellcheck SKIP branch present ---
# When shellcheck is absent, §0j must SKIP (not FAIL) for dependent-skill portability
if grep -A 30 '§0j' "$AUDIT" | grep -qE 'command -v shellcheck|which shellcheck'; then
    ok "§0j has absent-shellcheck detection (generic-safe SKIP, Gotcha #51)"
else
    fail "§0j missing absent-shellcheck guard — will FAIL on machines without shellcheck"
fi

# --- Test 6: absent-shellcheck branch emits a ➖ skip line (not ❌ fail) ---
if grep -A 30 '§0j' "$AUDIT" | grep -qE '➖.*shellcheck|shellcheck.*➖|generic.safe.*[Ss]kip|[Ss]kip.*shellcheck'; then
    ok "§0j absent-shellcheck branch emits ➖ SKIP marker"
else
    fail "§0j absent-shellcheck branch does not emit ➖ SKIP marker"
fi

# --- Test 7: CI-parity-contract guard code present in §0j ---
# §0j must contain the ci.yml detection guard so that projects without the
# gitx CI-parity contract get a generic-safe SKIP (Gotcha #51 — a dependent
# skill is never FAILed for a standard it never opted into).
# Verified via static grep (same approach as tests 1-6): the audit exits before
# §0j on a bare scratch dir (§7 sanity aborts with exit 2), so behavioral
# end-to-end is covered by test_release_pipeline_smoke.sh (6/0 green).
_sec7=$(grep -A 60 '§0j' "$AUDIT")
if echo "$_sec7" | grep -q '_has_ci_parity_contract'; then
    ok "§0j has _has_ci_parity_contract guard variable (Gotcha #51)"
else
    fail "§0j missing _has_ci_parity_contract guard — dependent skills will be FAILed unjustly"
fi
if echo "$_sec7" | grep -q '\.github/workflows/ci\.yml'; then
    ok "§0j guard checks .github/workflows/ci.yml (CI-parity contract file)"
else
    fail "§0j guard does not check .github/workflows/ci.yml"
fi
if echo "$_sec7" | grep -qE 'no CI-parity contract|generic.safe SKIP.*dependent skill|dependent skill not held'; then
    ok "§0j guard emits 'no CI-parity contract' SKIP message when contract absent"
else
    fail "§0j guard missing 'no CI-parity contract' SKIP message"
fi

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo PASS || { echo FAIL; exit 1; }
