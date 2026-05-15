#!/bin/bash
# test_install_docs_force.sh — install docs must explain --force overwrite path
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_install_docs_force.sh ══"

if grep -q -- './install.sh --force' "$PROJECT_ROOT/README.md" \
    && grep -qiE 'already|exist|已有|已存在|覆盖' "$PROJECT_ROOT/README.md"; then
    ok "README documents --force for existing installs"
else
    fail "README does not clearly document --force for existing installs"
fi

if grep -q -- './install.sh --force' "$PROJECT_ROOT/INSTALL.md" \
    && grep -qiE 'Already installed|已存在|覆盖|overwrite' "$PROJECT_ROOT/INSTALL.md"; then
    ok "INSTALL documents --force overwrite and Already installed recovery"
else
    fail "INSTALL does not clearly document --force overwrite recovery"
fi

if grep -q -- './install.sh --force' "$PROJECT_ROOT/TEST-SCENARIOS.md" \
    && grep -qiE '重复安装拒绝|unless.*--force|除非加 --force' "$PROJECT_ROOT/TEST-SCENARIOS.md"; then
    ok "TEST-SCENARIOS covers --force install behavior"
else
    fail "TEST-SCENARIOS does not cover --force install behavior"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
