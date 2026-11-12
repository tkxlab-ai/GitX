#!/bin/bash
# test_audit_no_silent_abort.sh — Deep Audit must never die silently under
# `set -euo pipefail` (and the .skill-vs-bundle diff filter must stay precise).
#
# Why: three `var=$(cmd | head -1)` / bare-redirect sites aborted the whole
# audit mid-run with no ❌ line when their input was malformed (flattened
# CHANGELOG without a `## ` line, a garbage source tarball, a failing
# quick_validate.py). A gate that exits early without a verdict is worse
# than a loud FAIL. B4: `grep -v evals` also dropped files like retrievals.md.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_SH="$ROOT/scripts/release-audit.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_audit_no_silent_abort.sh ══"

make_fixture() {
    local fix; fix=$(mktemp -d)
    mkdir -p "$fix/skills/demo-skill/scripts" \
             "$fix/Release/demo-v0.0.1" "$fix/scripts" "$fix/tests"
    cat > "$fix/SKILL.md" <<'EOF'
---
name: demo-skill
description: BDD fixture project for silent-abort audit testing — minimal valid layout only.
---
# Demo
EOF
    cp "$fix/SKILL.md" "$fix/skills/demo-skill/SKILL.md"
    echo "v0.0.1" > "$fix/VERSION"
    echo "v0.0.1" > "$fix/skills/demo-skill/VERSION"
    local RD="$fix/Release/demo-v0.0.1"
    echo "v0.0.1" > "$RD/VERSION"
    cp "$fix/SKILL.md" "$RD/SKILL.md"
    echo "# Demo" > "$RD/README.md"
    printf '# Demo — Release History\n\n## v0.0.1 — 2026-05-04\n\n- Initial.\n' > "$RD/CHANGELOG.md"
    echo "MIT" > "$RD/LICENSE"
    printf '# Install\nRun install.sh\n' > "$RD/INSTALL.md"
    printf '# Contributing\n## Dev setup\n## Submitting Patches / PRs\n' > "$RD/CONTRIBUTING.md"
    : > "$RD/TOKEN_USAGE.md"
    echo "$fix"
}

run_audit() {
    # $1 = fixture, $2 = optional PATH prefix
    PATH="${2:+$2:}$PATH" PROJECT_ROOT="$1" PROJECT_NAME=demo SKILL_NAME=demo-skill \
        bash "$AUDIT_SH" v0.0.1 2>&1 || true
}

# ── B3a: CHANGELOG with no `## ` line must not abort at §4 ────────────────
FIX=$(make_fixture)
printf '# Demo\n\nflattened, no version heading\n' > "$FIX/Release/demo-v0.0.1/CHANGELOG.md"
out=$(run_audit "$FIX")
if grep -q '§4' <<<"$out" && grep -q '§5' <<<"$out"; then
    ok "[B3a] CHANGELOG without '## ' line: audit continues past §4 into §5"
else
    fail "[B3a] audit aborted silently at §4 (no §5 in output)"
fi
rm -rf "$FIX"

# ── B3b: garbage source tarball must not abort at §5 ──────────────────────
FIX=$(make_fixture)
printf 'garbage' > "$FIX/Release/demo-v0.0.1/demo-v0.0.1-source.tar.gz"
out=$(run_audit "$FIX")
if grep -q '§5' <<<"$out" && grep -q '§6' <<<"$out"; then
    ok "[B3b] garbage source tarball: audit continues past §5 into §6"
else
    fail "[B3b] audit aborted silently at §5 (no §6 in output)"
fi
rm -rf "$FIX"

# ── B3c: failing quick_validate.py must not abort at §0a ──────────────────
FIX=$(make_fixture)
mkdir -p "$FIX/scripts/vendored/skill-creator/scripts" "$FIX/stub"
echo "# stub" > "$FIX/scripts/vendored/skill-creator/scripts/quick_validate.py"
cat > "$FIX/stub/python3" <<EOF
#!/bin/bash
# -c "import yaml" probe succeeds so the cross-check path is entered;
# the real validator invocation fails.
[ "\$1" = "-c" ] && exit 0
touch "$FIX/.qv-ran"
exit 1
EOF
chmod +x "$FIX/stub/python3"
out=$(run_audit "$FIX" "$FIX/stub")
if [ -f "$FIX/.qv-ran" ] && grep -q '§0b' <<<"$out"; then
    ok "[B3c] failing quick_validate.py: audit continues past §0a into §0b"
else
    fail "[B3c] quick_validate failure aborted audit (ran=$([ -f "$FIX/.qv-ran" ] && echo yes || echo no))"
fi
rm -rf "$FIX"

# ── B4: _filter_evals_diff drops only the evals dir, not *evals* names ────
eval "$(awk '/^_filter_evals_diff\(\)/,/^\}/' "$AUDIT_SH")"
if ! declare -F _filter_evals_diff >/dev/null; then
    fail "[B4] _filter_evals_diff not defined at top level of release-audit.sh"
else
    got=$(printf '%s\n' \
        'Only in /a: retrievals.md' \
        'Only in /a: evals' \
        'Only in /a/evals: data' | _filter_evals_diff)
    if [ "$got" = 'Only in /a: retrievals.md' ]; then
        ok "[B4] retrievals.md survives; evals dir + evals/ contents dropped"
    else
        fail "[B4] filter wrong, got: $got"
    fi
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
