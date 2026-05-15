#!/bin/bash
# test_audit_install_dependencies.sh — v1.1.2 BDD test for §11k.
#
# SCENARIO (catch the claudemex case BEFORE the user runs the install):
#   Given a Release/<ver>/install.sh that references $SELF_DIR/<file>
#   And   <file> is NOT present in Release/<ver>/
#   When  release-audit.sh runs
#   Then  it FAILs at the install-dependencies check
#   And   the failure message names the unresolved path.
#
#   Given a Release/<ver>/install.sh that references $SELF_DIR/<file>
#   And   <file> IS present in Release/<ver>/
#   When  release-audit.sh runs
#   Then  the install-dependencies check passes.
#
# This static check is conservative: it parses install.sh for QUOTED
# `"$SELF_DIR/<path>"` and `"${SELF_DIR}/<path>"` references (the two
# idiomatic bash forms). Variable substitution (`"$SELF_DIR/$f"`),
# heredocs, comment lines, and unquoted forms are out of scope —
# best-effort static analysis, not a full bash interpreter.
#
# Comment lines starting with `#` are stripped before grep so a
# documented example like `# cp "$SELF_DIR/example.md"` does NOT
# produce a false-positive missing-dep failure.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_SH="$ROOT/scripts/release-audit.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_audit_install_dependencies.sh ══"

# ── Static: §11k exists in audit ───────────────────────────────────────
if grep -qE '§11k|install\.sh.*依赖|install\.sh.*deps|install\.sh.*dependencies' "$AUDIT_SH"; then
    ok "release-audit.sh has §11k install.sh dependency gate"
else
    fail "release-audit.sh missing §11k install.sh dependency gate"
fi

# ── Static: gate parses cp \$SELF_DIR/ patterns from install.sh ────────
if grep -qE 'SELF_DIR|cp.*install\.sh|grep.*install\.sh' "$AUDIT_SH"; then
    ok "audit code references SELF_DIR / install.sh parsing logic"
else
    fail "audit code does not parse install.sh for dependencies"
fi

# ── Behavioral fixtures ────────────────────────────────────────────────
make_fixture() {
    # Build a minimal valid release dir + project layout suitable for
    # standalone audit invocation. Returns FIXTURE path on stdout.
    local fix; fix=$(mktemp -d)
    mkdir -p "$fix/skills/demo-skill/scripts" \
             "$fix/Release/demo-v0.0.1" "$fix/scripts" "$fix/tests"

    # Skill bundle frontmatter
    cat > "$fix/SKILL.md" <<'EOF'
---
name: demo-skill
description: BDD fixture project for install dep audit gate testing — covers both pass and fail cases.
---
# Demo
EOF
    cp "$fix/SKILL.md" "$fix/skills/demo-skill/SKILL.md"
    echo "v0.0.1" > "$fix/VERSION"
    echo "v0.0.1" > "$fix/skills/demo-skill/VERSION"

    # Release dir is what audit examines — minimum needed to NOT fail on
    # other gates (we only care about the install-dep gate's verdict).
    local RD="$fix/Release/demo-v0.0.1"
    echo "v0.0.1" > "$RD/VERSION"
    cp "$fix/SKILL.md" "$RD/SKILL.md"
    echo "# Demo" > "$RD/README.md"
    cat > "$RD/CHANGELOG.md" <<'EOF'
# Demo — Release History

## v0.0.1 — 2026-05-04

- Initial fixture release.
EOF
    echo "MIT" > "$RD/LICENSE"
    cat > "$RD/INSTALL.md" <<'EOF'
# Install
Run install.sh
EOF
    cat > "$RD/CONTRIBUTING.md" <<'EOF'
# Contributing
## Dev setup
## Submitting Patches / PRs
EOF
    : > "$RD/TOKEN_USAGE.md"

    echo "$fix"
}

# ── CASE A: install.sh references missing file → audit FAILs §11k ─────
FIXA=$(make_fixture)
RD="$FIXA/Release/demo-v0.0.1"
cat > "$RD/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SELF_DIR/MISSING-CUSTOM-FILE.md" "$HOME/foo"
EOF
chmod +x "$RD/install.sh"

audit_out=$(PROJECT_ROOT="$FIXA" PROJECT_NAME=demo SKILL_NAME=demo-skill \
            bash "$AUDIT_SH" v0.0.1 2>&1 || true)

if echo "$audit_out" | grep -qE "MISSING-CUSTOM-FILE\.md|install\.sh.*depends.*missing|install\.sh.*缺失"; then
    ok "[case A] audit FAILs and names the missing dependency 'MISSING-CUSTOM-FILE.md'"
else
    fail "[case A] audit silent on missing install.sh dependency (claudemex bug regression)"
    echo "$audit_out" | tail -20 | sed 's/^/       /'
fi
rm -rf "$FIXA"

# ── CASE B: install.sh references existing file → §11k passes ─────────
FIXB=$(make_fixture)
RD="$FIXB/Release/demo-v0.0.1"
echo "actually present" > "$RD/PRESENT-FILE.md"
cat > "$RD/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SELF_DIR/PRESENT-FILE.md" "$HOME/foo"
EOF
chmod +x "$RD/install.sh"

audit_out=$(PROJECT_ROOT="$FIXB" PROJECT_NAME=demo SKILL_NAME=demo-skill \
            bash "$AUDIT_SH" v0.0.1 2>&1 || true)

if echo "$audit_out" | grep -qE "PRESENT-FILE.*missing|PRESENT-FILE.*缺失"; then
    fail "[case B] audit incorrectly flagged a present file as missing"
elif echo "$audit_out" | grep -qE 'install\.sh.*依赖.*✅|install\.sh.*deps.*✅|✅.*install\.sh.*依赖|✅.*install\.sh.*dependenc'; then
    ok "[case B] audit passes when install.sh dependencies all resolve"
else
    # As long as it doesn't FALSELY fail on PRESENT-FILE we accept this case.
    # (Other audit gates may still FAIL on the minimal fixture — only §11k matters here.)
    if ! echo "$audit_out" | grep -qE "PRESENT-FILE"; then
        ok "[case B] audit does not flag PRESENT-FILE as missing (gate accepts resolved deps)"
    else
        fail "[case B] audit references PRESENT-FILE in unexpected way"
        echo "$audit_out" | grep PRESENT-FILE | sed 's/^/       /'
    fi
fi
rm -rf "$FIXB"

# ── CASE C: install.sh has no $SELF_DIR/ refs at all → gate is no-op ──
FIXC=$(make_fixture)
RD="$FIXC/Release/demo-v0.0.1"
cat > "$RD/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "no SELF_DIR references — pure copy-from-PATH installer"
mkdir -p "$HOME/.demo"
EOF
chmod +x "$RD/install.sh"
audit_out=$(PROJECT_ROOT="$FIXC" PROJECT_NAME=demo SKILL_NAME=demo-skill \
            bash "$AUDIT_SH" v0.0.1 2>&1 || true)
# Should not flag any false-positive missing dep
if echo "$audit_out" | grep -qE 'install\.sh.*missing.*dep|install\.sh.*缺失.*依赖'; then
    fail "[case C] empty install.sh wrongly flagged for missing deps"
else
    ok "[case C] install.sh with no SELF_DIR refs → §11k is a no-op (no false positives)"
fi
rm -rf "$FIXC"

# ── CASE D: install.sh has a $SELF_DIR/... reference inside a comment ──
# Reviewer #1: the gate must NOT extract paths from `# cp "$SELF_DIR/foo.md"`
# style documentation lines. Strip whole-line and trailing comments first.
FIXD=$(make_fixture)
RD="$FIXD/Release/demo-v0.0.1"
cat > "$RD/install.sh" <<'EOF'
#!/bin/bash
# Example usage (this is a comment, NOT a real reference):
#   cp "$SELF_DIR/example-doc.md" "$HOME/.demo/"
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.demo"
echo "no real $SELF_DIR/ refs at runtime"
EOF
chmod +x "$RD/install.sh"
audit_out=$(PROJECT_ROOT="$FIXD" PROJECT_NAME=demo SKILL_NAME=demo-skill \
            bash "$AUDIT_SH" v0.0.1 2>&1 || true)
if echo "$audit_out" | grep -q "example-doc\.md"; then
    fail "[case D] commented-out \$SELF_DIR/example-doc.md wrongly flagged as missing dep"
    echo "$audit_out" | grep example-doc | sed 's/^/       /'
else
    ok "[case D] commented \$SELF_DIR/ reference correctly ignored (no false positive)"
fi
rm -rf "$FIXD"

# ── CASE E: install.sh uses brace form "${SELF_DIR}/<path>" ────────────
# Reviewer #2: the gate must catch both `"$SELF_DIR/..."` and
# `"${SELF_DIR}/..."` (idiomatic bash). Both forms appear in real installers.
FIXE=$(make_fixture)
RD="$FIXE/Release/demo-v0.0.1"
cat > "$RD/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "${SELF_DIR}/MISSING-BRACE-FILE.md" "$HOME/foo"
EOF
chmod +x "$RD/install.sh"
audit_out=$(PROJECT_ROOT="$FIXE" PROJECT_NAME=demo SKILL_NAME=demo-skill \
            bash "$AUDIT_SH" v0.0.1 2>&1 || true)
if echo "$audit_out" | grep -q "MISSING-BRACE-FILE\.md"; then
    ok "[case E] brace-form \"\${SELF_DIR}/...\" reference correctly caught as missing"
else
    fail "[case E] brace-form reference SLIPPED past the gate (claudemex bug class still live)"
    echo "$audit_out" | tail -10 | sed 's/^/       /'
fi
rm -rf "$FIXE"

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
