#!/bin/bash
# test_skill_bundle_sync.sh — root SKILL.md must match packaged skill copy
#
# The release pipeline packages from skills/<name>/SKILL.md, while humans often
# edit the root SKILL.md. Drift means installed AI instructions can be stale.
#
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_SKILL="$PROJECT_ROOT/SKILL.md"
BUNDLE_SKILL="$PROJECT_ROOT/skills/gitx-release/SKILL.md"

PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_skill_bundle_sync.sh ══"

if [ -f "$ROOT_SKILL" ] && [ -f "$BUNDLE_SKILL" ]; then
    ok "root and bundled SKILL.md files exist"
else
    fail "root or bundled SKILL.md is missing"
fi

if diff -q "$ROOT_SKILL" "$BUNDLE_SKILL" >/dev/null 2>&1; then
    ok "root SKILL.md and bundled SKILL.md are byte-identical"
else
    fail "root SKILL.md and bundled SKILL.md drifted"
    diff -u "$ROOT_SKILL" "$BUNDLE_SKILL" | sed -n '1,40p' | sed 's/^/     /'
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
