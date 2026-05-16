#!/bin/bash
# test_install_path_completeness.sh — v1.9.6 (bootstrap-safe).
#
# Regression guard against v1.3.0-class bug: .skill bundle contained
# scripts/vendored/ but install.sh did not copy it to canonical install,
# silently breaking self-contained-vendoring for users who only ran
# install.sh. v1.3.1 hot-patch fixed install.sh; this test future-proofs by
# enforcing parity between the shipped payload and install.sh's copy list.
#
# Strategy (two layers):
#   (A) SOURCE-static — ALWAYS runs, bootstrap-independent: every top-level
#       dir/file under skills/gitx-release/ (the packaged payload source of
#       truth) must be referenced as a cp source in install.sh. This keeps
#       the v1.3.0-class "install.sh silently drops a top-level dir" guard
#       live even before any .skill artifact exists.
#   (B) BUNDLE-static + behavioral — runs only when the .skill for the
#       CURRENT VERSION exists. release.sh runs the test gate BEFORE it
#       builds the artifact (run_tests → build_skill_package), and a
#       legitimate full Release/ purge (the meta-skill's own leak audit can
#       force one) can leave no current artifact. Validating the "highest
#       leftover" bundle there is wrong — an ancient pre-vendored bundle
#       would false-FAIL the v1.3.0 sentinel. So when the current-VERSION
#       artifact is absent (bootstrap / pre-build), layer (B) is SKIPPed
#       (➖), not FAILed; it re-engages automatically once the artifact
#       exists (steady-state dev runs, and any post-build run).
#
# Why bind to CURRENT VERSION (not "highest .skill"): the guard's job is to
# validate the artifact being shipped, not whatever stale bundle happens to
# sort highest. In steady state current==highest, so behavior is unchanged.
#
# exit: 0=no failures (skips allowed), 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$ROOT/install.sh"
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
skip() { echo "  ➖ $1"; SKIP=$((SKIP+1)); }
echo "══ test_install_path_completeness.sh ══"

# install.sh references a top-level entry as a cp source (with -R or */ glob)
references_entry() {
    local e="$1"
    grep -qE "(cp -R \"\\\$SELF_DIR/$e\"|cp \"\\\$SELF_DIR/$e/\"|cp -R \"\\\$SELF_DIR/scripts/$e\")" "$INSTALL_SH" \
        || grep -qE "\\\$SELF_DIR/$e" "$INSTALL_SH"
}

# === Layer A: SOURCE-static parity (always, bootstrap-independent) ===
# skills/gitx-release/ is the payload that gets packaged into the .skill and
# laid down by install.sh; install.sh must copy every top-level dir from it.
SRC_SKILL="$ROOT/skills/gitx-release"
if [ -d "$SRC_SKILL" ]; then
    SRC_DIRS=$(find "$SRC_SKILL" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
    echo "  Source payload top-level dirs: $(echo "$SRC_DIRS" | tr '\n' ' ')"
    for d in $SRC_DIRS; do
        # Do NOT skip 'commands' here. Since v1.7.1 the bundle-static layer
        # deliberately checks commands/ — install.sh MUST copy the /gitx:*
        # subcommand shims; skipping it would let a shim-drop regression
        # pass the pre-build gate (codex P2, v1.9.6). Only the BEHAVIORAL
        # canonical-presence loop skips commands, because those shims land
        # in ~/.claude/commands, not the canonical skill dir.
        if references_entry "$d"; then
            ok "source-static: install.sh copies '$d/' to canonical"
        else
            fail "source-static: install.sh does NOT copy payload dir '$d/' — silent drop on install (v1.3.0-class bug)"
        fi
    done
else
    skip "source payload dir absent ($SRC_SKILL) — cannot run source-static parity"
fi

# === Layer B gate: only validate the artifact for the CURRENT VERSION ===
CUR_VER="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || true)"
CUR_SKILL="$ROOT/Release/git_release_skill-$CUR_VER/git_release_skill-$CUR_VER.skill"

if [ -z "$CUR_VER" ] || [ ! -f "$CUR_SKILL" ]; then
    skip "no .skill for current VERSION '${CUR_VER:-?}' (bootstrap / pre-build state) — bundle-static + behavioral parity will engage once Release/git_release_skill-$CUR_VER/ exists"
    echo ""
    echo "Results: ✅$PASS passed / ❌$FAIL failed / ➖$SKIP skipped"
    [ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
    echo "FAIL"; exit 1
fi

SKILL_BUNDLE="$CUR_SKILL"
ok ".skill bundle present (current VERSION $CUR_VER): $(basename "$SKILL_BUNDLE")"

# Unzip .skill bundle to discover top-level dirs
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unzip -q "$SKILL_BUNDLE" -d "$TMP"
SKILL_ROOT_IN_BUNDLE=$(ls "$TMP" | head -1)
if [ -z "$SKILL_ROOT_IN_BUNDLE" ] || [ ! -d "$TMP/$SKILL_ROOT_IN_BUNDLE" ]; then
    fail ".skill bundle missing top-level skill dir"
    echo "Results: ✅$PASS passed / ❌$FAIL failed / ➖$SKIP skipped"
    exit 1
fi
ok ".skill bundle top-level dir: $SKILL_ROOT_IN_BUNDLE"

# === Bundle-static: every top-level dir in .skill must appear in install.sh ===
BUNDLE_DIRS=$(find "$TMP/$SKILL_ROOT_IN_BUNDLE" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
echo "  Bundle top-level dirs: $(echo "$BUNDLE_DIRS" | tr '\n' ' ')"
for d in $BUNDLE_DIRS; do
    if references_entry "$d"; then
        ok "bundle-static: install.sh copies '$d/' to canonical"
    else
        fail "bundle-static: install.sh does NOT copy bundle dir '$d/' — silent drop on install (v1.3.0-class bug)"
    fi
done

# === Bundle-static: top-level files in .skill must also be copied ===
BUNDLE_FILES=$(find "$TMP/$SKILL_ROOT_IN_BUNDLE" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; | sort)
for f in $BUNDLE_FILES; do
    if grep -qE "cp \"\\\$SELF_DIR/$f\"" "$INSTALL_SH"; then
        ok "bundle-static: install.sh copies '$f' to canonical"
    else
        fail "bundle-static: install.sh does NOT copy bundle file '$f' — silent drop on install"
    fi
done

# === Behavioral: full install.sh on fixture HOME + .skill ↔ canonical parity ===
FIXTURE_HOME=$(mktemp -d)
RELEASE_DIR=$(dirname "$SKILL_BUNDLE")
HOME="$FIXTURE_HOME" bash "$RELEASE_DIR/install.sh" --force >/dev/null 2>&1 || {
    fail "behavioral: install.sh --force failed on fixture HOME"
    echo "Results: ✅$PASS passed / ❌$FAIL failed / ➖$SKIP skipped"
    rm -rf "$FIXTURE_HOME"
    exit 1
}

CANONICAL_DIR="$FIXTURE_HOME/.agents/skills/$SKILL_ROOT_IN_BUNDLE"
if [ ! -d "$CANONICAL_DIR" ]; then
    fail "behavioral: canonical install dir not created: $CANONICAL_DIR"
    echo "Results: ✅$PASS passed / ❌$FAIL failed / ➖$SKIP skipped"
    rm -rf "$FIXTURE_HOME"
    exit 1
fi
ok "behavioral: canonical install dir created at $CANONICAL_DIR"

for d in $BUNDLE_DIRS; do
    if [ "$d" = "commands" ]; then continue; fi
    if [ -d "$CANONICAL_DIR/$d" ]; then
        ok "behavioral: '$d/' present in installed canonical"
    else
        fail "behavioral: '$d/' missing from installed canonical (v1.3.0 vendored regression class)"
    fi
done

# v1.3.0 sentinel file
if [ -f "$CANONICAL_DIR/scripts/vendored/skill-creator/scripts/package_skill.py" ]; then
    ok "behavioral: vendored skill-creator package_skill.py present in canonical"
else
    fail "behavioral: vendored/skill-creator/scripts/package_skill.py missing (v1.3.0-class bug regression!)"
fi

rm -rf "$FIXTURE_HOME"

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed / ➖$SKIP skipped"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
