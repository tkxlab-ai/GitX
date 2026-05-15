#!/bin/bash
# test_wrapper_changelog_anchor.sh — v1.2 A1 fix.
#
# Wrapper `ensure_changelog_entry` assumed CHANGELOG starts with a fixed
# 4-line header (head -4 + tail -n +5). Mac-release v0.1.0 self-bake had
# a 2-line header — wrapper swallowed the v0.0.1-dev entry into "header"
# and the audit §4 then saw the wrong top version.
#
# Fix: anchor insertion to the first `^## ` line, auto-detecting header
# length. Header longer or shorter than 4 lines no longer breaks insertion.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$ROOT/scripts/gitx-release.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_wrapper_changelog_anchor.sh ══"

# === Static: wrapper no longer hardcodes head -4 / tail -n +5 ===
if ! grep -qE 'head -4 "\$changelog"' "$WRAPPER"; then
    ok "wrapper no longer uses 'head -4 \$changelog' (4-line header assumption removed)"
else
    fail "wrapper still has 'head -4 \$changelog' — fragile to non-default header lengths"
fi

if ! grep -qE 'tail -n \+5 "\$changelog"' "$WRAPPER"; then
    ok "wrapper no longer uses 'tail -n +5 \$changelog' (line-5 hardcode removed)"
else
    fail "wrapper still has 'tail -n +5 \$changelog' — companion to head -4 hardcode"
fi

# === Static: wrapper anchors to first `^## ` line ===
# Accept either awk (set-e safe: always exits 0) or grep with `|| true`.
# Plain `grep -n '^## ' | ...` would abort wrapper under pipefail+set-e
# when no match found (default CHANGELOG with header only). awk preferred.
if grep -qE "awk .*/\^## /|grep -nE? .\^## .* \|\| true" "$WRAPPER"; then
    ok "wrapper anchors to first '## ' line via set-e-safe pattern (awk or grep||true)"
else
    fail "wrapper anchor logic missing or unsafe under set -euo pipefail"
fi

# === Behavioral: extract function and exercise on fixtures ===
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
FN_FILE="$FIXTURE/fn.sh"
# slice from `ensure_changelog_entry() {` to the matching first column `}`
sed -n '/^ensure_changelog_entry()/,/^}$/p' "$WRAPPER" > "$FN_FILE"

# Required env the function reads
export PROJECT_ROOT="$FIXTURE"
export PROJECT_NAME="testproj"

# shellcheck disable=SC1090
source "$FN_FILE"

# --- Case 1: default 4-line header (existing-compat) ---
mkdir -p "$FIXTURE/Release"
cat > "$FIXTURE/Release/CHANGELOG.md" <<'EOF'
# Test — Release History

记录各版本的关键变化。最新版本在最上面。

## v1.0.0 — 2026-01-01
- existing entry
EOF
ensure_changelog_entry "v1.0.1" >/dev/null 2>&1 || true
LINE5=$(sed -n '5p' "$FIXTURE/Release/CHANGELOG.md")
if echo "$LINE5" | grep -q '^## v1.0.1'; then
    ok "case 1 (4-line header): new entry at line 5 (existing position preserved)"
else
    fail "case 1: expected '## v1.0.1' at line 5, got: $LINE5"
fi
if grep -q '^## v1.0.0' "$FIXTURE/Release/CHANGELOG.md"; then
    ok "case 1: existing v1.0.0 entry preserved"
else
    fail "case 1: existing v1.0.0 entry lost — header logic ate it"
fi

# --- Case 2: 2-line minimalist header (mac-release-style) ---
rm -rf "$FIXTURE/Release"
mkdir -p "$FIXTURE/Release"
cat > "$FIXTURE/Release/CHANGELOG.md" <<'EOF'
# Test — Release History

## v0.0.1-dev — 2026-01-01
- existing entry
EOF
ensure_changelog_entry "v0.0.2" >/dev/null 2>&1 || true
LINE3=$(sed -n '3p' "$FIXTURE/Release/CHANGELOG.md")
if echo "$LINE3" | grep -q '^## v0.0.2'; then
    ok "case 2 (2-line header): new entry at line 3 (anchor-correct, mac-release fixed)"
else
    fail "case 2: expected '## v0.0.2' at line 3, got: $LINE3"
fi
if grep -q '^## v0.0.1-dev' "$FIXTURE/Release/CHANGELOG.md"; then
    ok "case 2: existing v0.0.1-dev entry preserved (original bug: header ate it)"
else
    fail "case 2: existing v0.0.1-dev entry LOST — wrapper still swallows non-default headers"
fi

# --- Case 3: no CHANGELOG / no existing entries (fallback append path) ---
rm -rf "$FIXTURE/Release"
ensure_changelog_entry "v0.1.0" >/dev/null 2>&1 || true
if [ -f "$FIXTURE/Release/CHANGELOG.md" ] && grep -q '^## v0.1.0' "$FIXTURE/Release/CHANGELOG.md"; then
    ok "case 3 (no CHANGELOG): function creates default + appends entry"
else
    fail "case 3: function failed on missing CHANGELOG"
fi

# --- Case 4: idempotency — same version twice does not duplicate ---
ensure_changelog_entry "v0.1.0" >/dev/null 2>&1 || true
COUNT=$(grep -c '^## v0.1.0' "$FIXTURE/Release/CHANGELOG.md")
if [ "$COUNT" -eq 1 ]; then
    ok "case 4 (idempotent): same version twice does not duplicate"
else
    fail "case 4: expected 1 occurrence of v0.1.0, got $COUNT"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
