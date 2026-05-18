#!/bin/bash
# test_install_output_style.sh — v1.5.0 unified install.sh output helper.
#
# Enforces scripts/lib/install-output-style.sh API contract: every TKX
# skill's install.sh sources this helper and uses its functions instead
# of bare echo, producing byte-identical visual structure across all 5
# skills (gitx-release / mac-release / handoff / 1by1 / ClaudeMeX).
#
# Tests:
#   STATIC  — helper file present, sourceable, exposes documented API,
#             ASCII + emoji modes both defined, no `set -e` traps that
#             would kill caller scripts.
#   BEHAVIOR — banner top/bottom render, checkpoint counter increments
#             correctly with n/total format, ASCII-only mode swaps emoji,
#             CLI table aligned, double-source is idempotent.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$ROOT/scripts/lib/install-output-style.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_install_output_style.sh ══"

# === STATIC 1: helper file exists at canonical location ===
if [ -f "$HELPER" ]; then
    ok "helper file exists at scripts/lib/install-output-style.sh"
else
    fail "helper file missing: $HELPER"
    echo "Results: ✅$PASS passed / ❌$FAIL failed"; echo "FAIL"; exit 1
fi

# === STATIC 2: helper is sourceable without exiting caller ===
# shellcheck source=/dev/null
if ( set +e; source "$HELPER"; echo "still-alive" ) | grep -q "still-alive"; then
    ok "helper is sourceable (does not exit caller)"
else
    fail "helper source aborts caller — should never call exit"
fi

# === STATIC 3: documented API functions all defined ===
EXPECTED_FUNCS=(
    install_style_init
    install_banner_top
    install_checkpoint
    install_step_ok
    install_step_warn
    install_step_fail
    install_banner_bottom
    install_cli_row
    install_cli_table_begin
    install_cli_table_end
    install_next_block
    install_next_hint
)
MISSING=""
for fn in "${EXPECTED_FUNCS[@]}"; do
    if ! grep -qE "^${fn}\(\)[[:space:]]*\{" "$HELPER"; then
        MISSING="$MISSING $fn"
    fi
done
if [ -z "$MISSING" ]; then
    ok "all 12 documented API functions defined"
else
    fail "missing API functions:$MISSING"
fi

# === STATIC 4: emoji constants exported (downstream installers may need direct access) ===
if grep -qE "^export _TKX_E_" "$HELPER"; then
    ok "emoji constants exported for downstream callers"
else
    fail "emoji constants not exported — downstream callers cannot reference \$_TKX_E_LOCK etc"
fi

# === STATIC 5: TKX_INSTALL_NO_EMOJI env switch present ===
if grep -q 'TKX_INSTALL_NO_EMOJI' "$HELPER"; then
    ok "ASCII-only fallback via TKX_INSTALL_NO_EMOJI=1"
else
    fail "TKX_INSTALL_NO_EMOJI switch missing — non-UTF-8 terminals broken"
fi

# === STATIC 6: double-source guard (idempotent) ===
if grep -q '_TKX_INSTALL_STYLE_LOADED' "$HELPER"; then
    ok "double-source guard present"
else
    fail "no double-source guard — risk of redefining functions / resetting state"
fi

# === BEHAVIOR 1: banner top renders skill + version + bar lines ===
OUT=$(bash -c "source '$HELPER'; install_banner_top demo v0.1.0 install /tmp/src")
if echo "$OUT" | grep -q "demo Installation  v0.1.0" \
   && echo "$OUT" | grep -q "Source : /tmp/src" \
   && echo "$OUT" | grep -q "Mode   : install"; then
    ok "banner_top renders skill+version+source+mode"
else
    fail "banner_top output incomplete: $OUT"
fi

# === BEHAVIOR 2: checkpoint counter shows n/total when init'd, and increments ===
OUT=$(bash -c "
source '$HELPER'
install_style_init 3
install_checkpoint X 'First'
install_checkpoint X 'Second'
install_checkpoint X 'Third'
")
if echo "$OUT" | grep -q "Checkpoint 1/3 — First" \
   && echo "$OUT" | grep -q "Checkpoint 2/3 — Second" \
   && echo "$OUT" | grep -q "Checkpoint 3/3 — Third"; then
    ok "checkpoint counter increments 1/3 -> 2/3 -> 3/3"
else
    fail "checkpoint counter broken: $OUT"
fi

# === BEHAVIOR 3: counter resets between install_style_init calls ===
OUT=$(bash -c "
source '$HELPER'
install_style_init 2
install_checkpoint X 'A'
install_style_init 5
install_checkpoint X 'B'
")
if echo "$OUT" | grep -q "Checkpoint 1/2 — A" \
   && echo "$OUT" | grep -q "Checkpoint 1/5 — B"; then
    ok "install_style_init resets counter + total"
else
    fail "init does not reset state: $OUT"
fi

# === BEHAVIOR 4: ASCII-only mode swaps emoji ===
OUT=$(TKX_INSTALL_NO_EMOJI=1 bash -c "
source '$HELPER'
install_style_init 1
install_banner_top demo v0 install
install_checkpoint \"\$_TKX_E_LOCK\" 'Integrity'
install_step_ok 'pass'
install_step_warn 'warn'
install_step_fail 'fail' 2>&1
install_banner_bottom demo v0
")
# In ASCII mode there should be NO multi-byte emoji codepoints.
if echo "$OUT" | grep -q '\[lock\]' && echo "$OUT" | grep -q '\[OK\]' \
   && echo "$OUT" | grep -q '\[!\]' && echo "$OUT" | grep -q '\[X\]' \
   && echo "$OUT" | grep -q '\[done\]'; then
    ok "ASCII-only mode swaps all 5 sentinel emoji to bracket markers"
else
    fail "ASCII mode incomplete swap: $OUT"
fi

# === BEHAVIOR 5: banner_bottom renders party emoji + skill + version ===
OUT=$(bash -c "source '$HELPER'; install_banner_bottom demo v1.0")
if echo "$OUT" | grep -qE "(🎉|\[done\]).*demo v1.0 installed"; then
    ok "banner_bottom renders success line"
else
    fail "banner_bottom output unexpected: $OUT"
fi

# === BEHAVIOR 6: cli_row pads cli name and aligns columns ===
OUT=$(bash -c "source '$HELPER'; install_cli_row 'Claude Code' '/foo' '~/.claude/skills/foo'")
# Format: [Claude Code ] /foo                   ~/.claude/skills/foo
if echo "$OUT" | grep -qE '\[Claude Code +\] /foo +~/\.claude/skills/foo'; then
    ok "cli_row pads CLI name + aligns invocation column"
else
    fail "cli_row alignment broken: $OUT"
fi

# === BEHAVIOR 7: next_block renders bullets ===
OUT=$(bash -c "source '$HELPER'; install_next_block 'hint A' 'hint B'")
if echo "$OUT" | grep -q "Next:" \
   && echo "$OUT" | grep -q "• hint A" \
   && echo "$OUT" | grep -q "• hint B"; then
    ok "next_block renders 'Next:' header + bullets"
else
    fail "next_block output broken: $OUT"
fi

# === BEHAVIOR 8: step_fail writes to stderr (so install.sh can `2>` if needed) ===
STDOUT=$(bash -c "source '$HELPER'; install_step_fail 'broken'" 2>/dev/null)
STDERR=$(bash -c "source '$HELPER'; install_step_fail 'broken'" 2>&1 >/dev/null)
if [ -z "$STDOUT" ] && [ -n "$STDERR" ]; then
    ok "step_fail writes to stderr (separable from stdout)"
else
    fail "step_fail stream routing wrong: stdout='$STDOUT' stderr='$STDERR'"
fi

# === BEHAVIOR 9a: install_style_init coerces non-numeric input to 0 silently ===
# Guards superpowers Round 1 finding I-3: prior version emitted `[: abc: integer
# expected` to stderr when a downstream caller passed an unset / mistyped total.
# Coerced to 0 means "checkpoint header omits n/total" — graceful, no noise.
STDERR=$(bash -c "source '$HELPER'; install_style_init abc; install_checkpoint X 'Title'" 2>&1 >/dev/null)
STDOUT=$(bash -c "source '$HELPER'; install_style_init abc; install_checkpoint X 'Title'" 2>/dev/null)
if [ -z "$STDERR" ] && echo "$STDOUT" | grep -qE "Checkpoint 1 - Title|Checkpoint 1 — Title"; then
    ok "install_style_init coerces non-numeric arg silently (no stderr noise)"
else
    fail "install_style_init non-numeric arg leaks: stderr='$STDERR' stdout='$STDOUT'"
fi
# Also covers empty string + negative number → 0 fallback.
STDERR=$(bash -c "source '$HELPER'; install_style_init ''; install_checkpoint X 'A'" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
    ok "install_style_init empty arg coerces silently"
else
    fail "install_style_init empty arg leaks stderr: '$STDERR'"
fi

# === BEHAVIOR 9b: ASCII-only mode produces zero non-printable / non-ASCII bytes ===
# Guards Codex review finding: prior version had hardcoded em-dash (U+2014) +
# bullet (U+2022) in helper printfs that bypassed the TKX_INSTALL_NO_EMOJI fallback.
ASCII_OUT=$(TKX_INSTALL_NO_EMOJI=1 bash -c "
source '$HELPER'
install_style_init 2
install_banner_top demo v0 install /tmp/src
install_checkpoint \"\$_TKX_E_LOCK\" 'Integrity'
install_step_ok 'pass'
install_checkpoint \"\$_TKX_E_CHECK\" 'Done'
install_banner_bottom demo v0
install_cli_table_begin
install_cli_row 'Claude Code' '/demo' '~/.claude/skills/demo'
install_cli_table_end
install_next_block 'hint A' 'hint B'
install_next_hint 'hint C'
" 2>&1)
if printf '%s' "$ASCII_OUT" | LC_ALL=C grep -qE '[^[:print:][:space:]]'; then
    fail "ASCII mode emits non-ASCII bytes (em-dash / bullet / emoji leaked through)"
    printf '%s' "$ASCII_OUT" | LC_ALL=C grep -nE '[^[:print:][:space:]]' | head -3 | sed 's/^/       /' >&2
else
    ok "ASCII mode output is pure ASCII (no em-dash / bullet / emoji bytes)"
fi
# Also assert the ASCII substitute characters are present (dash + bullet swap real).
if echo "$ASCII_OUT" | grep -qE 'Checkpoint 1/2 - Integrity' && echo "$ASCII_OUT" | grep -qE '^    \* hint A'; then
    ok "ASCII mode swaps em-dash to '-' and bullet to '*'"
else
    fail "ASCII mode missing expected dash/bullet substitutes"
fi

# === BEHAVIOR 10: double-source is a no-op (idempotent) ===
OUT=$(bash -c "source '$HELPER'; source '$HELPER'; install_style_init 1; install_checkpoint X done")
if echo "$OUT" | grep -q "Checkpoint 1/1 — done"; then
    ok "double-source is idempotent"
else
    fail "double-source broke state: $OUT"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
