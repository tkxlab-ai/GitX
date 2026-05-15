#!/bin/bash
# test_release_sh_safety.sh — TDD test for S1-4 (audit error message) + S1-5 (latest symlink order)
# RED: current release.sh has '<重跑 release>' placeholder and updates latest before audit
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_SH="$SCRIPT_DIR/../scripts/release.sh"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_release_sh_safety.sh ══"

# ── S1-4: audit failure message ────────────────────────────────────────────

# Test 1: no angle-bracket placeholder '<重跑 release>' in audit failure block
if grep -q '<重跑 release>' "$RELEASE_SH"; then
    fail "S1-4: '<重跑 release>' placeholder still present — not executable"
else
    ok "S1-4: no '<重跑 release>' placeholder in release.sh"
fi

# Test 2: failure block contains actual executable commands (rm -rf and bash $0)
# Check for the pattern: rm -rf and bash $0 (or similar) near audit failure
if grep -A5 'Deep audit 未通过' "$RELEASE_SH" | grep -q 'rm -rf'; then
    ok "S1-4: audit failure message includes 'rm -rf' cleanup command"
else
    fail "S1-4: audit failure message MISSING 'rm -rf' cleanup command"
fi

if grep -A5 'Deep audit 未通过' "$RELEASE_SH" | grep -qE 'bash.*\$0|\$0.*\$VERSION'; then
    ok "S1-4: audit failure message includes re-run command with \$0"
else
    fail "S1-4: audit failure message MISSING re-run command"
fi

# ── S1-5: latest symlink order ─────────────────────────────────────────────

# Test 4: latest symlink update must appear AFTER the audit block
# Strategy: get line numbers of 'latest' symlink and audit call
latest_line=$(grep -n 'ln -s.*latest\|ln -sf.*latest' "$RELEASE_SH" | tail -1 | cut -d: -f1)
audit_call_line=$(grep -n 'bash.*release-audit\|bash.*\$AUDIT' "$RELEASE_SH" | head -1 | cut -d: -f1)

if [ -z "$latest_line" ]; then
    fail "S1-5: 'latest' symlink line NOT FOUND in release.sh"
elif [ -z "$audit_call_line" ]; then
    fail "S1-5: audit call line NOT FOUND in release.sh"
elif [ "$latest_line" -gt "$audit_call_line" ]; then
    ok "S1-5: latest symlink (line $latest_line) is AFTER audit call (line $audit_call_line)"
else
    fail "S1-5: latest symlink (line $latest_line) is BEFORE audit call (line $audit_call_line) — audit failure leaves bad latest"
fi

# Test 5: latest symlink uses portable ln -sfn pattern (Gotcha #15 fix)
# v0.9.8+: `ln -sfn` replaces the old `ln -sf .latest.tmp + mv` recipe that broke on BSD mv.
# -n flag is critical: without it, BSD ln follows existing symlink-to-directory.
if grep -q 'ln -sfn' "$RELEASE_SH"; then
    ok "S1-5: latest symlink uses portable ln -sfn pattern (Gotcha #15)"
else
    fail "S1-5: latest symlink MISSING 'ln -sfn' — BSD/GNU portability broken (Gotcha #15)"
fi

# ── S2-6: SKILL_STAGE trap integration ──────────────────────────────────────

# Test 6: SKILL_STAGE cleanup must be reachable from the EXIT trap.
# The trap calls cleanup_on_fail(), which must contain `rm -rf ... SKILL_STAGE`.
# Either the trap line itself or the cleanup function it calls must handle SKILL_STAGE.
if grep -q 'SKILL_STAGE' "$RELEASE_SH" && \
   grep -A20 'cleanup_on_fail()' "$RELEASE_SH" | grep -q 'SKILL_STAGE'; then
    ok "S2-6: SKILL_STAGE cleaned via cleanup_on_fail in EXIT trap chain"
else
    fail "S2-6: SKILL_STAGE not cleaned in EXIT trap chain"
fi

# ── S3-7: strict bash mode ─────────────────────────────────────────────────

# release.sh must run with set -euo pipefail to fail fast on:
#   - unset variables (typos)
#   - pipeline errors in the middle of a pipe
if grep -qE '^set[[:space:]]+-[eu]+o[[:space:]]+pipefail|^set[[:space:]]+-euo[[:space:]]+pipefail' "$RELEASE_SH"; then
    ok "S3-7: release.sh declares 'set -euo pipefail'"
else
    fail "S3-7: release.sh MISSING 'set -euo pipefail' — unset vars & pipe failures slip through"
fi

# ── S3-8: no upstream command copy-paste advice ────────────────────────────

AUDIT_SH="$SCRIPT_DIR/../scripts/release-audit.sh"
if grep -qE 'git[[:space:]]+push|push --tags|git[[:space:]]+tag' "$RELEASE_SH" "$AUDIT_SH"; then
    fail "S3-8: release/audit output still prints git tag/push commands"
else
    ok "S3-8: release/audit output avoids git tag/push copy-paste commands"
fi

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
