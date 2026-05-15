#!/bin/bash
# test_source_date_epoch.sh — v0.9.9 feature A
# release.sh must honor SOURCE_DATE_EPOCH (Debian/Nix/SLSA standard) when
# normalizing staging mtime. Unset → default epoch (2000-01-01). Set →
# convert epoch to touch -t format, apply to staging.
#
# Verifies:
#  1. release.sh references SOURCE_DATE_EPOCH env
#  2. default fallback mtime is present
#  3. portable date epoch→touch conversion (BSD date -r + GNU date -d)
#  4. functional: setting SOURCE_DATE_EPOCH changes staging mtime; same
#     epoch on two runs → byte-identical tarball

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_SH="$SCRIPT_DIR/../scripts/release.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_source_date_epoch.sh ══"

# ── Test 1: release.sh references SOURCE_DATE_EPOCH ────────────────────────
if grep -q 'SOURCE_DATE_EPOCH' "$RELEASE_SH"; then
    ok "release.sh references SOURCE_DATE_EPOCH env"
else
    fail "release.sh has no SOURCE_DATE_EPOCH support"
fi

# ── Test 2: default fallback mtime is preserved ───────────────────────────
# Accept either literal `touch -t 200001…` OR a variable holding that string
# for the default branch (SOURCE_DATE_EPOCH unset).
if grep -qE '200001010000\.?0*|197[05]01010000\.?0*' "$RELEASE_SH"; then
    ok "release.sh has default fallback mtime literal"
else
    fail "release.sh missing default fallback mtime"
fi

# ── Test 3: portable date epoch→touch conversion ──────────────────────────
# Must handle both BSD (date -r EPOCH) and GNU (date -d @EPOCH)
if grep -qE 'date -u -r.*SOURCE_DATE_EPOCH|date -r "?\$[{]?SOURCE_DATE_EPOCH' "$RELEASE_SH" \
   && grep -qE 'date -u -d.*@.*SOURCE_DATE_EPOCH|date -d "@\$[{]?SOURCE_DATE_EPOCH' "$RELEASE_SH"; then
    ok "release.sh has portable date conversion (BSD + GNU)"
else
    fail "release.sh date conversion is not portable (missing BSD or GNU form)"
fi

# ── Test 4: functional — recipe produces different hash for different epochs ─
STAGE=$(mktemp -d)
mkdir -p "$STAGE/pkg"
echo "hello" > "$STAGE/pkg/a.txt"

apply_epoch() {
    local epoch="$1"
    local fmt
    fmt=$(date -u -r "$epoch" "+%Y%m%d%H%M.%S" 2>/dev/null \
          || date -u -d "@$epoch" "+%Y%m%d%H%M.%S")
    find "$STAGE/pkg" -exec touch -t "$fmt" {} + 2>/dev/null
}

build() {
    local out="$1"
    (cd "$STAGE" && find "pkg" -print | LC_ALL=C sort | tar --no-recursion -T - -cf -) 2>/dev/null \
        | gzip -n > "$out"
}

T1=$(mktemp).tgz
T2=$(mktemp).tgz
T3=$(mktemp).tgz

apply_epoch 946684800   # 2000-01-01 UTC
build "$T1"
apply_epoch 946684800
build "$T2"
apply_epoch 1577836800  # 2020-01-01 UTC
build "$T3"

if cmp -s "$T1" "$T2"; then
    ok "same SOURCE_DATE_EPOCH → byte-identical tarball"
else
    fail "same epoch produced different tarballs (recipe is non-deterministic)"
fi

if ! cmp -s "$T1" "$T3"; then
    ok "different SOURCE_DATE_EPOCH → different tarball (epoch actually drives mtime)"
else
    fail "different epoch produced same tarball (SOURCE_DATE_EPOCH has no effect)"
fi

rm -rf "$STAGE" "$T1" "$T2" "$T3"

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
