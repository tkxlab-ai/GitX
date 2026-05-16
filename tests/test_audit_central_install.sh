#!/bin/bash
# §0h central-install — TDD: STATIC source-grep + BEHAVIORAL via inline
# replication of the §0h grep logic against fixtures (no audit run).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
A="$ROOT/scripts/release-audit.sh"; B="$ROOT/skills/gitx-release/scripts/release-audit.sh"
PASS=0; FAIL=0
ok(){ echo "  ✅ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_audit_central_install.sh ══"
for a in "$A" "$B"; do [ -f "$a" ] || continue
  lab="$(basename "$(dirname "$(dirname "$a")")")"
  grep -qE '^audit_section_0_central_install\(\)' "$a" \
   && grep -q '_track_start "§0h_central_install"' "$a" \
   && grep -q '_track_end "§0h_central_install"' "$a" && ok "§0h gate present ($lab)" || fail "$a missing §0h"
  grep -qF 'SKIP=$((SKIP+1))' "$a" && ok "§0h SKIP path ($lab)" || fail "$a §0h no SKIP"
  h0h="$(awk '/^audit_section_0_central_install\(\)/,/_track_end "§0h_central_install"/' "$a")"
  printf '%s\n' "$h0h" | grep -qF 'bash -c' && fail "$a §0h uses bash -c (injection risk, ${name} from downstream manifest)" || ok "§0h injection-safe: no bash -c ($lab)"
done
cmp -s "$A" "$B" && ok "dual-source byte-identical" || fail "dual-source drift"
ah=$(grep -n audit_section_0_central_install "$A"|head -1|cut -d: -f1)
ag=$(grep -n audit_section_0_readme_sync "$A"|head -1|cut -d: -f1)
[ "$ah" -gt "$ag" ] && ok "§0h after §0g" || fail "§0h ordering"
grep -qF 'central-install not applicable' "$A" && ok "§0h generic-safe SKIP phrase present" || fail "§0h missing SKIP phrase"
echo "§ behavioral (inline replica of §0h logic)"
chk(){ # $1=plugin.json path or '' ; $2=README ; expect $3 = PASS|FAIL|SKIP
  local pj="$1" rf="$2"
  if [ ! -f "$pj" ] || [ ! -f "$rf" ]; then echo SKIP; return; fi
  local n; n="$(grep -m1 '"name"' "$pj" 2>/dev/null | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
  if grep -qF '/plugin marketplace add tkxlab-ai/marketplace' "$rf" && grep -qF "/plugin install ${n}@tkx-skills" "$rf"; then echo PASS; else echo FAIL; fi
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/p"; printf '{\n  "name": "demoh"\n}\n' > "$T/p/plugin.json"
printf '# demoh\n```bash\n/plugin marketplace add tkxlab-ai/marketplace\n/plugin install demoh@tkx-skills\n```\n' > "$T/good.md"
echo '# demoh no block' > "$T/bad.md"
[ "$(chk "$T/p/plugin.json" "$T/good.md")" = PASS ] && ok "plugin + central block → PASS" || fail "good→PASS"
[ "$(chk "$T/p/plugin.json" "$T/bad.md")" = FAIL ] && ok "plugin + missing block → FAIL" || fail "bad→FAIL"
[ "$(chk "" "$T/good.md")" = SKIP ] && ok "non-plugin → SKIP (generic-safe)" || fail "nonplugin→SKIP"
echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && echo PASS && exit 0
echo FAIL; exit 1
