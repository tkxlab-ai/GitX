#!/bin/bash
# test_release_dry_run.sh — tests for --dry-run flag (H10-3)
# Verifies: --dry-run validates everything but skips filesystem mutations.
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

echo "══ test_release_dry_run.sh ══"

add_dual_source_scripts() {
    local fixture="$1"
    local skill="$2"

    mkdir -p "$fixture/scripts" "$fixture/skills/$skill/scripts"
    cat > "$fixture/scripts/scan-credentials.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
    cp "$fixture/scripts/scan-credentials.sh" "$fixture/skills/$skill/scripts/scan-credentials.sh"
}

# ── Test 1: release.sh accepts --dry-run flag ────────────────────────────
if grep -q '\-\-dry-run' "$RELEASE_SH"; then
    ok "release.sh accepts --dry-run flag"
else
    fail "release.sh has no --dry-run support"
fi

# ── Test 2: DRY_RUN variable is used ─────────────────────────────────────
if grep -q 'DRY_RUN' "$RELEASE_SH"; then
    ok "release.sh uses DRY_RUN variable"
else
    fail "release.sh missing DRY_RUN variable"
fi

# ── Test 3: run() wrapper function exists ─────────────────────────────────
if grep -qE '^run\(\)' "$RELEASE_SH" || grep -qE '^run ?\(\)' "$RELEASE_SH"; then
    ok "release.sh defines run() wrapper"
else
    fail "release.sh missing run() wrapper function"
fi

# ── Test 4: run() checks DRY_RUN ─────────────────────────────────────────
if grep -A3 'run()' "$RELEASE_SH" | grep -q 'DRY_RUN'; then
    ok "run() checks DRY_RUN flag"
else
    fail "run() does not check DRY_RUN"
fi

# ── Test 5: run() uses [dry-run] marker ──────────────────────────────────
if grep -q '\[dry-run\]' "$RELEASE_SH"; then
    ok "run() outputs [dry-run] marker"
else
    fail "run() missing [dry-run] marker"
fi

# ── Test 6: filesystem ops wrapped with run ───────────────────────────────
# At least mkdir and cp should be wrapped
if grep -q 'run mkdir' "$RELEASE_SH"; then
    ok "mkdir wrapped with run()"
else
    fail "mkdir not wrapped with run()"
fi

if grep -q 'run cp' "$RELEASE_SH"; then
    ok "cp wrapped with run()"
else
    fail "cp not wrapped with run()"
fi

# ── Test 7: functional — dry-run does not create Release dir ─────────────
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/skills/my-skill"
cat > "$FIXTURE/skills/my-skill/SKILL.md" <<'EOF'
---
name: my-skill
description: test
---
# My Skill
EOF
printf 'v0.0.1\n' > "$FIXTURE/skills/my-skill/VERSION"

mkdir -p "$FIXTURE/Release"
cat > "$FIXTURE/Release/CHANGELOG.md" <<'EOF'
# Test — Release History

## v0.0.1 — 2026-01-01

Real entry (not TODO).

Artifacts: `Release/my_skill-v0.0.1/`

---

EOF

mkdir -p "$FIXTURE/tests"
cat > "$FIXTURE/tests/run_all.sh" <<'TESTEOF'
#!/bin/bash
exit 0
TESTEOF
add_dual_source_scripts "$FIXTURE" "my-skill"

RELEASE_DIR="$FIXTURE/Release/my_skill-v0.0.1"

set +e
OUTPUT=$(PROJECT_ROOT="$FIXTURE" PROJECT_NAME="my_skill" SKILL_NAME="my-skill" bash "$RELEASE_SH" v0.0.1 --dry-run 2>&1)
RC=$?
set -e

if echo "$OUTPUT" | grep -q '\[dry-run\]'; then
    ok "dry-run output contains [dry-run] markers"
else
    fail "dry-run output missing [dry-run] markers"
    echo "   output: $(echo "$OUTPUT" | grep -i 'dry-run' | head -3)"
fi

if [ ! -d "$RELEASE_DIR" ]; then
    ok "dry-run did not create versioned Release dir"
else
    fail "dry-run created versioned Release dir $RELEASE_DIR (BUG: mkdir not wrapped in run())"
fi

# Test 7b: dry-run must NOT trigger cleanup (no filesystem state to clean)
if echo "$OUTPUT" | grep -q "Cleaning up failed release"; then
    fail "dry-run triggered cleanup — means real dirs were created then removed (masking bug)"
else
    ok "dry-run did not trigger cleanup (no real dirs created)"
fi

# Test 7c: dry-run should complete without crash (exit 0)
if [ "$RC" -eq 0 ]; then
    ok "dry-run completed successfully (exit 0)"
else
    fail "dry-run crashed (exit $RC) — pipeline broken in dry-run mode"
fi

# ── Test 8: dry-run still validates CHANGELOG ────────────────────────────
# Create fixture WITHOUT changelog entry — dry-run should still fail
FIXTURE2=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$FIXTURE2"' EXIT

mkdir -p "$FIXTURE2/skills/my-skill"
cat > "$FIXTURE2/skills/my-skill/SKILL.md" <<'EOF'
---
name: my-skill
description: test
---
# My Skill
EOF
printf 'v0.0.2\n' > "$FIXTURE2/skills/my-skill/VERSION"

mkdir -p "$FIXTURE2/Release"
cat > "$FIXTURE2/Release/CHANGELOG.md" <<'EOF'
# Test — Release History

(no entries)
EOF

mkdir -p "$FIXTURE2/tests"
cat > "$FIXTURE2/tests/run_all.sh" <<'TESTEOF'
#!/bin/bash
exit 0
TESTEOF

set +e
OUTPUT2=$(PROJECT_ROOT="$FIXTURE2" PROJECT_NAME="my_skill" SKILL_NAME="my-skill" bash "$RELEASE_SH" v0.0.2 --dry-run 2>&1)
RC2=$?
set -e

if [ "$RC2" -ne 0 ]; then
    ok "dry-run still enforces CHANGELOG gate"
else
    fail "dry-run skipped CHANGELOG gate (should still validate): $OUTPUT2"
fi

# ── Test 9: dry-run must NOT modify CHANGELOG.md ──────────────────────────
# (P0-4: CHANGELOG gate mv/echo paths should be short-circuited in dry-run)
FIXTURE3=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$FIXTURE2" "$FIXTURE3"' EXIT

mkdir -p "$FIXTURE3/skills/test-skill"
cat > "$FIXTURE3/skills/test-skill/SKILL.md" <<'EOF'
---
name: test-skill
description: test
---
# Test Skill
EOF
printf 'v0.0.3\n' > "$FIXTURE3/skills/test-skill/VERSION"

mkdir -p "$FIXTURE3/Release"
cat > "$FIXTURE3/Release/CHANGELOG.md" <<'EOF'
# Test — Release History

(no entries)
EOF

mkdir -p "$FIXTURE3/tests"
cat > "$FIXTURE3/tests/run_all.sh" <<'TESTEOF'
#!/bin/bash
exit 0
TESTEOF

# Record CHANGELOG checksum before dry-run
MD5_BEFORE=""
if command -v md5 >/dev/null 2>&1; then
    MD5_BEFORE=$(md5 -q "$FIXTURE3/Release/CHANGELOG.md" 2>/dev/null)
elif command -v md5sum >/dev/null 2>&1; then
    MD5_BEFORE=$(md5sum "$FIXTURE3/Release/CHANGELOG.md" | awk '{print $1}')
else
    MD5_BEFORE=$(cat "$FIXTURE3/Release/CHANGELOG.md" | wc -c)
fi

set +e
OUTPUT3=$(PROJECT_ROOT="$FIXTURE3" PROJECT_NAME="test_skill" SKILL_NAME="test-skill" bash "$RELEASE_SH" v0.0.3 --dry-run 2>&1)
RC3=$?
set -e

MD5_AFTER=""
if command -v md5 >/dev/null 2>&1; then
    MD5_AFTER=$(md5 -q "$FIXTURE3/Release/CHANGELOG.md" 2>/dev/null)
elif command -v md5sum >/dev/null 2>&1; then
    MD5_AFTER=$(md5sum "$FIXTURE3/Release/CHANGELOG.md" | awk '{print $1}')
else
    MD5_AFTER=$(cat "$FIXTURE3/Release/CHANGELOG.md" | wc -c)
fi

if [ "$MD5_BEFORE" = "$MD5_AFTER" ]; then
    ok "dry-run did NOT modify CHANGELOG.md"
else
    fail "dry-run modified CHANGELOG.md (P0-4: CHANGELOG gate leaks writes)"
fi

if [ "$RC3" -ne 0 ] && echo "$OUTPUT3" | grep -qi "CHANGELOG"; then
    ok "dry-run still reports CHANGELOG gate status"
else
    fail "dry-run should still report CHANGELOG gate (exit $RC3)"
fi

# ── Test 10: dry-run must NOT invoke skill-creator package code ───────────
FIXTURE4=$(mktemp -d)
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$FIXTURE2" "$FIXTURE3" "$FIXTURE4" "$FAKE_HOME"' EXIT

mkdir -p "$FIXTURE4/skills/my-skill"
cat > "$FIXTURE4/skills/my-skill/SKILL.md" <<'EOF'
---
name: my-skill
description: test
---
# My Skill
EOF
printf 'v0.0.5\n' > "$FIXTURE4/skills/my-skill/VERSION"

mkdir -p "$FIXTURE4/Release"
cat > "$FIXTURE4/Release/CHANGELOG.md" <<'EOF'
# Test — Release History

## v0.0.5 — 2026-01-01

Real entry.

Artifacts: `Release/my_skill-v0.0.5/`

---

EOF

mkdir -p "$FIXTURE4/tests"
cat > "$FIXTURE4/tests/run_all.sh" <<'TESTEOF'
#!/bin/bash
exit 0
TESTEOF
add_dual_source_scripts "$FIXTURE4" "my-skill"

FAKE_CREATOR="$FAKE_HOME/.claude/plugins/cache/claude-plugins-official/skill-creator/unknown/skills/skill-creator"
mkdir -p "$FAKE_CREATOR/scripts"
touch "$FAKE_CREATOR/scripts/__init__.py"
cat > "$FAKE_CREATOR/scripts/package_skill.py" <<'PYEOF'
import os
marker = os.environ.get("TKX_DRY_RUN_SKILL_CREATOR_MARKER")
if marker:
    with open(marker, "w", encoding="utf-8") as f:
        f.write("skill-creator was invoked\n")
PYEOF

MARKER="$FIXTURE4/skill-creator-invoked"
set +e
OUTPUT4=$(HOME="$FAKE_HOME" TKX_DRY_RUN_SKILL_CREATOR_MARKER="$MARKER" PROJECT_ROOT="$FIXTURE4" PROJECT_NAME="my_skill" SKILL_NAME="my-skill" bash "$RELEASE_SH" v0.0.5 --dry-run 2>&1)
RC4=$?
set -e

if [ ! -f "$MARKER" ]; then
    ok "dry-run did NOT invoke skill-creator package code"
else
    fail "dry-run invoked skill-creator package code"
fi

if [ "$RC4" -eq 0 ] && echo "$OUTPUT4" | grep -q '\[dry-run\]'; then
    ok "dry-run with skill-creator present still completes as preview"
else
    fail "dry-run with skill-creator present should complete as preview (exit $RC4)"
fi

# ── Test 11: dry-run reports existing release dir as a real blocker ───────
FIXTURE5=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$FIXTURE2" "$FIXTURE3" "$FIXTURE4" "$FAKE_HOME" "$FIXTURE5"' EXIT

mkdir -p "$FIXTURE5/skills/my-skill" "$FIXTURE5/Release/my_skill-v0.0.6" "$FIXTURE5/tests"
cat > "$FIXTURE5/skills/my-skill/SKILL.md" <<'EOF'
---
name: my-skill
description: test
---
# My Skill
EOF
printf 'v0.0.6\n' > "$FIXTURE5/skills/my-skill/VERSION"
cat > "$FIXTURE5/Release/CHANGELOG.md" <<'EOF'
# Test — Release History

## v0.0.6 — 2026-01-01

Real entry.

Artifacts: `Release/my_skill-v0.0.6/`

---

EOF
cat > "$FIXTURE5/tests/run_all.sh" <<'TESTEOF'
#!/bin/bash
exit 0
TESTEOF

set +e
OUTPUT5=$(PROJECT_ROOT="$FIXTURE5" PROJECT_NAME="my_skill" SKILL_NAME="my-skill" bash "$RELEASE_SH" v0.0.6 --dry-run 2>&1)
RC5=$?
set -e

if [ "$RC5" -ne 0 ] && echo "$OUTPUT5" | grep -qi "Release dir already exists"; then
    ok "dry-run reports existing release dir as blocker"
else
    fail "dry-run should fail when final release dir already exists (exit $RC5)"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
