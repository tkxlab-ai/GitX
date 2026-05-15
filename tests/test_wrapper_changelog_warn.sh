#!/bin/bash
# test_wrapper_changelog_warn.sh — v1.0.8 hardening (Arch #2).
# `gitx-release.sh` auto-appends "Automated GitX release: ..." to CHANGELOG
# so release.sh's TODO gate doesn't abort. Side effect: wrapper releases
# always ship with a placeholder CHANGELOG body. Quality regression vs the
# manual `release.sh` flow which emits a real `<!-- TODO -->` marker.
#
# Fix: wrapper inserts a sentinel HTML comment alongside the auto-line, then
# checks for it at end of run and warns the operator to edit before publish.
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$ROOT/scripts/gitx-release.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_wrapper_changelog_warn.sh ══"

# Static: wrapper writes a sentinel HTML comment in the auto-CHANGELOG entry
if grep -qE '<!-- *gitx-auto-entry|<!-- *auto-generated' "$WRAPPER"; then
    ok "wrapper inserts auto-entry sentinel comment"
else
    fail "wrapper does not insert sentinel — operator can't tell auto from manual"
fi

# Static: wrapper checks for the sentinel after release succeeds and warns
if grep -qE 'gitx-auto-entry|auto-generated' "$WRAPPER" && \
   grep -qiE 'placeholder|edit.*CHANGELOG|replace.*release notes|未编辑|占位' "$WRAPPER"; then
    ok "wrapper checks sentinel and warns about unedited CHANGELOG"
else
    fail "wrapper does not warn when CHANGELOG still has auto-line at end of run"
fi

# Behavioral: simulate the warning logic on a fixture CHANGELOG with sentinel.
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
cat > "$FIXTURE/CHANGELOG.md" <<'EOF'
# Test — Release History

## v1.0.0 — 2026-01-01

<!-- gitx-auto-entry: replace with real release notes before publishing -->
- Automated GitX release: run full gate suite, package artifacts, generate attestations, and complete deep audit.

Artifacts: `Release/test-v1.0.0/`

---
EOF

# The check should grep for the sentinel and detect it.
if grep -qF '<!-- gitx-auto-entry' "$FIXTURE/CHANGELOG.md"; then
    ok "sentinel-bearing CHANGELOG is detectable by grep -qF"
else
    fail "sentinel-bearing CHANGELOG not detected (wrong sentinel format)"
fi

# Removing the sentinel (simulating operator edit) should make grep fail.
sed -i.bak '/gitx-auto-entry/d' "$FIXTURE/CHANGELOG.md"
if grep -qF '<!-- gitx-auto-entry' "$FIXTURE/CHANGELOG.md"; then
    fail "sentinel still present after removal (test fixture issue)"
else
    ok "post-edit CHANGELOG (sentinel removed) is correctly detected as edited"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
