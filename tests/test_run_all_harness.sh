#!/bin/bash
# test_run_all_harness.sh — behavioural test for tests/run_all.sh
# A green gate must mean every suite really ran and really passed: run_all
# isolates each suite (env -i allowlist, private TMPDIR) and derives its
# verdict from both the exit code and the summary line, so a silent abort,
# a lying summary or a zero-assertion suite can no longer count as green.
# Each case runs a copy of run_all.sh against throwaway fixture suites.
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_run_all_harness.sh ══"

T=$(mktemp -d "${TMPDIR:-/tmp}/run_all_harness.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir "$T/tests"
cp "$SCRIPT_DIR/run_all.sh" "$T/tests/run_all.sh"

# mkfx NAME — fixture body from stdin becomes $T/tests/test_fx_NAME.sh
mkfx() { cat > "$T/tests/test_fx_$1.sh"; }

# run_fx — run the copied run_all under a fresh parent dir; sets R and rc.
# A private R per invocation keeps dirs retained by red runs out of later cases.
run_fx() {
    R=$(mktemp -d "$T/case.XXXXXX")
    # run_all pins RUN_TMP with `pwd`, which folds the `//` a trailing-slash
    # TMPDIR (macOS default) leaves in R; fold R the same way so prefixes match.
    R=$(cd "$R" && pwd)
    TMPDIR="$R" bash "$T/tests/run_all.sh" >"$R/out" 2>&1 && rc=0 || rc=$?
    rm -f "$T"/tests/test_fx_*.sh
}

good_fixture() {
    mkfx good <<'EOF'
echo "Results: ✅2 passed / ❌0 failed"
exit 0
EOF
}

# --- Case 1: a passing suite is reported with its assertion count ---
good_fixture
run_fx
if [ "$rc" -eq 0 ] && grep -qF "✅ test_fx_good.sh — 2 passed" "$R/out"; then
    ok "good suite → rc=0 and '— 2 passed'"
else
    fail "good suite → rc=$rc, expected 0 with '✅ test_fx_good.sh — 2 passed'"
fi

# --- Case 2: exit 0 without a summary line is a silent abort ---
mkfx silent <<'EOF'
exit 0
EOF
run_fx
if [ "$rc" -eq 1 ] && grep -qF "no summary line" "$R/out"; then
    ok "silent suite → rc=1 'no summary line'"
else
    fail "silent suite → rc=$rc, expected 1 with 'no summary line'"
fi

# --- Case 3: summary reports failures but the suite exits 0 ---
mkfx liar <<'EOF'
echo "Results: ✅1 passed / ❌1 failed"
exit 0
EOF
run_fx
if [ "$rc" -eq 1 ] && grep -qF "summary reports 1 failed but exit 0" "$R/out"; then
    ok "liar suite → rc=1 'summary reports 1 failed but exit 0'"
else
    fail "liar suite → rc=$rc, expected 1 with 'summary reports 1 failed but exit 0'"
fi

# --- Case 4: zero assertions is vacuous, not green ---
mkfx vacuous <<'EOF'
echo "Results: ✅0 passed / ❌0 failed"
exit 0
EOF
run_fx
if [ "$rc" -eq 1 ] && grep -qF "vacuous" "$R/out"; then
    ok "vacuous suite → rc=1 'vacuous'"
else
    fail "vacuous suite → rc=$rc, expected 1 with 'vacuous'"
fi

# --- Case 4a: an all-skipped suite is not vacuous (emoji and word forms) ---
mkfx skipper_emoji <<'EOF'
echo "Results: ✅0 passed / ❌0 failed / ➖2 skipped"
exit 0
EOF
run_fx
if [ "$rc" -eq 0 ]; then
    ok "skipped (➖2) suite → rc=0"
else
    fail "skipped (➖2) suite → rc=$rc, expected 0"
fi

mkfx skipper_word <<'EOF'
echo "SUMMARY: 0 passed, 0 failed, 1 skipped"
exit 0
EOF
run_fx
if [ "$rc" -eq 0 ]; then
    ok "skipped ('1 skipped') suite → rc=0"
else
    fail "skipped ('1 skipped') suite → rc=$rc, expected 0"
fi

# --- Case 4b: 'PASS N / M' form — failures are M-N ---
mkfx passform_ok <<'EOF'
echo "PASS 3 / 3"
exit 0
EOF
run_fx
if [ "$rc" -eq 0 ]; then
    ok "'PASS 3 / 3' suite → rc=0"
else
    fail "'PASS 3 / 3' suite → rc=$rc, expected 0"
fi

mkfx passform_bad <<'EOF'
echo "PASS 2 / 3"
exit 0
EOF
run_fx
if [ "$rc" -eq 1 ] && grep -qF "summary reports 1 failed" "$R/out"; then
    ok "'PASS 2 / 3' suite → rc=1 'summary reports 1 failed'"
else
    fail "'PASS 2 / 3' suite → rc=$rc, expected 1 with 'summary reports 1 failed'"
fi

# --- Case 4c: digits before the ✅ are not counts ---
mkfx digits_before <<'EOF'
echo "Results for v1.2: ✅3 passed / ❌0 failed"
exit 0
EOF
run_fx
if [ "$rc" -eq 0 ] && grep -qF "— 3 passed" "$R/out"; then
    ok "digits before ✅ → rc=0 '— 3 passed'"
else
    fail "digits before ✅ → rc=$rc, expected 0 with '— 3 passed'"
fi

# --- Case 5: non-zero exit after a passing summary fails; next suite still runs ---
mkfx a_rc7 <<'EOF'
echo "Results: ✅1 passed / ❌0 failed"
exit 7
EOF
good_fixture
run_fx
last=$(tail -1 "$R/out")
prev=$(tail -2 "$R/out" | head -1)
if [ "$rc" -eq 1 ] \
    && grep -qF "test_fx_a_rc7.sh FAILED (rc=7)" "$R/out" \
    && grep -qF "✅ test_fx_good.sh — 2 passed" "$R/out" \
    && [ "$last" = "❌ 1 test suite(s) FAILED" ] \
    && case "$prev" in "Suite Results: ✅1 suites passed / ❌1"*) true ;; *) false ;; esac; then
    ok "rc=7 suite → 'FAILED (rc=7)', next suite still runs, trailer counts 1/1"
else
    fail "rc=7 suite → rc=$rc, last='$last', prev='$prev'"
fi

# --- Case 6: caller env does not leak into suites ---
mkfx envleak <<'EOF'
echo "ENV=${PROJECT_ROOT:-unset}"
echo "Results: ✅1 passed / ❌0 failed"
exit 0
EOF
export PROJECT_ROOT=/leak
run_fx
unset PROJECT_ROOT
if grep -qxF "ENV=unset" "$R/out"; then
    ok "PROJECT_ROOT exported by caller is not visible to suites"
else
    fail "PROJECT_ROOT leaked into suite env"
fi

# --- Case 7: each suite gets a private TMPDIR, removed after a green run ---
mkfx tmpdir <<'EOF'
echo "TMP=$TMPDIR"
touch "$TMPDIR/marker"
echo "Results: ✅1 passed / ❌0 failed"
exit 0
EOF
run_fx
tmpval=$(sed -n 's/^TMP=//p' "$R/out")
if [ "$rc" -eq 0 ] \
    && case "$tmpval" in "$R/gitx-tests."*) true ;; *) false ;; esac \
    && [ ! -d "$tmpval" ] \
    && ! ls -d "$R"/gitx-tests.* >/dev/null 2>&1; then
    ok "suite TMPDIR under \$R/gitx-tests.* and cleaned after green run"
else
    fail "suite TMPDIR='$tmpval' (rc=$rc) not private or not cleaned"
fi

# --- Case 8: a red run keeps the log and the suite TMPDIR for inspection ---
mkfx red_keeps <<'EOF'
echo "TMP=$TMPDIR"
echo "Results: ✅0 passed / ❌1 failed"
exit 1
EOF
run_fx
tmpval=$(sed -n 's/^TMP=//p' "$R/out")
logpath=$(sed -n 's/.*→ log: //p' "$R/out")
last=$(tail -1 "$R/out")
prev=$(tail -2 "$R/out" | head -1)
if [ "$rc" -eq 1 ] \
    && grep -qF "kept for inspection: " "$R/out" \
    && case "$logpath" in "$R/"*) [ -f "$logpath" ] ;; *) false ;; esac \
    && case "$tmpval" in "$R/"*) [ -d "$tmpval" ] ;; *) false ;; esac \
    && [ "$last" = "❌ 1 test suite(s) FAILED" ] \
    && [ "$prev" = "Suite Results: ✅0 suites passed / ❌1 suites failed" ]; then
    ok "red run keeps log + TMPDIR and ends with the two anchor lines"
else
    fail "red run → rc=$rc, log='$logpath', tmp='$tmpval', last='$last'"
fi

# --- Case 9: test_suite_structure.sh is excluded (it would recurse) ---
cat > "$T/tests/test_suite_structure.sh" <<'EOF'
exit 1
EOF
good_fixture
run_fx
rm -f "$T/tests/test_suite_structure.sh"
if [ "$rc" -eq 0 ]; then
    ok "test_suite_structure.sh excluded from discovery"
else
    fail "test_suite_structure.sh was run (rc=$rc)"
fi

# --- Case 10: a relative TMPDIR is pinned to an absolute RUN_TMP ---
mkfx tmprel <<'EOF'
cd /
echo "TMP=$TMPDIR"
touch "$TMPDIR/marker" || exit 3
echo "Results: ✅1 passed / ❌0 failed"
exit 0
EOF
R=$(mktemp -d "$T/case.XXXXXX")
mkdir "$R/rel"
( cd "$R" && TMPDIR=rel bash "$T/tests/run_all.sh" ) >"$R/out" 2>&1 && rc=0 || rc=$?
rm -f "$T"/tests/test_fx_*.sh
tmpval=$(sed -n 's/^TMP=//p' "$R/out")
if [ "$rc" -eq 0 ] && case "$tmpval" in /*) true ;; *) false ;; esac; then
    ok "relative TMPDIR → rc=0 and suite TMPDIR is absolute ($tmpval)"
else
    fail "relative TMPDIR → rc=$rc, suite TMPDIR='$tmpval' (want absolute)"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ]
