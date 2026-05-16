#!/bin/bash
# test_release_private_state_excludes.sh — prevent local agent/cache state from shipping
#
# Verifies:
#   1. release.sh excludes private/local state directories from source staging.
#   2. release-audit.sh rejects source tarballs containing those paths.
#
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$PROJECT_ROOT/scripts/release.sh"
AUDIT_SH="$PROJECT_ROOT/scripts/release-audit.sh"

PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_release_private_state_excludes.sh ══"

# ── Test 1: release.sh excludes local AI/session/cache dotdirs ───────────
# .python-version: pyenv local pin — untracked local state, never a
# shippable input; rsync staging ignores .gitignore so it must be on the
# explicit --exclude list or it leaks into the public source tarball
# (codex P2, v1.9.6). Dual-source byte-identity covers the bundle copy.
for pat in ".omc" ".1by1" ".i18n-cache" ".cache" ".env*" ".ssh" ".aws" ".python-version" ".github-publish-wt"; do
    if grep -Fq -- "--exclude='$pat'" "$RELEASE_SH" || grep -Fq -- "--exclude=\"$pat\"" "$RELEASE_SH"; then
        ok "release.sh excludes $pat"
    else
        fail "release.sh does not exclude $pat from source tarball staging"
    fi
done

# ── Test 2: audit rejects these paths if they appear in tarball list ─────
if grep -qE '不含.*(\.1by1|i18n-cache|private local state|hidden state)' "$AUDIT_SH"; then
    ok "release-audit.sh checks for private/local state paths"
else
    fail "release-audit.sh does not reject private/local state paths in tarball"
fi

# ── Test 2b: fail-closed net must ALSO reject a root .python-version ──────
# codex P2 (v1.9.6): the staging-exclude (Test 1) only PREVENTS the leak
# on a fresh build. A stale or externally-supplied source tarball with a
# root pyenv pin must independently FAIL audit. Defense-in-depth: prevent
# AND detect. Both release-audit.sh (dual-source) and the artifact scanner
# must carry .python-version in their private-state regex.
if grep -qE 'python-version' "$AUDIT_SH"; then
    ok "release-audit.sh fail-closed net rejects root .python-version"
else
    fail "release-audit.sh private-state regex omits .python-version (fail-closed gap)"
fi

# ── Test 2c: fail-closed net must ALSO reject handoff v2 working memory ───
# codex P2 (v1.9.6): release.sh now PREVENTS GOTCHAS.md / Handoff_Logs/ /
# Handoff_Decisions/ / Handoff_Logs.archive/ / HANDOFF.md.bak /
# HANDOFF.md.pre-v2-backup from staging, but a stale/external tarball
# carrying one must independently FAIL audit (prevent AND detect, same as
# the pre-existing HANDOFF.md / HANDOFF.archive.md check_not lines).
if grep -qF '不含 handoff v2 工作记忆' "$AUDIT_SH" \
   && grep -qF 'GOTCHAS\.md$' "$AUDIT_SH" \
   && grep -qF 'Handoff_Logs/' "$AUDIT_SH" \
   && grep -qF 'Handoff_Decisions/' "$AUDIT_SH" \
   && grep -qF 'HANDOFF\.md\.pre-v2-backup$' "$AUDIT_SH"; then
    ok "release-audit.sh fail-closed net rejects handoff v2 working-memory files"
else
    fail "release-audit.sh omits handoff v2 files (GOTCHAS/Handoff_Logs/Handoff_Decisions/pre-v2-backup) — fail-closed gap"
fi

# ── Test 2d: fail-closed net must ALSO reject .github-publish-wt ──────────
# codex P2 (v1.9.6): the gitx-sop publish worktree is now staging-excluded
# (prevention) — a stale/external tarball carrying it must independently
# FAIL audit too (detection), same defense-in-depth as .python-version.
if grep -qF 'github-publish-wt' "$AUDIT_SH"; then
    ok "release-audit.sh fail-closed net rejects .github-publish-wt"
else
    fail "release-audit.sh omits .github-publish-wt — fail-closed gap"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
