#!/bin/bash
# test_release_cleanup.sh — tests for trap rollback (H2-2)
# Verifies: when release.sh fails after creating Release dir, the cleanup
# trap removes the partial release directory.
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

echo "══ test_release_cleanup.sh ══"

# ── Test 1: release.sh has cleanup_on_fail function ──────────────────────
if grep -q 'cleanup_on_fail' "$RELEASE_SH"; then
    ok "release.sh defines cleanup_on_fail"
else
    fail "release.sh missing cleanup_on_fail"
fi

# ── Test 2: trap references cleanup function ─────────────────────────────
if grep -qE 'trap.*cleanup_on_fail.*EXIT' "$RELEASE_SH"; then
    ok "release.sh traps EXIT with cleanup_on_fail"
else
    fail "release.sh EXIT trap does not reference cleanup_on_fail"
fi

# ── Test 3: cleanup removes RELEASE_DIR on failure ───────────────────────
if grep -q 'rm -rf.*RELEASE_DIR' "$RELEASE_SH"; then
    ok "cleanup_on_fail removes RELEASE_DIR"
else
    fail "cleanup_on_fail does not remove RELEASE_DIR"
fi

# ── Test 4: RELEASE_SUCCESS guard prevents cleanup on success ────────────
if grep -q 'RELEASE_SUCCESS' "$RELEASE_SH"; then
    ok "cleanup_on_fail checks RELEASE_SUCCESS"
else
    fail "cleanup_on_fail missing RELEASE_SUCCESS guard"
fi

# ── Test 5: functional — failing release cleans up Release dir ───────────
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

Artifacts: `Release/my-skill-v0.0.1/`

---

EOF

mkdir -p "$FIXTURE/tests"
cat > "$FIXTURE/tests/run_all.sh" <<'TESTEOF'
#!/bin/bash
echo "Simulated test failure"
exit 1
TESTEOF

RELEASE_DIR="$FIXTURE/Release/my_skill-v0.0.1"

set +e
PROJECT_ROOT="$FIXTURE" bash "$RELEASE_SH" v0.0.1 >/dev/null 2>&1
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
    ok "release.sh exits non-zero on test failure"
else
    fail "release.sh should have exited non-zero"
fi

if [ ! -d "$RELEASE_DIR" ]; then
    ok "cleanup trap removed Release dir after failure"
else
    fail "Release dir still exists after failure (cleanup trap broken)"
fi

# ── Test 6: failing rerun must preserve a pre-existing release dir ────────
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

mkdir -p "$FIXTURE2/Release/my_skill-v0.0.2" "$FIXTURE2/tests"
echo "do not delete" > "$FIXTURE2/Release/my_skill-v0.0.2/KEEP.txt"
cat > "$FIXTURE2/Release/CHANGELOG.md" <<'EOF'
# Test — Release History

## v0.0.2 — 2026-01-01

Real entry.

Artifacts: `Release/my_skill-v0.0.2/`

---

EOF
cat > "$FIXTURE2/tests/run_all.sh" <<'TESTEOF'
#!/bin/bash
echo "Simulated test failure"
exit 1
TESTEOF

set +e
PROJECT_ROOT="$FIXTURE2" PROJECT_NAME="my_skill" bash "$RELEASE_SH" v0.0.2 >/dev/null 2>&1
RC2=$?
set -e

if [ "$RC2" -ne 0 ]; then
    ok "rerun exits non-zero on test failure"
else
    fail "rerun should have exited non-zero"
fi

if [ -f "$FIXTURE2/Release/my_skill-v0.0.2/KEEP.txt" ]; then
    ok "cleanup preserves pre-existing release dir after failed rerun"
else
    fail "cleanup deleted pre-existing release dir after failed rerun"
fi

# ── Test 7: release.sh refuses to reuse an existing final release dir ─────
if grep -qE 'Release dir already exists|RELEASE_DIR.*already exists|已有.*RELEASE_DIR' "$RELEASE_SH"; then
    ok "release.sh has an explicit existing-release-dir guard"
else
    fail "release.sh lacks an explicit existing-release-dir guard"
fi

# ── Test 8: successful release does NOT clean up ─────────────────────────
# (Verify by checking that RELEASE_SUCCESS=1 is set before final message)
if grep -q 'RELEASE_SUCCESS=1' "$RELEASE_SH"; then
    ok "release.sh sets RELEASE_SUCCESS=1 on completion"
else
    fail "release.sh missing RELEASE_SUCCESS=1"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
