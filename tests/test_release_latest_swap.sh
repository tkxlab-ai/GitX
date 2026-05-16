#!/bin/bash
# test_release_latest_swap.sh — v0.9.8 Gotcha #15
# release.sh's latest-symlink update step (currently `mv -f .latest.tmp latest`)
# breaks on BSD mv (macOS): when `latest` already points to a directory,
# BSD mv FOLLOWS the symlink and moves `.latest.tmp` INTO that directory
# instead of replacing the symlink. Result: latest stays stale, an orphan
# `.latest.tmp` accumulates inside the previous version's dir.
#
# Reproduce in isolation, then assert release.sh uses a portable approach:
# either `ln -sfn` (replace-symlink, BSD+GNU) or explicit branching.
#
# exit: 0=all pass, 1=any fail

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_SH="$SCRIPT_DIR/../scripts/release.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_release_latest_swap.sh ══"

# ── Test 1: release.sh uses portable symlink swap (ln -sfn / mv -fh / mv -fT) ─
if grep -qE 'ln -sfn|mv -fh|mv -fT|mv -f.*--no-target-directory' "$RELEASE_SH"; then
    ok "release.sh uses portable atomic symlink swap"
else
    fail "release.sh uses non-portable 'mv -f' which follows symlinks on BSD/macOS"
fi

# ── Test 2: functional — recipe correctly replaces a symlink-to-directory ──
TMPROOT=$(mktemp -d)
mkdir -p "$TMPROOT/Release/v1.0.0" "$TMPROOT/Release/v1.0.1"
(cd "$TMPROOT/Release" && ln -sf "v1.0.0" "latest")

# Apply the recipe we're going to put into release.sh
(cd "$TMPROOT/Release" && ln -sfn "v1.0.1" "latest")

actual=$(readlink "$TMPROOT/Release/latest")
if [ "$actual" = "v1.0.1" ]; then
    ok "ln -sfn correctly replaces symlink-to-directory (now → $actual)"
else
    fail "ln -sfn failed; latest is still '$actual'"
fi

# ── Test 3: regression — no orphan tmp file inside the old version dir ────
if find "$TMPROOT/Release/v1.0.0" -name "*tmp*" 2>/dev/null | grep -q .; then
    fail "orphan tmp file leaked into v1.0.0/ (recipe is wrong)"
else
    ok "no orphan tmp file in previous version dir"
fi

rm -rf "$TMPROOT"

# ── Test 4: confirm BSD-style 'mv -f .latest.tmp latest' DOES break ───────
# Sanity check that the bug is reproducible with the bad recipe — guards
# against accidentally believing the bug is gone if Test 1 starts passing
# but the underlying fact about BSD mv hasn't changed.
TMPROOT2=$(mktemp -d)
mkdir -p "$TMPROOT2/Release/v2.0.0" "$TMPROOT2/Release/v2.0.1"
(cd "$TMPROOT2/Release" && ln -sf "v2.0.0" "latest")
(cd "$TMPROOT2/Release" && ln -sf "v2.0.1" ".latest.tmp" && mv -f ".latest.tmp" "latest" 2>/dev/null || true)

after=$(readlink "$TMPROOT2/Release/latest")
case "$(uname)" in
    Darwin|FreeBSD)
        if [ "$after" = "v2.0.0" ]; then
            ok "(diagnostic) BSD mv -f confirmed buggy on this platform — fix is justified"
        else
            ok "(diagnostic) BSD mv -f happens to work on this $(uname); fix is still defensive"
        fi
        ;;
    Linux)
        if [ "$after" = "v2.0.1" ]; then
            ok "(diagnostic) GNU mv -f works on Linux; fix is harmless / defensive"
        else
            ok "(diagnostic) Linux mv -f also broken on this system"
        fi
        ;;
    *)
        ok "(diagnostic) unknown platform $(uname); skip behavior probe"
        ;;
esac
rm -rf "$TMPROOT2"

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
