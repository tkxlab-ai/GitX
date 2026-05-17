#!/bin/bash
# §0g readme-sync — TDD mirrors test_audit_doc_numeric_rot.sh (§0f):
# STATIC source assertions + BEHAVIORAL via the standalone gitx-readme
# (no build, no release-audit --inline → bootstrap-safe, Gotcha #47).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
A="$ROOT/scripts/release-audit.sh"; B="$ROOT/skills/gitx-release/scripts/release-audit.sh"
GR="$ROOT/scripts/gitx-readme.sh"
PASS=0; FAIL=0
ok(){ echo "  ✅ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_audit_readme_sync.sh ══"
for a in "$A" "$B"; do [ -f "$a" ] || continue
  lab="$(basename "$(dirname "$(dirname "$a")")")"
  grep -qE '^audit_section_0_readme_sync\(\)' "$a" \
   && grep -q '_track_start "§0g_readme_sync"' "$a" \
   && grep -q '_track_end "§0g_readme_sync"' "$a" \
   && grep -q '§0g' "$a" && ok "§0g gate present ($lab)" || fail "$a missing §0g"
  g0g="$(awk '/^audit_section_0_readme_sync\(\)/,/_track_end "§0g_readme_sync"/' "$a")"
  printf '%s\n' "$g0g" | grep -qF 'SKIP=$((SKIP+1))' \
   && printf '%s\n' "$g0g" | grep -qE 'if \[ ! -f "\$rf" \] \|\| ! grep -qF' \
   && ok "§0g SKIP+errexit-safe idiom present, §0g-scoped ($lab)" || fail "$a §0g not generic/errexit-safe (scoped)"
done
cmp -s "$A" "$B" && ok "release-audit.sh dual-source byte-identical" || fail "dual-source drift"
ag=$(grep -n 'audit_section_0_readme_sync' "$A"|head -1|cut -d: -f1)
af=$(grep -n 'audit_section_0_doc_numeric_rot' "$A"|head -1|cut -d: -f1)
[ "$ag" -gt "$af" ] && ok "§0g after §0f" || fail "§0g ordering"
echo "§ behavioral (standalone gitx-readme, no audit run)"
mk(){ mkdir -p "$1/tests"; : > "$1/tests/test_suite_structure.sh"; : > "$1/tests/test_a.sh"; echo v1.0.0 > "$1/VERSION"; }
D1="$(mktemp -d)"; mk "$D1"; ( cd "$D1" && bash "$GR" --init --force >/dev/null 2>&1 )
( cd "$D1" && bash "$GR" --check >/dev/null 2>&1 ) && ok "in-sync adopted README → --check 0 (§0g would PASS)" || fail "in-sync false-drift"
D2="$(mktemp -d)"; mk "$D2"; ( cd "$D2" && bash "$GR" --init --force >/dev/null 2>&1 )
( cd "$D2" && perl -0pi -e 's{(<!-- gitx:managed:suite-count -->\n).*?(\n<!-- /gitx:managed:suite-count -->)}{${1}999STALE${2}}s' README.md )
( cd "$D2" && bash "$GR" --check >/dev/null 2>&1; [ $? -eq 1 ] ) && ok "stale managed region → --check 1 (§0g would FAIL)" || fail "managed drift not caught"
D2b="$(mktemp -d)"; mk "$D2b"; ( cd "$D2b" && bash "$GR" --init --force >/dev/null 2>&1 && printf '\nunmanaged prose edit\n' >> README.md )
( cd "$D2b" && bash "$GR" --check >/dev/null 2>&1 ) && ok "unmanaged-prose edit → --check 0 (§0g PASS, projen contract)" || fail "§0g false-FAIL on unmanaged prose"
D2c="$(mktemp -d)"; mk "$D2c"; ( cd "$D2c" && bash "$GR" --init --force >/dev/null 2>&1 )
# stale whats-new (simulate CHANGELOG advanced but README not regenerated)
( cd "$D2c" && perl -0pi -e 's{(<!-- gitx:managed:whats-new -->\n).*?(\n<!-- /gitx:managed:whats-new -->)}{${1}STALE-WN${2}}s' README.md )
( cd "$D2c" && bash "$GR" --check >/dev/null 2>&1; [ $? -eq 1 ] ) && ok "stale whats-new → --check 1 (§0g would FAIL, generic for dependent skills)" || fail "whats-new drift not caught"
D2d="$(mktemp -d)"; mk "$D2d"; ( cd "$D2d" && bash "$GR" --init --force >/dev/null 2>&1 )
( cd "$D2d" && perl -0pi -e 's{(<!-- gitx:managed:command-surface -->\n).*?(\n<!-- /gitx:managed:command-surface -->)}{${1}STALE-CS${2}}s' README.md )
( cd "$D2d" && bash "$GR" --check >/dev/null 2>&1; [ $? -eq 1 ] ) && ok "stale command-surface → --check 1 (§0g would FAIL)" || fail "command-surface drift not caught"
D3="$(mktemp -d)"; mk "$D3"; echo '# no markers' > "$D3/README.md"
( cd "$D3" && bash "$GR" --check >/dev/null 2>&1 ) && ok "no-marker README → --check 0 (§0g SKIPs, generic-safe)" || fail "no-marker false-fail"
grep -qF 'source README has no gitx:managed regions — readme-sync not applicable' "$A" && ok "§0g generic-safe SKIP phrase present" || fail "§0g missing SKIP phrase"
grep -qF 'cd "$PROJECT_ROOT" && bash "$PROJECT_ROOT/scripts/gitx-readme.sh" --check' "$A" && ok "§0g checks source tree not \$DIR (NEW-C1 fix)" || fail "§0g still targets \$DIR — NEW-C1 regressed"
rm -rf "$D1" "$D2" "$D2b" "$D2c" "$D2d" "$D3"
# STATIC: §0g shebang check must NOT string-interpolate $gr into bash -c
# (FIX C: path-quote injection risk in newly added code; §0c-§0e are
# out-of-scope pre-existing; only this §0g instance is targeted).
echo "§ §0g shebang check safe arg-passing (FIX C)"
for a in "$A" "$B"; do [ -f "$a" ] || continue
  lab="$(basename "$(dirname "$(dirname "$a")")")"
  g0g_block="$(awk '/--- §0g readme-sync/,/_track_end "§0g_readme_sync"/{print}' "$a")"
  # Safe form: bash -c '...' _ "$gr"  (path as positional arg, not interpolated)
  printf '%s\n' "$g0g_block" | grep -qF "bash -c 'head -1" \
    && ok "§0g uses safe bash -c '...' arg form ($lab)" \
    || fail "§0g missing safe arg-passing form ($lab) — FIX C not applied"
  # Unsafe form must be absent: "head -1 '$gr'"  (string interpolation of path)
  printf '%s\n' "$g0g_block" | grep -qF "head -1 '\$gr'" \
    && fail "§0g still contains unsafe string-interpolated path in bash -c ($lab)" \
    || ok "§0g no unsafe string-interpolated path in bash -c ($lab)"
done
echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && echo PASS && exit 0
echo FAIL; exit 1
