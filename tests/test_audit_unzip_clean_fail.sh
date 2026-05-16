#!/bin/bash
# test_audit_unzip_clean_fail.sh — v1.0.8 hardening (Bash #1).
# release-audit.sh §6 calls `unzip -q "$DIR/$SKILL_FILE" -d "$TMP"`. Under
# `set -euo pipefail`, a corrupt .skill aborts the script before FAIL is
# incremented and before the per-section summary line is written. The user
# sees a confusing rc=9 instead of "❌ .skill 损坏，无法解压" + summary.
# This test asserts §6 reports the unzip failure cleanly and the summary
# still emits.
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT="$ROOT/scripts/release-audit.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_audit_unzip_clean_fail.sh ══"

# Static check: §6 wraps unzip in `if !` (or equivalent) with FAIL increment
block=$(awk '/^audit_section_6_skill\(\)/,/^audit_section_7_sanity\(\)|^# --- §7/' "$AUDIT")
if echo "$block" | grep -qE 'if[[:space:]]*!.*unzip|unzip.*\|\|.*FAIL'; then
    ok "§6 guards unzip failure with explicit if/|| (no set-e abort)"
else
    fail "§6 still uses bare 'unzip ...' under set -e (will abort on corrupt .skill)"
fi

# Static: corrupt .skill produces a labelled FAIL line, not bare exit
if echo "$block" | grep -qE '损坏|无法解压|❌.*\.skill'; then
    ok "§6 has labelled FAIL message for unzip failure"
else
    fail "§6 missing labelled FAIL message — user would see only rc, not reason"
fi

# Behavioral: corrupt .skill must produce per-section summary even when §6 fails
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/Release/fakeproj-v1.0.0"
# Plant a fake .skill that's not a valid zip
echo "this is not a zip" > "$FIXTURE/Release/fakeproj-v1.0.0/fakeproj-v1.0.0.skill"
mkdir -p "$FIXTURE/skills/fakeproj"
echo "name: fakeproj"           > "$FIXTURE/skills/fakeproj/SKILL.md"
echo "v1.0.0"                   > "$FIXTURE/skills/fakeproj/VERSION"

audit_out=$(PROJECT_ROOT="$FIXTURE" PROJECT_NAME=fakeproj SKILL_NAME=fakeproj \
            bash "$AUDIT" v1.0.0 2>&1 || true)

# Even with corrupt .skill, the audit should still print Per-Section Summary.
# (Without the fix, set -e aborts before the summary block.)
if echo "$audit_out" | grep -qE 'Per-Section Summary|TOTAL'; then
    ok "Per-Section Summary still emitted when §6 unzip fails"
else
    fail "Per-Section Summary missing — audit aborted via set -e on corrupt .skill"
fi

if echo "$audit_out" | grep -qiE '损坏|无法解压|cannot.*unzip'; then
    ok "audit prints labelled corrupt-skill message"
else
    fail "audit silent about corrupt .skill (user sees rc only)"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
