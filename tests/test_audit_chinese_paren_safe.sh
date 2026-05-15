#!/bin/bash
# test_audit_chinese_paren_safe.sh — v1.1.7 hardening (Gotcha #32 in HANDOFF).
#
# In some bash versions / locales, a Chinese full-width punctuation char
# immediately after a `$var` expansion is mis-parsed as part of the variable
# identifier. With `set -u` that becomes "unbound variable" and aborts the
# script. Discovered when mac-release v0.1.0 self-bake hit
# `$first_ver_line）: unbound variable` at release-audit.sh:265.
#
# This test plants the offending pattern in a tiny fixture and asserts that
# the canonical fix — `${var}<chinese>` form — does NOT abort, while
# preserving the same printable output. It also asserts a static-source
# guard: no `$<word>` followed by Chinese punctuation should remain in any
# of the canonical release scripts.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_chinese_paren_safe.sh ══"

# ── Behavior 1: ${var} delimited form survives Chinese full-width punctuation ──
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

cat > "$TMP" <<'EOF'
#!/bin/bash
set -euo pipefail
my_value="hello"
echo "wrapped: ${my_value}）OK"
EOF
out=$(bash "$TMP" 2>&1)
rc=$?
if [ "$rc" = 0 ] && echo "$out" | grep -q 'wrapped: hello）OK'; then
    ok "\${var}）form prints wrapped correctly under set -u"
else
    fail "\${var}）form failed (rc=$rc, out=$out)"
fi

# ── Behavior 2: bare \$var）form is the documented hazard ──
# We do NOT assert it always crashes (varies by bash version + locale), but
# we capture observed behavior so a future bash upgrade making it harmless
# is recorded as a notification rather than a silent regression.
cat > "$TMP" <<'EOF'
#!/bin/bash
set -euo pipefail
my_value="hello"
echo "wrapped: $my_value）OK"
EOF
bare_out=$(bash "$TMP" 2>&1) || true
bare_rc=$?
if [ "$bare_rc" = 0 ] && echo "$bare_out" | grep -q 'wrapped: hello）OK'; then
    # Bash on this machine handles it fine; harmless on this bash, but the
    # ${var} form is still the portable + safe form for cross-bash scripts.
    ok "bare \$var）printed correctly on this bash (informational; \${var} still required for portability)"
else
    # Documented hazard reproduced — exactly what Gotcha #32 describes.
    ok "bare \$var）form abort/mis-parsed as Gotcha #32 documents (rc=$bare_rc) — \${var} fix is necessary"
fi

# ── Static guard: no surviving bare $var<chinese-punct> in canonical scripts ──
# This is the regression guard. Scan release-* and gitx-release.sh + dual mirror.
hits=""
for f in \
    "$ROOT/scripts/release-audit.sh" \
    "$ROOT/scripts/release.sh" \
    "$ROOT/scripts/gitx-release.sh" \
    "$ROOT/scripts/scan-credentials.sh" \
    "$ROOT/scripts/release-sanitize.sh" \
    "$ROOT/skills/gitx-release/scripts/release-audit.sh" \
    "$ROOT/skills/gitx-release/scripts/release.sh" \
    "$ROOT/skills/gitx-release/scripts/gitx-release.sh" \
    "$ROOT/skills/gitx-release/scripts/scan-credentials.sh" \
    "$ROOT/skills/gitx-release/scripts/release-sanitize.sh"
do
    [ -f "$f" ] || continue
    if grep -nE '\$[a-zA-Z_][a-zA-Z0-9_]+[）（，。：；！？「」『』、]' "$f" >/dev/null 2>&1; then
        hits="$hits$f\n"
    fi
done

if [ -z "$hits" ]; then
    ok "no bare \$var followed by Chinese full-width punctuation in canonical scripts"
else
    fail "bare \$var followed by Chinese punctuation found in:"
    printf '%b' "$hits" | sed 's/^/      /'
fi

# ── Static guard: scripts/lib/ also clean ──
lib_hits=""
for f in "$ROOT/scripts/lib"/*.sh "$ROOT/skills/gitx-release/scripts/lib"/*.sh; do
    [ -f "$f" ] || continue
    if grep -nE '\$[a-zA-Z_][a-zA-Z0-9_]+[）（，。：；！？「」『』、]' "$f" >/dev/null 2>&1; then
        lib_hits="$lib_hits$f\n"
    fi
done

if [ -z "$lib_hits" ]; then
    ok "no bare \$var followed by Chinese punctuation in scripts/lib/"
else
    fail "bare \$var followed by Chinese punctuation found in scripts/lib/:"
    printf '%b' "$lib_hits" | sed 's/^/      /'
fi

echo ""; echo "─── $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
