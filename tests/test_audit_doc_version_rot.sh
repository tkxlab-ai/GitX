#!/bin/bash
# test_audit_doc_version_rot.sh — v1.7.2 systemic doc-rot guard.
#
# Root cause of the v0.9.x README/ROADMAP rot: docs hardcoded a version
# inside "current scope / current status" claims, and gitx-release.sh
# bumped VERSION without ever syncing them, with NO audit catching it.
# This guards: a "当前 Scope" / "当前状态" line MUST NOT pin a version
# token (vN.N) — those sections must be version-agnostic and defer to
# VERSION / CHANGELOG.
#
# exit: 0=all pass, 1=any fail
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_doc_version_rot.sh ══"

# STATIC: release-audit.sh (root + bundle) defines the §0e doc-rot gate
for a in "$ROOT/scripts/release-audit.sh" "$ROOT/skills/gitx-release/scripts/release-audit.sh"; do
    [ -f "$a" ] || continue
    label="$(basename "$(dirname "$(dirname "$a")")")"
    if grep -qE '^audit_section_0_doc_version_rot\(\)' "$a" \
       && grep -q '§0e' "$a" \
       && grep -q '当前 Scope\|当前状态' "$a"; then
        ok "release-audit.sh has §0e doc-version-rot gate ($label)"
    else
        fail "$a missing §0e doc-version-rot gate"
    fi
done

# BEHAVIORAL: the rot regex flags a stale scope line, ignores a clean one.
ROT='(当前 Scope|当前状态)[^|]*v[0-9]'
echo '## 📌 当前 Scope（v0.9.x）' | grep -qE "$ROT" \
    && ok "rot regex flags '当前 Scope（v0.9.x）'" \
    || fail "rot regex failed to flag the known stale pattern"
echo '## 📌 Scope（版本号见 VERSION / CHANGELOG）' | grep -qE "$ROT" \
    && fail "rot regex false-positives on the version-agnostic fixed form" \
    || ok "rot regex passes the version-agnostic Scope heading"

# REGRESSION: the live README/ROADMAP must already be clean (we fixed them)
for d in README.md ROADMAP.md; do
    [ -f "$ROOT/$d" ] || continue
    if grep -qE "$ROT" "$ROOT/$d"; then
        fail "$d still has a version-pinned scope/status line: $(grep -nE "$ROT" "$ROOT/$d" | head -1)"
    else
        ok "$d scope/status is version-agnostic"
    fi
done

echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -gt 0 ] && { echo "FAIL"; exit 1; } || { echo "PASS"; exit 0; }
