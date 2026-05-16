#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SH="$ROOT/scripts/gitx-readme.sh"
PASS=0; FAIL=0
ok(){ echo "  ✅ $1"; PASS=$((PASS+1)); }
no(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_gitx_readme.sh ══"
# interface (Task 1)
test -x "$SH" && ok "executable" || no "executable"
grep -qE '^set -euo pipefail' "$SH" && ok "set -euo pipefail" || no "set -euo pipefail"
bash "$SH" --help >/dev/null 2>&1 && ok "--help exit 0" || no "--help exit 0"
( bash "$SH" --bogus >/dev/null 2>&1; [ $? -eq 2 ] ) && ok "unknown flag exit 2" || no "unknown flag exit 2"
grep -qE '(^|[^[:alnum:]_])(git|gh)[[:space:]]' "$SH" && no "no git/gh" || ok "no git/gh"
grep -qiE '(curl|anthropic|openai|claude)[[:space:]]' "$SH" && no "no LLM" || ok "no LLM"
# resolvers (sourced as lib — exercised under the script's own set -euo via subshell calls below)
echo "§ resolvers"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/tests" "$W/.claude-plugin"
: > "$W/tests/test_a.sh"; : > "$W/tests/test_b.sh"; : > "$W/tests/test_suite_structure.sh"
echo "v9.9.9" > "$W/VERSION"
printf '{\n  "name": "demoskill",\n  "version": "9.9.9"\n}\n' > "$W/.claude-plugin/plugin.json"
printf '## v9.9.9 — 2026-01-01\n- x\n' > "$W/CHANGELOG.md"
( cd "$W" && GITX_README_LIB=1 . "$SH" && [ "$(gr_suite_count)" = "2" ] ) && ok "suite_count=2 (excl suite_structure)" || no "suite_count"
( cd "$W" && GITX_README_LIB=1 . "$SH" && [ "$(gr_version)" = "v9.9.9" ] ) && ok "version" || no "version"
( cd "$W" && GITX_README_LIB=1 . "$SH" && gr_install | grep -q 'marketplace add tkxlab-ai/marketplace' ) && ok "install marketplace add" || no "install add"
( cd "$W" && GITX_README_LIB=1 . "$SH" && gr_install | grep -q 'plugin install demoskill@tkx-skills' ) && ok "install name" || no "install name"
( cd "$W" && GITX_README_LIB=1 . "$SH" && gr_whats_new | grep -q 'v9.9.9 — 2026-01-01' ) && ok "whats_new" || no "whats_new"
( cd "$W" && rm -rf .claude-plugin && GITX_README_LIB=1 . "$SH" && gr_install >/dev/null 2>&1 ) && ok "install exit0 non-plugin (errexit-safe)" || no "install errexit"
( cd "$W" && GITX_README_LIB=1 . "$SH" && gr_install | grep -q 'marketplace add' ) && no "non-plugin must omit marketplace" || ok "install generic-safe non-plugin"
# validator: fail-closed exit 5, NO write, on malformed regions
echo "§ validator (fail-closed)"
mkf(){ printf '%s\n' "$@"; }
V="$(mktemp -d)"; mkdir -p "$V/tests"; : > "$V/tests/test_suite_structure.sh"; echo v1 > "$V/VERSION"
# missing closer
mkf 'pre' '<!-- gitx:managed:version -->' 'BODY' 'post-prose' > "$V/README.md"
cp "$V/README.md" "$V/README.md.bak"
( cd "$V" && bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) && ok "missing closer → exit 5" || no "missing closer exit5"
cmp -s "$V/README.md" "$V/README.md.bak" && ok "missing closer → file untouched (no prose loss)" || no "missing closer mutated file"
# duplicate opener
mkf '<!-- gitx:managed:version -->' 'a' '<!-- /gitx:managed:version -->' '<!-- gitx:managed:version -->' 'b' '<!-- /gitx:managed:version -->' > "$V/README.md"
( cd "$V" && bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) && ok "duplicate opener → exit 5" || no "dup opener exit5"
# inline (same-line) markers rejected
echo '- v: <!-- gitx:managed:version -->x<!-- /gitx:managed:version -->' > "$V/README.md"
( cd "$V" && bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) && ok "inline same-line markers → exit 5" || no "inline exit5"
# leading content before marker rejected
echo 'JUNK <!-- gitx:managed:version -->' > "$V/README.md"; printf '<!-- /gitx:managed:version -->\n' >> "$V/README.md"
( cd "$V" && bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) && ok "leading content before marker → exit 5" || no "leading-content exit5"
# NEW-I-a: trailing whitespace / CR on marker line TOLERATED (no false exit 5, no prose loss)
printf 'pre\n<!-- gitx:managed:suite-count --> \nOLD\n<!-- /gitx:managed:suite-count -->\t\npost\n' > "$V/README.md"
( cd "$V" && bash "$SH" >/dev/null 2>&1 ) && ok "trailing ws/CR on marker tolerated (exit 0, NEW-I-a)" || no "trailing ws falsely rejected"
grep -qx 'pre' "$V/README.md" && grep -qx 'post' "$V/README.md" && ok "prose intact under ws-tolerant markers" || no "prose lost (ws case)"
echo "§ modes"
M="$(mktemp -d)"
mkdir -p "$M/tests" "$M/.claude-plugin"
: > "$M/tests/test_x.sh"; : > "$M/tests/test_suite_structure.sh"
echo v2.0.0 > "$M/VERSION"
printf '{\n  "name": "demox"\n}\n' > "$M/.claude-plugin/plugin.json"
printf '## v2.0.0 — 2026-02-02\n- hi\n' > "$M/CHANGELOG.md"
{
  echo '# Demo'
  echo 'PROSE-ABOVE-verbatim'
  echo '<!-- gitx:managed:suite-count -->'
  echo 'OLD'
  echo '<!-- /gitx:managed:suite-count -->'
  echo '## Install'
  echo '<!-- gitx:managed:install -->'
  echo 'OLD'
  echo '<!-- /gitx:managed:install -->'
  echo 'PROSE-BELOW-verbatim'
} > "$M/README.md"
cp "$M/README.md" "$M/README_CN.md"
( cd "$M" && bash "$SH" >/dev/null 2>&1 ) && ok "refresh exit 0" || no "refresh exit0"
awk '/gitx:managed:suite-count/{f=1;next}/\/gitx:managed:suite-count/{f=0}f' "$M/README.md" | grep -qx '1' && ok "suite-count → 1" || no "suite-count rewrite"
grep -qx 'PROSE-ABOVE-verbatim' "$M/README.md" && grep -qx 'PROSE-BELOW-verbatim' "$M/README.md" && ok "prose verbatim around regions" || no "prose lost"
awk '/gitx:managed:install/{f=1;next}/\/gitx:managed:install/{f=0}f' "$M/README.md" | grep -q 'plugin install demox@tkx-skills' && ok "multi-line install via temp-file (not awk -v)" || no "multi-line install"
cp "$M/README.md" /tmp/r1; ( cd "$M" && bash "$SH" >/dev/null 2>&1 ); diff -q /tmp/r1 "$M/README.md" >/dev/null && ok "idempotent" || no "not idempotent"
( cd "$M" && bash "$SH" --check >/dev/null 2>&1 ) && ok "--check exit 0 in sync" || no "--check false-drift"
printf '\nhand-written paragraph outside any managed region\n' >> "$M/README.md"
( cd "$M" && bash "$SH" --check >/dev/null 2>&1 ) && ok "--check exit 0 after unmanaged-prose edit (contract)" || no "--check false-drift on unmanaged prose"
perl -0pi -e 's{(<!-- gitx:managed:suite-count -->\n).*?(\n<!-- /gitx:managed:suite-count -->)}{${1}999STALE${2}}s' "$M/README.md"
( cd "$M" && bash "$SH" --check >/dev/null 2>&1; [ $? -eq 1 ] ) && ok "--check exit 1 on managed-region drift" || no "--check missed managed drift"
( cd "$M" && bash "$SH" >/dev/null 2>&1 && bash "$SH" --check >/dev/null 2>&1 ) && ok "refresh re-syncs the stale managed region" || no "refresh did not resync"
I="$(mktemp -d)"; ( cd "$I" && bash "$SH" --init >/dev/null 2>&1 ) && test -f "$I/README.md" && ok "--init scaffolds" || no "--init"
( cd "$I" && bash "$SH" --init >/dev/null 2>&1; [ $? -eq 4 ] ) && ok "--init exit 4 when exists" || no "--init no-clobber"
( cd "$I" && bash "$SH" --init --force >/dev/null 2>&1 ) && ok "--init --force" || no "--init force"
( cd "$I" && bash "$SH" --check >/dev/null 2>&1 ) && ok "scaffold self-consistent (no exit 5)" || no "scaffold malformed"
rm -rf "$M" "$I" /tmp/r1
# unknown managed region → fail-closed exit 5 (FIX B: gr_validate_regions
# must reject any NAME not in {suite-count,version,install,whats-new})
echo "§ unknown managed region (FIX B)"
U="$(mktemp -d)"; mkdir -p "$U/tests"; : > "$U/tests/test_suite_structure.sh"; echo v1 > "$U/VERSION"
printf '<!-- gitx:managed:bogus -->\nbody\n<!-- /gitx:managed:bogus -->\n' > "$U/README.md"
cp "$U/README.md" "$U/README.md.bak"
( cd "$U" && bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) \
  && ok "unknown managed name 'bogus' → exit 5 (fail-closed)" \
  || no "unknown managed name 'bogus' should exit 5 but did not"
cmp -s "$U/README.md" "$U/README.md.bak" \
  && ok "unknown name → file untouched (fail-closed, no write)" \
  || no "unknown name → file was mutated (should be untouched)"
rm -rf "$U"

echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && echo PASS && exit 0
echo FAIL; exit 1
