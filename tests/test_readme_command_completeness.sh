#!/bin/bash
# test_readme_command_completeness.sh — v1.7.3 doc-completeness guard.
#
# Root cause of "README never mentions /gitx-sop": new subcommand shims
# were added under commands/ but the README 命令矩阵 was not updated, and
# no test caught the omission. Invariant: every shipped commands/<name>.md
# slash shim MUST be referenced in README.md (the canonical command table).
#
# exit: 0=all pass, 1=any fail
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_readme_command_completeness.sh ══"

README="$ROOT/README.md"
CMD_DIR="$ROOT/commands"

if [ ! -f "$README" ]; then fail "README.md missing"; fi
if [ ! -d "$CMD_DIR" ]; then fail "root commands/ missing (dual-source, v1.7.1+)"; fi

if [ -f "$README" ] && [ -d "$CMD_DIR" ]; then
    miss=""
    for f in "$CMD_DIR"/*.md; do
        [ -f "$f" ] || continue
        cmd="$(basename "$f" .md)"          # e.g. gitx-sop
        # README must reference the slash form /<cmd> somewhere
        grep -qF "/$cmd" "$README" || miss="$miss /$cmd"
    done
    if [ -z "$miss" ]; then
        ok "every commands/*.md shim is documented in README.md"
    else
        fail "README.md never mentions:$miss (add to 命令矩阵)"
    fi

    # The canonical 命令矩阵 table specifically must carry the new shims
    if grep -q '命令矩阵' "$README"; then
        for cmd in gitx-init gitx-sop; do
            grep -qE "\`/$cmd\`" "$README" \
                && ok "命令矩阵 documents /$cmd" \
                || fail "命令矩阵 missing /$cmd row"
        done
    fi
fi

echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -gt 0 ] && { echo "FAIL"; exit 1; } || { echo "PASS"; exit 0; }
