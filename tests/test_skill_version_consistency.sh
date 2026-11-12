#!/bin/bash
# test_skill_version_consistency.sh — S3-3 TDD
# Verifies skill versioning uses VERSION sidecar files, not SKILL.md metadata.
#
# exit: 0=pass, 1=fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../SKILL.md"
ROOT_VERSION="$SCRIPT_DIR/../VERSION"
BUNDLE_VERSION="$SCRIPT_DIR/../skills/gitx-release/VERSION"
RELEASE_SH="$SCRIPT_DIR/../scripts/release.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_skill_version_consistency.sh ══"

# ── Test 1: frontmatter has no Codex-invalid metadata block ────────────────
frontmatter=$(awk '/^---$/{c++; next} c==1' "$SKILL_MD")
if grep -qE '^metadata:[[:space:]]*$' <<<"$frontmatter"; then
    fail "SKILL.md frontmatter has Codex-invalid 'metadata:' block"
else
    ok "SKILL.md frontmatter has no metadata block (Codex loader compatible)"
fi

# ── Test 2: VERSION sidecars exist ─────────────────────────────────────────
if [ -f "$ROOT_VERSION" ] && [ -f "$BUNDLE_VERSION" ]; then
    ok "VERSION sidecars exist at root and bundled skill"
else
    fail "VERSION sidecars missing"
fi

# ── Test 3: top-level `version:` is NOT used ───────────────────────────────
if grep -qE '^version:' <<<"$frontmatter"; then
    fail "SKILL.md has top-level 'version:' — Codex loader may reject"
else
    ok "SKILL.md has NO top-level 'version:'"
fi

# ── Test 4: version value is a valid semver-ish string ─────────────────────
sk_version="$(tr -d '[:space:]' < "$ROOT_VERSION" 2>/dev/null || true)"
if [ -n "${sk_version:-}" ] && grep -qE '^v[0-9]+\.[0-9]+(\.[0-9]+)?(-(alpha|beta|rc)\.?[0-9]*)?$' <<<"$sk_version"; then
    ok "VERSION '$sk_version' matches TKX format"
else
    fail "VERSION '$sk_version' invalid (expected vX.Y[.Z][-alpha|beta|rc[.N]])"
fi

bundle_version="$(tr -d '[:space:]' < "$BUNDLE_VERSION" 2>/dev/null || true)"
if [ "$sk_version" = "$bundle_version" ]; then
    ok "root VERSION and bundled VERSION are identical"
else
    fail "root VERSION '$sk_version' differs from bundled VERSION '$bundle_version'"
fi

# ── Test 5: release.sh reads VERSION sidecar ───────────────────────────────
if grep -q 'VERSION_FILE=' "$RELEASE_SH" && grep -q 'tr -d.*< "$VERSION_FILE"' "$RELEASE_SH"; then
    ok "release.sh reads VERSION sidecar"
else
    fail "release.sh does not read VERSION sidecar"
fi

# ── Test 6: mismatch produces a failure message (static grep) ──────────────
if grep -qE 'VERSION.*(不一致|mismatch|≠|不等)' "$RELEASE_SH"; then
    ok "release.sh has a mismatch error message"
else
    fail "release.sh has no mismatch error message for version inconsistency"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
