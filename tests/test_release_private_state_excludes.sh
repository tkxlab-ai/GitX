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
for pat in ".omc" ".1by1" ".i18n-cache" ".cache" ".env*" ".ssh" ".aws" ".python-version" ".github-publish-wt" ".gitx" "graphify-out" "CLAUDE.md"; do
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

# ── Test 2e: fail-closed net must ALSO reject graphify-out/ + CLAUDE.md ───
# graphify-out/ is a knowledge graph BUILT FROM the private-memory set
# (HANDOFF / Handoff_* / GOTCHAS / .omc); CLAUDE.md is local Claude
# instruction. release.sh now staging-excludes both (prevention, Test 1) —
# a stale/external tarball carrying either must independently FAIL audit
# (detection), same defense-in-depth + dual-source contract as the
# .python-version / .github-publish-wt precedents. Folded into the existing
# "private local state" regex so the audit count stays constant (no §0f rot).
if grep -qF 'graphify-out/' "$AUDIT_SH" && grep -qF 'CLAUDE\.md$' "$AUDIT_SH"; then
    ok "release-audit.sh fail-closed net rejects graphify-out/ + CLAUDE.md"
else
    fail "release-audit.sh omits graphify-out/ or CLAUDE.md — fail-closed gap"
fi

# ── Test 2f: detection MUST be path-depth-agnostic for CLAUDE.md/graphify-out ─
# codex round-3 [high]: the cd843dd regex was root-anchored
# (^${P}-${V}/(...|graphify-out/|CLAUDE\.md$)) so a stale/external tarball
# carrying NESTED skills/<skill>/CLAUDE.md or docs/.../graphify-out/ would
# PASS the fail-closed net. The detection half must catch these at ANY depth
# under the release root (pre-existing dotdir entries stay root-anchored —
# unchanged, Karpathy#3). Still ONE check_not (Gotcha #62, TOTAL constant).
if grep -qF '.*graphify-out/' "$AUDIT_SH" && grep -qF '(.*/)?CLAUDE\.md$' "$AUDIT_SH"; then
    ok "release-audit.sh private-state regex is depth-agnostic for graphify-out/ + CLAUDE.md"
else
    fail "release-audit.sh private-state regex still root-anchored (codex r3 [high] gap)"
fi
# Behavioral non-vacuity: the depth-agnostic pattern MUST match nested +
# top-level private-state and MISS a benign nested path.
_psf_re='^demo-1.0.0/(\.1by1/|\.i18n-cache/|\.cache/|\.ssh/|\.aws/|\.env[^/]*|\.python-version|\.github-publish-wt/)|^demo-1.0.0/.*graphify-out/|^demo-1.0.0/(.*/)?CLAUDE\.md$'
_psf_hits=$(printf '%s\n' \
  'demo-1.0.0/scripts/ok.sh' \
  'demo-1.0.0/skills/demo/CLAUDE.md' \
  'demo-1.0.0/docs/a/graphify-out/g.json' \
  'demo-1.0.0/CLAUDE.md' | grep -cE "$_psf_re" || true)
if [ "$_psf_hits" = 3 ] && ! printf '%s\n' 'demo-1.0.0/scripts/ok.sh' | grep -qE "$_psf_re"; then
    ok "private-state detection: nested skills/.../CLAUDE.md + docs/.../graphify-out/ + top-level caught (3), benign missed"
else
    fail "private-state depth-agnostic detection wrong (hits=$_psf_hits, expected 3 + benign miss)"
fi

# ── Test 2g: fail-closed net must ALSO reject .gitx/ (codex round-7 [med]) ─
# .gitx/ (gitx-sop policy pack) is .sanitize-ignore-whitelisted + release.sh
# --exclude='.gitx' (prevention, Test 1 above). The whitelist removed
# sanitizer detection, so the audit fail-closed net MUST positively reject a
# stale/external tarball carrying .gitx/ (detection) — same prevent-AND-
# detect pairing as .github-publish-wt (Test 2d).
if grep -qF '.gitx/' "$AUDIT_SH"; then
    ok "release-audit.sh fail-closed net rejects .gitx/ (codex round-7 [medium])"
else
    fail "release-audit.sh omits .gitx/ from private-state regex — whitelisted-but-undetected gap"
fi
# Behavioral non-vacuity: .gitx/ under the release root must match the regex.
if printf '%s\n' 'demo-1.0.0/.gitx/GITHUB_RELEASE_SOP.md' \
   | grep -qE '^demo-1.0.0/(\.1by1/|\.i18n-cache/|\.cache/|\.ssh/|\.aws/|\.env[^/]*|\.python-version|\.github-publish-wt/|\.gitx/)'; then
    ok "private-state detection: .gitx/ payload caught (non-vacuous)"
else
    fail "private-state regex does not actually match .gitx/ payload"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
