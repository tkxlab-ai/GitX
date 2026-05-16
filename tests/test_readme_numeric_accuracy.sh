#!/bin/bash
# test_readme_numeric_accuracy.sh — v1.9.8 strong per-repo README guard.
#
# §0f (release-audit.sh) is the generic cross-project CONSISTENCY floor
# (badge=prose=table agree). This is the STRONGER repo-local guard: the
# README's exact numeric claims must match the LIVE codebase —
#   • exact "N BDD suites" / "N / 0 fail" == real run_all suite count
#   • Deep-Audit citations internally consistent (badge=prose=table)
#   • no non-green audit advertised on a public README
# for BOTH README.md and README_CN.md. Root cause: every v1.9.x release
# only bumped the metrics-line version token; badges / suite counts /
# audit numbers / What's New silently rotted (94 vs 95, badge 227 vs 228,
# CN 90+ vs EN 95+) and shipped to the public mirror.
#
# exit: 0=all pass, 1=any fail
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_readme_numeric_accuracy.sh ══"

# Live suite count — exactly how run_all.sh discovers suites (non-recursive:
# count files, never execute run_all from inside a suite). run_all EXCLUDE
# = run_all.sh|test_suite_structure.sh; run_all.sh is not test_*.sh.
SUITES=$(ls "$SCRIPT_DIR"/test_*.sh 2>/dev/null | grep -vc 'test_suite_structure\.sh' || echo 0)
echo "  live suite count (test_*.sh minus meta): $SUITES"

for rf in "$ROOT/README.md" "$ROOT/README_CN.md"; do
    [ -f "$rf" ] || { fail "$(basename "$rf") missing"; continue; }
    b="$(basename "$rf")"

    # 1) exact "N BDD suites" / "N BDD 套件" / "N / 0 fail" must == live count.
    #    '+'-suffixed soft claims (e.g. 95+) are checked separately (≤ live).
    bad=0
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        [ "$n" -eq "$SUITES" ] || { bad=1; echo "    stale exact suite number $n (live $SUITES) in $b"; }
    done < <(grep -oE '[0-9]+ (BDD suites|BDD 套件)' "$rf" 2>/dev/null | grep -ovE '\+ ' | grep -oE '^[0-9]+')
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        [ "$n" -eq "$SUITES" ] || { bad=1; echo "    stale '$n / 0 fail' (live $SUITES) in $b"; }
    done < <(grep -oE '[0-9]+ / 0 fail' "$rf" 2>/dev/null | grep -oE '^[0-9]+')
    [ "$bad" -eq 0 ] && ok "$b exact suite numbers == live ($SUITES)" \
        || fail "$b has stale exact suite number(s) — must equal live $SUITES"

    # 2) soft '+'-claims must not overstate (claimed+ ≤ live)
    soft_bad=0
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        [ "$n" -le "$SUITES" ] || { soft_bad=1; echo "    overstated '${n}+' > live $SUITES in $b"; }
    done < <(grep -oE '[0-9]+\+ ?(BDD suites|BDD 套件)' "$rf" 2>/dev/null | grep -oE '^[0-9]+')
    [ "$soft_bad" -eq 0 ] && ok "$b soft 'N+' suite claims not overstated" \
        || fail "$b soft suite claim overstates live $SUITES"

    # 3) Deep-Audit citations internally consistent (badge=prose=table)
    nums=$( {
        grep -oE 'deep%20audit-[0-9]+%2F[0-9]+%2F[0-9]+' "$rf" | grep -oE '^deep%20audit-[0-9]+' | grep -oE '[0-9]+$'
        grep -oE '[0-9]+ checks' "$rf" | grep -oE '^[0-9]+'
        grep -oE '[0-9]+ PASS' "$rf" | grep -oE '^[0-9]+'
    } | sort -u )
    if [ "$(printf '%s\n' "$nums" | grep -c .)" -le 1 ]; then
        ok "$b Deep-Audit citations agree ($(printf '%s' "$nums" | tr '\n' ' '))"
    else
        fail "$b Deep-Audit citations disagree: $(printf '%s' "$nums" | tr '\n' ' ')"
    fi

    # 4) public README must not advertise a non-green audit
    grep -qE '[1-9][0-9]* FAIL' "$rf" \
        && fail "$b advertises a non-green Deep Audit (N FAIL > 0)" \
        || ok "$b advertises 0-FAIL (green) audit"
done

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
