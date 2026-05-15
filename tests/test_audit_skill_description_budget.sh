#!/bin/bash
# test_audit_skill_description_budget.sh — packaged skills keep metadata compact
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_SH="$PROJECT_ROOT/scripts/release-audit.sh"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_skill_description_budget.sh ══"

if grep -q 'MAX_SKILL_DESCRIPTION_CHARS=220' "$AUDIT_SH"; then
    ok "release-audit.sh defines a Codex metadata char budget"
else
    fail "release-audit.sh missing Codex metadata char budget"
fi

if grep -q 'SKILL.md description <=.*Codex metadata budget' "$AUDIT_SH" \
    && grep -q 'desc_chars=' "$AUDIT_SH"; then
    ok "release-audit.sh checks SKILL.md description length"
else
    fail "release-audit.sh does not check SKILL.md description length"
fi

if grep -q 'description field missing' "$AUDIT_SH"; then
    ok "release-audit.sh fails missing description explicitly"
else
    fail "release-audit.sh does not fail missing description explicitly"
fi

if grep -q 'frontmatter 含 Codex 不兼容 metadata' "$AUDIT_SH"; then
    ok "release-audit.sh rejects Codex-invalid SKILL.md metadata blocks"
else
    fail "release-audit.sh does not reject Codex-invalid SKILL.md metadata blocks"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
