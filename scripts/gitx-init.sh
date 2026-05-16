#!/bin/bash
# gitx-init.sh — generate .gitx/ policy package + top-level RELEASE_GUIDELINE.md
# in an existing project so its dev-session AI Agent knows how to release.
#
# Auto-detects project type: skill / mac / both / empty. Does NOT scaffold
# project skeleton (skills/<name>/, tests/, Release/) — that is out of scope
# (see references/gitx-init-design.md §11). gitx-init only teaches an
# existing project about GitX conventions.
#
# Usage:
#   gitx-init [--type=auto|skill|mac|both|empty] [--force] [--dry-run] [--help]
#
# Exit:
#   0 success (including dry-run)
#   2 usage error (unknown flag, invalid --type value)
#   3 --type=auto detected empty AND stdin is non-TTY (cannot prompt)
#   4 .gitx/ already exists and --force was not passed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REFS_DIR="$SCRIPT_DIR/../references/gitx-init"

TYPE=auto
DRY_RUN=0
FORCE=0

# detect_project_type — emit "skill" / "mac" / "both" / "" (empty) based on
# filesystem signals in $PWD. Uses `compgen -G` (bash builtin, no pipefail
# trap from Gotcha #36) so it works under `set -euo pipefail`.
detect_project_type() {
    local has_skill=0 has_mac=0
    if compgen -G "skills/*/SKILL.md" >/dev/null 2>&1; then
        has_skill=1
    fi
    if compgen -G "*.xcodeproj" >/dev/null 2>&1 \
       || [ -f Package.swift ] \
       || [ -f src-tauri/Cargo.toml ]; then
        has_mac=1
    fi
    if [ "$has_skill" -eq 1 ] && [ "$has_mac" -eq 1 ]; then
        echo both
    elif [ "$has_skill" -eq 1 ]; then
        echo skill
    elif [ "$has_mac" -eq 1 ]; then
        echo mac
    else
        echo ""
    fi
}

# kebab — normalize an arbitrary string to a Claude Code-safe slug:
# lowercase, every non-[a-z0-9-] → '-', collapse runs, trim ends. A name
# that kebabs to empty (e.g. all-punctuation dir) falls back to 'project'
# so emitted JSON values are never blank. Shared by plugin_name() and
# plugin_repo_name() — both must produce the same [a-z0-9-] guarantee, and
# this also keeps heredoc-interpolated JSON valid for hostile dir names.
kebab() {
    local out
    out="$(printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[^a-z0-9-]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"
    [ -n "$out" ] || out="project"
    printf '%s' "$out"
}

# semver_norm — take raw VERSION-file content and emit a strict semver string.
# Strips a single optional leading 'v', keeps only the first line, and accepts
# ONLY ^MAJOR.MINOR.PATCH(-/+prerelease)?$. Anything else (empty, multiline,
# quotes, injection attempts) falls back to 0.0.0 so the heredoc-emitted JSON
# stays valid — same hostile-input defense class as kebab() for repo names.
# awk 'NR==1' (not grep|head) avoids the pipefail SIGPIPE abort (Gotcha #36).
semver_norm() {
    local first norm
    first="$(printf '%s' "$1" | awk 'NR==1{print; exit}')"
    norm="${first#v}"
    if printf '%s' "$norm" \
        | grep -qxE '[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?'; then
        printf '%s' "$norm"
    else
        printf '0.0.0'
    fi
}

# plugin_name — kebab-cased, lowercased plugin/skill name for the target
# project. If skills/<X>/SKILL.md exists use <X>, else the cwd basename.
# Claude Code's plugin validator only accepts [a-z0-9-].
plugin_name() {
    local raw=""
    local d
    for d in skills/*/SKILL.md; do
        [ -f "$d" ] || continue
        raw="$(basename "$(dirname "$d")")"
        break
    done
    [ -n "$raw" ] || raw="$(basename "$(pwd)")"
    kebab "$raw"
}

# plugin_repo_name — kebab slug for the marketplace github source repo.
# Prefer the origin remote basename (without .git); fall back to the project
# dir basename. Normalized via kebab() so source.repo is always
# tkxlab-ai/<[a-z0-9-]+> and the emitted JSON stays valid even when the dir
# basename or remote name contains spaces/quotes/JSON metacharacters.
plugin_repo_name() {
    local url="" raw=""
    url="$(git remote get-url origin 2>/dev/null || true)"
    if [ -n "$url" ]; then
        url="${url%.git}"
        raw="${url##*[:/]}"
    else
        raw="$(basename "$(pwd)")"
    fi
    kebab "$raw"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            cat <<'EOF'
gitx-init — generate .gitx/ policy package + RELEASE_GUIDELINE.md

Usage:
  gitx-init [--type=auto|skill|mac|both|empty] [--force] [--dry-run] [--help]

Options:
  --type=<value>   Project type. Default: auto.
                   Valid values: auto skill mac both empty.
  --force          Overwrite existing .gitx/ (backs up old to .gitx/.previous-<ts>/).
  --dry-run        Print actions without writing any file.
  --help, -h       Show this help.

Exit codes:
  0 success (including dry-run completion)
  2 usage error (unknown flag, or invalid --type value)
  3 --type=auto detected empty AND stdin is non-TTY (cannot prompt)
  4 .gitx/ already exists and --force was not passed
EOF
            exit 0
            ;;
        --type=auto|--type=skill|--type=mac|--type=both|--type=empty)
            TYPE="${1#--type=}"
            ;;
        --type=*)
            echo "❌ invalid --type value: ${1#--type=}" >&2
            echo "   Valid: auto skill mac both empty" >&2
            exit 2
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        --force)
            FORCE=1
            ;;
        *)
            echo "❌ unknown flag: $1" >&2
            echo "   Try: gitx-init --help" >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$TYPE" = "auto" ]; then
    detected="$(detect_project_type)"
    if [ -n "$detected" ]; then
        TYPE="$detected"
    else
        # neither signal — interactive prompt deferred to a later cycle;
        # for now any auto-detect with no signals exits 3.
        echo "❌ no skill or mac signals detected in $(pwd)" >&2
        echo "   pass --type=<skill|mac|both|empty> explicitly" >&2
        exit 3
    fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "project type: $TYPE"
    echo "would write: $(pwd)/.gitx/policy.md"
    echo "would write: $(pwd)/RELEASE_GUIDELINE.md"
    echo "would write: $(pwd)/.claude-plugin/plugin.json"
    echo "would write: $(pwd)/.gitx/marketplace-entry.json"
    exit 0
fi

# Write phase (non-dry-run). Idempotent guard + --force / scenarios arrive
# in later TDD cycles.
PROJECT_NAME="$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')"
DATE="$(date +%Y-%m-%d)"
if [ -f "$SCRIPT_DIR/../VERSION" ]; then
    GITX_VERSION="$(cat "$SCRIPT_DIR/../VERSION")"
else
    GITX_VERSION="unknown"
fi

render_template() {
    sed -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
        -e "s/{{PROJECT_TYPE}}/$TYPE/g" \
        -e "s/{{DATE}}/$DATE/g" \
        -e "s/{{GITX_VERSION}}/$GITX_VERSION/g" \
        "$1"
}

if [ -d .gitx ] && [ "$FORCE" -eq 0 ]; then
    echo "❌ .gitx/ already exists at $(pwd)/.gitx" >&2
    echo "   Re-run with --force to overwrite (backs up old to .gitx/.previous-<ts>/)" >&2
    exit 4
fi

mkdir -p .gitx
render_template "$REFS_DIR/policy.template.md" > .gitx/policy.md

case "$TYPE" in
    skill|both)
        mkdir -p .gitx/scenarios
        render_template "$REFS_DIR/scenarios/skill-flow.template.md" > .gitx/scenarios/skill-flow.md
        ;;
esac

case "$TYPE" in
    mac|both)
        mkdir -p .gitx/scenarios
        render_template "$REFS_DIR/scenarios/mac-flow.template.md" > .gitx/scenarios/mac-flow.md
        ;;
esac

render_template "$REFS_DIR/RELEASE_GUIDELINE.template.md" > RELEASE_GUIDELINE.md

# Claude Code plugin manifest + marketplace entry. Author carries no email on
# purpose — an email in a shipped JSON trips secret/PII scanners.
PLUGIN_NAME="$(plugin_name)"
REPO_NAME="$(plugin_repo_name)"
if [ -f VERSION ]; then
    PLUGIN_VERSION="$(semver_norm "$(cat VERSION)")"
else
    PLUGIN_VERSION="$(semver_norm "")"
fi
PLUGIN_DESC="TKX release skill provisioned by gitx-init."

mkdir -p .claude-plugin
cat > .claude-plugin/plugin.json <<EOF
{
  "name": "$PLUGIN_NAME",
  "version": "$PLUGIN_VERSION",
  "description": "$PLUGIN_DESC",
  "author": { "name": "TKXLAB.AI" },
  "license": "MIT"
}
EOF

cat > .gitx/marketplace-entry.json <<EOF
{
  "name": "$PLUGIN_NAME",
  "source": { "source": "github", "repo": "tkxlab-ai/$REPO_NAME" },
  "description": "$PLUGIN_DESC",
  "version": "$PLUGIN_VERSION",
  "author": { "name": "TKXLAB.AI" },
  "license": "MIT"
}
EOF

cat <<EOF

✅ Plugin manifest written:
   .claude-plugin/plugin.json        (plugin: $PLUGIN_NAME @ $PLUGIN_VERSION)
   .gitx/marketplace-entry.json      (paste into tkxlab-ai/marketplace)

Next steps to publish:
  1. Add .gitx/marketplace-entry.json to the tkxlab-ai/marketplace repo's
     marketplace.json "plugins" array (commit + push there).
  2. Users then run:
       /plugin marketplace add tkxlab-ai/marketplace
       /plugin install $PLUGIN_NAME@tkx-skills
EOF
exit 0
