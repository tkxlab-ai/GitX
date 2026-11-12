#!/bin/bash
# test_changelog_gate.sh — tests for CHANGELOG gate awk range extraction
# Verifies: exact version matching, '.' not wildcarding, TODO detection
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_SH="$SCRIPT_DIR/../scripts/release.sh"
AUDIT_SH="$SCRIPT_DIR/../scripts/release-audit.sh"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_changelog_gate.sh ══"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Create a realistic CHANGELOG with two versions
cat > "$TMP/CHANGELOG.md" <<'EOF'
# Test Project — Release History

## v1.0.0 — 2026-04-22

✨ 新增：初始发布

Artifacts: `Release/v1.0.0/`

---
## v1X0Y0 — 2026-03-01

<!-- TODO: old entry with placeholder -->

Artifacts: `Release/v1X0Y0/`

---
EOF

# ── Test 1: grep -F exact match — v1.0.0 should match, v1X0Y0 should not ──

if grep -qF "## v1.0.0 " "$TMP/CHANGELOG.md"; then
    ok "grep -F: v1.0.0 correctly matches exact entry"
else
    fail "grep -F: v1.0.0 did NOT match — grep -F broken"
fi

if ! grep -qF "## v1X0Y0 " "$TMP/CHANGELOG.md"; then
    fail "grep -F: v1X0Y0 should be present but wasn't found"
else
    ok "grep -F: v1X0Y0 found (correct, it exists in changelog)"
fi

# ── Test 2: awk with safe (escaped) version — v1\.0\.0 doesn't match v1X0Y0 ──

SAFE_VERSION="v1\\.0\\.0"
entry=$(awk "/^## $SAFE_VERSION /,/^---$/" "$TMP/CHANGELOG.md")

if grep -q "初始发布" <<<"$entry"; then
    ok "awk SAFE: v1\\.0\\.0 extracts correct entry content"
else
    fail "awk SAFE: v1\\.0\\.0 did NOT extract expected content"
fi

if grep -q "TODO" <<<"$entry"; then
    fail "awk SAFE: v1\\.0\\.0 wrongly captured v1X0Y0's TODO — dot wildcarded!"
else
    ok "awk SAFE: v1\\.0\\.0 did NOT capture v1X0Y0 entry (dot not wildcarding)"
fi

# ── Test 3: awk with UNSAFE version — v1.0.0 DOES match v1X0Y0 (proves the bug) ──

UNSAFE_VERSION="v1.0.0"
unsafe_entry=$(awk "/^## $UNSAFE_VERSION /,/^---$/" "$TMP/CHANGELOG.md")

if grep -q "TODO" <<<"$unsafe_entry"; then
    ok "awk UNSAFE (bug demo): v1.0.0 DID wrongly capture v1X0Y0 TODO (dot wildcarded — bug confirmed)"
else
    # On some awk implementations the bug may not manifest — that's ok, note it
    ok "awk UNSAFE: v1.0.0 did not wildcard on this awk impl (safe either way)"
fi

# ── Test 4: TODO detection in the extracted entry ──────────────────────────

SAFE_V2="v1X0Y0"
todo_entry=$(awk "/^## $SAFE_V2 /,/^---$/" "$TMP/CHANGELOG.md")

if grep -q "<!-- TODO" <<<"$todo_entry"; then
    ok "TODO detection: <!-- TODO found in v1X0Y0 entry"
else
    fail "TODO detection: <!-- TODO NOT found in v1X0Y0 entry"
fi

# ── Test 5: release.sh uses SAFE_VERSION (grep -F or escaped awk) ──────────
# S2-2: $VERSION dot must be escaped in awk/grep to prevent wildcard matching
if grep -qE "grep -qF|SAFE_VERSION" "$RELEASE_SH"; then
    ok "release.sh uses grep -F or SAFE_VERSION for version matching"
else
    fail "release.sh MISSING grep -F / SAFE_VERSION (S2-2: dot wildcards v1X0Y0 as v1.0.0)"
fi

# ── Test 6: release-audit.sh uses SAFE_VERSION for §4 CHANGELOG awk/grep ──
# S2-2 (audit half): §4 entry extraction + top-of-file version check must also escape dots
if grep -qE "SAFE_VERSION|grep -qF" "$AUDIT_SH"; then
    ok "release-audit.sh §4 uses grep -F or SAFE_VERSION"
else
    fail "release-audit.sh MISSING grep -F / SAFE_VERSION in §4 (S2-2 audit half: awk dot wildcards)"
fi

# ── Test 7: release.sh scaffold anchors on the first `## ` line ─────────────
# A fixed `head -4` split put the new entry BELOW the existing top entry when
# the header was not exactly 4 lines, so audit §4 saw the wrong top version.
SC="$TMP/scaffold"
mkdir -p "$SC/skills/demo/" "$SC/Release"
printf -- '---\nname: demo\ndescription: d\n---\n# Demo\n' > "$SC/skills/demo/SKILL.md"
printf 'v0.0.2\n' > "$SC/skills/demo/VERSION"
cat > "$SC/Release/CHANGELOG.md" <<'EOF'
# Demo — Release History

## v0.0.1 — 2026-01-01

old body line one
old body line two

---
EOF
set +e
sc_out=$(cd "$TMP" && PROJECT_ROOT="$SC" PROJECT_NAME=demo SKILL_NAME=demo \
         bash "$RELEASE_SH" v0.0.2 2>&1)
sc_rc=$?
set -e
new_ln=$(awk '/^## v0\.0\.2 /{print NR; exit}' "$SC/Release/CHANGELOG.md")
old_ln=$(awk '/^## v0\.0\.1 /{print NR; exit}' "$SC/Release/CHANGELOG.md")
if [ "$sc_rc" -ne 0 ] && [ -n "$new_ln" ] && [ -n "$old_ln" ] && [ "$new_ln" -lt "$old_ln" ]; then
    ok "scaffold: new ## v0.0.2 inserted ABOVE existing ## v0.0.1 (2-line header)"
else
    fail "scaffold: v0.0.2 at line '${new_ln}', v0.0.1 at '${old_ln}' (rc=$sc_rc)"
    echo "$sc_out" | tail -5
fi
old_section=$(awk '/^## v0\.0\.1 /,/^---$/' "$SC/Release/CHANGELOG.md")
expected_old=$(printf '## v0.0.1 — 2026-01-01\n\nold body line one\nold body line two\n\n---')
if [ "$old_section" = "$expected_old" ] && [ "$(head -1 "$SC/Release/CHANGELOG.md")" = "# Demo — Release History" ]; then
    ok "scaffold: header + existing v0.0.1 body intact"
else
    fail "scaffold: header or v0.0.1 body mangled"
fi

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
