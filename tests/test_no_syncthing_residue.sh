#!/bin/bash
# test_no_syncthing_residue.sh — v1.4.0 (Gotcha #35).
#
# Enforces "Syncthing chunked-transfer staging + conflict files must be 0
# at release time". When Syncthing syncs a folder containing this repo,
# it leaves `.syncthing.<name>.tmp` (transfer staging) and `*.sync-conflict-*`
# (concurrent-edit forks). If any persist, release-time `find -type f` /
# audit scans hit them as noise. v1.3.x Gotcha #35 documented the cleanup
# (1463 + 8 files swept on 2026-05-10); v1.4.0 enforces "0 residue" as
# release-time guard.
#
# Also validates `.gitignore` has the explicit pattern (alongside the
# generic *.tmp catch-all) for maintainer clarity.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_no_syncthing_residue.sh ══"

# === Behavioral 1: no .syncthing.*.tmp anywhere in the repo (incl .git/) ===
TMP_COUNT=$(find "$ROOT" -name '.syncthing.*.tmp' 2>/dev/null | wc -l | tr -d ' ')
if [ "$TMP_COUNT" -eq 0 ]; then
    ok "no .syncthing.*.tmp residue (count=0)"
else
    fail "found $TMP_COUNT .syncthing.*.tmp residue files (run: find $ROOT -name '.syncthing.*.tmp' -delete)"
fi

# === Behavioral 2: no *.sync-conflict-* anywhere ===
CONFLICT_COUNT=$(find "$ROOT" -name '*.sync-conflict-*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$CONFLICT_COUNT" -eq 0 ]; then
    ok "no *.sync-conflict-* residue (count=0)"
else
    fail "found $CONFLICT_COUNT *.sync-conflict-* residue files (run: find $ROOT -name '*.sync-conflict-*' -delete)"
fi

# === Behavioral 3: .git/ specifically clean (Gotcha #35 surface 2 — Syncthing
# previously synced .git/ before folder ignore was added) ===
GIT_DIRTY=$(find "$ROOT/.git" \( -name '.syncthing.*.tmp' -o -name '*.sync-conflict-*' \) 2>/dev/null | wc -l | tr -d ' ')
if [ "$GIT_DIRTY" -eq 0 ]; then
    ok ".git/ clean of Syncthing residue"
else
    fail ".git/ has $GIT_DIRTY Syncthing residue files — Syncthing folder ignore .git/** missing?"
fi

# === Static 1: .gitignore has explicit *.sync-conflict-* rule ===
if grep -qE '^\*\.sync-conflict-\*$' "$ROOT/.gitignore"; then
    ok ".gitignore has '*.sync-conflict-*' pattern"
else
    fail ".gitignore missing '*.sync-conflict-*' rule"
fi

# === Static 2: .gitignore has explicit .syncthing.*.tmp rule (v1.4.0 addition) ===
if grep -qE '^\.syncthing\.\*\.tmp$' "$ROOT/.gitignore"; then
    ok ".gitignore has explicit '.syncthing.*.tmp' pattern (v1.4.0)"
else
    fail ".gitignore missing explicit '.syncthing.*.tmp' rule — relies on generic *.tmp only"
fi

# === Static 3: .gitignore has .syncthing-quarantine-*/ for manual triage ===
if grep -qE '^\.syncthing-quarantine-\*/$' "$ROOT/.gitignore"; then
    ok ".gitignore has '.syncthing-quarantine-*/' pattern"
else
    fail ".gitignore missing '.syncthing-quarantine-*/' rule"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
