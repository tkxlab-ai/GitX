#!/bin/bash
# release-audit.sh — post-release deep audit (TKX policy §8)
# usage:
#   release-audit.sh <version>
#   PROJECT_ROOT=<dir> PROJECT_NAME=<n> SKILL_NAME=<n> release-audit.sh <version>
#
# 默认从 $(pwd) 推断 PROJECT_ROOT；PROJECT_NAME/SKILL_NAME 缺失则自动探测。
# exit: 0 all green, 1 findings, 2 usage

set -euo pipefail

# v0.9.7: parse optional --inline flag. release.sh passes --inline when
# invoking audit before updating Release/latest (S1-5 ordering).
# In inline mode, §8 relaxes mismatched-target to SKIP when the target
# directory still exists (previous valid release) — release.sh will update
# latest atomically after audit passes. Standalone callers keep strict
# semantics: wrong latest → FAIL.
INLINE=0
ARGS=()
_INLINE_REQUESTED=0
for arg in "$@"; do
    case "$arg" in
        --inline) _INLINE_REQUESTED=1 ;;
        *)        ARGS+=("$arg") ;;
    esac
done
set -- "${ARGS[@]:-}"
# v1.0.8 hardening (Sec #2 / Arch #1): --inline relaxes §8 mismatched-target
# FAIL to SKIP, which is necessary mid-pipeline but a footgun if any caller
# can pass it. Require provenance via _GITX_INTERNAL_INLINE=1 env, set only
# by release.sh's run_deep_audit(). If env unset, ignore --inline with
# stderr warning so the user knows they can't bypass the gate this way.
if [ "$_INLINE_REQUESTED" = "1" ]; then
    if [ "${_GITX_INTERNAL_INLINE:-0}" = "1" ]; then
        INLINE=1
    else
        echo "⚠️  --inline ignored: _GITX_INTERNAL_INLINE env not set (provenance check)" >&2
        echo "    Standalone callers cannot bypass §8 strict mode via CLI flag." >&2
    fi
fi

# --- Section tracking for per-section summary (P3-2) ---
# Bash 3.2 compatible: write each section's delta to a temp file
_SEC_LOG=$(mktemp)
trap 'rm -f "${_SEC_LOG:-}"' EXIT

_track_start() {
    _TRACK_P=$PASS; _TRACK_F=$FAIL; _TRACK_S=$SKIP; _TRACK_N="$1"
}
_track_end() {
    local dp=$((PASS - _TRACK_P))
    local df=$((FAIL - _TRACK_F))
    local ds=$((SKIP - _TRACK_S))
    echo "$_TRACK_N|$dp|$df|$ds" >> "$_SEC_LOG"
}

# --- Resolve self location ---
# shellcheck disable=SC2034  # SELF_DIR kept for future extensions
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:?Usage: $0 [--inline] vX.Y[.Z][-alpha|beta|rc[.N]]}"
# v1.0.8 hardening (Sec Minor #3): standalone audit was unvalidated.
# Mirror release.sh:47 regex so VERSION is constrained before flowing into
# awk/grep patterns and Release/<PROJECT>-<VERSION> path components.
if ! echo "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+(\.[0-9]+)?(-(alpha|beta|rc)\.?[0-9]*)?$'; then
    echo "❌ Invalid version: $VERSION (expected vX.Y[.Z][-alpha|beta|rc[.N]])" >&2
    exit 2
fi

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
[ -d "$PROJECT_ROOT" ] || { echo "❌ PROJECT_ROOT 不存在: $PROJECT_ROOT"; exit 2; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

# Auto-detect PROJECT_NAME and SKILL_NAME via shared lib.
# INLINE flag parsing and LEGACY_LAYOUT detection remain audit-specific.
# detect-project.sh returns 1 on failure; audit convention is exit 2.
if ! source "$(cd "$(dirname "$0")" && pwd)/lib/detect-project.sh" 2>/dev/null; then
    echo "❌ SKILL_NAME 未设且无法自动探测"
    exit 2
fi

# v0.9.7 (S2-2): Pre-escape VERSION dots for all subsequent grep/awk usage.
# Replaces per-section ad-hoc escaping with a single canonical definition.
SAFE_VERSION=$(printf '%s' "$VERSION" | sed 's/\./\\./g')

# v0.9.10: Release dir naming now includes PROJECT_NAME (matches artifact
# naming). Legacy bare `Release/$VERSION/` layouts are auto-detected and
# honored for backward compatibility when auditing old releases.
DIR="$PROJECT_ROOT/Release/${PROJECT_NAME}-${VERSION}"
if [ ! -d "$DIR" ] && [ -d "$PROJECT_ROOT/Release/$VERSION" ]; then
    DIR="$PROJECT_ROOT/Release/$VERSION"
    LEGACY_LAYOUT=1
else
    LEGACY_LAYOUT=0
fi
SKILL_FILE="${PROJECT_NAME}-${VERSION}.skill"
TAR_FILE="${PROJECT_NAME}-${VERSION}-source.tar.gz"
MAX_SKILL_DESCRIPTION_CHARS=220
FAIL=0
PASS=0
SKIP=0
ADVISORY=0

check() {
    local title="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  ✅ $title"
        PASS=$((PASS+1))
    else
        echo "  ❌ $title"
        FAIL=$((FAIL+1))
    fi
}

check_not() {
    local title="$1"; shift
    if ! "$@" >/dev/null 2>&1; then
        echo "  ✅ $title"
        PASS=$((PASS+1))
    else
        echo "  ❌ $title"
        FAIL=$((FAIL+1))
    fi
}

warn() {
    local title="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  ✅ $title"
        PASS=$((PASS+1))
    else
        echo "  ⚠️  $title (soft warning — not counted as FAIL)"
        ADVISORY=$((ADVISORY+1))
    fi
}

_track_start "init"  # seed tracking vars
echo "═══ Post-Release Deep Audit: $PROJECT_NAME $VERSION ═══"
echo "   Project: $PROJECT_ROOT"
echo "   Skill:   $SKILL_NAME"
echo ""


# --- §0 SKILL.md spec conformance (agentskills.io / skill-creator equivalent) ---
# v1.2.1 fix: makes audit explicitly enforce the 6 rules from Anthropic's
# official skill-creator quick_validate.py (the source-of-truth for agentskills.io
# spec compliance):
#   1. SKILL.md exists
#   2. YAML frontmatter delimited by `---`
#   3. Top-level keys ⊆ {name description license allowed-tools metadata compatibility}
#   4. name: kebab-case `^[a-z0-9-]+$`, no leading/trailing/double hyphen, ≤64 chars
#   5. description: no `<` or `>` (angle brackets), ≤1024 chars
#   6. compatibility (optional): ≤500 chars
# We previously enforced these implicitly via Gotcha #16 docs + human discipline.
# Now any new skill's SKILL.md frontmatter passes the official spec gate before
# our 11-chapter superset audit runs. Note: this is flat-scalar parsing only;
# block-scalar multiline values (rare in well-formed SKILL.md frontmatter) fall
# through. Run `python3 quick_validate.py <path>` for full PyYAML conformance.
audit_section_0_spec() {
    echo "§0. SKILL.md spec conformance (agentskills.io)"
    local skill_md="$PROJECT_ROOT/skills/$SKILL_NAME/SKILL.md"

    # Rule 1
    if [ ! -f "$skill_md" ]; then
        echo "  ❌ SKILL.md not found at $skill_md"
        FAIL=$((FAIL+1))
        return
    fi
    PASS=$((PASS+1))
    echo "  ✅ SKILL.md exists"

    # Rule 2
    if ! head -1 "$skill_md" | grep -qE '^---[[:space:]]*$'; then
        echo "  ❌ Missing leading '---' (no YAML frontmatter)"
        FAIL=$((FAIL+1))
        return
    fi
    PASS=$((PASS+1))
    echo "  ✅ YAML frontmatter delimiter present"

    # Extract frontmatter (between first two --- lines, flat keys only)
    local fm
    fm=$(awk 'BEGIN{c=0} /^---[[:space:]]*$/{c++; if(c==2)exit; next} c==1' "$skill_md")

    # Rule 3: ALLOWED_PROPERTIES whitelist
    local allowed="name description license allowed-tools metadata compatibility"
    local unexpected=""
    local key
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        case " $allowed " in
            *" $key "*) ;;
            *) unexpected="$unexpected $key" ;;
        esac
    done < <(echo "$fm" | awk -F: '/^[a-zA-Z][a-zA-Z0-9_-]*:/ {print $1}')
    if [ -n "$unexpected" ]; then
        echo "  ❌ Unexpected top-level keys in SKILL.md frontmatter:$unexpected"
        echo "     Allowed: $allowed"
        FAIL=$((FAIL+1))
    else
        PASS=$((PASS+1))
        echo "  ✅ All top-level keys ∈ ALLOWED_PROPERTIES"
    fi

    # Rule 4: name
    local name
    name=$(echo "$fm" | awk '/^name:/ {sub(/^name:[[:space:]]*/, ""); print; exit}')
    if [ -z "$name" ]; then
        echo "  ❌ Missing required 'name' field"
        FAIL=$((FAIL+1))
    else
        local name_ok=1
        if ! echo "$name" | grep -qE '^[a-z0-9-]+$'; then name_ok=0; fi
        if echo "$name" | grep -qE '^-|-$|--'; then name_ok=0; fi
        if [ ${#name} -gt 64 ]; then name_ok=0; fi
        if [ "$name_ok" = "1" ]; then
            PASS=$((PASS+1))
            echo "  ✅ name='$name' valid (kebab-case, ≤64 chars)"
        else
            echo "  ❌ name='$name' invalid: must be kebab-case ^[a-z0-9-]+\$, no leading/trailing/double hyphen, ≤64 chars"
            FAIL=$((FAIL+1))
        fi
    fi

    # Rule 5: description
    local desc
    desc=$(echo "$fm" | awk '/^description:/ {sub(/^description:[[:space:]]*/, ""); print; exit}')
    if [ -z "$desc" ]; then
        echo "  ❌ Missing required 'description' field"
        FAIL=$((FAIL+1))
    else
        local desc_ok=1
        if echo "$desc" | grep -qE '<|>'; then desc_ok=0; fi
        if [ ${#desc} -gt 1024 ]; then desc_ok=0; fi
        if [ "$desc_ok" = "1" ]; then
            PASS=$((PASS+1))
            echo "  ✅ description valid (no angle brackets, ${#desc} chars ≤1024)"
        else
            echo "  ❌ description invalid: angle brackets forbidden, ≤1024 chars (got ${#desc} chars)"
            FAIL=$((FAIL+1))
        fi
    fi

    # Rule 6: compatibility (optional)
    local compat
    compat=$(echo "$fm" | awk '/^compatibility:/ {sub(/^compatibility:[[:space:]]*/, ""); print; exit}')
    if [ -n "$compat" ]; then
        if [ ${#compat} -le 500 ]; then
            PASS=$((PASS+1))
            echo "  ✅ compatibility present, ${#compat} chars ≤500"
        else
            echo "  ❌ compatibility too long (${#compat} chars > 500 max)"
            FAIL=$((FAIL+1))
        fi
    fi

    # v1.4.0: official Python cross-check (advisory only — bash inline above
    # remains primary enforcement). If PyYAML is available + vendored
    # quick_validate.py is present, also run it; disagreement → ADVISORY.
    # This catches block-scalar / multiline YAML edge cases bash inline can't
    # parse, without changing the PASS/FAIL audit numbers.
    local _qv="$PROJECT_ROOT/scripts/vendored/skill-creator/scripts/quick_validate.py"
    if [ -f "$_qv" ] && python3 -c "import yaml" >/dev/null 2>&1; then
        if python3 "$_qv" "$PROJECT_ROOT/skills/$SKILL_NAME" >/dev/null 2>&1; then
            echo "  ✅ official quick_validate.py cross-validates"
            PASS=$((PASS+1))
        else
            local _qv_err
            _qv_err=$(python3 "$_qv" "$PROJECT_ROOT/skills/$SKILL_NAME" 2>&1 | head -1)
            echo "  ⚠️  official quick_validate.py disagrees with bash inline: $_qv_err"
            ADVISORY=$((ADVISORY+1))
        fi
    fi
}
_track_start "§0_spec"
audit_section_0_spec
_track_end "§0_spec"
echo ""

# --- §0b INSTALL.md + install.sh 统一标准合规 (v1.5.0) ---
# Enforces the TKX unified install standard:
#   (a) INSTALL.md follows the 8-section EN schema (references/INSTALL_TEMPLATE_STANDARD.md)
#   (b) install.sh sources scripts/lib/install-output-style.sh (helper not bypassed)
audit_section_0_install_standard() {
echo "§0b. INSTALL.md + install.sh 统一标准 (v1.5.0)"
# INSTALL.md schema: soft-warn (TKX skills aspire to this; fixture / new
# projects without it ship anyway but get visible ⚠️). install.sh helper
# usage: hard-check when a unified helper file ships in the bundle (the
# skill claims standard conformance and is held to it). When the bundle
# does not ship the helper, install.sh checks are skipped — that is the
# "legacy skill or fixture project" path.
local install_md="$DIR/INSTALL.md"
if [ ! -f "$install_md" ]; then
    warn "INSTALL.md present in release dir" test -f "$install_md"
else
    # (a) 9 numbered headings + EN em-dash title + ToC — all soft-warn
    warn "INSTALL.md title is '# INSTALL —' (em-dash, EN standard)" \
        grep -qE "^# INSTALL —" "$install_md"
    warn "INSTALL.md has 📖 Table of Contents" \
        grep -qE "^## 📖 Table of Contents" "$install_md"
    local required_headings=(
        "^## 0\. File location cheat sheet"
        "^## 1\. Install"
        "^## 2\. First-time project initialization"
        "^## 3\. Upgrade"
        "^## 4\. Uninstall"
        "^## 5\. Verify"
        "^## 6\. Release"
        "^## 7\. Daily maintenance commands"
        "^## 8\. Troubleshooting"
    )
    local h disp
    for h in "${required_headings[@]}"; do
        # Strip regex anchors + escape backslashes for human-readable warn message:
        #   '^## 0\. File location cheat sheet' → '0. File location cheat sheet'
        disp="${h#^## }"
        disp="${disp//\\./.}"
        warn "INSTALL.md heading present: $disp" \
            grep -qE "$h" "$install_md"
    done
fi
# (b) install.sh — only enforce helper-usage when the install bundle
# ships scripts/lib/install-output-style.sh (skill opted into the standard).
local install_sh="$DIR/install.sh"
local helper="$DIR/scripts/lib/install-output-style.sh"
if [ -f "$install_sh" ] && [ -f "$helper" ]; then
    check "install.sh sources install-output-style.sh helper" \
        grep -qE "source[[:space:]]+.*install-output-style\.sh" "$install_sh"
    check "install.sh calls install_banner_top" \
        grep -q "install_banner_top" "$install_sh"
    check "install.sh calls install_checkpoint" \
        grep -q "install_checkpoint" "$install_sh"
    check "install.sh calls install_banner_bottom" \
        grep -q "install_banner_bottom" "$install_sh"
elif [ -f "$install_sh" ]; then
    warn "install.sh present but scripts/lib/install-output-style.sh not shipped — standard enforcement skipped" \
        test -f "$helper"
fi
}
_track_start "§0_install_standard"
audit_section_0_install_standard
_track_end "§0_install_standard"
echo ""

# --- §0c gitx-init template integrity (v1.6.0) ---
# Enforces gitx-init dual-source + reference templates present + valid.
# Hard-checks only fire when the release bundle ships scripts/gitx-init.sh
# (i.e. the skill version supports gitx-init); legacy / fixture skills
# without gitx-init are skipped silently.
audit_section_0_gitx_init() {
echo "§0c. gitx-init template integrity (v1.6.0)"
local init_sh="$DIR/scripts/gitx-init.sh"
if [ ! -f "$init_sh" ]; then
    warn "gitx-init present in release bundle (v1.6.0+ feature)" test -f "$init_sh"
    return 0
fi
check "gitx-init wrapper is executable" test -x "$init_sh"
check "gitx-init wrapper has bash shebang" \
    bash -c "head -1 '$init_sh' | grep -qE '^#!.*/bash$'"
local refs="$DIR/references/gitx-init"
check "references/gitx-init/ propagated to release bundle" test -d "$refs"
if [ -d "$refs" ]; then
    local templates=(
        "policy.template.md"
        "RELEASE_GUIDELINE.template.md"
        "scenarios/skill-flow.template.md"
        "scenarios/mac-flow.template.md"
    )
    local t
    for t in "${templates[@]}"; do
        check "references/gitx-init/$t exists + non-empty" test -s "$refs/$t"
        check "references/gitx-init/$t has at least one {{...}} placeholder" \
            grep -qE '\{\{[A-Z_]+\}\}' "$refs/$t"
    done
fi
local shim="$DIR/commands/gitx-init.md"
check "commands/gitx-init.md slash shim present" test -f "$shim"
}
_track_start "§0c_gitx_init"
audit_section_0_gitx_init
_track_end "§0c_gitx_init"
echo ""

# --- §0d gitx-sop template integrity (v1.7.0) ---
# Enforces gitx-sop generate-only SOP template present + valid. Hard-checks
# only fire when the release bundle ships scripts/gitx-sop.sh; legacy /
# fixture skills without gitx-sop are skipped silently.
audit_section_0_gitx_sop() {
echo "§0d. gitx-sop template integrity (v1.7.0)"
local sop_sh="$DIR/scripts/gitx-sop.sh"
if [ ! -f "$sop_sh" ]; then
    warn "gitx-sop present in release bundle (v1.7.0+ feature)" test -f "$sop_sh"
    return 0
fi
check "gitx-sop wrapper is executable" test -x "$sop_sh"
check "gitx-sop wrapper has bash shebang" \
    bash -c "head -1 '$sop_sh' | grep -qE '^#!.*/bash$'"
local tpl="$DIR/references/gitx-sop/GITHUB_RELEASE_SOP.template.md"
check "references/gitx-sop/ template propagated to release bundle" test -s "$tpl"
check "references/gitx-sop/ template has at least one {{...}} placeholder" \
    grep -qE '\{\{[A-Z_]+\}\}' "$tpl"
local shim="$DIR/commands/gitx-sop.md"
check "commands/gitx-sop.md slash shim present" test -f "$shim"
}
_track_start "§0d_gitx_sop"
audit_section_0_gitx_sop
_track_end "§0d_gitx_sop"
echo ""

# --- §0e doc version-rot guard (v1.7.2) ---
# Root cause of the v0.9.x README/ROADMAP rot: docs hardcoded a version
# inside "当前 Scope" / "当前状态" claims and VERSION bumps never synced
# them, with no gate catching it. Invariant: those sections stay
# version-agnostic (defer to VERSION / CHANGELOG). A "当前 Scope" or
# "当前状态" line that pins a vN token = stale by construction → FAIL.
audit_section_0_doc_version_rot() {
echo "§0e. doc version-rot guard (v1.7.2)"
local rot='(当前 Scope|当前状态)[^|]*v[0-9]'
local f
for f in "$DIR/README.md" "$DIR/ROADMAP.md"; do
    [ -f "$f" ] || continue
    check "$(basename "$f") scope/status is version-agnostic (no pinned vN)" \
        bash -c "! grep -qE '$rot' '$f'"
done
}
_track_start "§0e_doc_rot"
audit_section_0_doc_version_rot
_track_end "§0e_doc_rot"
echo ""

# --- §0f doc numeric-rot guard (v1.9.8) ---
# Root cause: README cited the Deep-Audit count in THREE places (shields
# badge `deep audit-N/0/1`, prose `~N checks`, status table `N PASS`); a
# release bumped one and not the others (badge said 227 while reality was
# 228) — §0e only catches version *strings*, not these semantic numbers,
# so it rotted silently. Generic invariant for ANY project releasing via
# gitx-release: all README Deep-Audit citations MUST agree, and a public
# README must never advertise a non-green audit (FAIL must be 0). Exact
# == live-total is enforced per-repo at release time (a stronger local
# test); §0f is the always-on cross-project consistency floor.
audit_section_0_doc_numeric_rot() {
echo "§0f. doc numeric-rot guard (v1.9.8)"
local rf="$DIR/README.md"
# Generic-safe: a project with no README, or a README that does not
# advertise a Deep-Audit count, has nothing to numeric-rot → SKIP, never
# FAIL. (A FAIL here would break every minimal/fixture project that
# releases via gitx-release — exactly what this guard must not do.)
if [ ! -f "$rf" ]; then
    echo "  ➖ no README.md — numeric-rot guard not applicable"; SKIP=$((SKIP+1)); return
fi
# errexit/pipefail-safe: under `set -euo pipefail` a grep with zero
# matches exits 1 and would abort the WHOLE audit (this exact bug failed
# the smoke fixture, which has no Deep-Audit citations). Each grep is
# `|| true`-guarded so the brace group always exits 0 — same robustness
# idiom §0e uses (`bash -c "! grep ..."`).
local nums
nums=$( {
    grep -oE 'deep%20audit-[0-9]+%2F[0-9]+%2F[0-9]+' "$rf" 2>/dev/null \
        | grep -oE '^deep%20audit-[0-9]+' | grep -oE '[0-9]+$' || true
    grep -oE '[0-9]+ checks' "$rf" 2>/dev/null | grep -oE '^[0-9]+' || true
    grep -oE '[0-9]+ PASS' "$rf" 2>/dev/null | grep -oE '^[0-9]+' || true
} | sort -u || true )
if [ -z "$nums" ]; then
    echo "  ➖ README cites no Deep-Audit count — numeric-rot guard not applicable"; SKIP=$((SKIP+1)); return
fi
# README DOES advertise an audit count → enforce the invariants.
if [ "$(printf '%s\n' "$nums" | grep -c .)" -le 1 ]; then
    check "README Deep-Audit citations agree (badge=prose=table)" true
else
    check "README Deep-Audit citations agree (badge=prose=table) — got: $(printf '%s' "$nums" | tr '\n' ' ')" false
fi
check "README does not advertise a non-green Deep Audit (0 FAIL)" \
    bash -c "! grep -qE '[1-9][0-9]* FAIL' '$rf'"
}
_track_start "§0f_doc_numeric_rot"
audit_section_0_doc_numeric_rot
_track_end "§0f_doc_numeric_rot"
echo ""

# --- §0g readme-sync guard (v1.10.0) ---
# Defense-in-depth partner of gitx-readme (Gotcha #46): generation alone
# can ship a stale README if a release forgot to re-run it. No
# gitx-readme.sh in the bundle (legacy/fixture) → warn advisory (mirrors
# §0d, non-FAIL). A source README without gitx:managed markers → SKIP
# (Gotcha #51). errexit-safe: grep is guarded inside if-conditions (errexit-exempt).
audit_section_0_readme_sync() {
echo "§0g. readme-sync guard (v1.10.0)"
# Static "shipped" checks target $DIR (these ARE in the public bundle:
# scripts/ + references/ are staged by release.sh).
local gr="$DIR/scripts/gitx-readme.sh"
if [ ! -f "$gr" ]; then
    warn "gitx-readme present in release bundle (v1.10.0+ feature)" test -f "$gr"
    return 0
fi
check "gitx-readme wrapper is executable" test -x "$gr"
check "gitx-readme wrapper has bash shebang" \
    bash -c 'head -1 "$1" | grep -qE "^#!.*/bash$"' _ "$gr"
# Satisfied via the dual-tree skill-side copy: release.sh:704-705 does
# cp -R skills/gitx-release/references → $DIR/references (codex-HIGH fix;
# root references/ is the dev copy, skill tree is what ships).
check "references/readme/ template propagated to release bundle" \
    test -s "$DIR/references/readme/README.template.md"
# Tacit#3 DECLARED DEVIATION from the §0d/§0f $DIR convention: gitx-readme's
# ground truths (tests/ → suite-count, Release/CHANGELOG.md → whats-new,
# .claude-plugin/ → install) are SOURCE-TREE artifacts deliberately
# excluded from the public bundle (release.sh rsync --exclude='Release';
# tests/ & .claude-plugin/ not staged — verified on disk). Running --check
# inside $DIR resolves suite-count→0 / whats-new→empty → deterministic
# false-FAIL (round-2 NEW-C1). The ghostwriter's subject IS the source
# README; the bundle copy is byte-derived. So verify the SOURCE tree.
local rf="$PROJECT_ROOT/README.md"
if [ ! -f "$rf" ] || ! grep -qF '<!-- gitx:managed:' "$rf" 2>/dev/null; then
    echo "  ➖ source README has no gitx:managed regions — readme-sync not applicable"
    SKIP=$((SKIP+1)); return 0
fi
if ( cd "$PROJECT_ROOT" && bash "$PROJECT_ROOT/scripts/gitx-readme.sh" --check >/dev/null 2>&1 ); then
    check "source README managed regions in sync (gitx-readme --check)" true
else
    check "source README managed regions in sync (gitx-readme --check) — run: gitx-readme" false
fi
}
_track_start "§0g_readme_sync"
audit_section_0_readme_sync
_track_end "§0g_readme_sync"
echo ""

# --- §0h central-install guard (v1.10.0) ---
# Boss requirement: every gitx-released skill advertises the central
# marketplace so users have one canonical install. Generic-safe: a
# non-plugin project (no .claude-plugin/plugin.json) or no README cannot
# use it → SKIP, never FAIL (Gotcha #51). errexit-safe greps.
audit_section_0_central_install() {
echo "§0h. central-install guard (v1.10.0)"
# Tacit#3 DECLARED DEVIATION (same root cause as §0g, round-2 NEW-C1):
# .claude-plugin/ is NOT staged into the public bundle (verified absent in
# Release/<name>-<ver>/). The central-install advertisement is a property
# of the SOURCE README + source manifest; verify the source tree.
local pj="$PROJECT_ROOT/.claude-plugin/plugin.json" rf="$PROJECT_ROOT/README.md"
if [ ! -f "$pj" ] || [ ! -f "$rf" ]; then
    echo "  ➖ no plugin.json or README — central-install not applicable"
    SKIP=$((SKIP+1)); return 0
fi
local name
name="$(grep -m1 '"name"' "$pj" 2>/dev/null | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
check "README advertises central marketplace add" \
    grep -qF '/plugin marketplace add tkxlab-ai/marketplace' "$rf"
check "README advertises central plugin install (${name}@tkx-skills)" \
    grep -qF "/plugin install ${name}@tkx-skills" "$rf"
}
_track_start "§0h_central_install"
audit_section_0_central_install
_track_end "§0h_central_install"
echo ""

# --- §1 基础存在性 ---
audit_section_1_basics() {
echo "§1. 基础存在性"
check "Release 目录存在"           test -d "$DIR"
check ".skill 文件存在"             test -f "$DIR/$SKILL_FILE"
check "source tarball 存在"         test -f "$DIR/$TAR_FILE"

}
_track_start "§1_basics"
audit_section_1_basics
_track_end "§1_basics"
echo ""

# --- §2 平摊文档 + install.sh ---
audit_section_2_docs() {
echo "§2. 平摊文档存在"
# v1.3.2 A2 fix: TEST-SCENARIOS.md 改 soft-warn 让新项目 onboarding 不被这一项
# block。REQUIRED-for-self-bake 列表保持硬 FAIL；TEST-SCENARIOS.md 是推荐文档
# （描述 skill 的测试场景），缺失只是 quality 下滑而非合规失败。mac-release
# v0.1.0 self-bake 第一次撞这关导致额外打通成本（详 Dev Log 2026-05-07 19:16）。
for f in README.md INSTALL.md CHANGELOG.md LICENSE CONTRIBUTING.md SKILL.md RELEASE_NOTES.md install.sh; do
    check "$f 平摊（REQUIRED）"  test -f "$DIR/$f"
done
warn "TEST-SCENARIOS.md 平摊（推荐，非硬性）"  test -f "$DIR/TEST-SCENARIOS.md"
check "install.sh 可执行" test -x "$DIR/install.sh"

}
_track_start "§2_docs"
audit_section_2_docs
_track_end "§2_docs"
echo ""

# --- §2b 平摊文档内容质量（开源项目标准）---
audit_section_2b_doc_quality() {
echo "§2b. 平摊文档内容质量"

# README.md
if [ -f "$DIR/README.md" ]; then
    check "README.md 有一级标题"        grep -q "^# " "$DIR/README.md"
    check "README.md 非空（>10行）"     test "$(wc -l < "$DIR/README.md")" -gt 10
    warn  "README.md 有安装说明"        grep -qiE "^#{1,3} .*(install|安装)" "$DIR/README.md"
    warn  "README.md 有使用说明"        grep -qiE "^#{1,3} .*(usage|使用|快速|quick|命令|command)" "$DIR/README.md"
    warn  "README.md 有 License 声明"   grep -qiE "(license|许可|mit|apache|gpl)" "$DIR/README.md"
fi

# LICENSE
if [ -f "$DIR/LICENSE" ]; then
    check "LICENSE 非空（>5行）"        test "$(wc -l < "$DIR/LICENSE")" -gt 5
    check "LICENSE 含许可证类型"        grep -qiE "^(MIT|Apache|GNU|BSD|ISC|MPL)" "$DIR/LICENSE"
    check "LICENSE 含 Copyright"        grep -q "Copyright" "$DIR/LICENSE"
    check "LICENSE 含版权年份"          grep -qE "Copyright.*20[0-9]{2}" "$DIR/LICENSE"
    check "LICENSE 含 Permission"       grep -q "Permission" "$DIR/LICENSE"
fi

# CONTRIBUTING.md
if [ -f "$DIR/CONTRIBUTING.md" ]; then
    check "CONTRIBUTING.md 有一级标题"  grep -q "^# " "$DIR/CONTRIBUTING.md"
    check "CONTRIBUTING.md 非空（>5行）" test "$(wc -l < "$DIR/CONTRIBUTING.md")" -gt 5
    warn  "CONTRIBUTING.md 有开发说明"  grep -qiE "^#{1,3} .*(开发|develop|setup|build|run|test)" "$DIR/CONTRIBUTING.md"
fi

# RELEASE_NOTES.md
if [ -f "$DIR/RELEASE_NOTES.md" ]; then
    check "RELEASE_NOTES.md 有一级标题" grep -q "^# " "$DIR/RELEASE_NOTES.md"
    check "RELEASE_NOTES.md 含发版版本" grep -q "$SAFE_VERSION" "$DIR/RELEASE_NOTES.md"
    check "RELEASE_NOTES.md 含发版日期" grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}" "$DIR/RELEASE_NOTES.md"
    check "RELEASE_NOTES.md 含方式 A"   grep -q "install.sh" "$DIR/RELEASE_NOTES.md"
    check "RELEASE_NOTES.md 含方式 C"   grep -q "tar xzf\|tar -xzf" "$DIR/RELEASE_NOTES.md"
fi

# INSTALL.md
if [ -f "$DIR/INSTALL.md" ]; then
    check "INSTALL.md 有一级标题"       grep -q "^# " "$DIR/INSTALL.md"
    check "INSTALL.md 非空（>10行）"    test "$(wc -l < "$DIR/INSTALL.md")" -gt 10
    warn  "INSTALL.md 有卸载说明"       grep -qiE "(uninstall|卸载)" "$DIR/INSTALL.md"
    warn  "INSTALL.md 有升级说明"       grep -qiE "(upgrade|update|升级)" "$DIR/INSTALL.md"
fi

# TEST-SCENARIOS.md
if [ -f "$DIR/TEST-SCENARIOS.md" ]; then
    check "TEST-SCENARIOS.md 有一级标题" grep -q "^# " "$DIR/TEST-SCENARIOS.md"
    check "TEST-SCENARIOS.md 非空（>5行）" test "$(wc -l < "$DIR/TEST-SCENARIOS.md")" -gt 5
fi

# SKILL.md (flattenend)
if [ -f "$DIR/SKILL.md" ]; then
    check "SKILL.md 有一级标题"          grep -q "^# " "$DIR/SKILL.md"
    # v1.4.0 A3: keyword scan lists explicitly documented for skill authors.
    # Trigger section: 中英任一即可 — 触发 / trigger / when / 何时
    check "SKILL.md 有触发条件说明"      grep -qiE "^#{1,3} .*(触发|trigger|when|何时)" "$DIR/SKILL.md"
    # Execution flow section: 中英任一即可 — 流程 / 执行 / 步骤 / step /
    #   execution / workflow / pipeline / process / how to use / usage
    check "SKILL.md 有执行流程说明"      grep -qiE "^#{1,3} .*(流程|执行|步骤|step|execution|workflow|pipeline|process|how to use|usage)" "$DIR/SKILL.md"
    check "SKILL.md 非空（>20行）"       test "$(wc -l < "$DIR/SKILL.md")" -gt 20
fi

}
_track_start "§2b_quality"
audit_section_2b_doc_quality
_track_end "§2b_quality"
echo ""

# --- §3 平摊文档与根同步 ---
audit_section_3_sync() {
echo "§3. 平摊文档与根目录同步"
for f in README.md INSTALL.md TEST-SCENARIOS.md LICENSE CONTRIBUTING.md; do
    if [ -f "$PROJECT_ROOT/$f" ] && [ -f "$DIR/$f" ]; then
        check "$f 与根目录 diff clean"   diff -q "$DIR/$f" "$PROJECT_ROOT/$f"
    else
        echo "  ➖ $f 缺失，跳过 diff"
        SKIP=$((SKIP+1))
    fi
done
if [ -f "$PROJECT_ROOT/Release/CHANGELOG.md" ] && [ -f "$DIR/CHANGELOG.md" ]; then
    check "CHANGELOG.md 与 Release/CHANGELOG.md 一致"   diff -q "$DIR/CHANGELOG.md" "$PROJECT_ROOT/Release/CHANGELOG.md"
else
    echo "  ➖ CHANGELOG.md 缺失，跳过 diff"
    SKIP=$((SKIP+1))
fi
if [ -f "$PROJECT_ROOT/skills/$SKILL_NAME/SKILL.md" ] && [ -f "$DIR/SKILL.md" ]; then
    check "SKILL.md 与 bundle 一致"  diff -q "$DIR/SKILL.md" "$PROJECT_ROOT/skills/$SKILL_NAME/SKILL.md"
fi
}

# --- §4 CHANGELOG 真实性 ---
audit_section_4_changelog() {
echo "§4. CHANGELOG 真实性"
if [ -f "$DIR/CHANGELOG.md" ]; then
    first_ver_line=$(grep "^## " "$DIR/CHANGELOG.md" | head -1)
    if echo "$first_ver_line" | grep -qF "## $VERSION "; then
        echo "  ✅ 顶部版本号 = $VERSION"
        PASS=$((PASS+1))
    else
        # v1.1.7 (Gotcha #32): wrap bare $first_ver_line in {} so adjacent Chinese
        # full-width 括号 isn't mis-parsed into the variable name under set -u.
        echo "  ❌ 顶部版本号 ≠ ${VERSION}（顶部为: ${first_ver_line}）"
        FAIL=$((FAIL+1))
    fi
    check_not "无 TODO 占位"         grep -q "<!-- TODO" "$DIR/CHANGELOG.md"
    entry=$(awk "/^## $SAFE_VERSION /,/^---$/" "$DIR/CHANGELOG.md")
    check_not "本版本条目非空"        test -z "$entry"
fi
}

# --- §3 平摊文档与根同步 ---
_track_start "§3_sync"
audit_section_3_sync
_track_end "§3_sync"
echo ""

# --- §4 CHANGELOG 真实性 ---
_track_start "§4_changelog"
audit_section_4_changelog
_track_end "§4_changelog"
echo ""

# --- §5 Tarball 内容 ---
audit_section_5_tarball() {
echo "§5. Source tarball 内容"
if [ -f "$DIR/$TAR_FILE" ]; then
    # v1.0.8 hardening (Sec Minor #4): use name-mangled _S5_LIST so the
    # global RETURN trap can't accidentally fire on an unrelated LIST var
    # in a future audit function. Trap is cleared at end of this function.
    _S5_LIST=$(mktemp)
    LIST="$_S5_LIST"   # back-compat alias; existing checks reference $LIST
    trap 'rm -f "${_S5_LIST:-}"' RETURN
    tar tzf "$DIR/$TAR_FILE" > "$LIST" 2>/dev/null
    check "含 install.sh"            grep -q "install.sh" "$LIST"
    check "含 README.md"              grep -q "README.md" "$LIST"
    # v0.9.7 (self-review F1): flat-layout projects (SKILL.md at root) use
    # skills/<name>/ as an internal self-release mirror that release.sh
    # deliberately excludes from the tarball. For those projects, tarball
    # should have root-level scripts/ + SKILL.md instead of a skills/ tree.
    if [ -f "$PROJECT_ROOT/SKILL.md" ]; then
        check "含 SKILL.md (flat layout)" grep -qE "^[^/]+/SKILL\.md$" "$LIST"
        check "含 scripts/ 目录 (flat layout)" grep -qE "^[^/]+/scripts/" "$LIST"
    else
        check "含 skills/ 目录"          grep -q "skills/${SKILL_NAME}/" "$LIST"
    fi
    check "含 tests/ 目录"            grep -q "tests/" "$LIST"
    # Bug #10 fix: if skill bundle has commands/, tarball must contain it too
    if [ -d "$PROJECT_ROOT/skills/$SKILL_NAME/commands" ] && [ ! -f "$PROJECT_ROOT/SKILL.md" ]; then
        check "含 skills/${SKILL_NAME}/commands/" grep -q "skills/${SKILL_NAME}/commands/" "$LIST"
    fi
    check_not "不含 Release/"        grep -qE "^${PROJECT_NAME}-${VERSION}/Release/" "$LIST"
    check_not "不含 *-workspace"     grep -qE "/${SKILL_NAME}-workspace(/|$)" "$LIST"
    check_not "不含 settings.local"  grep -q "settings.local" "$LIST"
    check_not "不含 .DS_Store"       grep -q "\.DS_Store" "$LIST"
    check_not "不含 *.bak"           grep -qE "\.bak($|/)" "$LIST"
    # Bug #7 fix: detect stray extracted tarball dirs (e.g. handoff-v0.9.5/ leaked from project root)
    check_not "不含 stray <proj>-v* 目录" grep -qE "^${PROJECT_NAME}-${VERSION}/${PROJECT_NAME}-v[0-9]" "$LIST"
    # Bug #9 fix: detect memory/ dir leak (project-level AI session memory, not distributable)
    check_not "不含 memory/ 目录"        grep -qE "^${PROJECT_NAME}-${VERSION}/memory/" "$LIST"
    # Bug #13 fix: HANDOFF.md / HANDOFF.archive.md are project-private, must not be distributed
    check_not "不含 HANDOFF.md"          grep -qE "^${PROJECT_NAME}-${VERSION}/HANDOFF\.md$" "$LIST"
    check_not "不含 HANDOFF.archive.md"  grep -qE "^${PROJECT_NAME}-${VERSION}/HANDOFF\.archive\.md$" "$LIST"
    # v1.9.6 (codex P2): handoff v2 working memory — prevention (release.sh
    # --exclude) AND detection. A stale/external tarball carrying any of
    # these must fail-closed here, same contract as HANDOFF.md above.
    check_not "不含 handoff v2 工作记忆" \
        grep -qE "^${PROJECT_NAME}-${VERSION}/(GOTCHAS\.md$|Handoff_Logs/|Handoff_Logs\.archive/|Handoff_Decisions/|HANDOFF\.md\.bak$|HANDOFF\.md\.pre-v2-backup$)" "$LIST"
    check_not "不含 private local state dotdirs" \
        grep -qE "^${PROJECT_NAME}-${VERSION}/(\.1by1/|\.i18n-cache/|\.cache/|\.ssh/|\.aws/|\.env[^/]*|\.python-version|\.github-publish-wt/)" "$LIST"
    rm -f "$LIST"
    trap - RETURN   # clear the §5-scoped RETURN trap before leaving the function
fi

}
_track_start "§5_tarball"
audit_section_5_tarball
_track_end "§5_tarball"
echo ""

# --- §6b .skill bundle 内容质量（开源标准）---
# P1-2: Moved BEFORE §6 which calls it, for code readability and
# to avoid confusing refactors. Bash allows "use before define" but
# explicit ordering is better practice.
audit_section_6b_bundle_quality() {
local TMP="$1"
if [ -d "$TMP/$SKILL_NAME" ]; then
    echo "  --- §6b. Skill bundle 内容质量 ---"

    # SKILL.md 内容
    if [ -f "$TMP/$SKILL_NAME/SKILL.md" ]; then
        check "  SKILL.md 有一级标题"        grep -q "^# " "$TMP/$SKILL_NAME/SKILL.md"
        check "  SKILL.md 非空（>20行）"     test "$(wc -l < "$TMP/$SKILL_NAME/SKILL.md")" -gt 20
        warn  "  SKILL.md 有触发条件说明"    grep -qiE "^#{1,3} .*(触发|trigger|when|何时)" "$TMP/$SKILL_NAME/SKILL.md"
        # v1.4.0 A3: keyword list synced with §2b doc-quality scan (line 349)
        warn  "  SKILL.md 有执行流程说明"    grep -qiE "^#{1,3} .*(流程|执行|步骤|step|execution|workflow|pipeline|process|how to use|usage)" "$TMP/$SKILL_NAME/SKILL.md"
        if awk '/^---$/{c++; next} c==1 && /^metadata:[[:space:]]*$/{found=1} END{exit found ? 0 : 1}' "$TMP/$SKILL_NAME/SKILL.md"; then
            echo "  ❌ SKILL.md frontmatter 含 Codex 不兼容 metadata: 块"
            FAIL=$((FAIL+1))
        else
            echo "  ✅ SKILL.md frontmatter 无 metadata: 块（Codex loader compatible）"
            PASS=$((PASS+1))
        fi
        desc=$(awk '/^---$/{c++; next} c==1 && /^description:/{sub(/^description:[[:space:]]*/, ""); print; exit}' "$TMP/$SKILL_NAME/SKILL.md")
        if [ -z "$desc" ]; then
            echo "  ❌ SKILL.md description field missing"
            FAIL=$((FAIL+1))
        else
            desc_chars=$(printf '%s' "$desc" | wc -m | tr -d ' ')
            if [ "$desc_chars" -le "$MAX_SKILL_DESCRIPTION_CHARS" ]; then
                echo "  ✅ SKILL.md description <= ${MAX_SKILL_DESCRIPTION_CHARS} chars Codex metadata budget"
                PASS=$((PASS+1))
            else
                echo "  ❌ SKILL.md description ${desc_chars} chars > ${MAX_SKILL_DESCRIPTION_CHARS} Codex metadata budget"
                FAIL=$((FAIL+1))
            fi
        fi
    fi

    # scripts/*.sh — shebang + usage + 执行权限
    if [ -d "$TMP/$SKILL_NAME/scripts" ]; then
        for sh in "$TMP/$SKILL_NAME/scripts/"*.sh; do
            [ -f "$sh" ] || continue
            bn="$(basename "$sh")"
            check "  scripts/$bn 有 shebang"  grep -q "^#!/" "$sh"
            check "  scripts/$bn 有 usage 注释" grep -qiE "^# (usage|用法)" "$sh"
            check "  scripts/$bn 可执行"       test -x "$sh"
        done
    fi

    # references/*.md — 一级标题 + 非空
    if [ -d "$TMP/$SKILL_NAME/references" ]; then
        for ref in "$TMP/$SKILL_NAME/references/"*.md; do
            [ -f "$ref" ] || continue
            bn="$(basename "$ref")"
            check "  references/$bn 有一级标题" grep -q "^# " "$ref"
            check "  references/$bn 非空（>5行）" test "$(wc -l < "$ref")" -gt 5
        done
    fi

    # commands/*.md — description frontmatter + 非空正文
    if [ -d "$TMP/$SKILL_NAME/commands" ]; then
        for cmd in "$TMP/$SKILL_NAME/commands/"*.md; do
            [ -f "$cmd" ] || continue
            bn="$(basename "$cmd")"
            check "  commands/$bn 有 description frontmatter" grep -q "^description:" "$cmd"
            check "  commands/$bn description 非空"           grep -qE "^description: .+" "$cmd"
            check "  commands/$bn 有正文（>3行）"             test "$(wc -l < "$cmd")" -gt 3
        done
    fi

    # Codex $ command selectors — every registered slash command must have
    # an explicit selector manifest entry, and the skill itself must be
    # invokable as $<skill-name>.
    selector_manifest="$TMP/$SKILL_NAME/agents/codex-commands.txt"
    echo "  --- Codex \$ command selectors ---"
    check "  agents/codex-commands.txt 存在" test -f "$selector_manifest"
    if [ -f "$selector_manifest" ]; then
        check "  \$${SKILL_NAME} selector 已注册" grep -qxF "\$$SKILL_NAME" "$selector_manifest"
        if [ -d "$TMP/$SKILL_NAME/commands" ]; then
            for cmd in "$TMP/$SKILL_NAME/commands/"*.md; do
                [ -f "$cmd" ] || continue
                cmd_name="$(basename "$cmd" .md)"
                check "  \$${cmd_name} selector 已注册" grep -qxF "\$$cmd_name" "$selector_manifest"
                cmd_name_lower="$(printf '%s' "$cmd_name" | tr '[:upper:]' '[:lower:]')"
                if [ "$cmd_name_lower" != "$cmd_name" ]; then
                    check "  \$${cmd_name_lower} selector alias 已注册" grep -qxF "\$$cmd_name_lower" "$selector_manifest"
                fi
            done
        fi
    fi

    # assets/ — 至少一个 .md 文件（空目录视为 ➖ 跳过，非空才检查）
    if [ -d "$TMP/$SKILL_NAME/assets" ]; then
        asset_any=$(find "$TMP/$SKILL_NAME/assets" -mindepth 1 -maxdepth 1 | head -1)
        if [ -z "$asset_any" ]; then
            echo "  ➖ assets/ 为空目录，跳过 .md 检查"
            SKIP=$((SKIP+1))
        else
            check "  assets/ 含至少一个 .md" \
                test -n "$(find "$TMP/$SKILL_NAME/assets" -name '*.md' | head -1)"
        fi
    fi
fi
}

# --- §6 .skill 解压与 bundle 对齐 ---
audit_section_6_skill() {
echo "§6. .skill 内容"
if [ -f "$DIR/$SKILL_FILE" ]; then
    TMP=$(mktemp -d)
    # v1.0.8 hardening (Bash #1): under `set -euo pipefail`, a corrupt .skill
    # would abort the script before FAIL increment + summary emit. Wrap unzip
    # in an explicit `if !` so failure is reported as a labelled audit FAIL,
    # the section returns cleanly, and the per-section summary still prints.
    if ! unzip -q "$DIR/$SKILL_FILE" -d "$TMP" 2>/dev/null; then
        echo "  ❌ .skill 损坏，无法解压：$DIR/$SKILL_FILE"
        FAIL=$((FAIL+1))
        rm -rf "$TMP"
        return
    fi
check ".skill 可正常解压"        test -d "$TMP/$SKILL_NAME"
check ".skill 含 SKILL.md"       test -f "$TMP/$SKILL_NAME/SKILL.md"
check ".skill 含 VERSION"        test -f "$TMP/$SKILL_NAME/VERSION"
check ".skill 含 scripts/"       test -d "$TMP/$SKILL_NAME/scripts"
    check ".skill 含 references/"    test -d "$TMP/$SKILL_NAME/references"
    check ".skill 含 assets/"        test -d "$TMP/$SKILL_NAME/assets"
    check ".skill 含 agents/"        test -d "$TMP/$SKILL_NAME/agents"
    # Bug #10 fix: if skill bundle has commands/, .skill must contain it too
    if [ -d "$PROJECT_ROOT/skills/$SKILL_NAME/commands" ]; then
        check ".skill 含 commands/"  test -d "$TMP/$SKILL_NAME/commands"
    fi
    if [ -d "$TMP/$SKILL_NAME" ] && [ -d "$PROJECT_ROOT/skills/$SKILL_NAME" ]; then
        diff_out=$(diff -r "$TMP/$SKILL_NAME" "$PROJECT_ROOT/skills/$SKILL_NAME" 2>&1 \
                   | grep -v evals | grep -v "^Only in.*evals" || true)
        if [ -z "$diff_out" ]; then
            echo "  ✅ .skill 与 skills/$SKILL_NAME/ 一致（除 evals/）"
            PASS=$((PASS+1))
        else
            echo "  ❌ .skill 与 bundle 有差异:"
            echo "$diff_out" | head -5 | sed 's/^/     /'
            FAIL=$((FAIL+1))
        fi
    fi

    # --- §6b .skill bundle 内容质量（开源标准）---
    audit_section_6b_bundle_quality "$TMP"

    rm -rf "$TMP"
fi

}
_track_start "§6_skill"
audit_section_6_skill
_track_end "§6_skill"
echo ""

# --- §7 二次 sanity 扫描 ---
audit_section_7_sanity() {
echo "§7. 平摊文档二次 sanity 扫描"
SANITIZE="$(cd "$(dirname "$0")" && pwd)/release-sanitize.sh"
if [ -x "$SANITIZE" ]; then
    # Provide project-root .sanitize-ignore to the Release dir scan so that
    # intentional exemptions (e.g. SECURITY.md contact email) carry through
    # to the post-release sanity pass without requiring a permanent copy.
    _S7_IGNORE_TMP=""
    if [ -f "$PROJECT_ROOT/.sanitize-ignore" ] && [ ! -f "$DIR/.sanitize-ignore" ]; then
        cp "$PROJECT_ROOT/.sanitize-ignore" "$DIR/.sanitize-ignore"
        _S7_IGNORE_TMP="$DIR/.sanitize-ignore"
    fi
    if bash "$SANITIZE" "$DIR" >/dev/null 2>&1; then
        echo "  ✅ 平摊文档无敏感信息"
        PASS=$((PASS+1))
    else
        echo "  ❌ sanity 扫描发现问题:"
        bash "$SANITIZE" "$DIR" 2>&1 | sed 's/^/     /' | head -20
        FAIL=$((FAIL+1))
    fi
    if [ -n "$_S7_IGNORE_TMP" ]; then rm -f "$_S7_IGNORE_TMP"; fi
else
    echo "  ➖ $SANITIZE 不在，跳过"
    SKIP=$((SKIP+1))
fi

}
_track_start "§7_sanity"
audit_section_7_sanity
_track_end "§7_sanity"
echo ""

# --- §8 Release/latest 软链接 ---
# v0.9.6: Absence is ➖ SKIP (not ❌ FAIL). S1-5 intentionally creates `latest`
# AFTER audit passes (atomic `ln -sf + mv` to keep broken releases invisible),
# so when audit runs inline from release.sh the symlink is expected to be
# missing. The important invariant — "latest never points to a wrong version"
# — is still enforced by the mismatched-target branch below.
# v0.9.7: N+1 scenario — inline audit sees latest pointing to the PREVIOUS
# release (existing directory). Relax to SKIP only in --inline mode and only
# if the target directory still exists. Standalone callers keep strict check.
audit_section_8_latest() {
echo "§8. Release/latest 软链接"
# v0.9.10: expected target is now `${PROJECT_NAME}-${VERSION}`. Legacy bare
# `$VERSION` is accepted when auditing a legacy-layout release dir.
if [ "${LEGACY_LAYOUT:-0}" = "1" ]; then
    EXPECTED_LATEST="$VERSION"
else
    EXPECTED_LATEST="${PROJECT_NAME}-${VERSION}"
fi
if [ -L "$PROJECT_ROOT/Release/latest" ]; then
    latest_target=$(readlink "$PROJECT_ROOT/Release/latest")
    if [ "$latest_target" = "$EXPECTED_LATEST" ]; then
        echo "  ✅ Release/latest → $EXPECTED_LATEST"
        PASS=$((PASS+1))
    elif [ "${INLINE:-0}" = "1" ] && [ -d "$PROJECT_ROOT/Release/$latest_target" ]; then
        echo "  ➖ Release/latest → ${latest_target}（inline audit；release.sh 通过后将更新为 ${EXPECTED_LATEST}）"
        SKIP=$((SKIP+1))
    else
        echo "  ❌ Release/latest → ${latest_target}（应为 ${EXPECTED_LATEST}）"
        FAIL=$((FAIL+1))
    fi
else
    echo "  ➖ Release/latest 尚未创建（release.sh 会在 audit 通过后原子创建）"
    SKIP=$((SKIP+1))
fi

}
_track_start "§8_latest"
audit_section_8_latest
_track_end "§8_latest"
echo ""

# --- §9 双源脚本 byte-identical (v2.3 §8.1 #14) ---
# S3-4: dual-source layout is MANDATORY; missing either side is a hard FAIL,
# not a silent SKIP — byte-identity is the whole policy.
audit_section_9_dual_source() {
echo "§9. 双源脚本一致性（v2.3 policy）"
if [ -d "$PROJECT_ROOT/scripts" ] && [ -d "$PROJECT_ROOT/skills/$SKILL_NAME/scripts" ]; then
    SCRIPTS_ROOT="$PROJECT_ROOT/scripts"
    drift=$(diff -rq "$PROJECT_ROOT/scripts/" "$PROJECT_ROOT/skills/$SKILL_NAME/scripts/" 2>&1 \
            | { while IFS= read -r _ln; do
                    case "$_ln" in
                        "Only in ${SCRIPTS_ROOT}: release-"*) ;;  # root-side release-* only: allowed
                        # scrub-tarball.sh is OPTIONAL project tooling (Gotcha #33, v1.1.7);
                        # see check_dual_source() in scripts/release.sh for rationale.
                        "Only in ${SCRIPTS_ROOT}: scrub-tarball.sh") ;;
                        *) printf '%s\n' "$_ln" ;;
                    esac
                done; } || true)
    if [ -z "$drift" ]; then
        echo "  ✅ 根 scripts/ 与 skill bundle scripts/ byte-identical"
        PASS=$((PASS+1))
    else
        echo "  ❌ 双源脚本漂移:"
        echo "$drift" | sed 's/^/     /'
        FAIL=$((FAIL+1))
    fi
else
    echo "  ❌ 双源结构缺失（S3-4 policy v2.3）"
    echo "     required: \$PROJECT_ROOT/scripts/ AND \$PROJECT_ROOT/skills/$SKILL_NAME/scripts/"
    [ -d "$PROJECT_ROOT/scripts" ] || echo "     missing: \$PROJECT_ROOT/scripts/"
    [ -d "$PROJECT_ROOT/skills/$SKILL_NAME/scripts" ] || echo "     missing: \$PROJECT_ROOT/skills/$SKILL_NAME/scripts/"
    FAIL=$((FAIL+1))
fi

}
_track_start "§9_dual"
audit_section_9_dual_source
_track_end "§9_dual"
echo ""

# --- §10 RELEASE_NOTES 质量（硬门禁）---
# S3-6: hardcoded KB numbers are a decay source (quickly become wrong after any
# repack) — treat as FAIL, not warn.
audit_section_10_release_notes() {
echo "§10. RELEASE_NOTES.md 质量"
if [ -f "$DIR/RELEASE_NOTES.md" ]; then
    if grep -qE '[0-9]+ KB' "$DIR/RELEASE_NOTES.md" 2>/dev/null; then
        echo "  ❌ 含硬编码 KB 数字（易过时 → S3-6 policy 禁止）"
        grep -nE '[0-9]+ KB' "$DIR/RELEASE_NOTES.md" | head -5 | sed 's/^/     /'
        FAIL=$((FAIL+1))
    else
        echo "  ✅ 无硬编码 KB 数字"
        PASS=$((PASS+1))
    fi
    # If skill has commands/, RELEASE_NOTES 方式 B must include commands install step
    if [ -d "$PROJECT_ROOT/skills/$SKILL_NAME/commands" ]; then
        if grep -q "commands" "$DIR/RELEASE_NOTES.md" 2>/dev/null; then
            echo "  ✅ 方式 B 含 commands 安装步骤"
            PASS=$((PASS+1))
        else
            echo "  ❌ 方式 B 缺少 commands 安装步骤（slash shims 装不上）"
            FAIL=$((FAIL+1))
        fi
    fi
fi
}
_track_start "§10_notes"
audit_section_10_release_notes
_track_end "§10_notes"
echo ""

# --- §11 开源合规检查（GitHub 开源项目标准）---
audit_section_11_compliance() {
echo "§11. 开源合规检查"
# §11a: 必要文件齐备（开源四件套）
check "README.md 存在"        test -f "$DIR/README.md"
check "LICENSE 存在"          test -f "$DIR/LICENSE"
check "CONTRIBUTING.md 存在"  test -f "$DIR/CONTRIBUTING.md"
check "CHANGELOG.md 存在"     test -f "$DIR/CHANGELOG.md"

# §11b: LICENSE 合规
if [ -f "$DIR/LICENSE" ]; then
    check "LICENSE 含 SPDX 识别的许可证类型" \
        grep -qiE "^(MIT|Apache License|GNU (General|Lesser|Affero)|BSD [0-9]|ISC|Mozilla Public|Creative Commons)" "$DIR/LICENSE"
    check "LICENSE 含 Copyright 行"   grep -q "Copyright" "$DIR/LICENSE"
    check "LICENSE 含年份"             grep -qE "20[0-9]{2}" "$DIR/LICENSE"
fi

# §11c: README 关键章节
if [ -f "$DIR/README.md" ]; then
    check "README 含项目标题（一级标题）"      grep -q "^# " "$DIR/README.md"
    check "README 含安装章节"                  grep -qiE "^#{1,3} .*(install|安装)" "$DIR/README.md"
    check "README 含使用/快速开始章节"         grep -qiE "^#{1,3} .*(usage|使用|quick.?start|快速|命令|command)" "$DIR/README.md"
    check "README 含 License 声明"             grep -qiE "(license|许可)" "$DIR/README.md"
    check "README 含贡献/Contributing 链接"    grep -qiE "(contribut|贡献)" "$DIR/README.md"
fi

# §11d: CONTRIBUTING.md 关键章节
if [ -f "$DIR/CONTRIBUTING.md" ]; then
    check "CONTRIBUTING 有开发环境说明"   grep -qiE "^#{1,3} .*(开发|develop|setup|environment|环境)" "$DIR/CONTRIBUTING.md"
    check "CONTRIBUTING 有提交/PR 规范"   grep -qiE "(commit|pull.?request|pr |提交|合并)" "$DIR/CONTRIBUTING.md"
fi

# §11e: CHANGELOG 格式合规（Keep a Changelog 风格）
if [ -f "$DIR/CHANGELOG.md" ]; then
    check "CHANGELOG 含版本条目（## vX 格式）" grep -qE "^## v[0-9]" "$DIR/CHANGELOG.md"
    check "CHANGELOG 含日期（YYYY-MM-DD）"      grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}" "$DIR/CHANGELOG.md"
fi

# §11f: 可安装性检查
check "install.sh 存在且可执行"    test -x "$DIR/install.sh"
check "分发包 .skill 存在"         test -f "$DIR/$SKILL_FILE"
check "source tarball 存在"        test -f "$DIR/$TAR_FILE"

# §11g: install.sh §6.10 接口契约验证（Gate #7）
if [ -f "$DIR/install.sh" ]; then
    check "install.sh 支持 --dry-run (§6.10)"  grep -q "\-\-dry-run" "$DIR/install.sh"
    check "install.sh 支持 --force (§6.10)"    grep -q "\-\-force"   "$DIR/install.sh"
    check "install.sh 支持 --help (§6.10)"     grep -q "\-\-help"    "$DIR/install.sh"
else
    echo "  ➖ install.sh 不存在，跳过 §6.10 接口检查"
    SKIP=$((SKIP+3))
fi

# §11h: checksums.txt 完整性（防篡改 / 分发完整性）
if [ -f "$DIR/checksums.txt" ]; then
    check "checksums.txt 存在" test -f "$DIR/checksums.txt"
    check "checksums.txt 覆盖 .skill"     grep -q "\.skill"        "$DIR/checksums.txt"
    check "checksums.txt 覆盖 tarball"    grep -q "source\.tar\.gz" "$DIR/checksums.txt"
    check "checksums.txt 覆盖 install.sh" grep -q "install\.sh"    "$DIR/checksums.txt"
    # Full tarball is built by release.sh after attestations; if the artifact
    # exists in $DIR, checksums.txt MUST cover it. Skip silently when absent
    # (older releases or mid-pipeline standalone audit) to keep this audit
    # backward-compatible with pre-v1.0.7 release dirs.
    if ls "$DIR"/*-full.tar.gz >/dev/null 2>&1; then
        check "checksums.txt 覆盖 full.tar.gz" grep -q "full\.tar\.gz" "$DIR/checksums.txt"
    fi
    # Verify digests match current artifacts.
    if command -v shasum >/dev/null 2>&1; then
        if (cd "$DIR" && shasum -a 256 -c checksums.txt >/dev/null 2>&1); then
            echo "  ✅ checksums.txt 所有 sha256 校验通过"
            PASS=$((PASS+1))
        else
            echo "  ❌ checksums.txt 校验失败（artifact 与 digest 不一致）"
            echo "     详情: $DIR/checksums.txt"
            (cd "$DIR" && shasum -a 256 -c checksums.txt 2>&1 || true) | tail -5 | sed 's/^/     /'
            FAIL=$((FAIL+1))
        fi
    elif command -v sha256sum >/dev/null 2>&1; then
        if (cd "$DIR" && sha256sum -c checksums.txt >/dev/null 2>&1); then
            echo "  ✅ checksums.txt 所有 sha256 校验通过"
            PASS=$((PASS+1))
        else
            echo "  ❌ checksums.txt 校验失败（artifact 与 digest 不一致）"
            echo "     详情: $DIR/checksums.txt"
            (cd "$DIR" && sha256sum -c checksums.txt 2>&1 || true) | tail -5 | sed 's/^/     /'
            FAIL=$((FAIL+1))
        fi
    else
        echo "  ➖ 本机无 shasum/sha256sum，跳过 digest 校验"
        SKIP=$((SKIP+1))
    fi
else
    echo "  ❌ checksums.txt 不存在（分发完整性缺失）"
    FAIL=$((FAIL+1))
fi
echo ""

# §11i: CycloneDX SBOM (v0.9.9 feature D — supply-chain attestation)
if [ -f "$DIR/sbom.cyclonedx.json" ]; then
    check "sbom.cyclonedx.json 存在"            test -f "$DIR/sbom.cyclonedx.json"
    check "SBOM 声明 bomFormat=CycloneDX"       grep -qE '"bomFormat"[[:space:]]*:[[:space:]]*"CycloneDX"' "$DIR/sbom.cyclonedx.json"
    check "SBOM 声明 specVersion=1.x"           grep -qE '"specVersion"[[:space:]]*:[[:space:]]*"1\.[0-9]+"' "$DIR/sbom.cyclonedx.json"
    check "SBOM 声明 metadata.component.version=$VERSION" grep -qE "\"version\"[[:space:]]*:[[:space:]]*\"$SAFE_VERSION\"" "$DIR/sbom.cyclonedx.json"
    check "SBOM 列出 .skill"                    grep -q "\.skill"        "$DIR/sbom.cyclonedx.json"
    check "SBOM 列出 tarball"                   grep -q "source\.tar\.gz" "$DIR/sbom.cyclonedx.json"
    check "SBOM 列出 install.sh"                grep -q "install\.sh"    "$DIR/sbom.cyclonedx.json"
    check "checksums.txt 覆盖 sbom.cyclonedx.json" grep -q "sbom\.cyclonedx\.json" "$DIR/checksums.txt"
else
    echo "  ➖ sbom.cyclonedx.json 不存在，跳过 §11i"
    SKIP=$((SKIP+1))
fi
echo ""

# §11j: TOKEN_USAGE.md — runtime context cost disclosure for end users
# Parity severity with SBOM/checksums: missing = FAIL (this is a commitment
# to transparency about what installing the skill will cost its users).
if [ -f "$DIR/TOKEN_USAGE.md" ]; then
    check "TOKEN_USAGE.md 存在"                    test -f "$DIR/TOKEN_USAGE.md"
    check "TOKEN_USAGE.md 声明标题"                grep -qE '^#[[:space:]]+Token Usage Analysis' "$DIR/TOKEN_USAGE.md"
    check "TOKEN_USAGE.md 标注 SKILL.md 基线"      grep -qiE 'SKILL\.md.*(baseline|always.?loaded)' "$DIR/TOKEN_USAGE.md"
    check "TOKEN_USAGE.md 披露 tokenizer 方法"     grep -qiE 'tokenizer|tiktoken|cl100k|heuristic|±[0-9]+%' "$DIR/TOKEN_USAGE.md"
    check "TOKEN_USAGE.md 场景表有数量级"          awk '/SKILL\.md/ {for(i=1;i<=NF;i++){gsub(/[,|]/,"",$i); if($i~/^[0-9]+$/ && $i+0>=10){found=1}}} END{exit !found}' "$DIR/TOKEN_USAGE.md"
    check "checksums.txt 覆盖 TOKEN_USAGE.md"      grep -q "TOKEN_USAGE\.md" "$DIR/checksums.txt"
else
    # For skill bundles this is a hard FAIL. Detect skill-ness via SKILL.md
    # presence in the flattened release dir.
    if [ -f "$DIR/SKILL.md" ]; then
        check "TOKEN_USAGE.md 存在（skill 必需）"  test -f "$DIR/TOKEN_USAGE.md"
    else
        echo "  ➖ 非 skill 项目，跳过 §11j（TOKEN_USAGE.md 只对 skill 有意义）"
        SKIP=$((SKIP+1))
    fi
fi

# §11k: install.sh dependency check (v1.1.2 — claudemex case)
# Static parse of Release/<ver>/install.sh for "$SELF_DIR/<path>" references
# and verify each path exists in $DIR. Catches the failure mode where an
# install.sh references project-specific files that flatten_docs didn't copy.
# Conservative: only the quoted form is parsed; dynamic paths and heredocs
# are out of scope (best-effort static analysis, not a bash interpreter).
echo ""
echo "§11k. install.sh 依赖完整性 (Codex parser perspective)"
if [ -f "$DIR/install.sh" ]; then
    _INSTALL_DEPS_UNRESOLVED=()
    while IFS= read -r dep; do
        [ -z "$dep" ] && continue
        if [ ! -e "$DIR/$dep" ]; then
            _INSTALL_DEPS_UNRESOLVED+=("$dep")
        fi
    done < <(
        # Strip whole-line + trailing comments BEFORE scanning so a
        # documented example like `# cp "$SELF_DIR/foo.md" ...` doesn't
        # produce a false-positive missing-dep failure (5th-pass review
        # Important #1).
        sed -E 's/[[:space:]]*#.*$//' "$DIR/install.sh" 2>/dev/null \
        | grep -oE '"\$\{?SELF_DIR\}?/[^"]+"' \
        | sed -E 's|^"\$\{?SELF_DIR\}?/||; s|"$||' \
        | grep -v '\$' \
        | sort -u
    )
    # Regex covers both idiomatic bash forms: "$SELF_DIR/..." and
    # "${SELF_DIR}/..." (Important #2). Runtime variable substitutions
    # like "$SELF_DIR/$f" inside for-loops are filtered via `grep -v '$'`
    # — best-effort gate validates literal paths only, which is sufficient
    # to catch the claudemex case (`cp $SELF_DIR/CUSTOM-PROMPT.md`).
    if [ "${#_INSTALL_DEPS_UNRESOLVED[@]}" -eq 0 ]; then
        echo "  ✅ install.sh 依赖检查 — 所有 \$SELF_DIR/ 引用都解析在 release dir"
        PASS=$((PASS+1))
    else
        echo "  ❌ install.sh 依赖缺失 — 用户运行 install.sh 时会 cp/source 失败:"
        for dep in "${_INSTALL_DEPS_UNRESOLVED[@]}"; do
            echo "     - \$SELF_DIR/$dep — not found in $DIR/"
        done
        echo "     修复：把缺失文件加入 .release-flatten 清单 (项目根)，或挪到 skills/<name>/{references,assets}/ 等被 flatten 的子目录"
        FAIL=$((FAIL+1))
    fi
else
    echo "  ➖ install.sh 不存在（不能 audit）"
    SKIP=$((SKIP+1))
fi

}
_track_start "§11_compliance"
audit_section_11_compliance
_track_end "§11_compliance"
echo ""

# --- Summary ---
TOTAL=$((PASS + FAIL + SKIP))

# --- §0i deep-audit-exactness (v1.10.0) — NON-COUNTING meta-gate ---
# I1/Decision 0019: §0f only proves the 3 README citations AGREE; it does
# not prove they equal the LIVE total, so a stale-but-consistent count
# (badge 227 vs real 230) ships undetected on dependent skills. §0i closes
# that generically and non-circularly: the audit is the authority on its
# OWN count, so AFTER totals are final it compares the README-cited
# Deep-Audit number to $TOTAL. To avoid the Gotcha #26 self-counting
# paradox it is NON-COUNTING — it never calls check()/_track (which would
# mutate the very TOTAL it validates); on mismatch it sets EXACTNESS_FAIL=1
# which the final decision honors (same spirit as warn/ADVISORY: can fail
# the build without being a counted check). Generic-safe: no README or no
# cited count → ➖ SKIP, no flag (Gotcha #51). errexit-safe greps.
EXACTNESS_FAIL=0
echo ""
echo "§0i. deep-audit-exactness (v1.10.0, non-counting)"
# Unlike §0g/§0h, §0i CORRECTLY targets $DIR: README.md IS flattened into
# the public bundle (verified present), and §0i's job is to ensure the
# SHIPPED README's advertised Deep-Audit count equals what this audit
# actually computed. Not the NEW-C1 class — no source-only truth involved.
_dai_rf="$DIR/README.md"
if [ ! -f "$_dai_rf" ]; then
    echo "  ➖ no README.md — deep-audit exactness not applicable"
else
    # Mirror §0f's full extraction set: badge + N checks + N PASS.
    # Gotcha #52 (closure): badge-only missed a dependent skill that cited the
    # count only in prose/table — §0f's consistency floor agreed but §0i never
    # set EXACTNESS_FAIL. Now ANY cited number that != TOTAL triggers failure.
    # errexit-safe: every grep is `|| true`-guarded; sort-u deduplicates.
    _dai_nums=$( {
        grep -oE 'deep%20audit-[0-9]+%2F[0-9]+%2F[0-9]+' "$_dai_rf" 2>/dev/null \
            | grep -oE '^deep%20audit-[0-9]+' | grep -oE '[0-9]+$' || true
        grep -oE '[0-9]+ checks' "$_dai_rf" 2>/dev/null | grep -oE '^[0-9]+' || true
        grep -oE '[0-9]+ PASS' "$_dai_rf" 2>/dev/null | grep -oE '^[0-9]+' || true
    } | sort -u || true )
    if [ -z "$_dai_nums" ]; then
        echo "  ➖ README cites no Deep-Audit count — deep-audit exactness not applicable"
    else
        _dai_bad=""
        while IFS= read -r _n; do
            [ -n "$_n" ] || continue
            [ "$_n" = "$TOTAL" ] || _dai_bad="$_dai_bad $_n"
        done <<EOF_DAI
$_dai_nums
EOF_DAI
        if [ -z "$_dai_bad" ]; then
            echo "  ✅ README Deep-Audit citations all == live total ($TOTAL)"
        else
            echo "  ❌ README Deep-Audit citation(s)$_dai_bad != live total ($TOTAL) — update README (gitx-readme manages other facts; this count is §0f/§0i-owned)"
            EXACTNESS_FAIL=1
        fi
    fi
fi

# Per-section summary (P3-2)
echo ""
echo "═══ Per-Section Summary ═══"
echo ""
echo "  Section   |  ✅ PASS  |  ❌ FAIL  |  ➖ SKIP"
echo "  ----------+---------+---------+---------"

while IFS="|" read -r name p f s; do
    [ -z "$name" ] && continue
    t=$((p+f+s))
    [ "$t" -eq 0 ] && continue
    printf "  %-12s | %2d      | %2d      | %2d\n" "$name" "$p" "$f" "$s"
done < "$_SEC_LOG"

printf "  %-12s | %2d      | %2d      | %2d\n" "TOTAL" "$PASS" "$FAIL" "$SKIP"

rm -f "$_SEC_LOG"

echo ""
echo "═══════════════════════════════════════════"
if [ "$FAIL" -eq 0 ] && [ "${EXACTNESS_FAIL:-0}" -eq 0 ]; then
    echo "🎉 Deep Audit PASS  (✅$PASS / ❌$FAIL / ➖$SKIP / ⚠️$ADVISORY total $TOTAL)"
    echo "   上游发布未自动执行；如需发布，请人工复核产物、CHANGELOG 和仓库状态后再操作。"
    exit 0
else
    echo "❌ Deep Audit FAIL  (✅$PASS / ❌$FAIL / ➖$SKIP / ⚠️$ADVISORY total $TOTAL)"
    echo "   修复后重跑 release"
    exit 1
fi
