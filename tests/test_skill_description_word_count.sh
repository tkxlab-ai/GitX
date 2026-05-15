#!/bin/bash
# test_skill_description_word_count.sh — S3-2
# SKILL.md frontmatter `description:` must stay compact for Codex skill-loader budget.
# exit: 0=pass, 1=fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../SKILL.md"
MAX_WORDS=80
MAX_CHARS=220
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_skill_description_word_count.sh ══"

# Extract description line (may be multi-line folded block later, but we assume single line)
desc=$(awk '/^---$/{c++; next} c==1 && /^description:/{sub(/^description:[[:space:]]*/, ""); print; exit}' "$SKILL_MD")

if [ -z "$desc" ]; then
    fail "description field missing from SKILL.md frontmatter"
    echo "Results: ✅$PASS passed / ❌$FAIL failed"
    exit 1
fi

words=$(echo "$desc" | wc -w | tr -d ' ')
chars=$(printf '%s' "$desc" | wc -m | tr -d ' ')

if [ "$words" -lt "$MAX_WORDS" ]; then
    ok "description is $words words (< $MAX_WORDS)"
else
    fail "description is $words words — exceeds $MAX_WORDS word budget (S3-2)"
fi

if [ "$chars" -le "$MAX_CHARS" ]; then
    ok "description is $chars chars (<= $MAX_CHARS Codex metadata budget)"
else
    fail "description is $chars chars — exceeds $MAX_CHARS Codex metadata budget"
fi

# ── Test 2: all three triggers still mentioned ─────────────────────────────
# Keep only compact trigger terms in the always-loaded description. Detailed
# syntax belongs in the SKILL.md body to avoid Codex metadata truncation.
# v1.1.0: trigger renamed /GitX-release → /gitx-release.
for trig in "/gitx-release" "release" "audit" "scan"; do
    if echo "$desc" | grep -qF "$trig"; then
        ok "description still mentions '$trig'"
    else
        fail "description lost trigger '$trig' — S3-2 must preserve semantics"
    fi
done

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
