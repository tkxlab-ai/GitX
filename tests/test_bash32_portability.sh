#!/usr/bin/env bash
# tests/test_bash32_portability.sh — guard: every shipped shell script must parse
# under the project's stated minimum, bash 3.2 (macOS /bin/bash).
#
# Why: bash 3.2 mis-parses a `case` nested inside $(…) command substitution — the
# case pattern's `)` is read as the closing `)` of $(…). release.sh and
# release-audit.sh both regressed on this (their dual-source drift filter used an
# inline `case` inside `drift=$(diff … | { while…case…done; })`), parsing fine on
# bash 4+/shellcheck but failing `bash -n` on 3.2. The fix moved the `case` into a
# helper function (parsed separately). This guard re-runs `bash -n` under the
# oldest bash available so the whole class cannot silently return.
#
# Generic-safe: SKIP when no bash <4 is available (e.g. Linux CI with bash 5 only).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0; SKIP=0

# Find an old bash (prefer /bin/bash — on macOS that is 3.2.57).
OLD_BASH=""
for cand in /bin/bash /usr/bin/bash bash; do
    p=$(command -v "$cand" 2>/dev/null) || continue
    major=$("$p" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || true)
    if [ -n "$major" ] && [ "$major" -lt 4 ]; then OLD_BASH="$p"; break; fi
done

if [ -z "$OLD_BASH" ]; then
    echo "  ➖ no bash <4 available — bash 3.2 portability check skipped (generic-safe)"
    echo "SUMMARY: 0 passed, 0 failed, 1 skipped"
    exit 0
fi
echo "Legacy bash for parse check: $OLD_BASH ($("$OLD_BASH" --version | head -1))"

for f in "$ROOT"/scripts/*.sh "$ROOT"/scripts/lib/*.sh "$ROOT"/install.sh; do
    [ -f "$f" ] || continue
    if "$OLD_BASH" -n "$f" 2>/dev/null; then
        PASS=$((PASS+1))
    else
        echo "  ❌ $(basename "$f") fails to parse under $OLD_BASH:"
        "$OLD_BASH" -n "$f" 2>&1 | head -2 | sed 's/^/      /'
        FAIL=$((FAIL+1))
    fi
done

# Why: bash 3.2 lexes the body of `< <( … )` without comment awareness, so a
# quote/apostrophe inside a comment line there opens an unterminated string
# ("bad substitution: no closing ')' in <(") — and, unlike `bash -n` on the
# cases above, the damage only shows at run time for that section. Scoped to
# process substitutions only: `$(` bodies (e.g. awk programs in
# docs-pipeline.sh) legitimately carry comments and would false-positive.
for f in "$ROOT"/scripts/*.sh "$ROOT"/scripts/lib/*.sh "$ROOT"/install.sh; do
    [ -f "$f" ] || continue
    hits=$(awk '
        /< <\($/                          { inps = 1; next }
        inps && /^[[:space:]]*\)[[:space:]]*$/ { inps = 0; next }
        inps && /^[[:space:]]*#.*['"'"'"]/ { printf "%s:%d: %s\n", FILENAME, FNR, $0 }
    ' "$f")
    if [ -n "$hits" ]; then
        echo "  ❌ $(basename "$f"): quote in a comment inside < <( … ) (bash 3.2 lexer hazard):"
        head -3 <<<"$hits" | sed 's/^/      /'
        FAIL=$((FAIL+1))
    else
        PASS=$((PASS+1))
    fi
done

# Why: on bash 3.2 a `${1:?}` failure reaches the EXIT trap with $? already 0,
# so a bare audit run used to exit 0 (gate silently open). The explicit
# argument check must exit 2 with a Usage message.
_b2_err=$(mktemp)
"$OLD_BASH" "$ROOT/scripts/release-audit.sh" >/dev/null 2>"$_b2_err"; _b2_rc=$?
if [ "$_b2_rc" = 2 ] && grep -q 'Usage' "$_b2_err"; then
    echo "  ✅ release-audit.sh with no version exits 2 + Usage under $OLD_BASH"
    PASS=$((PASS+1))
else
    echo "  ❌ release-audit.sh with no version: rc=$_b2_rc (want 2), Usage present: $(grep -c 'Usage' "$_b2_err" || true)"
    FAIL=$((FAIL+1))
fi
rm -f "$_b2_err"

[ "$FAIL" -eq 0 ] && echo "  ✅ all $PASS shipped script(s) parse under bash 3.2"
echo "SUMMARY: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
