#!/bin/bash
# docs-audit.sh — H1: contract sections present+ordered in each locale README;
# H2: EN/CN section-id lists are identical (structural parity).
# H3: CN files — detect long English runs (>= h3_threshold consecutive ASCII words).
# H4: every @machine token == recomputed ground truth (zero frozen literals).
# H5: CHANGELOG EN/CN structural parity (delegates to docs-pipeline --changelog-parity).
# H6: managed-region drift check (delegates to docs-pipeline --check); idempotent gate.
# H7: self shellcheck-clean at -S warning (generic-safe skip when shellcheck absent).
# Non-counting (Gotcha #62): never prints PASS/FAIL/SKIP tallies; owns STRUCTURE only.
# Generic-safe SKIP (Gotcha #51): absent manifest -> "not applicable" + exit 0.
# Usage: [PROJECT_ROOT=<dir>] docs-audit.sh
# Exit:  0 clean | 1 structure violation
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
MANIFEST="$PROJECT_ROOT/references/docs-contract/manifest.txt"

# Gotcha #51: generic-safe — no manifest means this project does not use the
# docs contract; audit is not applicable, not a failure.
if [ ! -f "$MANIFEST" ]; then
  echo "docs-audit: references/docs-contract/manifest.txt absent — not applicable, skipping"
  exit 0
fi

# _section_ids_in_file <locale> <file>
# Emit the ordered section-ids present in the given README, one per line.
# Uses awk with an inline bilingual heading->id table (BSD-awk + UTF-8 safe).
# Avoids pipe-subshell + shell-function calls that fail under set -euo pipefail.
_section_ids_in_file() {
  local locale="$1" file="$2"
  [ -f "$file" ] || return 0
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
    ' "$file"
  else
    awk '
      BEGIN {
        m["更新摘要"]          = "whats-new"
        m["目录"]              = "table-of-contents"
        m["命令行实况"]        = "cli-in-action"
        m["为什么选择 GitX"]   = "why-gitx"
        m["横向对比"]          = "comparison"
        m["命令面"]            = "command-surface"
        m["流水线与审计闸"]    = "pipeline-audit-gates"
        m["快速开始"]          = "quick-start"
        m["配置"]              = "configuration"
        m["架构"]              = "architecture"
        m["符号与状态系统"]    = "symbol-state"
        m["测试"]              = "testing"
        m["开发历程"]          = "development-journey"
        m["审查与代码评审"]    = "audits-code-review"
        m["多模型 AI 协作"]    = "multi-model-ai"
        m["研究与参考"]        = "research-references"
        m["安全"]              = "security"
        m["常见问题"]          = "faq"
        m["兼容性"]            = "compatibility"
        m["路线图"]            = "roadmap"
        m["鸣谢"]              = "acknowledgments"
        m["贡献"]              = "contributing"
        m["特别致谢"]          = "special-thanks"
        m["许可"]              = "license"
      }
      /^## / { h=substr($0,4); sub(/\r$/,"",h); if (h in m) print m[h] }
    ' "$file"
  fi
}

# _contract_section_ids: read ordered section-ids from manifest.txt.
_contract_section_ids() {
  grep -E '^section:[[:space:]]' "$MANIFEST" \
    | sed -E 's/^section:[[:space:]]+([A-Za-z0-9_-]+).*/\1/'
}

# H1: every contract section present and in contract order, per locale.
_check_h1() {
  local locale="$1" file="$2" label="$3"
  local rc=0 contract_ids present_ids

  if [ ! -f "$file" ]; then
    echo "  docs-audit H1 [$label]: $file not found — skipping locale" >&2
    return 0
  fi

  contract_ids="$(_contract_section_ids)"
  present_ids="$(_section_ids_in_file "$locale" "$file")"

  # Check each contract section is present.
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    if ! printf '%s\n' "$present_ids" | grep -qx "$sid"; then
      echo "  docs-audit H1 [$label]: section '$sid' missing from $file" >&2
      rc=1
    fi
  done <<EOF_CID
$contract_ids
EOF_CID

  # Check order: present_ids (filtered to contract members) must appear in
  # the same relative order as contract_ids.
  local prev_pos=0 cur_pos
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    cur_pos=$(printf '%s\n' "$contract_ids" | grep -nx "^${sid}$" | head -1 | cut -d: -f1 || true)
    [ -n "$cur_pos" ] || continue
    if [ "$cur_pos" -lt "$prev_pos" ]; then
      echo "  docs-audit H1 [$label]: section '$sid' is out of contract order in $file" >&2
      rc=1
    fi
    prev_pos="$cur_pos"
  done <<EOF_PID
$present_ids
EOF_PID

  return $rc
}

# H2: EN and CN have identical ordered section-id lists.
_check_h2() {
  local en_file="$1" cn_file="$2"
  local en_ids cn_ids

  en_ids="$(_section_ids_in_file en "$en_file")"
  cn_ids="$(_section_ids_in_file cn "$cn_file")"

  if [ "$en_ids" = "$cn_ids" ]; then
    return 0
  fi

  echo "  docs-audit H2: EN/CN section-id lists diverge" >&2
  echo "    EN: $(printf '%s\n' "$en_ids" | tr '\n' ' ')" >&2
  echo "    CN: $(printf '%s\n' "$cn_ids" | tr '\n' ' ')" >&2
  return 1
}

# H3: CN long-English-run detector.
# Strip fenced code blocks, HTML comments, inline code, and markdown link URLs,
# then ignore whitelist tokens. If >= h3_threshold consecutive ASCII-word tokens
# remain in any sequence, fail. BSD-awk + LC_ALL=C (ASCII pattern matching only;
# multibyte CN chars are opaque bytes, never match [A-Za-z] — UTF-8 safe).
# HTML comments (<!-- ... -->) are stripped because they are authoring metadata
# (forward-ref notices, gitx:managed markers) not body text — checking them
# would produce false positives on legitimate CN-file comment lines.
_check_h3() {
  local file="$1" label="$2"
  [ -f "$file" ] || return 0

  # Read threshold and cjk_allow path from manifest.
  local thresh allow_file allow_path
  thresh=$(grep -E '^h3_threshold:[[:space:]]' "$MANIFEST" \
    | sed -E 's/^h3_threshold:[[:space:]]*//' | tr -d '[:space:]' | head -1)
  thresh="${thresh:-8}"
  allow_path=$(grep -E '^cjk_allow:[[:space:]]' "$MANIFEST" \
    | sed -E 's/^cjk_allow:[[:space:]]*//' | tr -d '[:space:]' | head -1)
  allow_file="$PROJECT_ROOT/$allow_path"

  # Build whitelist: pipe-separated list of literal tokens.
  local wl_pattern=""
  if [ -f "$allow_file" ]; then
    wl_pattern=$(LC_ALL=C awk 'NF>0{print}' "$allow_file" | tr '\n' '|' | sed 's/|$//')
  fi

  # Generic-safe (Codex v1.12.2 [high]): the whats-new/command-surface
  # un-skip only applies when the project ADOPTED the bilingual changelog
  # (Release/CHANGELOG_CN.md present). A downstream repo with README_CN.md
  # but only CHANGELOG.md legitimately has EN-sourced (fallback) machine
  # prose there — it must NOT newly fail their release. cnscan=1 → scan
  # those regions (strict, GitX); cnscan=0 → keep skipping (status quo).
  local _h3_cnscan=0
  [ -f "$PROJECT_ROOT/Release/CHANGELOG_CN.md" ] && _h3_cnscan=1
  local snippet
  snippet=$(LC_ALL=C awk -v thresh="$thresh" -v wl="$wl_pattern" -v cnscan="$_h3_cnscan" '
    BEGIN {
      n = split(wl, a, "|")
      for (i=1; i<=n; i++) allowed[a[i]] = 1
    }
    # Skip fenced code blocks.
    /^```/ { fence = !fence; next }
    fence  { next }
    # Managed-region policy v1.12.2 closes the systemic blindspot that let
    # a Chinese README ship an English whats-new for ~every release.
    # NOTE: this comment is INSIDE the single-quoted awk program — keep it
    # apostrophe-free and paren-free (an apostrophe terminates the awk
    # string; SC1011). badges / build-metrics / suite-count are
    # language-NEUTRAL machine values (shields URLs, version-date-model
    # identifiers, a bare number) so they stay skipped. whats-new and
    # command-surface are prose that MUST match the file own-locale
    # language (cn now sourced from Release CHANGELOG_CN.md) so they are
    # NOT skipped WHEN cnscan==1 (project adopted Release CHANGELOG_CN.md):
    # a long English run there then fails H3 so an EN-in-CN whats-new
    # regression can never silently ship again. cnscan==0 keeps the prior
    # skip so a downstream without CHANGELOG_CN is not newly broken.
    /^<!-- gitx:managed:(badges|build-metrics|suite-count) -->/ { managed = 1; next }
    /^<!-- gitx:managed:(whats-new|command-surface) -->/         { managed = (cnscan == 1 ? 0 : 1); next }
    /^<!-- gitx:managed:/   { managed = 1; next }
    /^<!-- \/gitx:managed:/ { managed = 0; next }
    managed { next }
    {
      line = $0
      # Strip HTML comments (<!-- ... -->) — authoring metadata, not body text.
      # Handles single-line comments only (multi-line rare in these files).
      while (match(line, /<!--[^>]*-->/)) {
        line = substr(line,1,RSTART-1) " " substr(line,RSTART+RLENGTH)
      }
      # Strip inline code spans: `...`
      while (match(line, /`[^`]*`/)) {
        line = substr(line,1,RSTART-1) " " substr(line,RSTART+RLENGTH)
      }
      # Strip markdown link URLs: ](...)
      while (match(line, /\]\([^)]*\)/)) {
        line = substr(line,1,RSTART) " " substr(line,RSTART+RLENGTH)
      }
      # Count consecutive ASCII-word tokens ([A-Za-z][A-Za-z.-]*) not in whitelist.
      # Hyphen is included in the word-char set so compound technical terms
      # (fail-closed, meta-gate, five-facet) count as ONE token, not fragments.
      run = 0; bad_run = ""
      n = split(line, toks, /[^A-Za-z.-]+/)
      for (i=1; i<=n; i++) {
        t = toks[i]
        if (t !~ /^[A-Za-z][A-Za-z.-]*$/) { run=0; bad_run=""; continue }
        if (t in allowed)                  { run=0; bad_run=""; continue }
        run++
        bad_run = (run==1) ? t : bad_run " " t
        if (run >= thresh) { print bad_run; exit 3 }
      }
    }
  ' "$file") && _h3_awk_rc=0 || _h3_awk_rc=$?

  # Fail-closed: awk exit 3 = violation found (non-zero sentinel); also guard on
  # non-empty snippet in case shell somehow swallows the exit code.
  if [ "$_h3_awk_rc" -eq 3 ] || [ -n "$snippet" ]; then
    echo "  docs-audit H3 [$label]: long English run in $file: $snippet" >&2
    return 1
  fi
  return 0
}

# H4: every @machine token in managed regions equals recomputed ground truth.
# Derives all truths via DOCS_PIPELINE_LIB=1 source of docs-pipeline.sh.
# Explicitly skips: Deep-Audit N/0/1 shield; static shields (License/CLIs/
# Shell/Release/Status); models/token-estimate/snapshot prose (frozen §2b,
# Deep-Audit §0f/§0i owns them — double-ownership = rot).
_check_h4() {
  local readme="$1" label="$2"
  [ -f "$readme" ] || return 0

  # Resolve docs-pipeline.sh co-located with this script.
  # Use BASH_SOURCE[0] (the actual script file, not $0 which changes when
  # sourced) so the path is correct regardless of caller working directory.
  local pipeline_sh
  pipeline_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/docs-pipeline.sh"
  if [ ! -f "$pipeline_sh" ]; then
    echo "  docs-audit H4 [$label]: docs-pipeline.sh not found — skipping H4" >&2
    return 0
  fi

  local rc=0

  # Source the pipeline library (defines dp_suite_count, dp_version, dp_release_date).
  # `set --` clears $@ before sourcing so docs-pipeline.sh's top-level arg-
  # parsing loop (while [ $# -gt 0 ]) does not consume the calling script's
  # positional parameters and exit 2 (unknown flag).
  # shellcheck disable=SC1090
  set -- && DOCS_PIPELINE_LIB=1 source "$pipeline_sh"

  local live_sc live_ver live_rd
  live_sc="$(dp_suite_count)"
  live_ver="$(dp_version)"
  live_rd="$(dp_release_date)"

  # H4.1: badges region — tests-N%20suites sub-token.
  local readme_sc
  readme_sc=$(LC_ALL=C grep -oE 'tests-[0-9]+%20suites%20%2F%200%20fail' "$readme" \
    | head -1 | sed -E 's/tests-([0-9]+)%20suites.*/\1/' || true)
  if [ -n "$readme_sc" ] && [ "$readme_sc" != "$live_sc" ]; then
    echo "  docs-audit H4 [$label]: badge suite count is $readme_sc, expected $live_sc" >&2
    rc=1
  fi

  # H4.2: build-metrics region — **vX.Y.Z** must match VERSION.
  local readme_ver
  readme_ver=$(LC_ALL=C awk '
    /^<!-- gitx:managed:build-metrics -->/{f=1; next}
    /^<!-- \/gitx:managed:build-metrics -->/{f=0; next}
    f && /\*\*v[0-9]+\.[0-9]+\.[0-9]+\*\*/{
      match($0,/\*\*v[0-9]+\.[0-9]+\.[0-9]+\*\*/)
      s=substr($0,RSTART+2,RLENGTH-4); print s; exit
    }
  ' "$readme" || true)
  if [ -n "$readme_ver" ] && [ "$readme_ver" != "$live_ver" ]; then
    echo "  docs-audit H4 [$label]: build-metrics version is $readme_ver, expected $live_ver" >&2
    rc=1
  fi

  # H4.3: build-metrics region — **YYYY-MM-DD** must match top CHANGELOG date.
  local readme_rd
  readme_rd=$(LC_ALL=C awk '
    /^<!-- gitx:managed:build-metrics -->/{f=1; next}
    /^<!-- \/gitx:managed:build-metrics -->/{f=0; next}
    f && /\*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*/{
      match($0,/\*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*/)
      s=substr($0,RSTART+2,RLENGTH-4); print s; exit
    }
  ' "$readme" || true)
  if [ -n "$readme_rd" ] && [ "$readme_rd" != "$live_rd" ]; then
    echo "  docs-audit H4 [$label]: build-metrics date is $readme_rd, expected $live_rd" >&2
    rc=1
  fi

  # H4.4: suite-count region body — bare number must match dp_suite_count.
  local readme_sc_body
  readme_sc_body=$(LC_ALL=C awk '
    /^<!-- gitx:managed:suite-count -->/{f=1; next}
    /^<!-- \/gitx:managed:suite-count -->/{f=0; next}
    f && /^[0-9]+$/{print; exit}
  ' "$readme" || true)
  if [ -n "$readme_sc_body" ] && [ "$readme_sc_body" != "$live_sc" ]; then
    echo "  docs-audit H4 [$label]: suite-count region body is $readme_sc_body, expected $live_sc" >&2
    rc=1
  fi

  return $rc
}

# H5: CHANGELOG EN/CN structural parity — delegate to docs-pipeline --changelog-parity.
# Generic-safe: when CHANGELOG_CN.md is absent, docs-pipeline exits 0 ("not applicable").
_check_h5() {
  local pipeline_sh rc
  pipeline_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/docs-pipeline.sh"
  if [ ! -f "$pipeline_sh" ]; then
    echo "  docs-audit H5: docs-pipeline.sh not found — skipping H5" >&2
    return 0
  fi
  PROJECT_ROOT="$PROJECT_ROOT" "$pipeline_sh" --changelog-parity >/dev/null 2>&1 \
    && rc=0 || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  docs-audit H5 CHANGELOG EN/CN structural parity: failed (rc=$rc)" >&2
    return 1
  fi
  return 0
}

# H6: managed-region idempotency — delegate to docs-pipeline --check (read-only).
# Non-zero means a managed region has drifted and the release must not proceed.
_check_h6() {
  local pipeline_sh rc
  pipeline_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/docs-pipeline.sh"
  if [ ! -f "$pipeline_sh" ]; then
    echo "  docs-audit H6: docs-pipeline.sh not found — skipping H6" >&2
    return 0
  fi
  PROJECT_ROOT="$PROJECT_ROOT" "$pipeline_sh" --check >/dev/null 2>&1 \
    && rc=0 || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  docs-audit H6 refresh not idempotent (run docs-pipeline refresh)" >&2
    return 1
  fi
  return 0
}

# H7: self shellcheck-clean at -S warning.
# Generic-safe (Gotcha #51 style): if shellcheck is absent, emit an informational
# line and skip (do NOT fail — shellcheck may not be installed in all environments).
_check_h7() {
  local script_dir rc
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "  docs-audit H7: shellcheck not found — skipping (not applicable)"
    return 0
  fi
  shellcheck -S warning "$script_dir/docs-audit.sh" "$script_dir/docs-pipeline.sh" \
    >/dev/null 2>&1 && rc=0 || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  docs-audit H7 self not shellcheck-clean (rc=$rc)" >&2
    return 1
  fi
  return 0
}

# H10: every repo-local Markdown link target and <img src> in each README must
# resolve under PROJECT_ROOT — STRICT, no per-path skips. Anchors and absolute
# URLs are skipped. (Codex review: a skip of *referenced* missing assets let a
# downstream scaffold ship a visibly broken README image — removed.)
# Hero showcase asset (Gotcha #51/#63/#65 — host-agnostic, manifest-driven):
# `hero_asset:` DECLARED ⇒ a standalone gate (in main) hard-fails if that exact
# path is missing — UNCONDITIONALLY, even when no README links it (the origin,
# e.g. GitX, ships it as a committed asset). OMITTED ⇒ no special-casing here;
# the reusable README template carries NO hardcoded hero <img>, so a downstream
# scaffold produces no broken ref in the first place (the host-specific hero
# lives only in the origin's live README, never in the shared template).
_check_h10() {
  local file="$1" label="$2" rc=0
  [ -f "$file" ] || return 0

  # Extract Markdown link targets: ](target)  — strip #fragment
  # Extract img src="target"                  — strip #fragment
  # Skip http://, https://, mailto:, pure anchors (#...), empty
  local refs
  refs=$(LC_ALL=C awk '
    {
      line = $0
      # img src="..."
      while (match(line, /src="[^"]+"/) > 0) {
        v = substr(line, RSTART+5, RLENGTH-6)
        sub(/#.*$/, "", v)
        if (v != "" && v !~ /^https?:\/\// && v !~ /^mailto:/ && v !~ /^#/)
          print v
        line = substr(line, RSTART+RLENGTH)
      }
    }
    {
      line = $0
      # Markdown links: ](target)
      while (match(line, /\]\([^)]+\)/) > 0) {
        v = substr(line, RSTART+2, RLENGTH-3)
        sub(/#.*$/, "", v)
        if (v != "" && v !~ /^https?:\/\// && v !~ /^mailto:/ && v !~ /^#/)
          print v
        line = substr(line, RSTART+RLENGTH)
      }
    }
  ' "$file" | sort -u)

  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    if [ ! -e "$PROJECT_ROOT/$ref" ]; then
      echo "  docs-audit H10 [$label]: unresolved local ref in $file: $ref" >&2
      rc=1
    fi
  done <<EOF_REFS
$refs
EOF_REFS

  return $rc
}

# --- main ---
EN_README="$PROJECT_ROOT/README.md"
CN_README="$PROJECT_ROOT/README_CN.md"
OVERALL_RC=0

_check_h1 en "$EN_README" "en" || OVERALL_RC=1
_check_h1 cn "$CN_README" "cn" || OVERALL_RC=1
_check_h2 "$EN_README" "$CN_README" || OVERALL_RC=1
_check_h3 "$CN_README"                 "cn"         || OVERALL_RC=1
CN_CL="$PROJECT_ROOT/Release/CHANGELOG_CN.md"
_check_h3 "$CN_CL"                     "changelog-cn" || OVERALL_RC=1
_check_h4 "$EN_README"                 "en"         || OVERALL_RC=1
_check_h4 "$CN_README"                 "cn"         || OVERALL_RC=1
_check_h5 || OVERALL_RC=1
_check_h6 || OVERALL_RC=1
_check_h7 || OVERALL_RC=1

# Declared hero_asset MUST exist — UNCONDITIONAL, independent of whether any
# README references it (the manifest declares the project ships it as required;
# enforcement must not be contingent on a link surviving in the README).
# `|| true`: hero_asset is OPTIONAL — when absent grep exits 1 and, under
# `set -euo pipefail`, an unguarded command-substitution assignment would
# abort the whole audit before any check runs (set -e capture hazard).
HERO=$(grep -E '^hero_asset:[[:space:]]' "$MANIFEST" 2>/dev/null \
  | sed -E 's/^hero_asset:[[:space:]]+([^[:space:]]+).*/\1/' | head -1 || true)
if [ -n "$HERO" ] && [ ! -e "$PROJECT_ROOT/$HERO" ]; then
  echo "  docs-audit H10: declared hero_asset missing: $HERO" >&2
  OVERALL_RC=1
fi

_check_h10 "$EN_README" "en" || OVERALL_RC=1
_check_h10 "$CN_README" "cn" || OVERALL_RC=1

if [ "$OVERALL_RC" -eq 0 ]; then
  echo "docs-audit: H1+H2+H3+H4+H5+H6+H7+H10 clean"
fi
exit $OVERALL_RC
