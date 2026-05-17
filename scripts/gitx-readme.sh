#!/bin/bash
# gitx-readme.sh — deterministic README ghostwriter (projen / terraform-docs
# pattern, v1.10.0). Rewrites OWN-LINE-marker regions
#   <!-- gitx:managed:NAME -->\n ...body... \n<!-- /gitx:managed:NAME -->
# of README.md / README_CN.md from NON-CIRCULAR truths. Generate-only:
# NEVER runs git/gh/any LLM (SKILL.md #1, TKX §10.10). Markers MUST be on
# their own line; malformed regions fail closed (exit 5, nothing written).
#
# Manages: suite-count, version, install, whats-new, command-surface.
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
gr_skill_name(){
  local sm="$PROJECT_ROOT/SKILL.md" n="" d bn skip pat old_ifs matches
  # Resolve the install.sh flat command name with the SAME precedence the
  # release pipeline uses (detect-project.sh _detect_skill_name): explicit
  # SKILL_NAME env > the single standard-layout skills/<name>/ dir > root
  # SKILL.md frontmatter > sanitized basename. v1.10.1 closure (codex
  # adversarial [high]): a root-only resolver gave a STANDARD-LAYOUT
  # dependent skill (skills/<name>/SKILL.md, no root SKILL.md) the wrong
  # primary command while gitx-readme --check deterministically passed
  # (§0g blind). We MIRROR _detect_skill_name's precedence but do NOT
  # `source` detect-project.sh: its no-skills path WRITES
  # GitX_Upgrade_Guideline.md + returns 1 — both generate-unsafe for this
  # generate-only ghostwriter. 0-or->1 skills here falls through silently
  # (no error, no file write); same exclude set as the pipeline.
  if [ -n "${SKILL_NAME:-}" ]; then
    n="$SKILL_NAME"
  elif [ -d "$PROJECT_ROOT/skills" ]; then
    matches=()
    for d in "$PROJECT_ROOT"/skills/*/; do
      [ -f "${d}SKILL.md" ] || continue
      bn="$(basename "$d")"; skip=0
      old_ifs="$IFS"; IFS='|'
      for pat in ${SKILL_EXCLUDE_PATTERNS:-*-workspace|*-evals}; do
        # shellcheck disable=SC2254
        case "$bn" in $pat) skip=1 ;; esac
      done
      IFS="$old_ifs"
      [ "$skip" = 1 ] && continue
      matches+=("$bn")
    done
    [ "${#matches[@]}" = 1 ] && n="${matches[0]}"
  fi
  if [ -z "$n" ] && [ -f "$sm" ]; then
    # ONLY the YAML frontmatter (between the first two '---' lines).
    n=$(awk '
      NR==1 && $0=="---"{fm=1; next}
      fm && $0=="---"{exit}
      fm && /^name:[[:space:]]/{ sub(/^name:[[:space:]]*/,""); sub(/[[:space:]]+$/,""); print; exit }
    ' "$sm" 2>/dev/null | tr -d '\r' || true)
    # strip one layer of matching surrounding quotes
    case "$n" in \"*\") n="${n#\"}"; n="${n%\"}";; \'*\') n="${n#\'}"; n="${n%\'}";; esac
  fi
  # validate against the skill-name charset; else fall back to sanitized basename
  case "$n" in ''|[!a-z0-9]*|*[!a-z0-9._-]*) n="" ;; esac
  if [ -z "$n" ]; then
    n=$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]' \
        | LC_ALL=C tr -c 'a-z0-9._-' '-' | tr -d '\n' | sed 's/^[._-]*//; s/[._-]*$//')
    # round-3 codex-MEDIUM: RE-validate the fallback (it can still be empty —
    # basename '!!!' → '' — or otherwise invalid). Never emit an invalid /
    # empty command name; use a deterministic safe default.
    case "$n" in ''|[!a-z0-9]*|*[!a-z0-9._-]*) n="skill" ;; esac
  fi
  printf '%s\n' "$n"
}
gr_install(){
  if [ -d "$PROJECT_ROOT/.claude-plugin" ]; then
    printf '```bash\n/plugin marketplace add tkxlab-ai/marketplace\n/plugin install %s@tkx-skills\n```\n' "$(gr_plugin_name)"
  else printf '```bash\nbash install.sh\n```\n'; fi
}
gr_whats_new(){
  local cl entry out
  for cl in "$PROJECT_ROOT/Release/CHANGELOG.md" "$PROJECT_ROOT/CHANGELOG.md"; do
    [ -f "$cl" ] || continue
    entry=$(awk '/^## /{n++} n==1{print} n==2{exit}' "$cl" 2>/dev/null || true)
    [ -n "$entry" ] || continue
    # Buffer the whole region, then emit with ONE write. A consumer that
    # closes early (`gr_whats_new | head -1 | grep -q`) would otherwise
    # SIGPIPE a *later* internal write and — under the file's sourced
    # `set -euo pipefail` — kill this pipe-stage subshell (141) before
    # `return 0`; `|| true` on inner writes cannot catch a stage-killing
    # signal. Single final emit moves the only pipe-exposed write to one
    # place; truncation there is cleanly swallowed by `|| true`.
    out=$(
      printf '%s\n' "$entry" | head -1 | sed 's/^##[[:space:]]*/**/; s/[[:space:]]*$/**/' 2>/dev/null || true
      printf '\n'
      printf '%s\n' "$entry" | awk '
        # I-1: strip a trailing CR off EVERY record FIRST (no next → falls
        # through to the pattern rules with a CR-clean $0), consistent with
        # gr_skill_name (tr -d \r) + the header path (head -1 | sed). A CRLF
        # CHANGELOG would otherwise leak literal \r into ghostwritten bullets.
        # MUST be the first rule so all subsequent /^### /, /^- /, the
        # continuation match, and the END flush see no CR. POSIX/BSD-awk-safe.
        { sub(/\r$/, "") }
        # n = bullets ALREADY emitted. A new "- " means the prior buffered
        # bullet is complete (no continuation can still attach) → flush it
        # first, THEN cap: once 6 are emitted, exit (drops the 7th+ entirely;
        # the off-by-one was capping before flushing the 6th, destroying it).
        /^### /                  { next }
        /^- /                    { if (cur!="") { print cur; cur=""; n++
                                                  if (n>=6) exit }
                                   cur=$0; next }
        /^[[:space:]]+[^[:space:]]/ { if (cur=="") next
                                   line=$0; sub(/^[[:space:]]+/,"",line)
                                   cur=cur " " line; next }
        { next }
        # Last bullet has no following "- " to flush it; emit iff under cap.
        END { if (cur!="" && n<6) print cur }
      ' 2>/dev/null || true
    )
    printf '%s\n' "$out" || true
    return 0
  done
}
gr_command_surface(){
  local skill plug f pj="$PROJECT_ROOT/.claude-plugin/plugin.json" out cmd_dir plug_cmd_dirs
  skill="$(gr_skill_name)"
  [ -f "$pj" ] && plug="$(gr_plugin_name)" || plug=""
  # Command-shim source dir, standard-layout aware. v1.10.1 closure round-2
  # (codex adversarial [medium]): this enumerated ONLY root commands/, but
  # the release pipeline's flatten contract (release.sh: `cp -R
  # "$SKILL_SRC_DIR/commands" "$RELEASE_DIR/commands"`) takes a downstream
  # skill's shims from skills/<skill>/commands/. A standard-layout dependent
  # skill with no mirrored root commands/ would publish a command surface
  # omitting its actually-installed shims while gitx-readme --check stayed
  # green (deterministic-blind). Prefer root commands/ (GitX + flat/legacy +
  # mirrored-root projects); else the standard-layout skills/<skill>/commands/
  # (skill resolved by gr_skill_name above). Generate-safe: dir checks only.
  if [ -d "$PROJECT_ROOT/commands" ]; then cmd_dir="$PROJECT_ROOT/commands"
  elif [ -d "$PROJECT_ROOT/skills/$skill/commands" ]; then cmd_dir="$PROJECT_ROOT/skills/$skill/commands"
  else cmd_dir=""; fi
  # Plugin command dir(s) — DECLARED in .claude-plugin/plugin.json `commands[]`,
  # not hard-coded. v1.10.1 closure round-4 (codex adversarial [medium]):
  # section B enumerated only the literal $PROJECT_ROOT/gitx-plugin-commands/
  # (GitX's own path), so a dependent plugin declaring a different commands
  # path in its manifest got a README that omitted/misstated its /<plug>:*
  # commands while gitx-readme --check stayed green (deterministic-blind,
  # section-B analog of the round-1/2 root-only gaps). The manifest is
  # authoritative. Pure-shell parse (no jq; same idiom class as
  # gr_plugin_name): take the `commands` array body, pull each "..." entry,
  # strip leading ./ and trailing /. Absent/empty commands[] → no dirs → no
  # fabricated colon bullets (footer still states the colon cmds are
  # plugin-only). Newline-separated; consumed by an IFS=read while-loop.
  plug_cmd_dirs=""
  if [ -f "$pj" ]; then
    plug_cmd_dirs="$(awk '/"commands"[[:space:]]*:/{f=1} f{print} f&&/\]/{exit}' "$pj" 2>/dev/null \
      | sed -E '1s/.*\[//' | grep -oE '"[^"]+"' \
      | sed -E 's/^"//; s/"$//; s#^\.?/+##; s#/+$##' | grep -v '^[[:space:]]*$' || true)"
  fi
  # Buffer + single emit (same SIGPIPE rationale as gr_whats_new): a
  # `gr_command_surface | grep -qF X` consumer closes on first match and a
  # later printf would SIGPIPE-kill this pipe stage under the sourced
  # `set -euo pipefail`. One final write is the only pipe-exposed point.
  out=$(
    printf 'Two install paths.\n\n'
    printf -- '**A. install.sh** — run `bash install.sh` (skill + flat commands; no plugin needed)\n\n'
    printf -- '- `/%s` — the skill itself\n' "$skill"
    if [ -n "$cmd_dir" ]; then
      for f in "$cmd_dir"/*.md; do [ -f "$f" ] || continue
        printf -- '- `/%s`\n' "$(basename "$f" .md)"; done
    fi
    if [ -f "$pj" ]; then
      printf -- '\n**B. Plugin marketplace** — `/plugin marketplace add tkxlab-ai/marketplace` then `/plugin install %s@tkx-skills` (`/%s` colon namespace)\n\n' "$plug" "$plug"
      # M-1: the marketplace line above already ends with a blank line
      # (…namespace)\n\n). The footer is a new paragraph: prefix it with a
      # blank line ONLY when a bullet list was emitted between (the list
      # consumes that trailing blank, exactly as section A's bullet list is
      # terminated by the next block's leading \n). With NO list, the
      # marketplace blank already separates → a leading \n would double it.
      local _bn=0 _cd
      while IFS= read -r _cd; do
        [ -n "$_cd" ] || continue
        [ -d "$PROJECT_ROOT/$_cd" ] || continue
        for f in "$PROJECT_ROOT/$_cd"/*.md; do [ -f "$f" ] || continue
          printf -- '- `/%s:%s`\n' "$plug" "$(basename "$f" .md)"; _bn=1; done
      done <<<"$plug_cmd_dirs"
      [ "$_bn" = 1 ] && printf '\n'
      printf -- '> The `/%s` colon-prefixed commands are plugin-only (a plugin-namespacing design, per official docs). install.sh gives flat `/%s` + `/<cmd>`; the colon form requires this plugin install and is NEVER synthesized from flat commands.\n' "$plug" "$skill"
    else
      printf -- '\n**B. Plugin install** — N/A: no `.claude-plugin/plugin.json`; this skill installs only via path A (install.sh, flat commands).\n'
    fi
  )
  printf '%s\n' "$out" || true
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
  local _known="suite-count version install whats-new command-surface"
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
  for name in suite-count version install whats-new command-surface; do
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
  for name in suite-count version install whats-new command-surface; do
    op="<!-- gitx:managed:${name} -->"; cl="<!-- /gitx:managed:${name} -->"
    grep -qE "^<!-- gitx:managed:${name} -->[[:space:]]*\$" "$file" 2>/dev/null || continue
    case "$name" in
      suite-count) value="$(gr_suite_count)" ;;
      version)     value="$(gr_version)" ;;
      install)     value="$(gr_install)" ;;
      whats-new)   value="$(gr_whats_new)" ;;
      command-surface) value="$(gr_command_surface)" ;;
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
