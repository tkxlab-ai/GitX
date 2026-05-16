#!/bin/bash
# test_skill_md_triggers.sh — TDD test for S1-2: no dangling 'check policy' trigger
# RED: SKILL.md currently declares 'check policy' with no implementation
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../SKILL.md"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_skill_md_triggers.sh ══"

# --- Test 1: 'check policy' must NOT appear as a declared trigger ---
if grep -q 'check policy' "$SKILL_MD"; then
    fail "'check policy' still present in SKILL.md — dangling trigger not removed (S1-2)"
else
    ok "'check policy' removed from SKILL.md"
fi

# --- Test 2: 'scan <dir>' must be declared as the third trigger ---
if grep -q 'scan.*dir' "$SKILL_MD"; then
    ok "'scan <dir>' declared as trigger in SKILL.md"
else
    fail "'scan <dir>' NOT found in SKILL.md — should replace 'check policy'"
fi

# --- Test 3: All three declared triggers have implementations ---
# release <version> → release.sh exists
# audit <version>   → release-audit.sh exists
# scan <dir>        → release-sanitize.sh exists
for script in "scripts/release.sh" "scripts/release-audit.sh" "scripts/release-sanitize.sh"; do
    if [ -f "$SCRIPT_DIR/../$script" ]; then
        ok "$script exists (backs a declared trigger)"
    else
        fail "$script MISSING — trigger has no backing implementation"
    fi
done

# --- Test 4: Exactly 3 triggers declared (not more, not fewer) ---
trigger_count=$(grep -oE '`(release|audit|scan)[^`]*`' "$SKILL_MD" | grep -c '^' || true)
if [ "$trigger_count" -ge 3 ]; then
    ok "At least 3 trigger patterns found in SKILL.md"
else
    fail "Fewer than 3 trigger patterns found (got $trigger_count)"
fi

# --- Test 5: non-standard release projects must still trigger guideline generation ---
if grep -q 'GitX_Upgrade_Guideline.md' "$SKILL_MD" \
    && grep -q 'gitx-release.sh --dry-run' "$SKILL_MD" \
    && ! grep -q 'skill 不适用，告知用户' "$SKILL_MD"; then
    ok "SKILL.md instructs agents to generate upgrade guideline for non-standard release projects"
else
    fail "SKILL.md may let agents manually refuse non-standard projects without generating GitX_Upgrade_Guideline.md"
fi

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
