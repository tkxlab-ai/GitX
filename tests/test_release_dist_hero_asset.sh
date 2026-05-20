#!/usr/bin/env bash
# tests/test_release_dist_hero_asset.sh
#
# Codex v1.12.3 review round-1 [medium] regression guard.
#
# Invariant: the hero asset declared by the docs-contract manifest must be
# present at the SAME relative path inside the flattened release dir.
#
# Why: the README hero <img src="..."> is a relative repo-local ref. github.com
# rewrites it to a raw URL on render, so the public web page is always fine.
# But the flattened release dir (and the full tarball derived from it) ships
# README.md without docs/assets/, so a user opening the flattened README sees
# a broken image. release.sh:flatten_docs() now copies docs/assets/ into the
# flattened dir; this test fences that, plus release-audit §0m, against
# regressions in either direction.
#
# Layout:
#   T1: static contract — release.sh contains the docs/assets carry-over
#   T2: static contract — release-audit.sh wires §0m FLATHERO_FAIL into the final decision
#   T3: functional — built v1.12.3 release dir DOES carry the hero at docs/assets/<file>
#   T4: functional — built v1.12.3 full tarball DOES carry the hero at docs/assets/<file>
#
# Generic-safe: T3/T4 SKIP if no Release/<v>/ exists (downstream skill that
# never invoked release.sh on this repo) — they are bound to the local build.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE="$ROOT/scripts/release.sh"
AUDIT="$ROOT/scripts/release-audit.sh"
MANIFEST="$ROOT/references/docs-contract/manifest.txt"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

# Resolve the declared hero_asset (the project's source of truth).
HERO=""
if [ -f "$MANIFEST" ]; then
    HERO=$(grep -E '^hero_asset:' "$MANIFEST" | sed -E 's/^hero_asset:[[:space:]]*//' | head -1)
fi

# --- T1: release.sh:flatten_docs is README-driven (Codex round-6 symmetric contract) ---
# v1.12.3 round-6: producer (flatten_docs) and validator (release-audit §0m)
# walk the SAME refs — every repo-local <img src> in README{,_CN}.md — and the
# producer copies each referenced file to its same relative path under
# RELEASE_DIR. Unifies round-2 (no whole-dir cp, no decoys) + round-4 (validator
# walks all README imgs). Static checks fence three directions:
#   (a) walks every README{,_CN}.md (the same loop the validator uses)
#   (b) reads <img src> matches and cp's referenced file to $RELEASE_DIR/$_ref
#   (c) does NOT use the old whole-dir `cp -R docs/assets/. dst/` form
if [ -f "$RELEASE" ] \
   && grep -qE 'for _ff_readme in "\$PROJECT_ROOT/README\.md" "\$PROJECT_ROOT/README_CN\.md"' "$RELEASE" \
   && grep -qE '\[Ii\]\[Mm\]\[Gg\]\[\^>\]\*\[Ss\]\[Rr\]\[Cc\]=' "$RELEASE" \
   && grep -qE 'cp "\$_src" "\$RELEASE_DIR/\$_ref"' "$RELEASE" \
   && ! grep -qE 'cp -R "\$PROJECT_ROOT/docs/assets/\." "\$RELEASE_DIR/docs/assets/"' "$RELEASE"; then
    ok "release.sh:flatten_docs is README-driven (walks every README <img src>, cp each at its relative path) — Codex round-6 symmetric contract"
else
    fail "release.sh:flatten_docs MUST be README-driven (walk README <img src>, cp each at \$_ref path) — Codex v1.12.3 round-6 regression class"
fi

# --- T2: release-audit.sh §0m gate is wired into the final decision ---
if [ -f "$AUDIT" ] && grep -qE 'FLATHERO_FAIL:-0' "$AUDIT" \
   && grep -qE 'flattened README img-src gate' "$AUDIT"; then
    ok "release-audit.sh §0m flattened README img-src gate is wired into the final decision"
else
    fail "release-audit.sh §0m gate missing or not wired into final decision"
fi

# --- T2b: §0m iterates EVERY repo-local README <img src> (Codex round-4 contract) ---
# v1.12.3 round-4: not just the manifest hero — any repo-local <img src> in
# README.md or README_CN.md must resolve under $DIR. Drift case (README refs
# docs/assets/other.png while manifest declares release-demo.jpeg) would
# pass a hero-only gate but ship a broken README image; the wider gate
# fences both. Static-only here; the strict-superset behavior is itself
# functionally exercised by T3 (current GitX hero ref resolves) and T5
# (no undeclared siblings).
if [ -f "$AUDIT" ] \
   && grep -qE '\[Ii\]\[Mm\]\[Gg\]\[\^>\]\*\[Ss\]\[Rr\]\[Cc\]=' "$AUDIT" \
   && grep -qE 'for _fm_readme in "\$DIR/README\.md" "\$DIR/README_CN\.md"' "$AUDIT"; then
    ok "§0m iterates every README <img src> from \$DIR (flattened artifact, not working-tree) — Codex round-5 contract"
else
    fail "§0m must walk every README <img src> from \$DIR (round-5 fix) — Codex regression"
fi

# --- T2d: extractor supports single-quote + case-insensitive (Codex round-8) ---
# v1.12.3 round-8: HTML allows <IMG SRC='...'> and <img src='...'>; the
# extractor in BOTH release.sh:flatten_docs AND release-audit.sh §0m MUST
# match the same set of valid img syntaxes or producer/validator drift on
# downstream READMEs that use non-default quoting. Static check on awk
# program literal.
for _f in "$RELEASE" "$AUDIT"; do
    [ -f "$_f" ] || continue
    if grep -qE '\[Ii\]\[Mm\]\[Gg\]' "$_f" \
       && grep -qE '\[Ss\]\[Rr\]\[Cc\]' "$_f" \
       && grep -qE '\\047' "$_f"; then
        ok "$(basename "$_f") extractor supports both \" and ' quotes + case-insensitive <IMG SRC=> (Codex round-8)"
    else
        fail "$(basename "$_f") extractor MUST support single-quote + case-insensitive HTML img refs — Codex round-8 regression"
    fi
done

# --- T2e: extractor covers Markdown ![alt](path) syntax (Codex round-9) ---
# v1.12.3 round-9: README/MD often uses ![alt](docs/assets/x.png) — neither
# HTML-only extractor caught it. Producer + validator MUST both extract MD
# img refs or downstream MD-style README ships broken in flattened artifact.
for _f in "$RELEASE" "$AUDIT"; do
    [ -f "$_f" ] || continue
    if grep -qE '!\\\[\[\^\]\]\*\\\]\\\(\[\^\)\]\+\\\)' "$_f"; then
        ok "$(basename "$_f") extractor covers Markdown ![alt](path) image syntax (Codex round-9)"
    else
        fail "$(basename "$_f") extractor MUST cover Markdown ![alt](path) — Codex round-9 regression"
    fi
done

# --- T2f: flatten_docs trust-boundary (Codex round-10 [high]) ---
# Triple containment: reject symlinks + require regular file + require
# git-tracked. flatten_docs runs after run_sanity_scans on staging tree,
# so a README image ref to an untracked or symlinked file would otherwise
# bypass sanitize and land in the full tarball unscanned.
if [ -f "$RELEASE" ] \
   && grep -qE 'flatten_docs: skipping symlink' "$RELEASE" \
   && grep -qE 'flatten_docs: skipping untracked' "$RELEASE" \
   && grep -qE 'git -C "\$PROJECT_ROOT" ls-files --error-unmatch' "$RELEASE"; then
    ok "release.sh:flatten_docs has symlink reject + git-tracked requirement (Codex round-10 trust boundary)"
else
    fail "release.sh:flatten_docs MUST reject symlinks + require git-tracked refs — Codex round-10 [high] regression"
fi

# --- T2h: release.sh preflight aborts on dirty working tree (Codex round-12+13 [high]) ---
# Trust boundary: sanitize covers HEAD content; flatten cp's docs from
# working tree. Two-part check:
#   (1) tracked dirty  — diff-index --quiet HEAD (round-12)
#   (2) untracked-not-gitignored — ls-files --others --exclude-standard (round-13)
# Either non-empty → fail-close.
if [ -f "$RELEASE" ] \
   && grep -qE 'release.sh: working tree has uncommitted tracked changes' "$RELEASE" \
   && grep -qE 'diff-index --quiet HEAD' "$RELEASE"; then
    ok "release.sh preflight aborts on dirty tracked working tree (Codex round-12 [high] trust boundary)"
else
    fail "release.sh MUST preflight-abort on dirty tracked working tree (round-12 fix) — un-scanned content would ship"
fi

if [ -f "$RELEASE" ] \
   && grep -qE 'release.sh: untracked-not-gitignored files present' "$RELEASE" \
   && grep -qE 'ls-files --others --exclude-standard' "$RELEASE"; then
    ok "release.sh preflight aborts on untracked-not-gitignored files (Codex round-13 [high] trust boundary)"
else
    fail "release.sh MUST preflight-abort on untracked-not-gitignored (round-13 fix) — .release-flatten injection possible"
fi

# --- T2g: flatten_docs cp from HEAD (not working tree) for git-repos (Codex round-11 [high]) ---
# Dirty tracked files would bypass run_sanity_scans (which covers HEAD/staging
# tree). Producer MUST use `git cat-file -p HEAD:<ref>` for git repos so a
# modified working-tree blob never lands in the full tarball unscanned.
if [ -f "$RELEASE" ] \
   && grep -qE 'git -C "\$PROJECT_ROOT" cat-file -p "HEAD:\$_ref"' "$RELEASE"; then
    ok "release.sh:flatten_docs reads HEAD blob via cat-file (Codex round-11 — dirty-tracked trust boundary)"
else
    fail "release.sh:flatten_docs MUST cat-file HEAD:\$_ref (round-11 fix) — dirty tracked refs would otherwise ship unscanned"
fi

# --- T2i: .release-flatten manifest rejects gitignored/untracked paths (Codex round-14 [high]) ---
# Manifest could list private gitignored content (HANDOFF.md, .gitx/,
# docs/superpowers/, etc.); without this guard a tracked .release-flatten
# pointing at gitignored paths would publish private design material.
# Hard fail on: absolute/`..`, symlinks, gitignored, untracked.
if [ -f "$RELEASE" ] \
   && grep -qE 'release-flatten: unsafe path' "$RELEASE" \
   && grep -qE 'check-ignore -q --' "$RELEASE" \
   && grep -qE 'release-flatten:.*is a symlink' "$RELEASE" \
   && grep -qE 'release-flatten:.*is not git-tracked' "$RELEASE"; then
    ok "release.sh:.release-flatten rejects gitignored/untracked/symlink/traversal paths (Codex round-14 [high] trust boundary)"
else
    fail "release.sh:.release-flatten MUST reject gitignored/untracked/symlink/traversal (round-14 fix) — private content publish risk"
fi

# --- T2j: .release-flatten rejects directory entries (Codex round-15 [high]) ---
# `cp -R` on a dir would copy nested gitignored/untracked content (e.g.
# manifest "docs" sweeps docs/superpowers/). Until per-file tracked-only
# enumeration is implemented, dir entries are rejected; require explicit
# file paths.
if [ -f "$RELEASE" ] \
   && grep -qE 'release-flatten:.*is a directory' "$RELEASE" \
   && grep -qE 'list explicit file paths instead' "$RELEASE"; then
    ok "release.sh:.release-flatten rejects directory entries (Codex round-15 [high] — would leak nested gitignored)"
else
    fail "release.sh:.release-flatten MUST reject directory entries (round-15 fix) — cp -R would leak nested gitignored content"
fi

# --- T2c: §0m rejects `..` traversal + absolute README img refs (Codex round-7) ---
# v1.12.3 round-7: symmetric with release.sh producer which already does
# `case "$_ref" in /*|*..*) continue ;;`. Without this rejection, a README
# `<img src="../neighbor">` would pass `[ -e $DIR/../neighbor ]` because the
# parent dir exists, while the producer never copies it — silently shipping
# a README whose image lives OUTSIDE the tarball.
if [ -f "$AUDIT" ] \
   && grep -qE 'unsafe README img ref' "$AUDIT" \
   && grep -qE '/\*\|\*\.\.\*' "$AUDIT"; then
    ok "§0m rejects \`..\` traversal + absolute README img refs (Codex round-7 — symmetric with producer)"
else
    fail "§0m must reject \`..\` + absolute refs (round-7 fix) — silent escape outside artifact possible"
fi

# --- T3/T4: functional checks (generic-safe SKIP when no build exists) ---
VER_FILE="$ROOT/VERSION"
if [ ! -f "$VER_FILE" ] || [ -z "$HERO" ]; then
    ok "T3/T4 SKIP — no VERSION or hero_asset declared (generic-safe)"
else
    VER=$(tr -d '[:space:]' < "$VER_FILE")
    # Project's release dir uses the prefix git_release_skill-<VER> (see release.sh)
    DIST="$ROOT/Release/git_release_skill-${VER}"
    # release.sh creates RELEASE_DIR BEFORE run_tests but flatten_docs runs
    # AFTER — so when this test is invoked by run_tests under release.sh,
    # the dir exists but is empty. Require README.md as a positive flatten
    # signal: absent ⇒ flatten not done yet (mid-build) ⇒ SKIP functional.
    if [ ! -d "$DIST" ] || [ ! -f "$DIST/README.md" ]; then
        ok "T3 SKIP — release dir absent or pre-flatten (generic-safe / mid-build by release.sh)"
        ok "T4 SKIP — full tarball not built yet (generic-safe / mid-build by release.sh)"
    else
        # T3: flattened dir carries the hero at the declared path
        if [ -f "$DIST/$HERO" ]; then
            ok "flattened release dir carries hero_asset at $HERO"
        else
            fail "flattened release dir MISSING $HERO — Codex v1.12.3 round-1 regression"
        fi
        # T4: full tarball carries the hero at the declared path
        FULL="$DIST/git_release_skill-${VER}-full.tar.gz"
        if [ -f "$FULL" ]; then
            # full tarball top dir is git_release_skill-<VER>; the hero lives at <topdir>/<HERO>
            if tar tzf "$FULL" 2>/dev/null | grep -qxE "git_release_skill-${VER}/${HERO}"; then
                ok "full tarball carries hero_asset at git_release_skill-${VER}/${HERO}"
            else
                fail "full tarball MISSING git_release_skill-${VER}/${HERO} — flattened-dir bug bled into full.tar.gz"
            fi
        else
            ok "T4 SKIP — no full tarball file at $FULL (generic-safe)"
        fi
        # T5 (Codex round-2 [medium]): flattened docs/assets/ must carry ONLY the
        # declared hero — proves we didn't silently publish unrelated siblings
        # from the source tree's docs/assets/. Narrow contract = manifest-driven.
        if [ -d "$DIST/docs/assets" ]; then
            _hero_base=$(basename "$HERO")
            _count=$(find "$DIST/docs/assets" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
            _decoy=$(find "$DIST/docs/assets" -maxdepth 1 -type f ! -name "$_hero_base" 2>/dev/null | head -1)
            if [ "$_count" = "1" ] && [ -z "$_decoy" ]; then
                ok "flattened docs/assets/ carries ONLY declared hero — no undeclared siblings (Codex round-2)"
            else
                fail "flattened docs/assets/ leaked undeclared file: $_decoy (count=$_count) — Codex round-2 regression"
            fi
        else
            ok "T5 SKIP — no flattened docs/assets/ (hero_asset not declared / not flattened)"
        fi
    fi
fi

echo ""
echo "Results: ✅${PASS} passed / ❌${FAIL} failed"
if [ "$FAIL" -eq 0 ]; then
    echo "PASS"
    exit 0
else
    echo "FAIL"
    exit 1
fi
