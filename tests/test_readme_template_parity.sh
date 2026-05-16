#!/bin/bash
# codex-HIGH guard: root references/readme/ must be byte-identical to the
# SHIPPED skill-tree copy (release.sh ships skills/gitx-release/references;
# sync-dual-source.sh covers only scripts/*.sh, so references parity has no
# auto-sync — assert it, improving on gitx-sop's implicit-only enforcement).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  ✅ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_readme_template_parity.sh ══"
for f in README.template.md README_CN.template.md; do
  a="$ROOT/references/readme/$f"; b="$ROOT/skills/gitx-release/references/readme/$f"
  if [ -f "$a" ] && [ -f "$b" ]; then
    cmp -s "$a" "$b" && ok "$f root↔skill byte-identical" || fail "$f drifted root vs skill tree"
  else
    fail "$f missing (root=$([ -f "$a" ]&&echo y||echo n) skill=$([ -f "$b" ]&&echo y||echo n))"
  fi
done
sf=test_readme_numeric_accuracy.sh.template
sa="$ROOT/references/readme/$sf"; sb="$ROOT/skills/gitx-release/references/readme/$sf"
if [ ! -e "$sa" ] && [ ! -e "$sb" ]; then
  echo "  ➖ $sf not yet created (Task 7) — parity n/a"
elif [ -f "$sa" ] && [ -f "$sb" ] && cmp -s "$sa" "$sb"; then
  ok "$sf root↔skill byte-identical"
else
  fail "$sf half-shipped or drifted (root=$([ -f "$sa" ]&&echo y||echo n) skill=$([ -f "$sb" ]&&echo y||echo n))"
fi
echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && echo PASS && exit 0
echo FAIL; exit 1
