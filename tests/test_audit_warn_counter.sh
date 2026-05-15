#!/bin/bash
# test_audit_warn_counter.sh — TDD test for warn() ADVISORY counter
# Verifies warn() increments ADVISORY on failure, and summary reports ADVISORY count.
# RED phase: expects these features which are NOT yet implemented.
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT="$SCRIPT_DIR/../scripts/release-audit.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_warn_counter.sh ══"

# --- Test 1: ADVISORY=0 initialisation exists ---
# Must appear near PASS=0 / FAIL=0 / SKIP=0
if grep -q "^ADVISORY=0" "$AUDIT"; then
    ok "ADVISORY=0 initialisation found"
else
    fail "ADVISORY=0 initialisation MISSING — warn() counter not yet implemented"
fi

# --- Test 2: warn() function increments ADVISORY on failure ---
# The else/failure branch of warn() must contain ADVISORY=\$((ADVISORY+1))
# We check the warn() function body for this increment.
if grep -A 10 "^warn()" "$AUDIT" | grep -q 'ADVISORY=\$((ADVISORY+1))'; then
    ok "warn() increments ADVISORY on failure"
else
    fail "warn() does NOT increment ADVISORY on failure — silent failure counter bug present"
fi

# --- Test 3: summary section includes ADVISORY count ---
# The final echo lines must reference \$ADVISORY (e.g. ⚠️\$ADVISORY)
if grep -q '\$ADVISORY' "$AUDIT"; then
    ok "Summary section references \$ADVISORY"
else
    fail "Summary section does NOT reference \$ADVISORY — advisory count invisible to users"
fi

# --- Test 4: ADVISORY is distinct from FAIL (not added to FAIL) ---
# TOTAL formula should NOT include ADVISORY — it's informational only
# Check that TOTAL still uses only PASS + FAIL + SKIP
if grep -qE 'TOTAL=\$\(\(PASS \+ FAIL \+ SKIP\)\)' "$AUDIT"; then
    ok "TOTAL formula unchanged — ADVISORY is informational only (not counted in TOTAL)"
else
    fail "TOTAL formula was changed — ADVISORY must NOT be counted in TOTAL"
fi

# --- Test 5: warn() still increments PASS on success (existing behaviour preserved) ---
if grep -A 10 "^warn()" "$AUDIT" | grep -q 'PASS=\$((PASS+1))'; then
    ok "warn() still increments PASS on success (existing behaviour preserved)"
else
    fail "warn() no longer increments PASS on success — existing behaviour broken"
fi

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
