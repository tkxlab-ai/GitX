#!/bin/bash
# test_detect_project.sh — tests for scripts/lib/detect-project.sh
# shellcheck disable=SC1090
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$_ROOT/scripts/lib/detect-project.sh"

PASS=0; FAIL=0
ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== test_detect_project.sh ==="

# --- Setup fixture ---
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/skills/my-skill"
cat > "$FIXTURE/skills/my-skill/SKILL.md" <<'EOF'
---
name: my-skill
description: test skill
---
# My Skill
EOF

EXPECTED_NAME="$(basename "$FIXTURE" | tr '[:upper:]' '[:lower:]')"

run_case() {
    local name="$1"; shift
    if "$@"; then
        ok "$name"
    else
        fail "$name"
    fi
}

test_detect_project_name_from_basename() {
    cd "$FIXTURE"
    unset PROJECT_ROOT PROJECT_NAME SKILL_NAME
    source "$LIB"
    [ "$PROJECT_NAME" = "$EXPECTED_NAME" ]
}

test_detect_project_name_override() {
    cd "$FIXTURE"
    unset PROJECT_ROOT PROJECT_NAME SKILL_NAME
    PROJECT_NAME="custom-name"
    source "$LIB"
    [ "$PROJECT_NAME" = "custom-name" ]
}

test_detect_skill_name_from_skills_dir() {
    cd "$FIXTURE"
    unset PROJECT_ROOT PROJECT_NAME SKILL_NAME
    source "$LIB"
    [ "$SKILL_NAME" = "my-skill" ]
}

test_detect_skill_name_override() {
    cd "$FIXTURE"
    unset PROJECT_ROOT PROJECT_NAME SKILL_NAME
    SKILL_NAME="override-skill"
    source "$LIB"
    [ "$SKILL_NAME" = "override-skill" ]
}

test_error_without_skills_dir() {
    FIXTURE2=$(mktemp -d)
    cd "$FIXTURE2"
    unset PROJECT_ROOT PROJECT_NAME SKILL_NAME
    set +e
    source "$LIB" 2>/dev/null
    rc=$?
    set -e
    rm -rf "$FIXTURE2"
    [ "$rc" -ne 0 ]
}

test_exclude_workspace_evals_dirs() {
    mkdir -p "$FIXTURE/skills/my-workspace" "$FIXTURE/skills/my-evals"
    touch "$FIXTURE/skills/my-workspace/SKILL.md"
    touch "$FIXTURE/skills/my-evals/SKILL.md"
    cd "$FIXTURE"
    unset PROJECT_ROOT PROJECT_NAME SKILL_NAME
    set +e
    source "$LIB" 2>/dev/null
    rc=$?
    set -e
    [ "$rc" -eq 0 ] && [ "${SKILL_NAME:-}" = "my-skill" ]
}

test_legacy_flat_skill_hint() {
    FIXTURE3=$(mktemp -d)
    mkdir -p "$FIXTURE3/old/1by1-skill-dev" "$FIXTURE3/releases/1by1-v0.3"
    cat > "$FIXTURE3/old/1by1-skill-dev/SKILL.md" <<'EOF'
---
name: 1by1
description: legacy flat skill
---
EOF
    cat > "$FIXTURE3/releases/1by1-v0.3/SKILL.md" <<'EOF'
---
name: archived
description: archived release
---
EOF
    cd "$FIXTURE3"
    unset PROJECT_ROOT PROJECT_NAME SKILL_NAME
    set +e
    source "$LIB" 2>"$FIXTURE3/err.txt"
    rc=$?
    set -e
    local err
    err="$(cat "$FIXTURE3/err.txt")"
    rm -rf "$FIXTURE3"
    [ "$rc" -ne 0 ] \
        && echo "$err" | grep -q '发现可能的旧式 flat skill bundle' \
        && echo "$err" | grep -q 'old/1by1-skill-dev/SKILL.md' \
        && echo "$err" | grep -q 'GitX 需要标准布局'
}

test_legacy_flat_skill_generates_upgrade_guideline() {
    FIXTURE4=$(mktemp -d)
    mkdir -p "$FIXTURE4/old/1by1-skill-dev" "$FIXTURE4/backups/old"
    cat > "$FIXTURE4/old/1by1-skill-dev/SKILL.md" <<'EOF'
---
name: 1by1
description: legacy flat skill
metadata:
  version: 0.5.0
---
EOF
    cat > "$FIXTURE4/backups/old/SKILL.md" <<'EOF'
---
name: ignored-backup
description: should not appear in upgrade guideline
---
EOF
    cd "$FIXTURE4"
    unset PROJECT_ROOT PROJECT_NAME SKILL_NAME
    set +e
    source "$LIB" 2>"$FIXTURE4/err.txt"
    rc=$?
    set -e
    local guide="$FIXTURE4/GitX_Upgrade_Guideline.md"
    local ok_result=1
    if [ "$rc" -ne 0 ] \
        && [ -f "$guide" ] \
        && grep -q '# GitX Upgrade Guideline' "$guide" \
        && grep -q 'old/1by1-skill-dev/SKILL.md' "$guide" \
        && ! grep -q 'backups/old/SKILL.md' "$guide" \
        && grep -q 'No behavior change before RED' "$guide" \
        && grep -q 'TDD Migration Plan' "$guide" \
        && grep -q 'Prompt for AI Agent' "$guide" \
        && grep -q 'skills/1by1/SKILL.md' "$guide" \
        && grep -q '不自动 tag / push' "$guide"; then
        ok_result=0
    fi
    rm -rf "$FIXTURE4"
    [ "$ok_result" -eq 0 ]
}

run_case "detect_project_name from basename" test_detect_project_name_from_basename
run_case "detect_project_name respects override" test_detect_project_name_override
run_case "detect_skill_name from skills/*/SKILL.md" test_detect_skill_name_from_skills_dir
run_case "detect_skill_name respects override" test_detect_skill_name_override
run_case "errors when no skills/ dir" test_error_without_skills_dir
run_case "excludes workspace/evals dirs" test_exclude_workspace_evals_dirs
run_case "reports actionable hint for legacy flat skill bundles" test_legacy_flat_skill_hint
run_case "generates GitX upgrade guideline for legacy flat skill bundles" test_legacy_flat_skill_generates_upgrade_guideline

# --- Summary ---
if [ "$PASS" -lt 8 ]; then
    fail "expected at least 8 assertions to run in parent shell, got $PASS"
fi

echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
