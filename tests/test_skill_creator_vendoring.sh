#!/bin/bash
# test_skill_creator_vendoring.sh — v1.3.0.
#
# Validates self-contained vendoring of Anthropic skill-creator inside
# scripts/vendored/skill-creator/ + system-vs-vendored version detection
# logic in scripts/lib/skill-creator-version.sh. Reproducibility goal:
# gitx-release should not rely on Claude Code plugin marketplace being
# present (e.g. fresh machine, container, CI).
#
# Decision matrix (build_skill_package uses SKC_VERDICT):
#   same             → silent use system
#   system_newer     → silent use system
#   vendored_newer   → prompt (TTY) or default vendored (non-TTY/CI/DRY_RUN)
#   system_absent    → silent use vendored
#   both_absent      → zip fallback (caller handles)
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"
HELPER_SH="$ROOT/scripts/lib/skill-creator-version.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_skill_creator_vendoring.sh ══"

# === Static 1-5: vendoring artifacts present ===
for f in "scripts/vendored/skill-creator/VERSION" \
         "scripts/vendored/skill-creator/LICENSE.txt" \
         "scripts/vendored/skill-creator/scripts/quick_validate.py" \
         "scripts/vendored/skill-creator/scripts/package_skill.py" \
         "scripts/vendored/skill-creator/scripts/utils.py"; do
    if [ -f "$ROOT/$f" ]; then
        ok "vendored artifact present: $f"
    else
        fail "missing vendored artifact: $f"
    fi
done

# === Static 6: VERSION contains upstream commit + date pinning ===
if grep -qE '^upstream_commit=[a-f0-9]{40}$' "$ROOT/scripts/vendored/skill-creator/VERSION" && \
   grep -qE '^upstream_date=20[0-9]{2}-[0-9]{2}-[0-9]{2}$' "$ROOT/scripts/vendored/skill-creator/VERSION"; then
    ok "VERSION pinning has 40-char upstream_commit + ISO date"
else
    fail "VERSION pinning missing upstream_commit (40 hex) or upstream_date (YYYY-MM-DD)"
fi

# === Static 7: helper lib defines skill_creator_status ===
if grep -qE '^skill_creator_status\(\)' "$HELPER_SH"; then
    ok "lib helper defines skill_creator_status()"
else
    fail "lib helper missing skill_creator_status() entry"
fi

# === Static 8: helper exports SKC_VERDICT with all 6 verdict values ===
if grep -qE 'SKC_VERDICT="(same|system_newer|vendored_newer|system_absent|vendored_absent|both_absent)"' "$HELPER_SH"; then
    ok "helper enumerates verdict values"
else
    fail "helper missing one or more SKC_VERDICT enum values"
fi

# === Static 9: release.sh sources the helper ===
if grep -qE 'source .*lib/skill-creator-version\.sh' "$RELEASE_SH"; then
    ok "release.sh sources skill-creator-version.sh helper"
else
    fail "release.sh does not source the helper"
fi

# === Static 10: build_skill_package uses SKC_VERDICT case statement ===
if awk '/^build_skill_package\(\)/,/^}$/' "$RELEASE_SH" | grep -qE 'case "\$SKC_VERDICT"'; then
    ok "build_skill_package decision via case \$SKC_VERDICT"
else
    fail "build_skill_package missing case \$SKC_VERDICT decision matrix"
fi

# === Static 11: TTY check guards interactive prompt ===
if awk '/^build_skill_package\(\)/,/^}$/' "$RELEASE_SH" | grep -qE '\[ -t 0 \].*-z .*CI.*DRY_RUN'; then
    ok "interactive prompt guarded by [-t 0] + CI + DRY_RUN check"
else
    fail "interactive prompt missing TTY/CI/DRY_RUN guard (would hang non-tty)"
fi

# === Behavioral: helper verdict computation on fixtures ===
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

# Setup: 4 fixture scenarios, each with its own SKC_ROOT (vendored path) +
# fake HOME (system path probe target)
setup_vendored() {
    local skc_root="$1"
    local date="$2"
    mkdir -p "$skc_root/vendored/skill-creator/scripts"
    touch "$skc_root/vendored/skill-creator/scripts/package_skill.py"
    cat > "$skc_root/vendored/skill-creator/VERSION" <<EOF
upstream_commit=abc1234567890abcdef1234567890abcdef12345
upstream_date=$date
EOF
}

setup_system_at_date() {
    local home="$1"
    local plugin_dir="$home/.claude/plugins/cache/claude-plugins-official/skill-creator/hash123/skills/skill-creator/scripts"
    mkdir -p "$plugin_dir"
    touch "$plugin_dir/package_skill.py"
    # Use touch -t to set mtime; macOS BSD touch -t YYYYMMDDhhmm
    local mtime_arg
    mtime_arg=$(echo "$2" | tr -d '-')"1200"  # YYYYMMDD1200
    touch -t "$mtime_arg" "$plugin_dir/.."
}

run_status() {
    local skc_root="$1"
    local home="$2"
    HOME="$home" bash -c "
        set -u
        SKC_VENDORED_PATH=''; SKC_VENDORED_DATE=''; SKC_VENDORED_COMMIT=''
        SKC_SYSTEM_PATH=''; SKC_SYSTEM_DATE=''; SKC_PYYAML_OK=''; SKC_VERDICT=''
        source '$HELPER_SH'
        skill_creator_status '$skc_root'
        echo \"VERDICT=\$SKC_VERDICT VENDORED=\$SKC_VENDORED_DATE SYSTEM=\$SKC_SYSTEM_DATE\"
    "
}

# Case A: same date → verdict=same
mkdir -p "$FIXTURE/A_skc" "$FIXTURE/A_home"
setup_vendored "$FIXTURE/A_skc" "2026-05-08"
setup_system_at_date "$FIXTURE/A_home" "2026-05-08"
RES=$(run_status "$FIXTURE/A_skc" "$FIXTURE/A_home")
if echo "$RES" | grep -qE "VERDICT=same"; then
    ok "case A (same date): verdict=same ($RES)"
else
    fail "case A: expected verdict=same, got '$RES'"
fi

# Case B: system newer
mkdir -p "$FIXTURE/B_skc" "$FIXTURE/B_home"
setup_vendored "$FIXTURE/B_skc" "2026-05-08"
setup_system_at_date "$FIXTURE/B_home" "2026-05-10"
RES=$(run_status "$FIXTURE/B_skc" "$FIXTURE/B_home")
if echo "$RES" | grep -qE "VERDICT=system_newer"; then
    ok "case B (system newer): verdict=system_newer ($RES)"
else
    fail "case B: expected verdict=system_newer, got '$RES'"
fi

# Case C: vendored newer
mkdir -p "$FIXTURE/C_skc" "$FIXTURE/C_home"
setup_vendored "$FIXTURE/C_skc" "2026-05-10"
setup_system_at_date "$FIXTURE/C_home" "2026-05-08"
RES=$(run_status "$FIXTURE/C_skc" "$FIXTURE/C_home")
if echo "$RES" | grep -qE "VERDICT=vendored_newer"; then
    ok "case C (vendored newer): verdict=vendored_newer ($RES)"
else
    fail "case C: expected verdict=vendored_newer, got '$RES'"
fi

# Case D: system absent
mkdir -p "$FIXTURE/D_skc" "$FIXTURE/D_home"
setup_vendored "$FIXTURE/D_skc" "2026-05-08"
# Don't setup system
RES=$(run_status "$FIXTURE/D_skc" "$FIXTURE/D_home")
if echo "$RES" | grep -qE "VERDICT=system_absent"; then
    ok "case D (system absent): verdict=system_absent ($RES)"
else
    fail "case D: expected verdict=system_absent, got '$RES'"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
