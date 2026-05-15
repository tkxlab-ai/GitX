#!/bin/bash
# test_install_sh_interface.sh — S2-7: install.sh §6.10 interface contract verification
# Tests that release-audit.sh checks install.sh for --dry-run/--force/--help flags
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT="$SCRIPT_DIR/../scripts/release-audit.sh"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_install_sh_interface.sh ══"

# --- Test 1: audit.sh checks for --dry-run in install.sh ---
if grep -qE "dry.run" "$AUDIT"; then
    ok "audit checks for --dry-run in install.sh (§6.10)"
else
    fail "audit MISSING --dry-run check (S2-7: §6.10 Gate #7 not implemented)"
fi

# --- Test 2: audit.sh checks for --force in install.sh ---
if grep -qE "\-\-force" "$AUDIT"; then
    ok "audit checks for --force in install.sh (§6.10)"
else
    fail "audit MISSING --force check (S2-7: §6.10 Gate #7 not implemented)"
fi

# --- Test 3: audit.sh checks for --help in install.sh ---
if grep -qE "\-\-help" "$AUDIT"; then
    ok "audit checks for --help in install.sh (§6.10)"
else
    fail "audit MISSING --help check (S2-7: §6.10 Gate #7 not implemented)"
fi

# --- Test 4: audit actually validates content not just existence ---
# The check must go beyond "file exists" — must grep inside install.sh
if grep -A5 "§6.10\|dry.run.*install\|install.*dry.run" "$AUDIT" | grep -qE "grep.*install\.sh|check.*install"; then
    ok "audit performs content-check on install.sh for §6.10"
else
    # Broader check: any grep looking inside install.sh for interface flags
    if grep -E "grep.*dry.run.*install\.sh|grep.*\-\-force.*install\.sh" "$AUDIT" > /dev/null 2>&1; then
        ok "audit greps install.sh content for §6.10 interface flags"
    else
        fail "audit does not grep install.sh content for §6.10 flags — only existence check"
    fi
fi

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
