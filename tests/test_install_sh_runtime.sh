#!/bin/bash
# test_install_sh_runtime.sh — runtime contract for install.sh §6.10
# Verifies install.sh actually responds to --help / --dry-run / --force
# (beyond the audit static grep, which tests audit not install.sh itself).
# exit: 0=pass, 1=fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SH="$SCRIPT_DIR/../install.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_install_sh_runtime.sh ══"

# ── Test 1: install.sh exists and is executable ────────────────────────────
if [ -x "$INSTALL_SH" ]; then
    ok "install.sh exists and is executable"
else
    fail "install.sh missing or not executable: $INSTALL_SH"
    echo ""
    echo "Results: ✅$PASS passed / ❌$FAIL failed"
    exit 1
fi

# ── Test 2: --help exits 0 and prints usage ────────────────────────────────
help_out=$(bash "$INSTALL_SH" --help 2>&1 || true)
help_status=$(bash "$INSTALL_SH" --help > /dev/null 2>&1; echo $?)
if [ "$help_status" -eq 0 ]; then
    ok "install.sh --help exits 0"
else
    fail "install.sh --help exits $help_status (expected 0)"
fi

if echo "$help_out" | grep -qiE 'usage|用法'; then
    ok "install.sh --help prints usage text"
else
    fail "install.sh --help output missing 'usage' keyword"
fi

# ── Test 3: --dry-run does not touch filesystem ────────────────────────────
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT
dry_status=$(HOME="$FAKE_HOME" bash "$INSTALL_SH" --dry-run > /dev/null 2>&1; echo $?)
if [ "$dry_status" -eq 0 ]; then
    ok "install.sh --dry-run exits 0"
else
    fail "install.sh --dry-run exits $dry_status (expected 0)"
fi
if [ ! -d "$FAKE_HOME/.claude" ] || ! find "$FAKE_HOME/.claude" -name 'gitx-release' 2>/dev/null | grep -q .; then
    ok "install.sh --dry-run did not create skill dir in fake HOME"
else
    fail "install.sh --dry-run WROTE to $FAKE_HOME — not dry!"
fi

# ── Test 4: --force flag is accepted (no error on unknown flag) ────────────
force_help=$(bash "$INSTALL_SH" --force --dry-run 2>&1 || true)
if ! echo "$force_help" | grep -qiE 'unknown|unrecognized|invalid.*option'; then
    ok "install.sh accepts --force flag"
else
    fail "install.sh rejects --force: $force_help"
fi

# ── Test 5: existing user-owned CLI dirs are not deleted without --force ──
COLLIDE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME" "$COLLIDE_HOME"' EXIT
mkdir -p "$COLLIDE_HOME/.claude/skills/gitx-release"
echo "user data" > "$COLLIDE_HOME/.claude/skills/gitx-release/KEEP.txt"

set +e
HOME="$COLLIDE_HOME" bash "$INSTALL_SH" > /dev/null 2>&1
collision_status=$?
set -e

if [ "$collision_status" -ne 0 ]; then
    ok "install.sh refuses existing user-owned Claude skill dir without --force"
else
    fail "install.sh overwrote existing user-owned Claude skill dir without --force"
fi

if [ -f "$COLLIDE_HOME/.claude/skills/gitx-release/KEEP.txt" ]; then
    ok "install.sh preserved existing Claude skill dir contents"
else
    fail "install.sh deleted existing Claude skill dir contents"
fi

# ── Test 6: existing canonical non-directory is not deleted without --force ─
CANON_COLLIDE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME" "$COLLIDE_HOME" "$CANON_COLLIDE_HOME"' EXIT
mkdir -p "$CANON_COLLIDE_HOME/.agents/skills"
echo "user file" > "$CANON_COLLIDE_HOME/.agents/skills/gitx-release"

set +e
HOME="$CANON_COLLIDE_HOME" bash "$INSTALL_SH" > /dev/null 2>&1
canon_collision_status=$?
set -e

if [ "$canon_collision_status" -ne 0 ]; then
    ok "install.sh refuses existing canonical file without --force"
else
    fail "install.sh overwrote existing canonical file without --force"
fi

if [ -f "$CANON_COLLIDE_HOME/.agents/skills/gitx-release" ]; then
    ok "install.sh preserved existing canonical file"
else
    fail "install.sh deleted existing canonical file"
fi

# ── Test 7: successful install prints per-CLI command summary ──────────────
SUMMARY_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME" "$COLLIDE_HOME" "$CANON_COLLIDE_HOME" "$SUMMARY_HOME"' EXIT

set +e
summary_out=$(HOME="$SUMMARY_HOME" bash "$INSTALL_SH" 2>&1)
summary_status=$?
set -e

if [ "$summary_status" -eq 0 ]; then
    ok "install.sh succeeds in clean fake HOME"
else
    fail "install.sh failed in clean fake HOME: $summary_status"
fi

for expected in \
    "Installed CLI commands" \
    "Claude Code" \
    "/gitx-release" \
    "Codex CLI" \
    "\$gitx-release" \
    "\$git-release-pipeline" \
    "/skills" \
    "OpenCode" \
    "Gemini CLI"; do
    if echo "$summary_out" | grep -q "$expected"; then
        ok "install summary includes: $expected"
    else
        fail "install summary missing: $expected"
    fi
done

if [ -d "$SUMMARY_HOME/.codex/skills" ]; then
    codex_entries=$(find "$SUMMARY_HOME/.codex/skills" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort | tr '\n' ' ')
else
    codex_entries=""
fi
if [ -z "$codex_entries" ]; then
    ok "install.sh does not create duplicate visible Codex alias skills"
else
    fail "install.sh created duplicate visible Codex alias skills: $codex_entries"
fi

# ── Test 8: --force cleans legacy Codex duplicate selector paths ───────────
LEGACY_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME" "$COLLIDE_HOME" "$CANON_COLLIDE_HOME" "$SUMMARY_HOME" "$LEGACY_HOME"' EXIT
mkdir -p \
    "$LEGACY_HOME/.agents/skills/GitX-release" \
    "$LEGACY_HOME/.codex/skills/gitx-release" \
    "$LEGACY_HOME/.codex/skills/GitX-release" \
    "$LEGACY_HOME/.codex/skills/gitx-release"
printf 'legacy\n' > "$LEGACY_HOME/.agents/skills/GitX-release/SKILL.md"
printf 'legacy\n' > "$LEGACY_HOME/.codex/skills/gitx-release/SKILL.md"
printf 'legacy\n' > "$LEGACY_HOME/.codex/skills/GitX-release/SKILL.md"
printf 'legacy\n' > "$LEGACY_HOME/.codex/skills/gitx-release/SKILL.md"

set +e
legacy_out=$(HOME="$LEGACY_HOME" bash "$INSTALL_SH" --force 2>&1)
legacy_status=$?
set -e

if [ "$legacy_status" -eq 0 ]; then
    ok "install.sh --force succeeds with legacy Codex selector duplicates"
else
    fail "install.sh --force failed with legacy Codex selector duplicates: $legacy_status $legacy_out"
fi

agent_entries=$(find "$LEGACY_HOME/.agents/skills" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort | tr '\n' ' ')
if [ -d "$LEGACY_HOME/.codex/skills" ]; then
    codex_entries=$(find "$LEGACY_HOME/.codex/skills" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort | tr '\n' ' ')
else
    codex_entries=""
fi
if [ "$agent_entries" = "gitx-release " ] && [ -z "$codex_entries" ]; then
    ok "install.sh --force removes legacy duplicate selector entries"
else
    fail "install.sh --force left duplicate selector entries: agents=[$agent_entries] codex=[$codex_entries]"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
