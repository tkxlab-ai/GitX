#!/bin/bash
# test_release_skill_creator_discovery.sh — v1.2.1 B fix.
#
# release.sh:326 hardcoded
#   SKILL_CREATOR="$HOME/.claude/plugins/cache/claude-plugins-official/skill-creator/unknown/skills/skill-creator"
# using the literal segment 'unknown' as if it were a placeholder, but never
# implementing glob expansion. Claude Code plugin marketplace assigns a real
# hash dir name (e.g. 76b35e91d1c9) so this hardcoded path NEVER matches.
# Result: every self-bake printed "skill-creator 不在，改用 zip 直接打包" even
# when skill-creator was actually installed via Claude Code plugins.
#
# Fix (v1.2.1): _discover_skill_creator() helper globs the cache base, falls
# back to legacy ~/.claude/skills/ and ~/.agents/skills/ paths, and verifies
# scripts/package_skill.py exists in the candidate before accepting (avoid
# false-positive on stale empty dirs).
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_release_skill_creator_discovery.sh ══"

# === Static 1: no more hardcoded 'unknown' segment ===
if ! grep -qE "skill-creator/unknown" "$RELEASE_SH"; then
    ok "release.sh no longer hardcodes 'skill-creator/unknown' path segment"
else
    fail "release.sh still has 'skill-creator/unknown' hardcode — glob expansion missing"
fi

# === Static 2: discovery references plugin cache base ===
if grep -qE "plugins/cache/claude-plugins-official/skill-creator" "$RELEASE_SH"; then
    ok "release.sh references plugins/cache/claude-plugins-official/skill-creator base"
else
    fail "release.sh missing plugin marketplace cache base path"
fi

# === Static 3: discovery validates package_skill.py before accepting ===
if grep -qE 'package_skill\.py' "$RELEASE_SH"; then
    ok "release.sh checks package_skill.py existence (validates candidate is real)"
else
    fail "release.sh does not verify package_skill.py — risks accepting stale empty cache"
fi

# === Static 4: _discover_skill_creator helper function exists ===
if grep -qE '^_discover_skill_creator\(\)' "$RELEASE_SH"; then
    ok "release.sh defines _discover_skill_creator() helper"
else
    fail "release.sh missing _discover_skill_creator() helper function"
fi

# === Behavioral: source the helper from a fixture HOME and verify resolution ===
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

# Extract _discover_skill_creator function body into a temp script
FN_FILE="$FIXTURE/discover.sh"
sed -n '/^_discover_skill_creator()/,/^}$/p' "$RELEASE_SH" > "$FN_FILE"

# Case A: planted cache hash dir with package_skill.py → discovered
mkdir -p "$FIXTURE/homeA/.claude/plugins/cache/claude-plugins-official/skill-creator/abc123hash/skills/skill-creator/scripts"
touch "$FIXTURE/homeA/.claude/plugins/cache/claude-plugins-official/skill-creator/abc123hash/skills/skill-creator/scripts/package_skill.py"
RESULT=$(HOME="$FIXTURE/homeA" bash -c "set -u; SKILL_CREATOR=''; $(cat "$FN_FILE"); _discover_skill_creator; echo \"\${SKILL_CREATOR:-NONE}\"")
if echo "$RESULT" | grep -qE "/.claude/plugins/cache/.*/abc123hash/.*/skill-creator$"; then
    ok "behavior A: planted cache hash dir → SKILL_CREATOR resolves correctly"
else
    fail "behavior A: planted cache failed. Got: $RESULT"
fi

# Case B: no cache, but ~/.claude/skills/skill-creator/ exists with package_skill.py → fallback
mkdir -p "$FIXTURE/homeB/.claude/skills/skill-creator/scripts"
touch "$FIXTURE/homeB/.claude/skills/skill-creator/scripts/package_skill.py"
RESULT=$(HOME="$FIXTURE/homeB" bash -c "set -u; SKILL_CREATOR=''; $(cat "$FN_FILE"); _discover_skill_creator; echo \"\${SKILL_CREATOR:-NONE}\"")
if echo "$RESULT" | grep -qE "/homeB/.claude/skills/skill-creator$"; then
    ok "behavior B: cache empty + ~/.claude/skills/ exists → fallback discovered"
else
    fail "behavior B: fallback failed. Got: $RESULT"
fi

# Case C: nothing exists → returns empty SKILL_CREATOR (no crash)
RESULT=$(HOME="$FIXTURE/empty" bash -c "set -u; SKILL_CREATOR=''; $(cat "$FN_FILE"); _discover_skill_creator || true; echo \"\${SKILL_CREATOR:-NONE}\"")
if [ "$RESULT" = "NONE" ]; then
    ok "behavior C: nothing exists → SKILL_CREATOR empty (zip fallback path works)"
else
    fail "behavior C: expected NONE, got: $RESULT"
fi

# Case D: empty hash dir (no package_skill.py) → rejected, not accepted
mkdir -p "$FIXTURE/homeD/.claude/plugins/cache/claude-plugins-official/skill-creator/empty/skills/skill-creator"
RESULT=$(HOME="$FIXTURE/homeD" bash -c "set -u; SKILL_CREATOR=''; $(cat "$FN_FILE"); _discover_skill_creator || true; echo \"\${SKILL_CREATOR:-NONE}\"")
if [ "$RESULT" = "NONE" ]; then
    ok "behavior D: stale empty dir rejected (package_skill.py check works)"
else
    fail "behavior D: should reject empty dir, got: $RESULT"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
