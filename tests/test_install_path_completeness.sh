#!/bin/bash
# test_install_path_completeness.sh — v1.3.2.
#
# Regression guard against v1.3.0-class bug: .skill bundle contained
# scripts/vendored/ but install.sh did not copy it to canonical install,
# silently breaking self-contained-vendoring feature for users who only ran
# install.sh (not direct repo read). v1.3.1 hot-patch fixed install.sh; this
# test future-proofs by enforcing parity between .skill bundle content and
# install.sh copy list.
#
# Strategy: (1) static — every top-level dir in .skill bundle must have a
# corresponding cp/cp -R in install.sh; (2) behavioral — install.sh into
# fixture HOME, then verify every top-level entry in .skill bundle is also
# present in $CANONICAL.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$ROOT/install.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_install_path_completeness.sh ══"

# Find the latest .skill bundle via shell glob (avoids pipefail / set-e
# friction with `ls | head | xargs sh -c` chain when invoked from release.sh's
# run_tests under set -euo pipefail).
SKILL_BUNDLE=""
for cand in "$ROOT"/Release/git_release_skill-v*/git_release_skill-v*.skill; do
    [ -f "$cand" ] && SKILL_BUNDLE="$cand"  # last alphabetical = highest semver
done
if [ -z "$SKILL_BUNDLE" ]; then
    fail "no .skill bundle found under Release/git_release_skill-v*/"
    echo "Results: ✅$PASS passed / ❌$FAIL failed"
    exit 1
fi
ok ".skill bundle present: $(basename "$SKILL_BUNDLE")"

# Unzip .skill bundle to discover top-level dirs
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unzip -q "$SKILL_BUNDLE" -d "$TMP"
SKILL_ROOT_IN_BUNDLE=$(ls "$TMP" | head -1)
if [ -z "$SKILL_ROOT_IN_BUNDLE" ] || [ ! -d "$TMP/$SKILL_ROOT_IN_BUNDLE" ]; then
    fail ".skill bundle missing top-level skill dir"
    echo "Results: ✅$PASS passed / ❌$FAIL failed"
    exit 1
fi
ok ".skill bundle top-level dir: $SKILL_ROOT_IN_BUNDLE"

# === Static: every top-level dir in .skill must appear as a cp source in install.sh ===
BUNDLE_DIRS=$(find "$TMP/$SKILL_ROOT_IN_BUNDLE" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
echo "  Bundle top-level dirs: $(echo "$BUNDLE_DIRS" | tr '\n' ' ')"

for d in $BUNDLE_DIRS; do
    # v1.7.1: 'commands' is NO LONGER skipped. v1.6.0+ ships real subcommand
    # shims (/gitx-init, /gitx-sop) that install.sh MUST propagate; the old
    # v1.1.0 skip masked a dead $SELF_DIR/commands guard for two releases.
    # install.sh must reference this dir as a cp source (with -R or via */ glob)
    if grep -qE "(cp -R \"\\\$SELF_DIR/$d\"|cp \"\\\$SELF_DIR/$d/\"|cp -R \"\\\$SELF_DIR/scripts/$d\")" "$INSTALL_SH" || \
       grep -qE "\\\$SELF_DIR/$d" "$INSTALL_SH"; then
        ok "static: install.sh copies '$d/' to canonical"
    else
        fail "static: install.sh does NOT copy bundle dir '$d/' — silent drop on install (v1.3.0-class bug)"
    fi
done

# === Static: top-level files in .skill must also be copied (SKILL.md, VERSION) ===
BUNDLE_FILES=$(find "$TMP/$SKILL_ROOT_IN_BUNDLE" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; | sort)
for f in $BUNDLE_FILES; do
    if grep -qE "cp \"\\\$SELF_DIR/$f\"" "$INSTALL_SH"; then
        ok "static: install.sh copies '$f' to canonical"
    else
        fail "static: install.sh does NOT copy bundle file '$f' — silent drop on install"
    fi
done

# === Behavioral: full install.sh on fixture HOME + verify .skill ↔ canonical parity ===
FIXTURE_HOME=$(mktemp -d)
# Use the Release dir (not bundle) as install source — install.sh runs from there
RELEASE_DIR=$(dirname "$SKILL_BUNDLE")
HOME="$FIXTURE_HOME" bash "$RELEASE_DIR/install.sh" --force >/dev/null 2>&1 || {
    fail "behavioral: install.sh --force failed on fixture HOME"
    echo "Results: ✅$PASS passed / ❌$FAIL failed"
    rm -rf "$FIXTURE_HOME"
    exit 1
}

CANONICAL_DIR="$FIXTURE_HOME/.agents/skills/$SKILL_ROOT_IN_BUNDLE"
if [ ! -d "$CANONICAL_DIR" ]; then
    fail "behavioral: canonical install dir not created: $CANONICAL_DIR"
    echo "Results: ✅$PASS passed / ❌$FAIL failed"
    rm -rf "$FIXTURE_HOME"
    exit 1
fi
ok "behavioral: canonical install dir created at $CANONICAL_DIR"

# For each top-level dir in bundle, verify it's present in canonical
for d in $BUNDLE_DIRS; do
    if [ "$d" = "commands" ]; then continue; fi  # see static section
    if [ -d "$CANONICAL_DIR/$d" ]; then
        ok "behavioral: '$d/' present in installed canonical"
    else
        fail "behavioral: '$d/' missing from installed canonical (v1.3.0 vendored regression class)"
    fi
done

# Verify vendored/skill-creator/scripts/package_skill.py specifically (v1.3.0 sentinel file)
if [ -f "$CANONICAL_DIR/scripts/vendored/skill-creator/scripts/package_skill.py" ]; then
    ok "behavioral: vendored skill-creator package_skill.py present in canonical"
else
    fail "behavioral: vendored/skill-creator/scripts/package_skill.py missing (v1.3.0-class bug regression!)"
fi

rm -rf "$FIXTURE_HOME"

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
