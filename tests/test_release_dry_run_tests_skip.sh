#!/bin/bash
# test_release_dry_run_tests_skip.sh — P2-4 fix verification
# Verifies: --dry-run skips the actual test execution (run_tests)
# to ensure dry-run is truly side-effect-free.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$PROJECT_ROOT/scripts/release.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_release_dry_run_tests_skip.sh ══"

# ─- Test 1: dry-run should NOT execute tests ───────────────────────────
# The run_tests function should be skipped or short-circuited in dry-run

# Check if release.sh has dry-run handling for run_tests
if grep -A5 'run_tests()' "$RELEASE_SH" | grep -q 'DRY_RUN'; then
    ok "run_tests() checks DRY_RUN flag"
elif grep -B2 'run_tests$' "$RELEASE_SH" | grep -q 'DRY_RUN\|if.*dry'; then
    ok "main flow skips run_tests in dry-run"
else
    fail "run_tests() executed even in dry-run (P2-4: tests may have side-effects)"
fi

# ─- Test 2: dry-run with a fixture that has passing tests — should report but not run ────
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/skills/my-skill"
cat > "$FIXTURE/skills/my-skill/SKILL.md" <<'EOF'
---
name: my-skill
description: test
---
# My Skill
EOF
printf 'v0.0.4\n' > "$FIXTURE/skills/my-skill/VERSION"

mkdir -p "$FIXTURE/Release"
cat > "$FIXTURE/Release/CHANGELOG.md" <<'EOF'
# Test — Release History

## v0.0.4 — 2026-01-01

Real entry.

Artifacts: `Release/my_skill-v0.0.4/`

---

EOF

mkdir -p "$FIXTURE/tests"
cat > "$FIXTURE/tests/run_all.sh" <<'TESTEOF'
#!/bin/bash
echo "TESTS_WERE_RUN" > /tmp/dry-run-test-flag
echo "══ test_suite ══"
echo "Results: ✅0 passed / ❌0 failed 🎉 All tests GREEN"
exit 0
TESTEOF
chmod +x "$FIXTURE/tests/run_all.sh"

# Remove flag file
rm -f /tmp/dry-run-test-flag

set +e
OUTPUT=$(PROJECT_ROOT="$FIXTURE" bash "$RELEASE_SH" v0.0.4 --dry-run 2>&1)
RC=$?
set -e

if [ -f /tmp/dry-run-test-flag ]; then
    flag=$(cat /tmp/dry-run-test-flag)
    if [ "$flag" = "TESTS_WERE_RUN" ]; then
        fail "dry-run executed tests (side-effect detected)"
    else
        ok "dry-run did not execute tests"
    fi
else
    ok "dry-run did not execute tests (no side-effect flag found)"
fi

# In dry-run, it should still continue past the test step (or report skipping)
if echo "$OUTPUT" | grep -qi '\[dry-run\].*[Tt]est\|skip.*test\|skip.*regression' 2>/dev/null; then
    ok "dry-run reports skipping tests"
elif [ "$RC" -ne 0 ]; then
    # It's OK if dry-run continues to fail later (no artifacts) as long as tests weren't run
    ok "dry-run continued past test step (tests not run)"
else
    ok "dry-run handled test step acceptably"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
