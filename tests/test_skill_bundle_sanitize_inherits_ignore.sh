#!/bin/bash
# test_skill_bundle_sanitize_inherits_ignore.sh — v1.2 A4 fix (Gotcha #11 surface 3).
#
# release.sh:497-505 unzips the .skill bundle into a mktemp staging dir and
# runs release-sanitize.sh on it. release-sanitize.sh reads $DIR/.sanitize-ignore
# (the whitelist), but the unzipped .skill stage contains NO .sanitize-ignore —
# because .sanitize-ignore must never be persisted into .skill (Gotcha #11
# original contract: whitelist would leak downstream).
#
# Effect: any "intentional" fixture content (MAC literals, sample IPs, sample
# paths, sample emails) that exists in the .skill bundle hits sanitize as a
# false positive. mac-release v0.1.0 self-bake hit this with a MAC-pattern
# literal in assets/TEST-SCENARIOS.md (Dev Log 2026-05-07; Gotcha #31 forbids
# pasting literal bait strings into source files — sanitize reads them).
#
# Fix: temporarily copy PROJECT_ROOT/.sanitize-ignore into SKILL_STAGE/ for
# the scan duration, then rm it immediately on both success and failure paths.
# Mirrors release-audit.sh §7 (line 504-508) pattern.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"
SANITIZE_SH="$ROOT/scripts/release-sanitize.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_skill_bundle_sanitize_inherits_ignore.sh ══"

# === Static 1: release.sh copies project-root .sanitize-ignore into SKILL_STAGE
# before invoking sanitize on the unzipped bundle ===
if awk '/SKILL_STAGE=\$\(mktemp/,/--label .skill/' "$RELEASE_SH" \
   | grep -qE "cp .*PROJECT_ROOT/\.sanitize-ignore.*SKILL_STAGE"; then
    ok "release.sh cp's PROJECT_ROOT/.sanitize-ignore into SKILL_STAGE before .skill scan"
else
    fail "release.sh does NOT inherit project .sanitize-ignore for .skill bundle scan (Gotcha #11 surface 3)"
fi

# === Static 2: release.sh removes the temporary .sanitize-ignore after scan
# (success path) — must not leak into any subsequent step or persist if
# SKILL_STAGE somehow survives ===
if awk '/--label .skill/,/^}/' "$RELEASE_SH" \
   | grep -qE "rm .*SKILL_STAGE.*sanitize-ignore"; then
    ok "release.sh rm's temp .sanitize-ignore after .skill scan (no leak)"
else
    fail "release.sh leaves temp .sanitize-ignore in SKILL_STAGE after scan"
fi

# === Static 3: Gotcha #11 ORIGINAL contract preserved — .sanitize-ignore
# must NOT be flatten'd into Release/<ver>/ or into the .skill bundle source
# (skills/<name>/). Any cp into those persistent locations would leak the
# whitelist downstream. ===
if grep -nE "cp .*\.sanitize-ignore" "$RELEASE_SH" \
   | grep -vE "SKILL_STAGE|RELEASE_DIR.*\$_S7|/Release/\$_S7" \
   | grep -qE "RELEASE_DIR|SKILL_SRC_DIR|skills/.*sanitize-ignore"; then
    fail "release.sh persists .sanitize-ignore into bundle/Release dir — breaks Gotcha #11 contract"
else
    ok "Gotcha #11 contract preserved: .sanitize-ignore never persisted into bundle or Release dir"
fi

# === Behavioral: simulate the fixed flow ===
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

# Build a fake project root with .sanitize-ignore exempting a specific file
mkdir -p "$FIXTURE/project"
cat > "$FIXTURE/project/.sanitize-ignore" <<'EOF'
assets/TEST-SCENARIOS.md
EOF

# Build a fake .skill stage containing the exempted file with a MAC literal.
# Gotcha #31 anti-self-trip: assemble the MAC literal at runtime from byte
# fragments so the source file itself does NOT carry the full literal —
# sanitize reads source files looking for these patterns and would trip if
# we pasted a fixture MAC literal here directly. Same trick the v1.0.8
# credential test fixtures use for Bearer/Stripe tokens.
mkdir -p "$FIXTURE/skill_stage/myskill/assets"
B1="aa"; B2="bb"; B3="cc"; B4="dd"; B5="ee"; B6="ff"
{
    echo "# Test Scenarios"
    echo "Sample MAC literal in fixture: ${B1}:${B2}:${B3}:${B4}:${B5}:${B6}"
} > "$FIXTURE/skill_stage/myskill/assets/TEST-SCENARIOS.md"

# Match release.sh fix shape: scan root is SKILL_STAGE/$SKILL_NAME (the actual
# unzipped bundle root), not SKILL_STAGE itself. That way file-paths-relative-
# to-scan-root are `assets/TEST-SCENARIOS.md` (matching what PROJECT_ROOT scan
# saw), and project-root .sanitize-ignore patterns work unchanged.
SCAN_ROOT="$FIXTURE/skill_stage/myskill"

# --- Behavior 1: WITH .sanitize-ignore inherited → scan PASSes (MAC exempted) ---
cp "$FIXTURE/project/.sanitize-ignore" "$SCAN_ROOT/.sanitize-ignore"
if bash "$SANITIZE_SH" --label .skill "$SCAN_ROOT" >/dev/null 2>&1; then
    ok "behavior: WITH inherited .sanitize-ignore → MAC literal in fixture file is exempted (PASS)"
else
    fail "behavior: inherited .sanitize-ignore did NOT exempt the fixture file (sanitize FAILed)"
fi
rm -f "$SCAN_ROOT/.sanitize-ignore"

# --- Behavior 2: WITHOUT .sanitize-ignore (pre-fix bug state) → scan FAILs ---
# This is the bug Dev Log 2026-05-07 documented: mac-release v0.1.0 hit this.
if ! bash "$SANITIZE_SH" --label .skill "$SCAN_ROOT" >/dev/null 2>&1; then
    ok "behavior: WITHOUT .sanitize-ignore → MAC literal trips sanitize (confirms bug shape)"
else
    fail "behavior: scan unexpectedly passed without .sanitize-ignore — fixture or sanitize broken"
fi

# === Static 4: documentation comment links A4 fix back to Gotcha #11 ===
if grep -qE "Gotcha #11|surface 3|third surface|inherit.*\.sanitize-ignore" "$RELEASE_SH"; then
    ok "release.sh comments reference Gotcha #11 / surface 3 (Tacit#4 Why > How)"
else
    fail "release.sh fix lacks Gotcha #11 reference comment — future maintainers won't see the contract"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
