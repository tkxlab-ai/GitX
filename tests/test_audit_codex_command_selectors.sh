#!/bin/bash
# test_audit_codex_command_selectors.sh — every slash command has Codex $ selector coverage
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_SH="$PROJECT_ROOT/scripts/release-audit.sh"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_codex_command_selectors.sh ══"

if grep -q 'Codex \$ command selectors' "$AUDIT_SH" \
    && grep -q 'agents/codex-commands.txt' "$AUDIT_SH"; then
    ok "release-audit.sh has a Codex $ selector audit gate"
else
    fail "release-audit.sh missing Codex $ selector audit gate"
fi

if grep -q 'basename "$cmd" .md' "$AUDIT_SH" \
    && grep -q 'grep -qxF "\\$$cmd_name"' "$AUDIT_SH" \
    && grep -q 'cmd_name_lower=' "$AUDIT_SH"; then
    ok "release-audit.sh validates every commands/*.md basename as a $ selector"
else
    fail "release-audit.sh does not validate every slash command as a Codex $ selector"
fi

if grep -q 'grep -qxF "\\$$SKILL_NAME"' "$AUDIT_SH"; then
    ok "release-audit.sh validates the skill-name $ selector"
else
    fail "release-audit.sh does not validate the skill-name $ selector"
fi

for manifest in "$PROJECT_ROOT/agents/codex-commands.txt" "$PROJECT_ROOT/skills/gitx-release/agents/codex-commands.txt"; do
    label="${manifest#$PROJECT_ROOT/}"
    if [ -f "$manifest" ]; then
        ok "$label exists"
    else
        fail "$label missing"
        continue
    fi

    # v1.1.0 rebrand: canonical selector is $gitx-release; legacy
    # $git-release-pipeline retained as a deprecated alias for one
    # minor version (removed in v1.2.0). $GitX-release was retired
    # along with the commands/GitX-release.md slash command shim.
    if grep -qxF '$gitx-release' "$manifest" \
        && grep -qxF '$gitx-init' "$manifest" \
        && grep -qxF '$git-release-pipeline' "$manifest"; then
        ok "$label covers \$gitx-release + \$gitx-init + deprecated alias"
    else
        fail "$label missing required Codex $ selectors"
    fi

    # Upper-bound (v1.7.0): exactly the 4 expected selectors. Set-based
    # comparison so any drift (stray fifth, or rename without test update)
    # surfaces immediately. Allowed: $gitx-release (canonical v1.1.0+),
    # $gitx-init (canonical v1.6.0+ for subcommand slash), $gitx-sop
    # (canonical v1.7.0+ for GitHub-publish SOP slash), $git-release-pipeline
    # (deprecated alias retained for grace period). Codex treats every
    # non-empty line as a selector — comments aren't safe (see agents/README.md).
    expected_set="$(printf '%s\n' '$git-release-pipeline' '$gitx-init' '$gitx-release' '$gitx-sop' | sort)"
    actual_set="$(grep -E '^\$' "$manifest" | sort)"
    if [ "$expected_set" = "$actual_set" ]; then
        ok "$label selectors match expected set ({\$gitx-release, \$gitx-init, \$gitx-sop, \$git-release-pipeline})"
    else
        fail "$label selectors differ from expected; got: $(echo "$actual_set" | tr '\n' ' ')"
    fi
done

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
