#!/bin/bash
# §0i deep-audit-exactness — generic non-circular exactness (I1/Decision
# 0019). NON-COUNTING meta-gate (modeled on warn): does NOT touch
# PASS/FAIL/SKIP; on mismatch sets EXACTNESS_FAIL=1 forcing audit exit 1.
# Resolves the Gotcha #26 self-counting paradox. Test mirrors §0f harness.
# v1.10.0-closure: ex() now mirrors §0f full-citation-set (badge + checks +
# PASS); STATIC assertions verify §0i source extracts checks/PASS too.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
A="$ROOT/scripts/release-audit.sh"; B="$ROOT/skills/gitx-release/scripts/release-audit.sh"
PASS=0; FAIL=0
ok(){ echo "  ✅ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_audit_deep_audit_exactness.sh ══"
for a in "$A" "$B"; do [ -f "$a" ] || continue
  lab="$(basename "$(dirname "$(dirname "$a")")")"
  grep -q '§0i' "$a" && grep -q 'EXACTNESS_FAIL' "$a" && ok "§0i exactness gate present ($lab)" || fail "$a missing §0i"
  grep -qF 'deep-audit exactness not applicable' "$a" && ok "§0i generic-safe SKIP phrase ($lab)" || fail "$a §0i no SKIP phrase"
  grep -qF '|| true' "$a" && ok "§0i errexit-safe idiom present ($lab)" || fail "$a §0i not errexit-safe"
  grep -qE '_track_start "§0i' "$a" && fail "$a §0i must be non-counting (no _track_start)" || ok "§0i non-counting: no _track_start ($lab)"
  grep -qE 'check "[^"]*deep-audit exactness' "$a" && fail "$a §0i must not call check (paradox)" || ok "§0i non-counting: no check() ($lab)"
  grep -qE 'EXACTNESS_FAIL.*-eq 0|EXACTNESS_FAIL.*!= *1|EXACTNESS_FAIL\}? *-ne 1' "$a" && ok "§0i wired into final exit ($lab)" || fail "$a EXACTNESS_FAIL not gating exit"
  # STATIC: §0i must extract 'checks' and ' PASS' patterns (full citation set, mirrors §0f)
  dai_block="$(awk '/--- §0i deep-audit-exactness/,/^fi$/{print}' "$a")"
  printf '%s\n' "$dai_block" | grep -qF 'checks' \
    && ok "§0i source extracts 'checks' citations ($lab)" \
    || fail "$a §0i source missing 'checks' extraction (badge-only — FIX A regression)"
  printf '%s\n' "$dai_block" | grep -qF ' PASS' \
    && ok "§0i source extracts ' PASS' citations ($lab)" \
    || fail "$a §0i source missing ' PASS' extraction (badge-only — FIX A regression)"
done
cmp -s "$A" "$B" && ok "dual-source byte-identical" || fail "dual-source drift"
echo "§ behavioral (inline replica of §0i compare — full citation set)"
# Mirrors §0f extraction: badge + N checks + N PASS; unique-sort; SKIP if none;
# MISMATCH if ANY number != total; MATCH only if all present numbers == total.
ex(){ # $1=live total $2=README ; echo MATCH|MISMATCH|SKIP
  local total="$1" rf="$2"
  [ -f "$rf" ] || { echo SKIP; return; }
  local nums
  nums=$( {
    grep -oE 'deep%20audit-[0-9]+%2F[0-9]+%2F[0-9]+' "$rf" 2>/dev/null \
      | grep -oE '^deep%20audit-[0-9]+' | grep -oE '[0-9]+$' || true
    grep -oE '[0-9]+ checks' "$rf" 2>/dev/null | grep -oE '^[0-9]+' || true
    grep -oE '[0-9]+ PASS' "$rf" 2>/dev/null | grep -oE '^[0-9]+' || true
  } | sort -u || true )
  [ -z "$nums" ] && { echo SKIP; return; }
  local bad=""
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    [ "$n" = "$total" ] || bad="$bad $n"
  done <<EOF_EX
$nums
EOF_EX
  [ -z "$bad" ] && echo MATCH || echo MISMATCH
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# badge-only (existing fixture) — total matches
printf '[![Deep Audit](https://img.shields.io/badge/deep%%20audit-230%%2F0%%2F1-x)](y)\n' > "$T/m.md"
# no citation at all
echo '# no audit badge' > "$T/n.md"
# ONLY "240 PASS" (prose/table, no badge) — total 239 → MISMATCH (regression case)
printf '240 PASS\n' > "$T/pass_only.md"
# ONLY "239 checks" — total 239 → MATCH
printf '239 checks\n' > "$T/checks_only.md"
# badge 239 + prose 239 checks + 239 PASS — total 239 → MATCH
printf '[![Deep Audit](https://img.shields.io/badge/deep%%20audit-239%%2F0%%2F0-x)](y)\n239 checks\n239 PASS\n' > "$T/full.md"

[ "$(ex 230 "$T/m.md")" = MATCH ]    && ok "badge cited==total → MATCH" || fail "badge match"
[ "$(ex 231 "$T/m.md")" = MISMATCH ] && ok "badge cited!=total → MISMATCH (would set EXACTNESS_FAIL)" || fail "badge mismatch"
[ "$(ex 230 "$T/n.md")" = SKIP ]     && ok "no citation → SKIP (generic-safe, no flag)" || fail "skip"
[ "$(ex 230 "$T/none.md")" = SKIP ]  && ok "no README → SKIP" || fail "noreadme skip"
# Regression case: ONLY "240 PASS" with total=239 → MISMATCH (old badge-only code missed this)
[ "$(ex 239 "$T/pass_only.md")" = MISMATCH ] && ok "ONLY '240 PASS', total=239 → MISMATCH (FIX A regression gate)" || fail "ONLY-PASS mismatch (FIX A regression missed)"
# "239 checks" with total=239 → MATCH
[ "$(ex 239 "$T/checks_only.md")" = MATCH ]  && ok "ONLY '239 checks', total=239 → MATCH" || fail "checks-only match"
# full set badge+checks+PASS all 239, total=239 → MATCH
[ "$(ex 239 "$T/full.md")" = MATCH ]          && ok "badge+checks+PASS all==total → MATCH" || fail "full set match"

echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && echo PASS && exit 0
echo FAIL; exit 1
