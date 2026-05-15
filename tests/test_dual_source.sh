#!/bin/bash
# test_dual_source.sh — tests for dual-source script drift detection
# Verifies: same content passes, different content fails, release-*.sh exempted
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_SH="$SCRIPT_DIR/../scripts/release.sh"
MIRROR_RELEASE_SH="$SCRIPT_DIR/../skills/gitx-release/scripts/release.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CI_WORKFLOW="$PROJECT_ROOT/.github/workflows/ci.yml"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_dual_source.sh ══"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ROOT_SCRIPTS="$TMP/scripts"
BUNDLE_SCRIPTS="$TMP/skills/my-skill/scripts"
mkdir -p "$ROOT_SCRIPTS" "$BUNDLE_SCRIPTS"

# Helper: run the drift detection filter from release.sh
# Uses the same grep-v pattern as the actual script
detect_drift() {
    local root="$1"
    local bundle="$2"
    diff -rq "$root/" "$bundle/" 2>&1 \
        | grep -v "^Only in.*scripts: release-" || true
}

# ── Test 1: identical files → no drift ─────────────────────────────────────
echo '#!/bin/bash\necho hello' > "$ROOT_SCRIPTS/scan-credentials.sh"
cp "$ROOT_SCRIPTS/scan-credentials.sh" "$BUNDLE_SCRIPTS/scan-credentials.sh"

drift=$(detect_drift "$ROOT_SCRIPTS" "$BUNDLE_SCRIPTS")
if [ -z "$drift" ]; then
    ok "Identical files: no drift detected (PASS)"
else
    fail "Identical files: drift wrongly detected: $drift"
fi

# ── Test 2: different content → drift detected ──────────────────────────────
echo '#!/bin/bash\necho MODIFIED' > "$ROOT_SCRIPTS/scan-credentials.sh"

drift=$(detect_drift "$ROOT_SCRIPTS" "$BUNDLE_SCRIPTS")
if [ -n "$drift" ]; then
    ok "Different content: drift correctly detected (FAIL signal)"
else
    fail "Different content: drift NOT detected — scanner blind to modification"
fi

# Restore
cp "$ROOT_SCRIPTS/scan-credentials.sh" "$BUNDLE_SCRIPTS/scan-credentials.sh"
echo '#!/bin/bash\necho hello' > "$ROOT_SCRIPTS/scan-credentials.sh"
cp "$ROOT_SCRIPTS/scan-credentials.sh" "$BUNDLE_SCRIPTS/scan-credentials.sh"

# ── Test 3: release-*.sh in root only → exempted ───────────────────────────
echo '#!/bin/bash\n# release script' > "$ROOT_SCRIPTS/release-audit.sh"
# release-audit.sh only in root (not in bundle) — should be exempted

drift=$(detect_drift "$ROOT_SCRIPTS" "$BUNDLE_SCRIPTS")
if [ -z "$drift" ]; then
    ok "release-audit.sh only in root: correctly exempted from drift check"
else
    fail "release-audit.sh only in root: wrongly flagged as drift: $drift"
fi

# ── Test 4: release-audit.sh with DIFFERENT content in bundle → still detected ─
cp "$ROOT_SCRIPTS/release-audit.sh" "$BUNDLE_SCRIPTS/release-audit.sh"
echo '#!/bin/bash\n# MODIFIED release script' > "$BUNDLE_SCRIPTS/release-audit.sh"

# Both have release-audit.sh but different content — "Files differ" should appear
# The grep-v only suppresses "Only in", NOT "Files ... differ"
drift=$(detect_drift "$ROOT_SCRIPTS" "$BUNDLE_SCRIPTS")
if [ -n "$drift" ]; then
    ok "release-audit.sh with different content in bundle: drift detected (content diff not exempted)"
else
    fail "release-audit.sh content diff in bundle: wrongly NOT detected"
fi

# Cleanup bundle's release-audit.sh
rm -f "$BUNDLE_SCRIPTS/release-audit.sh"

# ── Test 5: release.sh implements dual-source check ────────────────────────
if grep -q 'diff -rq.*scripts' "$RELEASE_SH"; then
    ok "release.sh implements diff -rq dual-source check"
else
    fail "release.sh MISSING diff -rq dual-source check"
fi

# ── Test 6: mirror skill must be trackable, not hidden by .gitignore ───────
if git -C "$PROJECT_ROOT" check-ignore --no-index -q "skills/gitx-release/SKILL.md"; then
    fail "skills/gitx-release is ignored by .gitignore; CI cannot enforce mirror drift"
else
    ok "skills/gitx-release is trackable by git"
fi

# ── Test 7: CI must fail closed if tracked mirror is missing ───────────────
if grep -q 'skills/gitx-release/scripts is required' "$CI_WORKFLOW"; then
    ok "CI fails closed when dual-source mirror scripts are missing"
else
    fail "CI silently skips dual-source check when mirror scripts are missing"
fi

# ── Test 8: release.sh must fail closed if either script source is missing ─
for candidate in "$RELEASE_SH" "$MIRROR_RELEASE_SH"; do
    label="${candidate#$PROJECT_ROOT/}"
    if grep -q 'Missing root scripts directory' "$candidate" \
        && grep -q 'Missing bundled scripts directory' "$candidate"; then
        ok "$label fails closed when either dual-source directory is missing"
    else
        fail "$label silently skips when a dual-source directory is missing"
    fi
done

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
