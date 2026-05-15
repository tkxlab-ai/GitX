#!/bin/bash
# test_audit_test_scenarios_soft_warn.sh — v1.3.2 #A2.
#
# Audit §2 used to fail-hard if TEST-SCENARIOS.md was missing from the
# flattened release dir, blocking new-project onboarding (mac-release
# v0.1.0 self-bake hit this; Dev Log 2026-05-07 19:16). v1.3.2 reclassifies
# TEST-SCENARIOS.md as a recommended-but-not-required flatten doc:
# - REQUIRED (hard FAIL): README / INSTALL / CHANGELOG / LICENSE / CONTRIBUTING / SKILL / RELEASE_NOTES / install.sh
# - RECOMMENDED (soft ADVISORY): TEST-SCENARIOS.md
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_SH="$ROOT/scripts/release-audit.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_audit_test_scenarios_soft_warn.sh ══"

# === Static 1: TEST-SCENARIOS.md uses warn (not check) for flatten presence ===
if grep -qE 'warn .*TEST-SCENARIOS\.md 平摊' "$AUDIT_SH"; then
    ok "TEST-SCENARIOS.md 平摊 uses 'warn' (soft advisory)"
else
    fail "TEST-SCENARIOS.md 平摊 still uses 'check' (hard FAIL) — onboarding friction not fixed"
fi

# === Static 2: REQUIRED docs still in 'check' for-loop (hard FAIL on missing) ===
# Extract §2 for-loop and verify it lists the 8 REQUIRED docs but NOT TEST-SCENARIOS.md
REQUIRED_LOOP=$(awk '/^echo "§2\. 平摊文档存在"/,/^check "install\.sh 可执行"/' "$AUDIT_SH")
for req in "README.md" "INSTALL.md" "CHANGELOG.md" "LICENSE" "CONTRIBUTING.md" "SKILL.md" "RELEASE_NOTES.md" "install.sh"; do
    if echo "$REQUIRED_LOOP" | grep -qE "for f in.*$req|check.*$req"; then
        ok "REQUIRED doc '$req' is hard-checked in §2"
    else
        fail "REQUIRED doc '$req' is not hard-checked in §2 (regression!)"
    fi
done

# === Static 3: TEST-SCENARIOS.md NOT in REQUIRED for-loop ===
if echo "$REQUIRED_LOOP" | awk '/for f in/{found=0; for(i=1;i<=NF;i++){if($i=="TEST-SCENARIOS.md")found=1}; if(found)exit 1}'; then
    ok "TEST-SCENARIOS.md correctly excluded from REQUIRED for-loop"
else
    fail "TEST-SCENARIOS.md still in REQUIRED for-loop — would still fail-hard"
fi

# === Static 4: warn function exists in audit (used to enforce soft semantics) ===
if grep -qE '^warn\(\) \{' "$AUDIT_SH"; then
    ok "warn() helper function exists for soft advisories"
else
    fail "warn() function missing — soft-warn semantics not enforceable"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
