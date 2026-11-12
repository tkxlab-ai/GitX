#!/bin/bash
# test_harness_hygiene.sh — static guard over tests/test_*.sh + tests/run_all.sh.
# Why: two anti-patterns were swept out of the suites and must not creep back:
#   1. fixed scratch paths under the system temp root — concurrent runs collide;
#      every scratch file must live under the suite's own TMPDIR.
#   2. an echo/printf of a captured variable piped into a matcher or a
#      line-limiter — under `set -o pipefail` an early match closes the pipe,
#      the writer dies of SIGPIPE, and a matched assertion flips to failure.
# This file scans itself (no self-exemption), so its own source must never
# hold the forbidden text (Gotcha #41): needles use character classes and the
# planted fixtures are assembled at runtime from string fragments.
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

TMP_RE='/tm[p]/'
# Optional `VAR=value ` group catches `| LC_ALL=C <matcher>`.
# Known gaps (accepted, not widened): an echo of a command substitution is not
# caught (the `(` stops the match), nor is a matcher reached through the
# `command` builtin or by absolute path (e.g. /usr/bin/<matcher>).
# Accepted false positives: a pipe character inside a quoted string after the
# echo/printf, and a pipeline inside a trailing comment on a code line.
PIPE_RE='(ech[o]|print[f])[^|;()&]*\|[[:space:]]*([A-Za-z_]+=[^[:space:]]*[[:space:]]+)*(gre[p]|hea[d])'

# join_lines FILE… — print `file:line:text` per logical line, joining
# backslash-continued lines and keeping the FIRST physical line's number, so a
# pipeline split across lines is seen whole. A comment line never continues
# (bash does not continue comments), so code after a comment ending in `\` is
# still scanned on its own line. END flushes a trailing continuation that runs
# into EOF instead of silently dropping it.
join_lines() {
    local f
    for f in "$@"; do
        awk -v f="$f" 'BEGIN{start=0;buf=""} { line=$0; if (start==0) start=NR; if (line ~ /\\$/ && line !~ /^[[:space:]]*#/) { sub(/\\$/, "", line); buf = buf line; next } buf = buf line; print f ":" start ":" buf; buf=""; start=0 } END { if (start!=0) print f ":" start ":" buf }' "$f"
    done
}

# Every filter is anchored past the `file:line:` prefix: a scanned file whose
# PATH holds the temp-root segment (CI leaves TMPDIR unset) must not turn
# every one of its lines into a hit.
PFX='^[^:]*:[0-9]+:'
scan_tmp() { join_lines "$@" | grep -vE "${PFX}[[:space:]]*#" | grep -E "${PFX}.*$TMP_RE" || true; }
scan_pipe() { join_lines "$@" | grep -vE "${PFX}[[:space:]]*#" | grep -E "${PFX}.*$PIPE_RE" || true; }

# count_lines TEXT — number of lines in captured output (0 when empty).
count_lines() {
    if [ -z "$1" ]; then echo 0; else echo $(( $(wc -l <<<"$1") )); fi
}

# hit_lines TEXT PREFIX — space-separated line numbers of the hits in TEXT.
hit_lines() {
    local l s=""
    while IFS= read -r l; do
        [ -n "$l" ] || continue
        l=${l#"$2"}
        s="$s${l%%:*} "
    done <<<"$1"
    echo "${s% }"
}

echo "══ test_harness_hygiene.sh ══"

T=$(mktemp -d "${TMPDIR:-/tmp}/harness_hygiene.XXXXXX")
trap 'rm -rf "$T"' EXIT
# Fixtures live under a dir whose path holds the temp-root segment, so every
# machine (not only CI) proves the scan is blind to the file's own path.
FX="$T/tm""p"
mkdir "$FX"

# --- Planted violations, built from fragments (never literal in this file) ---
sl='/'
pipe='|'
bad_tmp="cat > ${sl}tmp${sl}x"
bad_tmp_comment="# ${sl}tmp${sl} ok"
bad_pipe_comment="# ech""o \"\$v\" $pipe gre""p -q y"
bad_pipe1="ech""o \"\$v\" $pipe gre""p -q y"
bad_pipe2="print""f '%s' \"\$v\" $pipe hea""d -1"
bad_pipe3="print""f '%s' \"\$v\" $pipe LC_ALL=C gre""p -q y"
bad_pipe4a="ech""o \"\$v\" \\"
bad_pipe4b="  $pipe gre""p -q y"
bad_cc_comment="# a comment ending in a backslash \\"
printf '%s\n' '#!/bin/bash' "$bad_tmp" "$bad_tmp_comment" "$bad_pipe_comment" \
    "$bad_pipe1" "$bad_pipe2" "$bad_pipe3" "$bad_pipe4a" "$bad_pipe4b" \
    "$bad_cc_comment" "$bad_pipe1" > "$FX/bad.sh"
cont_line=8   # physical line of bad_pipe4a in bad.sh (1-based, shebang = 1)
cc_line=11    # pipeline right after the comment ending in a backslash

# --- Test (a): planted fixture — exact hit counts + line numbers ---
tmp_out=$(scan_tmp "$FX/bad.sh")
pipe_out=$(scan_pipe "$FX/bad.sh")
tmp_n=$(count_lines "$tmp_out")
pipe_n=$(count_lines "$pipe_out")
if [ "$tmp_n" -eq 1 ]; then
    ok "planted fixture: temp-root literal scan finds exactly 1 (comment ignored)"
else
    fail "planted fixture: temp-root literal scan found $tmp_n, expected 1"
    printf '%s\n' "$tmp_out" >&2
fi
if [ "$pipe_n" -eq 5 ]; then
    ok "planted fixture: pipeline scan finds exactly 5 (incl. VAR=val + continuation; comment ignored)"
else
    fail "planted fixture: pipeline scan found $pipe_n, expected 5"
    printf '%s\n' "$pipe_out" >&2
fi
last_hit=$(sed -n '4p' <<<"$pipe_out")
last_hit=${last_hit#"$FX/bad.sh:"}
last_line=${last_hit%%:*}
if [ "$last_line" = "$cont_line" ]; then
    ok "continuation hit reports its FIRST physical line ($cont_line)"
else
    fail "continuation hit reports line '$last_line', expected $cont_line"
fi
cc_hit=$(sed -n '5p' <<<"$pipe_out")
cc_hit=${cc_hit#"$FX/bad.sh:"}
if [ "${cc_hit%%:*}" = "$cc_line" ]; then
    ok "comment ending in a backslash does not swallow the next line (hit at $cc_line)"
else
    fail "pipeline after a backslash-ended comment: got '${cc_hit%%:*}', expected $cc_line"
fi
tmp_lines=$(hit_lines "$tmp_out" "$FX/bad.sh:")
pipe_lines=$(hit_lines "$pipe_out" "$FX/bad.sh:")
if [ "$tmp_lines" = "2" ] && [ "$pipe_lines" = "5 6 7 8 11" ]; then
    ok "fixture under a temp-root-segment path: hits are exactly its real lines"
else
    fail "path-sensitive scan: temp-root hits '$tmp_lines' (want 2), pipeline hits '$pipe_lines' (want 5 6 7 8 11)"
fi

# --- Test (b): clean fixture (here-strings, TMPDIR-rooted scratch) ---
cat > "$FX/clean.sh" <<'EOF'
#!/bin/bash
d=$(mktemp -d "${TMPDIR:-/tmp}/clean.XXXXXX")
v=$(cat "$d/in" 2>/dev/null || true)
if grep -q y <<<"$v"; then :; fi
first=$(head -1 <<<"$v")
LC_ALL=C grep -nE 'x' <<<"$v" | head -3 | sed 's/^/  /'
echo "done"; grep -q x "$d/in" || true
sort "$d/in" | head -1
EOF
clean_tmp_n=$(count_lines "$(scan_tmp "$FX/clean.sh")")
clean_pipe_n=$(count_lines "$(scan_pipe "$FX/clean.sh")")
if [ "$clean_tmp_n" -eq 0 ]; then
    ok "clean fixture: temp-root literal scan finds 0"
else
    fail "clean fixture: temp-root literal scan found $clean_tmp_n, expected 0"
fi
if [ "$clean_pipe_n" -eq 0 ]; then
    ok "clean fixture: pipeline scan finds 0"
else
    fail "clean fixture: pipeline scan found $clean_pipe_n, expected 0"
fi

# --- Test (c): repo scan — every suite + run_all.sh, this file included ---
repo_tmp=$(scan_tmp "$SCRIPT_DIR"/test_*.sh "$SCRIPT_DIR/run_all.sh")
repo_pipe=$(scan_pipe "$SCRIPT_DIR"/test_*.sh "$SCRIPT_DIR/run_all.sh")
if [ -z "$repo_tmp" ] && [ -z "$repo_pipe" ]; then
    ok "tests/ is clean: no temp-root literals, no echo/printf-to-matcher pipelines"
else
    fail "tests/ hygiene violations (temp-root: $(count_lines "$repo_tmp"), pipeline: $(count_lines "$repo_pipe"))"
    [ -n "$repo_tmp" ] && printf '%s\n' "$repo_tmp" >&2
    [ -n "$repo_pipe" ] && printf '%s\n' "$repo_pipe" >&2
fi

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ]
