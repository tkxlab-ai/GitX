#!/bin/bash
# docs-pipeline.sh — deterministic bilingual doc generator (absorbs gitx-readme.sh per Boss-signed P3/Q-A 2026-05-17). No LLM in loop. Contract: references/docs-contract/manifest.txt
# Rewrites OWN-LINE-marker regions
#   <!-- gitx:managed:NAME -->\n ...body... \n<!-- /gitx:managed:NAME -->
# of README.md / README_CN.md from NON-CIRCULAR truths. Generate-only:
# NEVER runs git/gh/any LLM (SKILL.md #1, TKX §10.10). Markers MUST be on
# their own line; malformed regions fail closed (exit 5, nothing written).
#
# Manages: badges, build-metrics, whats-new, command-surface, suite-count.
# DOES NOT manage the Deep-Audit N/0/1 count — circular via §0g; owned by
# release-audit.sh §0f (consistency) + §0i (generic exactness) + per-repo
# test_readme_numeric_accuracy.sh (Decision 0018/0019).
#
# Usage: docs-pipeline [--locale en|cn] [--check] [--init] [--force] [--dry-run] [--print-regions] [--print-target] [--changelog-parity] [--help]
# Exit: 0 ok | 1 --check drift | 2 usage | 4 --init exists w/o --force
#       5 malformed managed region (fail-closed, no write)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
TPL_DIR="$SCRIPT_DIR/../references/readme"
MODE="refresh"; FORCE=0; DRY_RUN=0; LOCALE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) cat <<'H'
docs-pipeline — deterministic bilingual doc generator (absorbs gitx-readme.sh)
Usage: docs-pipeline [--locale en|cn] [--check] [--init] [--force] [--dry-run] [--print-regions] [--print-target] [--changelog-parity] [--help]
  (default)        refresh managed regions in ALL locale README targets (en+cn)
  --locale en|cn   scope to a single locale (default: both en and cn)
  --check          regenerate to temp; exit 1 if any managed region drifted
  --init           scaffold ./README.md from references/readme/README.template.md
  --force          with --init, overwrite existing README.md
  --dry-run        print intended actions; write nothing
  --print-regions  print the space-separated list of managed region names and exit 0
  --print-target   print the resolved README basename(s) and exit 0
  --changelog-parity  check CHANGELOG EN/CN structural parity (versions + subsections)
Exit: 0 ok | 1 drift | 2 usage | 4 init-exists | 5 malformed region
H
      exit 0 ;;
    --check) MODE="check" ;;
    --init) MODE="init" ;;
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --locale)
      shift
      [ $# -gt 0 ] || { echo "❌ --locale requires an argument (en|cn)" >&2; exit 2; }
      LOCALE="$1" ;;
    --print-regions) MODE="print-regions" ;;
    --print-target) MODE="print-target" ;;
    --changelog-parity) MODE="changelog-parity" ;;
    --section-ids)
      shift
      [ $# -gt 0 ] || { echo "❌ --section-ids requires an argument (en|cn)" >&2; exit 2; }
      MODE="section-ids"; LOCALE="$1" ;;
    --map-headings)
      shift
      [ $# -gt 0 ] || { echo "❌ --map-headings requires an argument (en|cn)" >&2; exit 2; }
      MODE="map-headings"; LOCALE="$1" ;;
    *) echo "❌ unknown flag: $1" >&2; echo "   Try: docs-pipeline --help" >&2; exit 2 ;;
  esac; shift
done
# Validate locale fail-closed when --locale was explicitly given.
# When LOCALE is empty (no flag), both locales are processed — no validation needed.
if [ -n "$LOCALE" ]; then
  case "$LOCALE" in
    en|cn) ;;
    *) echo "❌ unknown --locale '$LOCALE' (allowed: en, cn)" >&2; echo "   Try: docs-pipeline --help" >&2; exit 2 ;;
  esac
fi
# Derive LOCALES list: all when unset, single when --locale given.
# LOCALES is a space-separated list used by check/refresh/print-target loops.
if [ -z "$LOCALE" ]; then
  LOCALES="en cn"
else
  LOCALES="$LOCALE"
fi
# Map a locale token to its README basename.
_locale_to_readme(){
  case "$1" in
    cn) printf '%s\n' "README_CN.md" ;;
    *)  printf '%s\n' "README.md" ;;
  esac
}
# --- ground-truth resolvers (non-circular only) ---
dp_suite_count(){
  local n=0 f
  for f in "$PROJECT_ROOT"/tests/test_*.sh; do
    [ -e "$f" ] || continue
    case "$f" in */test_suite_structure.sh) continue;; esac
    n=$((n+1))
  done
  printf '%s' "$n"
}
dp_version(){ [ -f "$PROJECT_ROOT/VERSION" ] && cat "$PROJECT_ROOT/VERSION" || echo unknown; }
# Release date = date of the TOP entry in Release/CHANGELOG.md (the @machine
# source for the build-metrics "Released" sub-token, frozen spec §2b/H4).
dp_release_date(){
  local cl="$PROJECT_ROOT/Release/CHANGELOG.md"
  [ -f "$cl" ] || { echo unknown; return 0; }
  grep -E '^## v[0-9]' "$cl" 2>/dev/null | head -1 \
    | sed -E 's/^## v[^ ]+ —[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/' \
    | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || echo unknown
}
dp_plugin_name(){
  local pj="$PROJECT_ROOT/.claude-plugin/plugin.json" n=""
  if [ -f "$pj" ]; then
    n=$(grep -m1 '"name"' "$pj" | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)
  fi
  [ -n "$n" ] || n=$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$n"
}
dp_skill_name(){
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
dp_install(){
  if [ -d "$PROJECT_ROOT/.claude-plugin" ]; then
    printf '```bash\n/plugin marketplace add tkxlab-ai/marketplace\n/plugin install %s@tkx-skills\n```\n' "$(dp_plugin_name)"
  else printf '```bash\nbash install.sh\n```\n'; fi
}
dp_whats_new(){
  local cl entry out
  # v1.12.2 (locale-aware): the cn README's whats-new MUST render Chinese.
  # Source it from the hand-authored CN changelog (Release/CHANGELOG_CN.md,
  # H5 structural-parity-gated; root /CHANGELOG_CN.md is its generated
  # mirror). en unchanged. Was locale-blind (always EN) — that shipped a
  # Chinese README with an English whats-new for ~every release; the §2b
  # "locale-invariant" assumption is retired now that CHANGELOG_CN.md is a
  # real source-of-truth (docs-audit H3 now scans this region, prevent-rot).
  # Codex v1.12.2 [high]: cn MUST fall back to the EN changelog when no
  # CHANGELOG_CN.md exists. A downstream repo with README_CN.md but only the
  # historically-supported Release/CHANGELOG.md would otherwise get its cn
  # whats-new region blanked (empty output → dp_rewrite_file writes empty),
  # silent doc corruption with exit 0. CN-first, EN-fallback = never empty;
  # adopters of the bilingual changelog get Chinese, non-adopters keep their
  # prior (EN-sourced) content unchanged — strictly backward-compatible.
  local -a _cls
  case "${LOCALE:-en}" in
    cn) _cls=("$PROJECT_ROOT/Release/CHANGELOG_CN.md" "$PROJECT_ROOT/CHANGELOG_CN.md" \
              "$PROJECT_ROOT/Release/CHANGELOG.md"    "$PROJECT_ROOT/CHANGELOG.md") ;;
    *)  _cls=("$PROJECT_ROOT/Release/CHANGELOG.md"    "$PROJECT_ROOT/CHANGELOG.md") ;;
  esac
  for cl in "${_cls[@]}"; do
    [ -f "$cl" ] || continue
    entry=$(awk '/^## /{n++} n==1{print} n==2{exit}' "$cl" 2>/dev/null || true)
    [ -n "$entry" ] || continue
    # Buffer the whole region, then emit with ONE write. A consumer that
    # closes early (`dp_whats_new | head -1 | grep -q`) would otherwise
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
        # dp_skill_name (tr -d \r) + the header path (head -1 | sed). A CRLF
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
dp_command_surface(){
  local skill plug f pj="$PROJECT_ROOT/.claude-plugin/plugin.json" out cmd_dir plug_cmd_dirs
  local _label_two_paths _label_a_prefix _label_b_prefix _label_b_na _label_footer_only _label_skill_self
  # Locale-aware framing labels (static text only; machine values — skill name,
  # plug name, command names — are locale-invariant identical bytes per §2b).
  case "${LOCALE:-en}" in
    cn)
      _label_two_paths='两种安装路径。'
      _label_a_prefix='**A. install.sh** — 运行 `bash install.sh`（技能 + 扁平命令；无需插件）'
      _label_b_prefix='**B. 插件市场** — `/plugin marketplace add tkxlab-ai/marketplace` 然后 `/plugin install %s@tkx-skills`（`/%s` 冒号命名空间）'
      _label_b_na='**B. 插件安装** — 不适用：无 `.claude-plugin/plugin.json`；本技能仅通过路径 A（install.sh，扁平命令）安装。'
      _label_footer_only='> `/%s` 冒号前缀命令仅限插件（官方文档的插件命名空间设计）。install.sh 提供扁平 `/%s` + `/<cmd>`；冒号形式需要安装此插件，从不由扁平命令合成。'
      _label_skill_self='技能本体'
      ;;
    *)
      _label_two_paths='Two install paths.'
      _label_a_prefix='**A. install.sh** — run `bash install.sh` (skill + flat commands; no plugin needed)'
      _label_b_prefix='**B. Plugin marketplace** — `/plugin marketplace add tkxlab-ai/marketplace` then `/plugin install %s@tkx-skills` (`/%s` colon namespace)'
      _label_b_na='**B. Plugin install** — N/A: no `.claude-plugin/plugin.json`; this skill installs only via path A (install.sh, flat commands).'
      _label_footer_only='> The `/%s` colon-prefixed commands are plugin-only (a plugin-namespacing design, per official docs). install.sh gives flat `/%s` + `/<cmd>`; the colon form requires this plugin install and is NEVER synthesized from flat commands.'
      _label_skill_self='the skill itself'
      ;;
  esac
  skill="$(dp_skill_name)"
  [ -f "$pj" ] && plug="$(dp_plugin_name)" || plug=""
  # Command-shim source dir, standard-layout aware. v1.10.1 closure round-2
  # (codex adversarial [medium]): this enumerated ONLY root commands/, but
  # the release pipeline's flatten contract (release.sh: `cp -R
  # "$SKILL_SRC_DIR/commands" "$RELEASE_DIR/commands"`) takes a downstream
  # skill's shims from skills/<skill>/commands/. A standard-layout dependent
  # skill with no mirrored root commands/ would publish a command surface
  # omitting its actually-installed shims while gitx-readme --check stayed
  # green (deterministic-blind). Prefer root commands/ (GitX + flat/legacy +
  # mirrored-root projects); else the standard-layout skills/<skill>/commands/
  # (skill resolved by dp_skill_name above). Generate-safe: dir checks only.
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
  # dp_plugin_name): take the `commands` array body, pull each "..." entry,
  # strip leading ./ and trailing /. Absent/empty commands[] → no dirs → no
  # fabricated colon bullets (footer still states the colon cmds are
  # plugin-only). Newline-separated; consumed by an IFS=read while-loop.
  plug_cmd_dirs=""
  if [ -f "$pj" ]; then
    plug_cmd_dirs="$(awk '/"commands"[[:space:]]*:/{f=1} f{print} f&&/\]/{exit}' "$pj" 2>/dev/null \
      | sed -E '1s/.*\[//' | grep -oE '"[^"]+"' \
      | sed -E 's/^"//; s/"$//; s#^\.?/+##; s#/+$##' | grep -v '^[[:space:]]*$' || true)"
  fi
  # Buffer + single emit (same SIGPIPE rationale as dp_whats_new): a
  # `dp_command_surface | grep -qF X` consumer closes on first match and a
  # later printf would SIGPIPE-kill this pipe stage under the sourced
  # `set -euo pipefail`. One final write is the only pipe-exposed point.
  out=$(
    printf '%s\n\n' "$_label_two_paths"
    printf -- '%s\n\n' "$_label_a_prefix"
    printf -- '- `/%s` — %s\n' "$skill" "$_label_skill_self"
    if [ -n "$cmd_dir" ]; then
      for f in "$cmd_dir"/*.md; do [ -f "$f" ] || continue
        printf -- '- `/%s`\n' "$(basename "$f" .md)"; done
    fi
    if [ -f "$pj" ]; then
      # shellcheck disable=SC2059
      printf -- "\n${_label_b_prefix}\n\n" "$plug" "$plug"
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
      # shellcheck disable=SC2059
      printf -- "${_label_footer_only}\n" "$plug" "$skill"
    else
      printf -- '\n%s\n' "$_label_b_na"
    fi
  )
  printf '%s\n' "$out" || true
}
# --- fail-closed region validator (C2). Own-line markers only. ---
# For every managed NAME that appears at all: exactly one line that is the
# opener (only the opener marker, nothing else), exactly one closer line,
# opener strictly before closer, no second opener before closer. Any
# violation (incl. inline same-line marker) → exit 5, caller writes nothing.
dp_validate_regions(){
  local file="$1" name nop ncl lo lc
  [ -f "$file" ] || return 0
  # FIX B (Gotcha #52 closure): scan for ANY gitx:managed NAME that appears as
  # a valid OWN-LINE marker; reject unknown names immediately (fail-closed
  # contract). A typo or future marker silently ignored → --check exits clean
  # → silent drift, so an unrecognised NAME is always an error. Using the same
  # own-line ERE as the structural checks ensures we skip documentation prose
  # (e.g. the template's comment block) that mentions NAME inline or indented.
  # errexit-safe: grep guarded || true.
  local _known="badges build-metrics whats-new command-surface suite-count"
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
  for name in badges build-metrics whats-new command-surface suite-count; do
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
# --- changelog parity engine (H5 precursor): structure-only EN vs CN check ---
# Compares (version,date) tuple set + ### subsection heading set per version.
# Does NOT generate CHANGELOG_CN (no LLM in loop) — parity is structure-only.
dp_changelog_parity(){
  local en="$PROJECT_ROOT/Release/CHANGELOG.md" cn="$PROJECT_ROOT/Release/CHANGELOG_CN.md"
  [ -f "$cn" ] || { echo "CHANGELOG_CN.md absent — parity not applicable"; return 0; }
  [ -f "$en" ] || { echo "❌ Release/CHANGELOG.md missing" >&2; return 1; }
  _ver_set(){ grep -E '^## v[0-9]' "$1" | sed -E 's/^## (v[^ ]+) — ([0-9-]+).*/\1|\2/' | sort; }
  if [ "$(_ver_set "$en")" != "$(_ver_set "$cn")" ]; then
    echo "❌ CHANGELOG (version,date) tuple set differs EN vs CN" >&2; return 1; fi
  local v
  # shellcheck disable=SC2086
  # Word-split intentional: _ver_set emits one v#.#.# token per line; no spaces in version tokens.
  for v in $(_ver_set "$en" | cut -d'|' -f1); do
    _subs(){ awk -v V="## $v " 'index($0,V)==1{f=1;next} /^## v/{f=0} f&&/^### /{print}' "$1" | sort -u; }
    if [ "$(_subs "$en")" != "$(_subs "$cn")" ]; then
      echo "❌ CHANGELOG subsection set differs at $v" >&2; return 1; fi
  done
  echo "✅ CHANGELOG EN/CN structural parity"; return 0
}

# --- read-only deterministic helpers (additive; no LLM; no write) ---
# dp_section_ids <en|cn>: emit the ordered contract section-ids present in
# that locale's rendered README, one per line. Used by docs-audit.sh H1/H2.
# The heading->id table is the fixed bilingual map derived from the templates.
# Uses awk (BSD-awk + UTF-8 safe) to avoid pipe-subshell/function-visibility
# issues under set -euo pipefail.
dp_section_ids(){
  local locale="$1" readme
  case "$locale" in
    cn) readme="$PROJECT_ROOT/README_CN.md" ;;
    *)  readme="$PROJECT_ROOT/README.md" ;;
  esac
  [ -f "$readme" ] || return 0
  if [ "$locale" = "en" ]; then
    awk '
      BEGIN {
        m["What'"'"'s New"]              = "whats-new"
        m["Table of Contents"]           = "table-of-contents"
        m["CLI in Action"]               = "cli-in-action"
        m["Why GitX"]                    = "why-gitx"
        m["Comparison"]                  = "comparison"
        m["Command Surface"]             = "command-surface"
        m["Pipeline & Audit Gates"]      = "pipeline-audit-gates"
        m["Quick Start"]                 = "quick-start"
        m["Configuration"]               = "configuration"
        m["Architecture"]                = "architecture"
        m["Symbol & State System"]       = "symbol-state"
        m["Testing"]                     = "testing"
        m["Development Journey"]         = "development-journey"
        m["Audits & Code Review"]        = "audits-code-review"
        m["Multi-Model AI Collaboration"]= "multi-model-ai"
        m["Research & References"]       = "research-references"
        m["Security"]                    = "security"
        m["FAQ"]                         = "faq"
        m["Compatibility"]               = "compatibility"
        m["Roadmap"]                     = "roadmap"
        m["Acknowledgments"]             = "acknowledgments"
        m["Contributing"]                = "contributing"
        m["Special Thanks"]              = "special-thanks"
        m["License"]                     = "license"
      }
      /^## / { h=substr($0,4); sub(/\r$/,"",h); if (h in m) print m[h] }
    ' "$readme"
  else
    awk '
      BEGIN {
        m["更新摘要"]         = "whats-new"
        m["目录"]             = "table-of-contents"
        m["命令行实况"]       = "cli-in-action"
        m["为什么选择 GitX"]  = "why-gitx"
        m["横向对比"]         = "comparison"
        m["命令面"]           = "command-surface"
        m["流水线与审计闸"]   = "pipeline-audit-gates"
        m["快速开始"]         = "quick-start"
        m["配置"]             = "configuration"
        m["架构"]             = "architecture"
        m["符号与状态系统"]   = "symbol-state"
        m["测试"]             = "testing"
        m["开发历程"]         = "development-journey"
        m["审查与代码评审"]   = "audits-code-review"
        m["多模型 AI 协作"]   = "multi-model-ai"
        m["研究与参考"]       = "research-references"
        m["安全"]             = "security"
        m["常见问题"]         = "faq"
        m["兼容性"]           = "compatibility"
        m["路线图"]           = "roadmap"
        m["鸣谢"]             = "acknowledgments"
        m["贡献"]             = "contributing"
        m["特别致谢"]         = "special-thanks"
        m["许可"]             = "license"
      }
      /^## / { h=substr($0,4); sub(/\r$/,"",h); if (h in m) print m[h] }
    ' "$readme"
  fi
}

# dp_map_headings <en|cn>: read headings from stdin (one per line; leading
# "## " is stripped if present), emit <heading>TAB<section-id> for each
# known heading. Unknown headings are silently omitted. Deterministic lookup
# only — no LLM, no I/O side effects. Uses awk to avoid pipe-subshell issues.
dp_map_headings(){
  local locale="$1"
  if [ "$locale" = "en" ]; then
    awk '
      BEGIN {
        m["What'"'"'s New"]              = "whats-new"
        m["Table of Contents"]           = "table-of-contents"
        m["CLI in Action"]               = "cli-in-action"
        m["Why GitX"]                    = "why-gitx"
        m["Comparison"]                  = "comparison"
        m["Command Surface"]             = "command-surface"
        m["Pipeline & Audit Gates"]      = "pipeline-audit-gates"
        m["Quick Start"]                 = "quick-start"
        m["Configuration"]               = "configuration"
        m["Architecture"]                = "architecture"
        m["Symbol & State System"]       = "symbol-state"
        m["Testing"]                     = "testing"
        m["Development Journey"]         = "development-journey"
        m["Audits & Code Review"]        = "audits-code-review"
        m["Multi-Model AI Collaboration"]= "multi-model-ai"
        m["Research & References"]       = "research-references"
        m["Security"]                    = "security"
        m["FAQ"]                         = "faq"
        m["Compatibility"]               = "compatibility"
        m["Roadmap"]                     = "roadmap"
        m["Acknowledgments"]             = "acknowledgments"
        m["Contributing"]                = "contributing"
        m["Special Thanks"]              = "special-thanks"
        m["License"]                     = "license"
      }
      {
        h=$0; sub(/^## /, "", h); sub(/\r$/, "", h)
        if (h in m) printf "%s\t%s\n", h, m[h]
      }
    '
  else
    awk '
      BEGIN {
        m["更新摘要"]         = "whats-new"
        m["目录"]             = "table-of-contents"
        m["命令行实况"]       = "cli-in-action"
        m["为什么选择 GitX"]  = "why-gitx"
        m["横向对比"]         = "comparison"
        m["命令面"]           = "command-surface"
        m["流水线与审计闸"]   = "pipeline-audit-gates"
        m["快速开始"]         = "quick-start"
        m["配置"]             = "configuration"
        m["架构"]             = "architecture"
        m["符号与状态系统"]   = "symbol-state"
        m["测试"]             = "testing"
        m["开发历程"]         = "development-journey"
        m["审查与代码评审"]   = "audits-code-review"
        m["多模型 AI 协作"]   = "multi-model-ai"
        m["研究与参考"]       = "research-references"
        m["安全"]             = "security"
        m["常见问题"]         = "faq"
        m["兼容性"]           = "compatibility"
        m["路线图"]           = "roadmap"
        m["鸣谢"]             = "acknowledgments"
        m["贡献"]             = "contributing"
        m["特别致谢"]         = "special-thanks"
        m["许可"]             = "license"
      }
      {
        h=$0; sub(/^## /, "", h); sub(/\r$/, "", h)
        if (h in m) printf "%s\t%s\n", h, m[h]
      }
    '
  fi
}

# Sourced as a library for tests: stop before main.
[ "${DOCS_PIPELINE_LIB:-0}" = "1" ] && return 0 2>/dev/null || true
# --- region rewriter: own-line markers; multi-line value via temp file ---
dp_rewrite_file(){
  local file="$1" name value vf op cl
  [ -f "$file" ] || return 0
  dp_validate_regions "$file" || return 5      # fail-closed: nothing written
  # §2b/H4 (T2.5): @machine ground-truth values computed ONCE per file.
  local _sc _ver _rd _mode
  _sc="$(dp_suite_count)"; _ver="$(dp_version)"; _rd="$(dp_release_date)"
  for name in badges build-metrics whats-new command-surface suite-count; do
    op="<!-- gitx:managed:${name} -->"; cl="<!-- /gitx:managed:${name} -->"
    grep -qE "^<!-- gitx:managed:${name} -->[[:space:]]*\$" "$file" 2>/dev/null || continue
    case "$name" in
      suite-count)     value="$(dp_suite_count)";     _mode=body ;;
      whats-new)       value="$(dp_whats_new)";       _mode=body ;;
      command-surface) value="$(dp_command_surface)"; _mode=body ;;
      # §2b: badges + build-metrics are NOT whole-region generated (that would
      # destroy curated License/CLIs/Shell/Release/Status shields + the models/
      # token-estimate/snapshot prose). Only their @machine SUB-TOKENS are
      # rewritten to ground truth (T2.5):
      #   badges        : tests-<N>%20suites%20%2F%200%20fail  → live dp_suite_count
      #   build-metrics : **v<semver>** → VERSION ; **<ISO date>** → top CHANGELOG date
      # Every other line in the region is reprinted verbatim → idempotent.
      badges|build-metrics) _mode=subtoken ;;
    esac
    if [ "$_mode" = subtoken ]; then
      if awk -v o="$op" -v c="$cl" -v sc="$_sc" -v ver="$_ver" -v rd="$_rd" '
          { lm=$0; sub(/[ \t\r]+$/,"",lm) }
          lm==o { print; inreg=1; next }
          lm==c { inreg=0; print; next }
          inreg==1 {
            L=$0
            gsub(/tests-[0-9]+%20suites%20%2F%200%20fail/, "tests-" sc "%20suites%20%2F%200%20fail", L)
            gsub(/\*\*v[0-9]+\.[0-9]+\.[0-9]+\*\*/, "**" ver "**", L)
            gsub(/\*\*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\*\*/, "**" rd "**", L)
            print L; next
          }
          { print }
        ' "$file" > "$file.gitxtmp"; then
          mv "$file.gitxtmp" "$file"
      else
          rm -f "$file.gitxtmp"
          echo "❌ docs-pipeline: awk sub-token rewrite failed for region '$name' in $file" >&2
          return 6
      fi
      continue
    fi
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
        echo "❌ docs-pipeline: awk rewrite failed for region '$name' in $file" >&2
        return 6
    fi
  done
  return 0
}
case "$MODE" in
  changelog-parity) dp_changelog_parity; exit $? ;;
  section-ids)
    # Validate locale then emit the present ordered section-ids for that locale.
    case "$LOCALE" in
      en|cn) ;;
      *) echo "❌ --section-ids requires en or cn" >&2; exit 2 ;;
    esac
    dp_section_ids "$LOCALE"
    exit 0 ;;
  map-headings)
    # Validate locale then map headings from stdin to section-ids.
    case "$LOCALE" in
      en|cn) ;;
      *) echo "❌ --map-headings requires en or cn" >&2; exit 2 ;;
    esac
    dp_map_headings "$LOCALE"
    exit 0 ;;
  print-regions)
    # Print the contracted region inventory (space-separated) and exit.
    # Sourced from dp_validate_regions' _known; kept in sync by design.
    # Locale-invariant: same 5 regions regardless of --locale (§2a frozen spec).
    printf '%s\n' "badges build-metrics whats-new command-surface suite-count"
    exit 0 ;;
  print-target)
    # Print the resolved README basename(s) and exit.
    # No --locale: both locales, one per line (en first, then cn).
    # --locale X: only that locale's file.
    for _loc in $LOCALES; do
      _locale_to_readme "$_loc"
    done
    exit 0 ;;
  init)
    t="$PROJECT_ROOT/README.md"
    if [ -f "$t" ] && [ "$FORCE" -eq 0 ]; then echo "❌ $t exists — use --force" >&2; exit 4; fi
    [ "$DRY_RUN" -eq 1 ] && { echo "would scaffold $t"; exit 0; }
    p="$(basename "$PROJECT_ROOT")"
    # Literal {{PROJECT}} → $p substitution that is safe for ANY project
    # dir name (&, |, \, / etc): awk split on the literal token then
    # reassemble with string concat — never a regex/sed replacement, so
    # no `&`/delimiter injection. Idempotent + portable (BSD awk).
    _dp_render_tpl(){ # $1=template $2=dest
      awk -v p="$p" '{
        out=""; n=split($0, a, /\{\{PROJECT\}\}/)
        for (i=1;i<=n;i++){ out=out a[i]; if (i<n) out=out p }
        print out
      }' "$1" > "$2"
    }
    # Drop scaffold BEFORE dp_rewrite_file so suite-count already includes it.
    if [ ! -f "$PROJECT_ROOT/tests/test_readme_numeric_accuracy.sh" ] && [ -f "$TPL_DIR/test_readme_numeric_accuracy.sh.template" ]; then
        mkdir -p "$PROJECT_ROOT/tests"
        cp "$TPL_DIR/test_readme_numeric_accuracy.sh.template" "$PROJECT_ROOT/tests/test_readme_numeric_accuracy.sh"
        chmod +x "$PROJECT_ROOT/tests/test_readme_numeric_accuracy.sh"
    fi
    _dp_render_tpl "$TPL_DIR/README.template.md" "$t"
    if [ -f "$TPL_DIR/README_CN.template.md" ]; then
      _dp_render_tpl "$TPL_DIR/README_CN.template.md" "$PROJECT_ROOT/README_CN.md"
    fi
    # Locale-correct rewrite per file (T3 added per-locale to check/refresh
    # but init was locale-blind → EN command-surface leaked into README_CN
    # and a later locale-correct --check reported false drift). Mirror the
    # check/refresh contract: en→README.md, cn→README_CN.md.
    LOCALE="en"; dp_rewrite_file "$t" || exit 5
    [ -f "$PROJECT_ROOT/README_CN.md" ] && { LOCALE="cn"; dp_rewrite_file "$PROJECT_ROOT/README_CN.md" || exit 5; }
    exit 0 ;;
  check)
    # Iterate over all locales in scope (both when no --locale, one when --locale given).
    # If EITHER locale drifts, exit 1 (§0g: one bare --check catches drift in either locale).
    _overall_rc=0
    for _loc in $LOCALES; do
      _readme="$(_locale_to_readme "$_loc")"
      trap 'rm -f "$PROJECT_ROOT/'"$_readme"'.gitxchk" 2>/dev/null || true' EXIT
      [ -f "$PROJECT_ROOT/$_readme" ] || continue
      cp "$PROJECT_ROOT/$_readme" "$PROJECT_ROOT/$_readme.gitxchk"
      # dp_command_surface uses LOCALE for framing labels; set it for this iteration.
      LOCALE="$_loc"
      if ! dp_rewrite_file "$PROJECT_ROOT/$_readme.gitxchk"; then
        echo "❌ malformed managed region in $_readme" >&2
        rm -f "$PROJECT_ROOT/$_readme.gitxchk"
        exit 5
      fi
      diff -q "$PROJECT_ROOT/$_readme" "$PROJECT_ROOT/$_readme.gitxchk" >/dev/null 2>&1 \
        || { echo "❌ managed-region drift in $_readme (run: docs-pipeline)" >&2; _overall_rc=1; }
      rm -f "$PROJECT_ROOT/$_readme.gitxchk"
    done
    exit $_overall_rc ;;
  refresh)
    # Iterate over all locales in scope.
    [ "$DRY_RUN" -eq 1 ] && {
      for _loc in $LOCALES; do echo "would refresh $(_locale_to_readme "$_loc")"; done
      exit 0
    }
    for _loc in $LOCALES; do
      _readme="$(_locale_to_readme "$_loc")"
      # dp_command_surface uses LOCALE for framing labels; set it for this iteration.
      LOCALE="$_loc"
      dp_rewrite_file "$PROJECT_ROOT/$_readme" || exit 5
    done
    exit 0 ;;
esac
