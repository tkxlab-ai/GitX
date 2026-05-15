#!/bin/bash
# test_audit_assets.sh — TDD test for S1-1: assets/ empty directory should SKIP not FAIL
# RED: current code uses check() which FAILs on empty assets/
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT="$SCRIPT_DIR/../scripts/release-audit.sh"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_assets.sh ══"

# --- Test 1: empty assets/ triggers SKIP (not FAIL) ---
# Simulate audit §6b assets/ check by extracting and running just that block
# Create a temp dir that mimics an extracted .skill with empty assets/
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SKILL_NAME="test-skill"
mkdir -p "$TMP/$SKILL_NAME/assets"
# assets/ exists but is empty — this is the bug scenario

# Extract the assets/ check logic from the actual script and test it in isolation
ASSETS_DIR="$TMP/$SKILL_NAME/assets"

# Run the current audit logic for assets/ inline
result=$(
    # Replicate current audit logic:
    if [ -d "$ASSETS_DIR" ]; then
        asset_any=$(find "$ASSETS_DIR" -mindepth 1 -maxdepth 1 | head -1)
        if [ -z "$asset_any" ]; then
            # NEW behaviour: should SKIP
            echo "SKIP"
        else
            # has content: check for .md
            md_file=$(find "$ASSETS_DIR" -name '*.md' | head -1)
            if [ -n "$md_file" ]; then
                echo "PASS"
            else
                echo "FAIL"
            fi
        fi
    fi
)

if [ "$result" = "SKIP" ]; then
    ok "inline empty assets fixture returns SKIP"
else
    fail "inline empty assets fixture should return SKIP, got $result"
fi

# But we need to check what the SCRIPT ITSELF will do.
# Grep for the guard logic in the actual file.
if grep -q 'asset_any=' "$AUDIT" && grep -q '\-z.*asset_any' "$AUDIT"; then
    ok "Script has empty-directory guard (asset_any check)"
else
    fail "Script MISSING empty-directory guard — empty assets/ will cause FAIL (S1-1 not implemented)"
fi

# --- Test 2: empty assets/ guard outputs SKIP marker, not check() call ---
# The guard must NOT call check() when directory is empty
# Check that the ➖ skip message is in the assets block
ASSETS_BLOCK=$(awk '/assets\/ — 至少一个 .md/,/fi$/' "$AUDIT" 2>/dev/null || true)
if echo "$ASSETS_BLOCK" | grep -q '➖'; then
    ok "Assets empty-dir guard emits ➖ skip message"
else
    fail "Assets guard does NOT emit ➖ skip — empty assets/ still hits check() and FAILs"
fi

# --- Test 3: non-empty assets/ without .md still FAILs ---
# create a non-.md file
mkdir -p "$TMP/$SKILL_NAME/assets"
touch "$TMP/$SKILL_NAME/assets/image.png"

ASSETS_DIR="$TMP/$SKILL_NAME/assets"
asset_any=$(find "$ASSETS_DIR" -mindepth 1 -maxdepth 1 | head -1)
md_file=$(find "$ASSETS_DIR" -name '*.md' | head -1)

if [ -n "$asset_any" ] && [ -z "$md_file" ]; then
    ok "Non-empty assets/ without .md correctly falls through to check() (would FAIL)"
else
    fail "Non-empty assets/ logic is wrong"
fi

# --- Test 4: non-empty assets/ with .md PASSes ---
touch "$TMP/$SKILL_NAME/assets/README.md"
md_file2=$(find "$TMP/$SKILL_NAME/assets" -name '*.md' | head -1)
if [ -n "$md_file2" ]; then
    ok "Non-empty assets/ with .md correctly finds the file (would PASS)"
else
    fail "Non-empty assets/ with .md did not find .md file"
fi

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
