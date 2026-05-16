#!/bin/bash
# test_codex_skill_metadata.sh — Codex selector metadata and docs
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_codex_skill_metadata.sh ══"

for file in "$PROJECT_ROOT/agents/openai.yaml" "$PROJECT_ROOT/skills/gitx-release/agents/openai.yaml"; do
    label="${file#$PROJECT_ROOT/}"
    if [ -f "$file" ]; then
        ok "$label exists"
    else
        fail "$label missing"
        continue
    fi

    if grep -q '^interface:' "$file" \
        && grep -q 'display_name: "GitX"' "$file" \
        && grep -q 'default_prompt:' "$file" \
        && grep -q 'GitX release this project' "$file"; then
        ok "$label exposes GitX metadata for Codex selectors"
    else
        fail "$label missing GitX selector metadata"
    fi
done

for file in "$PROJECT_ROOT/agents/codex-commands.txt" "$PROJECT_ROOT/skills/gitx-release/agents/codex-commands.txt"; do
    label="${file#$PROJECT_ROOT/}"
    # v1.1.0 rebrand: canonical selector is $gitx-release; legacy
    # $git-release-pipeline retained as deprecated alias (one-version
    # grace period). $GitX-release was retired with the slash command shim.
    if [ -f "$file" ] \
        && grep -qxF '$gitx-release' "$file" \
        && grep -qxF '$git-release-pipeline' "$file"; then
        ok "$label registers Codex $ selectors (canonical + deprecated alias)"
    else
        fail "$label missing required Codex $ selectors"
    fi
done

if grep -q '\$gitx-release' "$PROJECT_ROOT/README.md" \
    && grep -q '/skills' "$PROJECT_ROOT/README.md"; then
    ok "README documents Codex $ skill invocation and /skills discovery"
else
    fail "README missing Codex $ invocation or /skills discovery docs"
fi

if grep -q 'cp -R "$SELF_DIR/agents"' "$PROJECT_ROOT/install.sh"; then
    ok "install.sh copies agents/openai.yaml metadata into installed skill"
else
    fail "install.sh does not copy agents/openai.yaml into installed skill"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
