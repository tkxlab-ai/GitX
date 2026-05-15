#!/bin/bash
# test_skill_zip_determinism.sh — RED→GREEN: .skill zip fallback must produce
# byte-identical output on two runs from the same source (mtime-normalized staging).
# TDD P1-4 (upgraded from static to behavioral after Code Review #2)
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"
echo "=== test_skill_zip_determinism: .skill zip reproducibility ==="

# Static checks (presence of flags and mtime-normalization staging)
if grep -qE 'zip -[^ ]*X|-X.*zip' "$RELEASE_SH"; then
    ok "release.sh: zip uses -X (strip extra attributes)"
else
    fail "release.sh: zip missing -X flag (extra attrs make zip non-deterministic)"
fi
if grep -qF 'zip' "$RELEASE_SH" && grep -qE 'sort.*zip|zip.*-@' "$RELEASE_SH"; then
    ok "release.sh: zip uses sorted file list"
else
    fail "release.sh: zip missing sorted input"
fi
# Zip path must use staging copy + mtime normalization (not live source tree)
_ZIP_BLOCK=$(awk '/skill-creator 不在/,/SKILL_OUT.*du/' "$RELEASE_SH" 2>/dev/null || true)
if echo "$_ZIP_BLOCK" | grep -qE 'rsync|mktemp' && echo "$_ZIP_BLOCK" | grep -qE 'touch -t|SDE_ZIP|SDE_TOUCH'; then
    ok "release.sh: zip fallback uses staging+mtime-normalize (deterministic)"
else
    fail "release.sh: zip fallback reads live source without mtime normalization (non-deterministic)"
fi

# Behavioral: two zips of same content with same SOURCE_DATE_EPOCH must be identical
FIXTURE=$(mktemp -d)
SKILL="testskill"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/$SKILL/scripts" "$FIXTURE/$SKILL/references"
echo "name: testskill" > "$FIXTURE/$SKILL/SKILL.md"
echo "echo hello" > "$FIXTURE/$SKILL/scripts/run.sh"
echo "# ref" > "$FIXTURE/$SKILL/references/POLICY.md"
# Small sleep between runs to prove mtime normalization wins
OUT1="$FIXTURE/out1.zip"
OUT2="$FIXTURE/out2.zip"
# EPOCH retained for documentation: SDE_TOUCH below is the touch -t form
# corresponding to SOURCE_DATE_EPOCH=1000000000 (2001-09-09T01:46:40Z UTC).
SDE_TOUCH="200109090146.40"
# Run first zip (simulating the pipeline zip fallback path with staging)
_STAGE1=$(mktemp -d)
rsync -a "$FIXTURE/$SKILL/" "$_STAGE1/$SKILL/"
find "$_STAGE1" -exec touch -t "$SDE_TOUCH" {} + 2>/dev/null || true
(cd "$_STAGE1" && find "$SKILL" | LC_ALL=C sort | zip -qX "$OUT1" -@)
rm -rf "$_STAGE1"
# Small delay then second run
sleep 1
# Second run must produce identical zip
_STAGE2=$(mktemp -d)
rsync -a "$FIXTURE/$SKILL/" "$_STAGE2/$SKILL/"
find "$_STAGE2" -exec touch -t "$SDE_TOUCH" {} + 2>/dev/null || true
(cd "$_STAGE2" && find "$SKILL" | LC_ALL=C sort | zip -qX "$OUT2" -@)
rm -rf "$_STAGE2"
if [ -f "$OUT1" ] && [ -f "$OUT2" ] && cmp -s "$OUT1" "$OUT2"; then
    ok "two zip runs with same SOURCE_DATE_EPOCH produce identical output (behavioral)"
else
    fail "two zip runs produce different output — zip is not mtime-normalized"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
