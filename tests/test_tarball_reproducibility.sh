#!/bin/bash
# test_tarball_reproducibility.sh — v0.9.8 Gotcha #14
# Two consecutive source-tarball builds from identical staging must produce
# byte-identical output. Covers SLSA L3 reproducible-build requirement:
# users can offline-verify that their tarball matches the official one.
#
# Needed transforms in release.sh:
#   1. `gzip -n`                     → strip gzip header timestamp + filename
#   2. `touch -t <fixed>` on staging → normalize tar file-mtime entries
#   3. `find | sort | tar -T -`      → deterministic archive file order
#     (filesystem order is not guaranteed stable across runs)
#
# exit: 0=all pass, 1=any fail

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$PROJECT_ROOT/scripts/release.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_tarball_reproducibility.sh ══"

# ── Test 1: release.sh uses gzip -n ────────────────────────────────────────
if grep -q 'gzip -n' "$RELEASE_SH"; then
    ok "release.sh pipes through 'gzip -n' (strips gzip timestamp/filename)"
else
    fail "release.sh does NOT use 'gzip -n' — gzip header will vary between runs"
fi

# ── Test 2: release.sh normalizes mtime before tar ────────────────────────
if grep -qE 'touch -t|touch -d.*"?19|touch -d.*"?20' "$RELEASE_SH"; then
    ok "release.sh normalizes mtime before tar invocation"
else
    fail "release.sh does NOT normalize staging mtime — tar file-headers will vary"
fi

# ── Test 3: release.sh uses deterministic file order ──────────────────────
# Accept either GNU tar --sort=name or the portable find|sort|tar -T - pattern.
if grep -qE 'find.*\| *sort|--sort=name|tar.*-T *-' "$RELEASE_SH"; then
    ok "release.sh enforces deterministic tar file order"
else
    fail "release.sh relies on filesystem ordering (not stable between runs)"
fi

# ── Test 4: functional — two builds using the intended recipe are identical ─
# This validates the recipe itself. If this fails, the approach is wrong
# (and Tests 1-3 don't matter).
STAGE=$(mktemp -d)
mkdir -p "$STAGE/pkg/sub"
echo "hello" > "$STAGE/pkg/a.txt"
echo "world" > "$STAGE/pkg/sub/b.txt"
mkdir "$STAGE/pkg/nested"
echo "deep"  > "$STAGE/pkg/nested/c.txt"

# Normalize mtime across all files + dirs
find "$STAGE/pkg" -exec touch -t 200001010000.00 {} + 2>/dev/null

TAR1=$(mktemp).tar.gz
TAR2=$(mktemp).tar.gz

build_tar() {
    local out="$1"
    (cd "$STAGE" && \
     find "pkg" -print | LC_ALL=C sort | tar --no-recursion -T - -cf -) 2>/dev/null \
       | gzip -n > "$out"
}

build_tar "$TAR1"
sleep 1   # force wall-clock tick between runs
build_tar "$TAR2"

if cmp -s "$TAR1" "$TAR2"; then
    ok "two consecutive builds produce byte-identical tarball (recipe is sound)"
else
    fail "tarball recipe is NOT reproducible"
    echo "     sha256:"
    shasum -a 256 "$TAR1" "$TAR2" 2>/dev/null | sed 's/^/       /'
fi

rm -rf "$STAGE" "$TAR1" "$TAR2"

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
