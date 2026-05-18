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
# passthrough contract (gitx-readme.sh is now a pure shim → docs-pipeline.sh)
echo "§ passthrough contract"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/tests" "$W/.claude-plugin"
: > "$W/tests/test_a.sh"; : > "$W/tests/test_b.sh"; : > "$W/tests/test_suite_structure.sh"
echo "v9.9.9" > "$W/VERSION"
printf '{\n  "name": "demoskill",\n  "version": "9.9.9"\n}\n' > "$W/.claude-plugin/plugin.json"
printf '## v9.9.9 — 2026-01-01\n- x\n' > "$W/CHANGELOG.md"
# --help forwards: output contains deprecation notice AND docs-pipeline flags (e.g. --check)
out="$(PROJECT_ROOT="$W" bash "$SH" --help 2>&1)"
printf '%s\n' "$out" | grep -qi 'deprecat' && ok "--help contains deprecation notice" || no "--help missing deprecation notice"
printf '%s\n' "$out" | grep -q -- '--check' && ok "--help forwards docs-pipeline flags (--check present)" || no "--help did not forward --check flag"
# --check exit code == docs-pipeline --check exit code (shim is a pure passthrough)
DP="$ROOT/scripts/docs-pipeline.sh"
( cd "$W" && PROJECT_ROOT="$W" bash "$SH" --init --force >/dev/null 2>&1 )
PROJECT_ROOT="$W" bash "$SH" --check >/dev/null 2>&1 && shim_rc=0 || shim_rc=$?
PROJECT_ROOT="$W" bash "$DP" --check >/dev/null 2>&1 && dp_rc=0 || dp_rc=$?
[ "$shim_rc" -eq "$dp_rc" ] && ok "shim --check exit code == docs-pipeline --check exit code ($shim_rc)" || no "shim --check exit code ($shim_rc) != docs-pipeline ($dp_rc)"
# validator: fail-closed exit 5, NO write, on malformed regions
echo "§ validator (fail-closed)"
mkf(){ printf '%s\n' "$@"; }
V="$(mktemp -d)"; mkdir -p "$V/tests"; : > "$V/tests/test_suite_structure.sh"; echo v1 > "$V/VERSION"
# missing closer — use suite-count (a valid new-contract region name)
mkf 'pre' '<!-- gitx:managed:suite-count -->' 'BODY' 'post-prose' > "$V/README.md"
cp "$V/README.md" "$V/README.md.bak"
( cd "$V" && PROJECT_ROOT="$V" bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) && ok "missing closer → exit 5" || no "missing closer exit5"
cmp -s "$V/README.md" "$V/README.md.bak" && ok "missing closer → file untouched (no prose loss)" || no "missing closer mutated file"
# duplicate opener
mkf '<!-- gitx:managed:suite-count -->' 'a' '<!-- /gitx:managed:suite-count -->' '<!-- gitx:managed:suite-count -->' 'b' '<!-- /gitx:managed:suite-count -->' > "$V/README.md"
( cd "$V" && PROJECT_ROOT="$V" bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) && ok "duplicate opener → exit 5" || no "dup opener exit5"
# inline (same-line) markers rejected
echo '- v: <!-- gitx:managed:suite-count -->x<!-- /gitx:managed:suite-count -->' > "$V/README.md"
( cd "$V" && PROJECT_ROOT="$V" bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) && ok "inline same-line markers → exit 5" || no "inline exit5"
# leading content before marker rejected
echo 'JUNK <!-- gitx:managed:suite-count -->' > "$V/README.md"; printf '<!-- /gitx:managed:suite-count -->\n' >> "$V/README.md"
( cd "$V" && PROJECT_ROOT="$V" bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) && ok "leading content before marker → exit 5" || no "leading-content exit5"
# NEW-I-a: trailing whitespace / CR on marker line TOLERATED (no false exit 5, no prose loss)
printf 'pre\n<!-- gitx:managed:suite-count --> \nOLD\n<!-- /gitx:managed:suite-count -->\t\npost\n' > "$V/README.md"
( cd "$V" && PROJECT_ROOT="$V" bash "$SH" >/dev/null 2>&1 ) && ok "trailing ws/CR on marker tolerated (exit 0, NEW-I-a)" || no "trailing ws falsely rejected"
grep -qx 'pre' "$V/README.md" && grep -qx 'post' "$V/README.md" && ok "prose intact under ws-tolerant markers" || no "prose lost (ws case)"
echo "§ modes"
M="$(mktemp -d)"
mkdir -p "$M/tests" "$M/.claude-plugin"
: > "$M/tests/test_x.sh"; : > "$M/tests/test_suite_structure.sh"
echo v2.0.0 > "$M/VERSION"
printf '{\n  "name": "demox"\n}\n' > "$M/.claude-plugin/plugin.json"
printf '## v2.0.0 — 2026-02-02\n- hi\n' > "$M/CHANGELOG.md"
# fixture uses the new 5-region contract (no install/version regions)
{
  echo '# Demo'
  echo 'PROSE-ABOVE-verbatim'
  echo '<!-- gitx:managed:suite-count -->'
  echo 'OLD'
  echo '<!-- /gitx:managed:suite-count -->'
  echo 'PROSE-BELOW-verbatim'
} > "$M/README.md"
cp "$M/README.md" "$M/README_CN.md"
( cd "$M" && PROJECT_ROOT="$M" bash "$SH" >/dev/null 2>&1 ) && ok "refresh exit 0" || no "refresh exit0"
awk '/gitx:managed:suite-count/{f=1;next}/\/gitx:managed:suite-count/{f=0}f' "$M/README.md" | grep -qx '1' && ok "suite-count → 1" || no "suite-count rewrite"
grep -qx 'PROSE-ABOVE-verbatim' "$M/README.md" && grep -qx 'PROSE-BELOW-verbatim' "$M/README.md" && ok "prose verbatim around regions" || no "prose lost"
cp "$M/README.md" /tmp/r1; ( cd "$M" && PROJECT_ROOT="$M" bash "$SH" >/dev/null 2>&1 ); diff -q /tmp/r1 "$M/README.md" >/dev/null && ok "idempotent" || no "not idempotent"
( cd "$M" && PROJECT_ROOT="$M" bash "$SH" --check >/dev/null 2>&1 ) && ok "--check exit 0 in sync" || no "--check false-drift"
printf '\nhand-written paragraph outside any managed region\n' >> "$M/README.md"
( cd "$M" && PROJECT_ROOT="$M" bash "$SH" --check >/dev/null 2>&1 ) && ok "--check exit 0 after unmanaged-prose edit (contract)" || no "--check false-drift on unmanaged prose"
perl -0pi -e 's{(<!-- gitx:managed:suite-count -->\n).*?(\n<!-- /gitx:managed:suite-count -->)}{${1}999STALE${2}}s' "$M/README.md"
( cd "$M" && PROJECT_ROOT="$M" bash "$SH" --check >/dev/null 2>&1; [ $? -eq 1 ] ) && ok "--check exit 1 on managed-region drift" || no "--check missed managed drift"
( cd "$M" && PROJECT_ROOT="$M" bash "$SH" >/dev/null 2>&1 && PROJECT_ROOT="$M" bash "$SH" --check >/dev/null 2>&1 ) && ok "refresh re-syncs the stale managed region" || no "refresh did not resync"
I="$(mktemp -d)"; ( cd "$I" && PROJECT_ROOT="$I" bash "$SH" --init >/dev/null 2>&1 ) && test -f "$I/README.md" && ok "--init scaffolds" || no "--init"
( cd "$I" && PROJECT_ROOT="$I" bash "$SH" --init >/dev/null 2>&1; [ $? -eq 4 ] ) && ok "--init exit 4 when exists" || no "--init no-clobber"
( cd "$I" && PROJECT_ROOT="$I" bash "$SH" --init --force >/dev/null 2>&1 ) && ok "--init --force" || no "--init force"
( cd "$I" && PROJECT_ROOT="$I" bash "$SH" --check >/dev/null 2>&1 ) && ok "scaffold self-consistent (no exit 5)" || no "scaffold malformed"
rm -rf "$M" "$I" /tmp/r1
# unknown managed region → fail-closed exit 5 (FIX B: gr_validate_regions
# must reject any NAME not in {suite-count,version,install,whats-new})
echo "§ unknown managed region (FIX B)"
U="$(mktemp -d)"; mkdir -p "$U/tests"; : > "$U/tests/test_suite_structure.sh"; echo v1 > "$U/VERSION"
printf '<!-- gitx:managed:bogus -->\nbody\n<!-- /gitx:managed:bogus -->\n' > "$U/README.md"
cp "$U/README.md" "$U/README.md.bak"
( cd "$U" && PROJECT_ROOT="$U" bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) \
  && ok "unknown managed name 'bogus' → exit 5 (fail-closed)" \
  || no "unknown managed name 'bogus' should exit 5 but did not"
cmp -s "$U/README.md" "$U/README.md.bak" \
  && ok "unknown name → file untouched (fail-closed, no write)" \
  || no "unknown name → file was mutated (should be untouched)"
rm -rf "$U"

# gr_* library-source assertions removed (v1.11.0): gitx-readme.sh is now a
# pure passthrough shim. Sourcing it (with GITX_README_LIB=1) hits the final
# `exec bash docs-pipeline.sh "$@"` line, which exec-replaces the subshell
# before any gr_* call can execute — every post-source assertion is vacuous.
# All resolver behaviors (skill-name frontmatter/env/standard-layout/
# workspace-exclude/ambiguous, command-surface enumeration, install
# marketplace/generic-safe, suite_count, version, whats-new) are now covered
# by test_docs_pipeline.sh §dp_* resolver library (DOCS_PIPELINE_LIB=1) which
# sources the REAL engine directly.
# Task 2: a scaffold (--init from the dual-tree template) MUST inherit BOTH
# own-line managed regions (whats-new + command-surface), and --check must
# pass on it — so every dependent skill (Decision 0019) gets the §0g guard.
# grep -qx below is INTENTIONALLY stricter than gr_validate_regions' whitespace-tolerant marker match — the §0g/scaffold guard wants zero marker rot; do not relax to a tolerant grep.
SC="$(mktemp -d)"
( cd "$SC" && PROJECT_ROOT="$SC" bash "$SH" --init --force >/dev/null 2>&1 ) \
  && grep -qx '<!-- gitx:managed:whats-new -->' "$SC/README.md" \
  && grep -qx '<!-- gitx:managed:command-surface -->' "$SC/README.md" \
  && ( cd "$SC" && PROJECT_ROOT="$SC" bash "$SH" --check >/dev/null 2>&1 ) \
  && ok "scaffold inherits own-line whats-new + command-surface, --check exit 0" \
  || no "scaffold missing whats-new/command-surface region or --check drift"
rm -rf "$SC"

echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && echo PASS && exit 0
echo FAIL; exit 1
