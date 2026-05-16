#!/bin/bash
# gitx-readme.sh — deterministic README ghostwriter (projen / terraform-docs
# pattern, v1.10.0). Rewrites OWN-LINE-marker regions
#   <!-- gitx:managed:NAME -->\n ...body... \n<!-- /gitx:managed:NAME -->
# of README.md / README_CN.md from NON-CIRCULAR truths. Generate-only:
# NEVER runs git/gh/any LLM (SKILL.md #1, TKX §10.10). Markers MUST be on
# their own line; malformed regions fail closed (exit 5, nothing written).
#
# Manages: suite-count, version, install, whats-new.
# DOES NOT manage the Deep-Audit N/0/1 count — circular via §0g; owned by
# release-audit.sh §0f (consistency) + §0i (generic exactness) + per-repo
# test_readme_numeric_accuracy.sh (Decision 0018/0019).
#
# Usage: gitx-readme [--check] [--init] [--force] [--dry-run] [--help]
# Exit: 0 ok | 1 --check drift | 2 usage | 4 --init exists w/o --force
#       5 malformed managed region (fail-closed, no write)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(pwd)"
TPL_DIR="$SCRIPT_DIR/../references/readme"
MODE="refresh"; FORCE=0; DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) cat <<'H'
gitx-readme — deterministic README managed-region generator
Usage: gitx-readme [--check] [--init] [--force] [--dry-run] [--help]
  (default) refresh managed regions in ./README.md and ./README_CN.md
  --check   regenerate to temp; exit 1 if any managed region drifted
  --init    scaffold ./README.md from references/readme/README.template.md
  --force   with --init, overwrite existing README.md
  --dry-run print intended actions; write nothing
Exit: 0 ok | 1 drift | 2 usage | 4 init-exists | 5 malformed region
H
      exit 0 ;;
    --check) MODE="check" ;;
    --init) MODE="init" ;;
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "❌ unknown flag: $1" >&2; echo "   Try: gitx-readme --help" >&2; exit 2 ;;
  esac; shift
done
# --- ground-truth resolvers (non-circular only) ---
gr_suite_count(){ ls -1 "$PROJECT_ROOT"/tests/test_*.sh 2>/dev/null | grep -vc 'test_suite_structure\.sh' || true; }
gr_version(){ [ -f "$PROJECT_ROOT/VERSION" ] && cat "$PROJECT_ROOT/VERSION" || echo unknown; }
gr_plugin_name(){
  local pj="$PROJECT_ROOT/.claude-plugin/plugin.json" n=""
  if [ -f "$pj" ]; then
    n=$(grep -m1 '"name"' "$pj" | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)
  fi
  [ -n "$n" ] || n=$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$n"
}
gr_install(){
  if [ -d "$PROJECT_ROOT/.claude-plugin" ]; then
    printf '```bash\n/plugin marketplace add tkxlab-ai/marketplace\n/plugin install %s@tkx-skills\n```\n' "$(gr_plugin_name)"
  else printf '```bash\nbash install.sh\n```\n'; fi
}
gr_whats_new(){
  local cl result
  for cl in "$PROJECT_ROOT/Release/CHANGELOG.md" "$PROJECT_ROOT/CHANGELOG.md"; do
    [ -f "$cl" ] || continue
    result=$(grep -m1 -E '^## ' "$cl" 2>/dev/null | sed 's/^##[[:space:]]*//' || true)
    [ -n "$result" ] && { printf '%s\n' "$result"; return 0; }
  done
}
# --- fail-closed region validator (C2). Own-line markers only. ---
# For every managed NAME that appears at all: exactly one line that is the
# opener (only the opener marker, nothing else), exactly one closer line,
# opener strictly before closer, no second opener before closer. Any
# violation (incl. inline same-line marker) → exit 5, caller writes nothing.
gr_validate_regions(){
  local file="$1" name nop ncl lo lc
  [ -f "$file" ] || return 0
  # FIX B (Gotcha #52 closure): scan for ANY gitx:managed NAME that appears as
  # a valid OWN-LINE marker; reject unknown names immediately (fail-closed
  # contract). A typo or future marker silently ignored → --check exits clean
  # → silent drift, so an unrecognised NAME is always an error. Using the same
  # own-line ERE as the structural checks ensures we skip documentation prose
  # (e.g. the template's comment block) that mentions NAME inline or indented.
  # errexit-safe: grep guarded || true.
  local _known="suite-count version install whats-new"
  local _found_names
  _found_names=$( grep -oE '^<!-- /?gitx:managed:[A-Za-z0-9_-]+ -->[[:space:]]*$' "$file" 2>/dev/null \
      | sed -E 's@.*gitx:managed:([A-Za-z0-9_-]+) -->.*@\1@' | sort -u || true )
  while IFS= read -r _fname; do
    [ -n "$_fname" ] || continue
    case " $_known " in
      *" $_fname "*) ;;  # known — ok
      *) echo "❌ unknown managed region '$_fname' in $file (allowed: $_known)" >&2; return 5 ;;
    esac
  done <<EOF_VR
$_found_names
EOF_VR
  for name in suite-count version install whats-new; do
    grep -qF "<!-- gitx:managed:${name} -->" "$file" 2>/dev/null || continue
    # NEW-I-a: own-line marker, trailing whitespace/CR TOLERATED (benign
    # editor artifact must not hard-fail a meta-skill release); leading or
    # inline content still REJECTED (genuine inline = exit 5, no prose
    # loss). The marker has no ERE metacharacters so it is safe literal in
    # the regex. \r tolerated via the optional [:space:] class.
    nop=$(grep -cE "^<!-- gitx:managed:${name} -->[[:space:]]*\$" "$file" 2>/dev/null || true)
    ncl=$(grep -cE "^<!-- /gitx:managed:${name} -->[[:space:]]*\$" "$file" 2>/dev/null || true)
    if [ "${nop:-0}" != "1" ] || [ "${ncl:-0}" != "1" ]; then
      echo "❌ malformed managed region '$name' in $file: need exactly one own-line opener+closer (got opener=$nop closer=$ncl — inline/duplicate/missing, or content before the marker)" >&2; return 5
    fi
    lo=$(grep -nE "^<!-- gitx:managed:${name} -->[[:space:]]*\$" "$file" | head -1 | cut -d: -f1)
    lc=$(grep -nE "^<!-- /gitx:managed:${name} -->[[:space:]]*\$" "$file" | head -1 | cut -d: -f1)
    if [ -z "$lo" ] || [ -z "$lc" ] || [ "$lo" -ge "$lc" ]; then
      echo "❌ managed region '$name' opener not strictly before closer in $file" >&2; return 5
    fi
  done
  return 0
}
# Sourced as a library for tests: stop before main.
[ "${GITX_README_LIB:-0}" = "1" ] && return 0 2>/dev/null || true
# --- region rewriter: own-line markers; multi-line value via temp file ---
gr_rewrite_file(){
  local file="$1" name value vf op cl
  [ -f "$file" ] || return 0
  gr_validate_regions "$file" || return 5      # fail-closed: nothing written
  for name in suite-count version install whats-new; do
    op="<!-- gitx:managed:${name} -->"; cl="<!-- /gitx:managed:${name} -->"
    grep -qE "^<!-- gitx:managed:${name} -->[[:space:]]*\$" "$file" 2>/dev/null || continue
    case "$name" in
      suite-count) value="$(gr_suite_count)" ;;
      version)     value="$(gr_version)" ;;
      install)     value="$(gr_install)" ;;
      whats-new)   value="$(gr_whats_new)" ;;
    esac
    vf="$(mktemp)"
    printf '%s\n' "$value" > "$vf"
    # Per-line trim ONLY for marker matching (NEW-I-a: trailing ws/CR
    # tolerated); prose & marker lines are reprinted from the ORIGINAL $0
    # → verbatim + idempotent. Multi-line value via getline from $vf
    # (never `awk -v`, which cannot carry newlines / the install block).
    # awk inside `if` (not `&&`) so a nonzero awk under set -e does not
    # abort the function and leak $file.gitxtmp / $vf.
    if awk -v o="$op" -v c="$cl" -v vf="$vf" '
        { ln=$0; sub(/[ \t\r]+$/,"",ln) }
        ln==o { print; while((getline L < vf)>0) print L; close(vf); skip=1; next }
        ln==c { skip=0; print; next }
        skip!=1 { print }
      ' "$file" > "$file.gitxtmp"; then
        mv "$file.gitxtmp" "$file"
        rm -f "$vf"
    else
        rm -f "$file.gitxtmp" "$vf"
        echo "❌ gitx-readme: awk rewrite failed for region '$name' in $file" >&2
        return 6
    fi
  done
  return 0
}
case "$MODE" in
  init)
    t="$PROJECT_ROOT/README.md"
    if [ -f "$t" ] && [ "$FORCE" -eq 0 ]; then echo "❌ $t exists — use --force" >&2; exit 4; fi
    [ "$DRY_RUN" -eq 1 ] && { echo "would scaffold $t"; exit 0; }
    p="$(basename "$PROJECT_ROOT")"
    # Literal {{PROJECT}} → $p substitution that is safe for ANY project
    # dir name (&, |, \, / etc): awk split on the literal token then
    # reassemble with string concat — never a regex/sed replacement, so
    # no `&`/delimiter injection. Idempotent + portable (BSD awk).
    _gr_render_tpl(){ # $1=template $2=dest
      awk -v p="$p" '{
        out=""; n=split($0, a, /\{\{PROJECT\}\}/)
        for (i=1;i<=n;i++){ out=out a[i]; if (i<n) out=out p }
        print out
      }' "$1" > "$2"
    }
    # Drop scaffold BEFORE gr_rewrite_file so suite-count already includes it.
    if [ ! -f "$PROJECT_ROOT/tests/test_readme_numeric_accuracy.sh" ] && [ -f "$TPL_DIR/test_readme_numeric_accuracy.sh.template" ]; then
        mkdir -p "$PROJECT_ROOT/tests"
        cp "$TPL_DIR/test_readme_numeric_accuracy.sh.template" "$PROJECT_ROOT/tests/test_readme_numeric_accuracy.sh"
        chmod +x "$PROJECT_ROOT/tests/test_readme_numeric_accuracy.sh"
    fi
    _gr_render_tpl "$TPL_DIR/README.template.md" "$t"
    if [ -f "$TPL_DIR/README_CN.template.md" ]; then
      _gr_render_tpl "$TPL_DIR/README_CN.template.md" "$PROJECT_ROOT/README_CN.md"
    fi
    gr_rewrite_file "$t" || exit 5
    [ -f "$PROJECT_ROOT/README_CN.md" ] && { gr_rewrite_file "$PROJECT_ROOT/README_CN.md" || exit 5; }
    exit 0 ;;
  check)
    trap 'rm -f "$PROJECT_ROOT/README.md.gitxchk" "$PROJECT_ROOT/README_CN.md.gitxchk" 2>/dev/null || true' EXIT
    rc=0
    for f in README.md README_CN.md; do
      [ -f "$PROJECT_ROOT/$f" ] || continue
      cp "$PROJECT_ROOT/$f" "$PROJECT_ROOT/$f.gitxchk"
      if ! gr_rewrite_file "$PROJECT_ROOT/$f.gitxchk"; then
        echo "❌ malformed managed region in $f" >&2; rm -f "$PROJECT_ROOT/$f.gitxchk"; exit 5
      fi
      diff -q "$PROJECT_ROOT/$f" "$PROJECT_ROOT/$f.gitxchk" >/dev/null 2>&1 || { echo "❌ managed-region drift in $f (run: gitx-readme)" >&2; rc=1; }
      rm -f "$PROJECT_ROOT/$f.gitxchk"
    done
    exit $rc ;;
  refresh)
    [ "$DRY_RUN" -eq 1 ] && { echo "would refresh README.md / README_CN.md"; exit 0; }
    gr_rewrite_file "$PROJECT_ROOT/README.md" || exit 5
    gr_rewrite_file "$PROJECT_ROOT/README_CN.md" || exit 5
    exit 0 ;;
esac
