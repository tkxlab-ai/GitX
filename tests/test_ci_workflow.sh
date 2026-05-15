#!/bin/bash
# test_ci_workflow.sh — .github/workflows/ci.yml contract
# Asserts:
#   - ci.yml exists
#   - runs shellcheck on scripts/*.sh + install.sh
#   - runs bash tests/run_all.sh
#   - triggers on push + pull_request
# exit: 0=all pass, 1=any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
CI="$ROOT/.github/workflows/ci.yml"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_ci_workflow.sh ══"

# ── Test 1: ci.yml exists ─────────────────────────────────────────────
if [ -f "$CI" ]; then
    ok "ci.yml exists at .github/workflows/ci.yml"
else
    fail "ci.yml missing: $CI"
    echo ""
    echo "Results: ✅$PASS passed / ❌$FAIL failed"
    exit 1
fi

# ── Test 2: triggers push + pull_request ──────────────────────────────
if grep -qE '^[[:space:]]*push:' "$CI" && grep -qE '^[[:space:]]*pull_request:' "$CI"; then
    ok "ci.yml triggers on push + pull_request"
else
    fail "ci.yml missing push/pull_request triggers"
fi

# ── Test 3: runs run_all.sh ───────────────────────────────────────────
if grep -qE 'tests/run_all\.sh' "$CI"; then
    ok "ci.yml invokes tests/run_all.sh"
else
    fail "ci.yml does NOT invoke tests/run_all.sh"
fi

# ── Test 4: runs shellcheck ───────────────────────────────────────────
if grep -qi 'shellcheck' "$CI"; then
    ok "ci.yml runs shellcheck"
else
    fail "ci.yml does NOT run shellcheck"
fi

# ── Test 5: uses ubuntu runner ────────────────────────────────────────
if grep -qE 'runs-on:[[:space:]]*ubuntu' "$CI"; then
    ok "ci.yml uses ubuntu runner"
else
    fail "ci.yml missing runs-on: ubuntu-*"
fi

# ── Test 6: checks out with actions/checkout ─────────────────────────
if grep -qE 'actions/checkout@v[0-9]+' "$CI"; then
    ok "ci.yml uses actions/checkout"
else
    fail "ci.yml missing actions/checkout step"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
