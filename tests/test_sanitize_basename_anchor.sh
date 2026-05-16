#!/bin/bash
# test_sanitize_basename_anchor.sh — v1.0.8 hardening (Sec #1).
# release-sanitize.sh excludes its own scanner files from being scanned to
# avoid self-recursion on the credential patterns. The original guards used
# `! -name 'scan-credentials.sh'` which matches ANY file named that, anywhere.
# A release dir with `references/scan-credentials.sh` or
# `assets/TEST-SCENARIOS.md` would silently skip those files from the entire
# scan. This test asserts the exclusion is anchored to a canonical path.
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SANITIZE="$ROOT/scripts/release-sanitize.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_sanitize_basename_anchor.sh ══"

# Static: every -name exclusion that targets a project file should also have
# a -path counterpart (or be replaced by -path). Bare -name matches anywhere.
self_excludes=(
    'release-sanitize.sh'
    'scan-credentials.sh'
    'test_release_sanitize.sh'
    'test_scan_credentials.sh'
    'TKX_Git_Release_policy_and_process.md'
    'TEST-SCENARIOS.md'
)
for f in "${self_excludes[@]}"; do
    if grep -qE "\-path[[:space:]]+['\"][^'\"]*${f//./\\.}['\"]" "$SANITIZE"; then
        ok "exclusion for '$f' is path-anchored"
    else
        fail "exclusion for '$f' uses bare -name (collides on any same-basename file)"
    fi
done

# Behavioral: a planted file with colliding basename in an unexpected path
# must be scanned (i.e., its credentials must be found).
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/references"
# Plant a file with a colliding basename, containing a fake AWS key. The
# pre-fix sanitizer would skip this entire file because of the `-name` match.
JWT_HDR_A='ey'; JWT_HDR_B='J'; JWT_HDR_C='hbGciOiJIUzI1NiJ9'
JWT_PL_A='ey';  JWT_PL_B='J';  JWT_PL_C='zdWIiOiIxMjM0NTY3ODkwIn0'
JWT_SIG='SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c'
JWT_BODY="${JWT_HDR_A}${JWT_HDR_B}${JWT_HDR_C}.${JWT_PL_A}${JWT_PL_B}${JWT_PL_C}.${JWT_SIG}"
{
    echo "# This file's basename collides with the scanner's exclusion list."
    echo "# But it lives at references/scan-credentials.sh, NOT scripts/."
    echo "# A bare -name 'scan-credentials.sh' would skip it; -path would not."
    echo "Bearer ${JWT_BODY}"
} > "$FIXTURE/references/scan-credentials.sh"

scan_out=$(PROJECT_ROOT="$FIXTURE" bash "$SANITIZE" "$FIXTURE" 2>&1 || true)
if echo "$scan_out" | grep -qiE 'JWT|bearer|credential'; then
    ok "planted credential at colliding-basename path is detected (not skipped)"
else
    fail "planted credential at references/scan-credentials.sh is NOT detected"
    echo "       sanitize output head:"
    echo "$scan_out" | head -5 | sed 's/^/         /'
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
