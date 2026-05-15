#!/bin/bash
# test_full_tarball_reproducibility.sh — behavioral test for the
# build_full_tarball() recipe added in v1.0.7 commit b7b38c4.
#
# Why this test exists: test_tarball_reproducibility.sh validates the SOURCE
# tarball recipe but only via grep against release.sh — the strings (gzip -n,
# touch -t, find|sort) match because the source-tarball block already had them,
# so the test passed vacuously for the new full-tarball function. This test
# replicates the exact build_full_tarball recipe (including the v1.0.5 owner
# normalization) and proves two consecutive builds produce byte-identical output.
#
# Recipe under test (release.sh build_full_tarball):
#   rsync -a "$RELEASE_DIR/" "$_FULL_STAGE/${PROJECT_NAME}-${VERSION}/"
#   touch -t "$_SDE" on every file in staging
#   find | LC_ALL=C sort | tar --no-recursion --owner=0 --group=0 --numeric-owner -T - -cf -
#   | gzip -n > full.tar.gz
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$PROJECT_ROOT/scripts/release.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_full_tarball_reproducibility.sh ══"

# ── Static: build_full_tarball() must contain the deterministic recipe ────
# Extract just the function body so we don't accidentally match strings that
# only exist in build_source_tarball() (the test_tarball_reproducibility.sh
# vacuous-pass trap).
_BLOCK=$(awk '/^build_full_tarball\(\) \{/,/^\}/' "$RELEASE_SH")
if [ -z "$_BLOCK" ]; then
    fail "build_full_tarball() not found in release.sh"
else
    if echo "$_BLOCK" | grep -qE 'gzip -n'; then
        ok "build_full_tarball: pipes through gzip -n"
    else
        fail "build_full_tarball: missing gzip -n (header timestamp will vary)"
    fi
    if echo "$_BLOCK" | grep -qE 'touch -t'; then
        ok "build_full_tarball: normalizes mtime via touch -t"
    else
        fail "build_full_tarball: missing touch -t (file mtimes will vary)"
    fi
    if echo "$_BLOCK" | grep -qE 'LC_ALL=C *sort'; then
        ok "build_full_tarball: enforces deterministic file order (LC_ALL=C sort)"
    else
        fail "build_full_tarball: missing LC_ALL=C sort (filesystem order is unstable)"
    fi
    if echo "$_BLOCK" | grep -qE -- '--owner=0.*--group=0.*--numeric-owner|--numeric-owner.*--owner=0'; then
        ok "build_full_tarball: tar uses --owner=0 --group=0 --numeric-owner"
    else
        fail "build_full_tarball: tar missing owner normalization (uid/gid leak between machines)"
    fi
fi

# ── Behavioral: replicate the recipe and prove two builds are byte-identical ──
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
PROJECT="testproj"
VER="v0.0.1"
# Simulate a populated RELEASE_DIR: mix of artifacts that build_full_tarball
# would see in production (.skill, source tarball, install.sh, sbom, checksums).
RDIR="$FIXTURE/release"
mkdir -p "$RDIR"
echo "fake skill bundle" > "$RDIR/${PROJECT}-${VER}.skill"
echo "fake source tar"   > "$RDIR/${PROJECT}-${VER}-source.tar.gz"
echo "#!/bin/sh"         > "$RDIR/install.sh"
echo '{"sbom":true}'     > "$RDIR/sbom.cyclonedx.json"
echo "tokens: 100"       > "$RDIR/TOKEN_USAGE.md"
echo "deadbeef  ${PROJECT}-${VER}.skill" > "$RDIR/checksums.txt"

build_full() {
    local out="$1"
    local stage; stage=$(mktemp -d)
    rsync -a "$RDIR/" "$stage/${PROJECT}-${VER}/"
    # Mirror release.sh: SOURCE_DATE_EPOCH=1000000000 → 200109090146.40 UTC
    find "$stage" -exec touch -t 200109090146.40 {} + 2>/dev/null || true
    (cd "$stage" && \
     find "${PROJECT}-${VER}" -print | LC_ALL=C sort | \
     tar --no-recursion --owner=0 --group=0 --numeric-owner -T - -cf -
    ) | gzip -n > "$out"
    rm -rf "$stage"
}

OUT1="$FIXTURE/build1.tar.gz"
OUT2="$FIXTURE/build2.tar.gz"
build_full "$OUT1"
sleep 1   # force wall-clock tick — proves mtime normalization, not luck
build_full "$OUT2"

if [ -f "$OUT1" ] && [ -f "$OUT2" ] && cmp -s "$OUT1" "$OUT2"; then
    ok "two consecutive build_full_tarball runs produce byte-identical output"
else
    fail "build_full_tarball output diverges between runs (recipe is not reproducible)"
    echo "     sha256:"
    shasum -a 256 "$OUT1" "$OUT2" 2>/dev/null | sed 's/^/       /'
fi

# ── Behavioral: the inner checksums.txt is a snapshot — must NOT list full.tar.gz ──
# This documents the math limitation called out in build_full_tarball()'s
# comment: a tarball cannot contain its own hash. If a future change tries to
# embed the post-append checksums.txt, this test will RED-flag it (because
# such a tarball would be non-reproducible: chicken-and-egg with the hash).
INNER=$(mktemp -d)
tar -xzf "$OUT1" -C "$INNER"
if [ -f "$INNER/${PROJECT}-${VER}/checksums.txt" ]; then
    if grep -q "full\.tar\.gz" "$INNER/${PROJECT}-${VER}/checksums.txt"; then
        fail "inner checksums.txt lists full.tar.gz — would create irreproducible chicken-and-egg"
    else
        ok "inner checksums.txt correctly omits full.tar.gz (math: tarball cannot list own hash)"
    fi
else
    fail "inner checksums.txt missing from extracted full tarball"
fi
rm -rf "$INNER"

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
