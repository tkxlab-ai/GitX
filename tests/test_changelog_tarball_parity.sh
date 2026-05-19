#!/bin/bash
# test_changelog_tarball_parity.sh — guards release.sh's
# assert_changelog_tarball_parity gate (Codex v1.12.1 independent review,
# [high]: the public source tarball must carry flat CHANGELOG{,_CN}.md.
# The rsync path injects them into the staging tree non-destructively
# (inject_root_changelog_into_stage — $PROJECT_ROOT untouched); the
# scrub-tarball path runs `git archive HEAD` and cannot inject, so a stale
# committed root mirror would ship — the Gotcha #81 class on the scrub
# path. This gate is the universal fail-closed post-condition for BOTH).
# Two halves:
#   A. STATIC contract: the gate function exists, is wired into the main
#      sequence AFTER build_source_tarball and BEFORE run_sanity_scans,
#      is fail-closed (exit 1 on mismatch / missing), CN is generic-safe,
#      and the bundled dual-source mirror carries it byte-identical.
#   B. FUNCTIONAL non-vacuity: the exact extract+cmp predicate the gate
#      performs flags a stale tarball CHANGELOG.md and a missing one, and
#      passes a byte-identical one (no false positive).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RS="$ROOT/scripts/release.sh"
RS_MIRROR="$ROOT/skills/gitx-release/scripts/release.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=1; }

# ---- A. static contract ----
if [ -f "$RS" ]; then
    _blk=$(awk '/^assert_changelog_tarball_parity\(\) \{/,/^\}/' "$RS")
    [ -n "$_blk" ] && ok "assert_changelog_tarball_parity() defined in release.sh" \
        || fail "assert_changelog_tarball_parity() missing from release.sh"
    # Wired into the main sequence in the correct position. Portable
    # (BSD/macOS grep has no -P): assert the three BARE call lines
    # (not the `name() {` defs) are consecutive via awk line numbers.
    if awk '
        /^build_source_tarball$/{a=NR}
        /^assert_changelog_tarball_parity$/{b=NR}
        /^run_sanity_scans$/{c=NR}
        END{exit !(a&&b&&c&&b==a+1&&c==b+1)}' "$RS"; then
        ok "gate called between build_source_tarball and run_sanity_scans"
    else
        fail "gate NOT wired in correct main-sequence position (vacuous)"
    fi
    printf '%s\n' "$_blk" | grep -q 'cmp -s' \
        && ok "gate byte-compares (cmp -s) tarball vs Release/CHANGELOG" \
        || fail "gate does not byte-compare — content rot can slip"
    [ "$(printf '%s\n' "$_blk" | grep -c 'exit 1')" -ge 2 ] \
        && ok "gate is fail-closed (exit 1 on missing AND on mismatch)" \
        || fail "gate not fail-closed on both missing and mismatch"
    printf '%s\n' "$_blk" | grep -q '\[ -f "\$_cp_src" \] || continue' \
        && ok "CN parallel is generic-safe (skip when source absent)" \
        || fail "CN not generic-safe — would FAIL projects without CHANGELOG_CN"
else
    fail "release.sh not found"
fi
if [ -f "$RS_MIRROR" ]; then
    cmp -s "$RS" "$RS_MIRROR" \
        && ok "bundled dual-source mirror byte-identical (gate ships in .skill)" \
        || fail "dual-source drift — mirror lacks the gate"
else
    fail "bundled release.sh mirror not found"
fi

# ---- B. functional non-vacuity (the gate's extract+cmp predicate) ----
# Mirrors the gate: extract tarball, find CHANGELOG.md at depth<=2, cmp
# byte-for-byte against the source-of-truth Release/CHANGELOG.md.
parity() {  # $1=tarball $2=truth → 0 ok, 1 mismatch/missing
    local t got; t=$(mktemp -d)
    tar -xzf "$1" -C "$t" 2>/dev/null || { rm -rf "$t"; return 1; }
    got=$(find "$t" -maxdepth 2 -name CHANGELOG.md -type f 2>/dev/null | head -1)
    if [ -z "$got" ]; then rm -rf "$t"; return 1; fi
    if cmp -s "$2" "$got"; then rm -rf "$t"; return 0; fi
    rm -rf "$t"; return 1
}
# Mirrors inject_root_changelog_into_stage's symlink hardening (Codex
# round-3 [high]): unlink the staged dest, copy, assert not a symlink.
inject_safe() {  # $1=src $2=stage_sub
    local dest="$2/CHANGELOG.md"
    rm -f -- "$dest"
    cp "$1" "$dest"   # no `cp --` — BSD/macOS portable (Codex round-5 [high])
    [ ! -L "$dest" ]
}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf 'v1.12.1 TRUTH\n' > "$T/truth.md"
mkdir -p "$T/proj-1/."  # tarball top-level dir, like ${PROJECT_NAME}-${VERSION}/

# (b1) stale CHANGELOG.md in tarball → must be flagged
printf 'v1.11.0 STALE\n' > "$T/proj-1/CHANGELOG.md"
( cd "$T" && tar -czf stale.tgz proj-1 )
parity "$T/stale.tgz" "$T/truth.md" \
    && fail "gate VACUOUS: stale tarball CHANGELOG.md not flagged (#81 scrub regression)" \
    || ok "gate non-vacuous: stale tarball CHANGELOG.md flagged"

# (b2) byte-identical CHANGELOG.md → must pass (no false positive)
cp "$T/truth.md" "$T/proj-1/CHANGELOG.md"
( cd "$T" && tar -czf good.tgz proj-1 )
parity "$T/good.tgz" "$T/truth.md" \
    && ok "gate passes a byte-identical tarball CHANGELOG.md (no false positive)" \
    || fail "gate false-fails a correct tarball (would block valid releases)"

# (b3) CHANGELOG.md missing from tarball → must be flagged (would 404 publicly)
rm -f "$T/proj-1/CHANGELOG.md"
( cd "$T" && tar -czf nochg.tgz proj-1 )
parity "$T/nochg.tgz" "$T/truth.md" \
    && fail "gate VACUOUS: missing tarball CHANGELOG.md not flagged (public 404)" \
    || ok "gate non-vacuous: missing tarball CHANGELOG.md flagged"

# (b4) Codex round-3 [high]: a downstream root CHANGELOG.md that is a SYMLINK
#      is preserved by `rsync -a` into the staging tree; the inject step must
#      NOT write through it (would escape STAGE_SUB and corrupt the target).
OUT="$T/outside-sentinel"; printf 'UNTOUCHED\n' > "$OUT"
mkdir -p "$T/stg/proj-1"
ln -s "$OUT" "$T/stg/proj-1/CHANGELOG.md"   # what rsync -a would carry over
inject_safe "$T/truth.md" "$T/stg/proj-1" || true
[ "$(cat "$OUT")" = "UNTOUCHED" ] \
    && ok "symlink-escape blocked: outside target unmodified (Codex round-3 [high])" \
    || fail "SYMLINK ESCAPE: inject wrote through preserved symlink to outside target"
{ [ ! -L "$T/stg/proj-1/CHANGELOG.md" ] && cmp -s "$T/truth.md" "$T/stg/proj-1/CHANGELOG.md"; } \
    && ok "staged dest is a clean regular file carrying source content" \
    || fail "staged dest not a clean regular file after hardened inject"

# (b5) Codex round-4 [high]: scrub path = build tarball from HEAD (carries
#      the STALE committed root CHANGELOG), extract, then inject+re-pack so
#      the SHIPPED tarball carries source-of-truth Release/CHANGELOG without
#      mutating the working tree, AND the re-pack is deterministic.
SC=$(mktemp -d)
mkdir -p "$SC/proj-1"; printf 'v1.10.0 STALE-COMMITTED\n' > "$SC/proj-1/CHANGELOG.md"
( cd "$SC" && tar -czf head.tgz proj-1 )            # ~ git archive HEAD (stale)
EX="$SC/ex"; mkdir -p "$EX"; tar -xzf "$SC/head.tgz" -C "$EX"   # scrub extract
inject_safe "$T/truth.md" "$EX/proj-1"              # inject source-of-truth
# deterministic re-pack (same recipe shape as pack_source_tarball_deterministic;
# touch -h mirrors the Codex round-8 [high] no-dereference fix)
find "$EX/proj-1" -exec touch -h -t 200001010000.00 {} + 2>/dev/null || true
( cd "$EX" && find proj-1 -print | LC_ALL=C sort | tar --no-recursion --owner=0 --group=0 --numeric-owner -T - -cf - ) 2>/dev/null | gzip -n > "$SC/repack1.tgz"
( cd "$EX" && find proj-1 -print | LC_ALL=C sort | tar --no-recursion --owner=0 --group=0 --numeric-owner -T - -cf - ) 2>/dev/null | gzip -n > "$SC/repack2.tgz"
parity "$SC/repack1.tgz" "$T/truth.md" \
    && ok "scrub path: re-packed tarball carries source-of-truth CHANGELOG (Codex round-4 [high])" \
    || fail "scrub path STILL ships stale CHANGELOG after inject+re-pack"
cmp -s "$SC/repack1.tgz" "$SC/repack2.tgz" \
    && ok "scrub re-pack is deterministic (two builds byte-identical, Gotcha #14)" \
    || fail "scrub re-pack NOT reproducible (determinism regression)"
rm -rf "$SC"

# (b6) Codex round-8 [high]: pack_source_tarball_deterministic's mtime
#      normalization (`find STAGE_SUB -exec touch -h -t ...`) must NOT
#      dereference a tracked symlink and rewrite its target's mtime
#      OUTSIDE the staging dir. Simulate the exact recipe; prove the
#      out-of-stage sentinel keeps its (distinct) mtime + content.
SM=$(mktemp -d)
OUT="$SM/outside-sentinel"; printf 'SENTINEL\n' > "$OUT"
touch -t 202601011200.00 "$OUT"                 # distinct, recent mtime
REF="$SM/ref2000"; : > "$REF"; touch -t 200001010000.00 "$REF"
mkdir -p "$SM/stg/proj-1"; ln -s "$OUT" "$SM/stg/proj-1/CHANGELOG.md"
# the exact helper recipe (no-dereference)
find "$SM/stg" -exec touch -h -t 200001010000.00 {} + 2>/dev/null || true
{ [ "$OUT" -nt "$REF" ] && cmp -s <(printf 'SENTINEL\n') "$OUT"; } \
    && ok "mtime-normalize no-deref: out-of-stage symlink target untouched (Codex round-8 [high])" \
    || fail "SYMLINK-DEREF: touch rewrote out-of-stage target mtime/content (non-destructive contract broken)"
[ -L "$SM/stg/proj-1/CHANGELOG.md" ] \
    && ok "staged symlink preserved as a symlink (touch -h acted on the link)" \
    || fail "staged symlink was dereferenced/replaced by touch"
rm -rf "$SM"

echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo PASS || { echo FAIL; exit 1; }
