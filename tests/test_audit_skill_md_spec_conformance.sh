#!/bin/bash
# test_audit_skill_md_spec_conformance.sh — v1.2.1 B fix.
#
# Adds audit §0: SKILL.md spec conformance check, equivalent to Anthropic's
# official skill-creator quick_validate.py (102 lines, agentskills.io spec
# source of truth). Enforces the 6 rules officially:
#
#   1. SKILL.md exists
#   2. YAML frontmatter delimited by `---`
#   3. Top-level keys in ALLOWED_PROPERTIES = {name, description, license,
#      allowed-tools, metadata, compatibility} — anything else FAILs
#   4. name: kebab-case `^[a-z0-9-]+$`, no leading/trailing/double hyphen, ≤64 chars
#   5. description: no `<` or `>`, ≤1024 chars
#   6. compatibility (optional): string, ≤500 chars
#
# Rationale: We previously enforced these implicitly (Gotcha #16 docs, human
# discipline). v1.2.1 makes audit explicitly enforce them so any new skill
# project's SKILL.md frontmatter passes the official spec gate before our own
# 11-chapter superset audit runs.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_SH="$ROOT/scripts/release-audit.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_audit_skill_md_spec_conformance.sh ══"

# === Static 1: audit_section_0_spec function defined ===
if grep -qE '^audit_section_0_spec\(\)' "$AUDIT_SH"; then
    ok "release-audit.sh defines audit_section_0_spec()"
else
    fail "release-audit.sh missing audit_section_0_spec()"
fi

# === Static 2: ALLOWED_PROPERTIES whitelist enforced ===
if grep -qE 'name description license allowed-tools metadata compatibility' "$AUDIT_SH"; then
    ok "audit references agentskills.io ALLOWED_PROPERTIES whitelist"
else
    fail "audit missing ALLOWED_PROPERTIES = {name description license allowed-tools metadata compatibility}"
fi

# === Static 3: kebab-case regex for name ===
if grep -qE '\^\[a-z0-9-\]\+\$' "$AUDIT_SH"; then
    ok "audit enforces kebab-case name regex"
else
    fail "audit missing kebab-case name regex"
fi

# === Static 4: angle bracket check for description ===
if grep -qE 'angle brackets?|<\|>' "$AUDIT_SH"; then
    ok "audit checks description for angle brackets"
else
    fail "audit missing description angle bracket check"
fi

# === Static 5: 1024-char description limit ===
if grep -qE '1024' "$AUDIT_SH"; then
    ok "audit enforces description ≤1024 chars"
else
    fail "audit missing description 1024 char limit"
fi

# === Static 6: 64-char name limit ===
if grep -qE '\b64\b' "$AUDIT_SH"; then
    ok "audit enforces name ≤64 chars"
else
    fail "audit missing name 64 char limit"
fi

# === Static 7: §0 wired into audit runner ===
if grep -qE '_track_start[[:space:]]+"§0_spec"' "$AUDIT_SH" && \
   grep -qE '_track_end[[:space:]]+"§0_spec"' "$AUDIT_SH"; then
    ok "§0_spec section wired into _track_start/_track_end runner"
else
    fail "§0_spec not registered in audit runner pipeline"
fi

# === Behavioral: extract function + run on fixtures ===
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
FN_FILE="$FIXTURE/fn.sh"
sed -n '/^audit_section_0_spec()/,/^}$/p' "$AUDIT_SH" > "$FN_FILE"

run_spec() {
    local fixture_path="$1"
    PROJECT_ROOT="$fixture_path" SKILL_NAME="demo-skill" PASS=0 FAIL=0 bash -c "
        set -u
        PASS=0; FAIL=0
        source '$FN_FILE'
        audit_section_0_spec >/dev/null 2>&1 || true
        echo \"PASS=\$PASS FAIL=\$FAIL\"
    "
}

# Case A: valid SKILL.md → §0 all PASS (no FAIL)
mkdir -p "$FIXTURE/A/skills/demo-skill"
cat > "$FIXTURE/A/skills/demo-skill/SKILL.md" <<'EOF'
---
name: demo-skill
description: A valid demo skill. Use when the user runs /demo-skill or asks for demo.
license: MIT
---

Body content.
EOF
RES=$(run_spec "$FIXTURE/A")
if echo "$RES" | grep -qE "FAIL=0"; then
    ok "case A (valid): §0 produces 0 FAILs"
else
    fail "case A: expected FAIL=0, got '$RES'"
fi

# Case B: unexpected top-level `version:` → §0 catches
mkdir -p "$FIXTURE/B/skills/demo-skill"
cat > "$FIXTURE/B/skills/demo-skill/SKILL.md" <<'EOF'
---
version: bogus
name: demo-skill
description: A skill with forbidden top-level version field.
---
EOF
RES=$(run_spec "$FIXTURE/B")
if echo "$RES" | grep -qE "FAIL=[1-9]"; then
    ok "case B (unexpected key): §0 catches 'version:' top-level violation"
else
    fail "case B: expected FAIL≥1, got '$RES'"
fi

# Case C: name with UpperCase → §0 catches
mkdir -p "$FIXTURE/C/skills/demo-skill"
cat > "$FIXTURE/C/skills/demo-skill/SKILL.md" <<'EOF'
---
name: Demo-Skill
description: Name has uppercase letters, should fail.
---
EOF
RES=$(run_spec "$FIXTURE/C")
if echo "$RES" | grep -qE "FAIL=[1-9]"; then
    ok "case C (UpperCase name): §0 catches non-kebab-case name"
else
    fail "case C: expected FAIL≥1, got '$RES'"
fi

# Case D: description with `<` → §0 catches
mkdir -p "$FIXTURE/D/skills/demo-skill"
cat > "$FIXTURE/D/skills/demo-skill/SKILL.md" <<'EOF'
---
name: demo-skill
description: Description with forbidden angle bracket like /demo skill --version XYZ here.
---
EOF
# Inject a literal `<` via printf to avoid heredoc YAML pitfalls
printf '%s\n' '---' 'name: demo-skill' 'description: Has a less-than sign right here X < Y forbidden.' '---' > "$FIXTURE/D/skills/demo-skill/SKILL.md"
RES=$(run_spec "$FIXTURE/D")
if echo "$RES" | grep -qE "FAIL=[1-9]"; then
    ok "case D (angle bracket in description): §0 catches it"
else
    fail "case D: expected FAIL≥1 for angle bracket in description, got '$RES'"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
