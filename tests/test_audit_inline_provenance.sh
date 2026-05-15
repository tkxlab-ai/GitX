#!/bin/bash
# test_audit_inline_provenance.sh — v1.0.8 hardening (Sec #2 / Arch #1).
# `--inline` flag relaxes §8 mismatched-target FAIL to SKIP. Without
# provenance, anyone running standalone audit can pass `--inline` to
# silence a real failure. This test asserts:
#   1. release.sh exports _GITX_INTERNAL_INLINE=1 before invoking audit
#   2. release-audit.sh ignores `--inline` (with warning) when env unset
#   3. release-audit.sh honors `--inline` only when env=1
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT="$ROOT/scripts/release-audit.sh"
RELEASE="$ROOT/scripts/release.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_audit_inline_provenance.sh ══"

# ── Test 1: release.sh sets _GITX_INTERNAL_INLINE=1 before invoking audit ──
# Look inside run_deep_audit() for the env export adjacent to --inline.
block=$(awk '/^run_deep_audit\(\)/,/^\}/' "$RELEASE")
if echo "$block" | grep -qE '_GITX_INTERNAL_INLINE.*=.*1|_GITX_INTERNAL_INLINE="1"'; then
    ok "release.sh sets _GITX_INTERNAL_INLINE=1 in run_deep_audit"
else
    fail "release.sh does NOT set _GITX_INTERNAL_INLINE — audit accepts --inline from any caller"
fi

# ── Test 2: release-audit.sh checks env before honoring --inline ───────────
if grep -qE '_GITX_INTERNAL_INLINE' "$AUDIT"; then
    ok "release-audit.sh references _GITX_INTERNAL_INLINE env"
else
    fail "release-audit.sh ignores _GITX_INTERNAL_INLINE — provenance check missing"
fi

# ── Test 3: behavioral — --inline without env prints warning ────────────
# Probe with a nonexistent version so audit aborts early but argv parsing
# fires first. Expect a warning about untrusted --inline invocation.
warn_out=$(env -u _GITX_INTERNAL_INLINE bash "$AUDIT" --inline v99.99.99 2>&1 | head -10 || true)
if echo "$warn_out" | grep -qiE 'inline.*ignored|inline.*untrusted|provenance|_GITX_INTERNAL_INLINE'; then
    ok "audit warns when --inline used without _GITX_INTERNAL_INLINE env"
else
    fail "audit silently accepts --inline from any caller (no warning)"
    echo "     stderr/stdout:"
    echo "$warn_out" | head -5 | sed 's/^/       /'
fi

# ── Test 4: behavioral — --inline WITH env produces no warning ──────────
no_warn_out=$(_GITX_INTERNAL_INLINE=1 bash "$AUDIT" --inline v99.99.99 2>&1 | head -10 || true)
if echo "$no_warn_out" | grep -qiE 'inline.*ignored|inline.*untrusted|provenance'; then
    fail "audit warns even when env IS set — should be silent"
else
    ok "audit silent when --inline used with _GITX_INTERNAL_INLINE=1"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
