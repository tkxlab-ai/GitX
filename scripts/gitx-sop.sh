#!/bin/bash
# gitx-sop.sh — render a parameterized GitHub-publish SOP into a project's
# .gitx/GITHUB_RELEASE_SOP.md so its dev-session AI knows how to publish a
# release to a public GitHub mirror WITHOUT leaking the private Git host.
#
# Generate-only. NEVER runs git / gh (SKILL.md constraint #1, TKX §10.10) —
# same model as gitx-init: it writes a runbook for a human-supervised AI.
#
# Usage:
#   gitx-sop [--repo=<owner/slug>] [--project=<name>]
#            [--private-host=<h>] [--force] [--dry-run] [--help]
#
# Exit:
#   0 success (including dry-run)
#   2 usage error (unknown flag, or invalid --project/--repo/--private-host)
#   4 .gitx/GITHUB_RELEASE_SOP.md already exists and --force was not passed
#   5 target (or .gitx) is a symlink — refused

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REFS_DIR="$SCRIPT_DIR/../references/gitx-sop"

REPO=""
PROJECT=""
PRIVATE_HOST=""
DRY_RUN=0
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            cat <<'EOF'
gitx-sop — render .gitx/GITHUB_RELEASE_SOP.md (GitHub publish runbook)

Usage:
  gitx-sop [--repo=<owner/slug>] [--project=<name>]
           [--private-host=<host>] [--force] [--dry-run] [--help]

Options:
  --repo=<owner/slug>     GitHub public mirror slug. Default: derived.
  --project=<name>        Project name. Default: cwd dir name (lowercased).
  --private-host=<host>   Private Git host to redact. Default: placeholder.
  --force                 Overwrite existing .gitx/GITHUB_RELEASE_SOP.md.
  --dry-run               Print actions without writing any file.
  --help, -h              Show this help.

Exit codes:
  0 success (including dry-run completion)
  2 usage error (unknown flag, or invalid --project/--repo/--private-host)
  4 .gitx/GITHUB_RELEASE_SOP.md already exists and --force was not passed
  5 target (or .gitx) is a symlink — refused
EOF
            exit 0
            ;;
        --repo=*)         REPO="${1#--repo=}" ;;
        --project=*)      PROJECT="${1#--project=}" ;;
        --private-host=*) PRIVATE_HOST="${1#--private-host=}" ;;
        --dry-run)        DRY_RUN=1 ;;
        --force)          FORCE=1 ;;
        *)
            echo "❌ unknown flag: $1" >&2
            echo "   Try: gitx-sop --help" >&2
            exit 2
            ;;
    esac
    shift
done

# Resolve defaults from cwd when flags omitted.
PROJECT="${PROJECT:-$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')}"
REPO="${REPO:-tkxlab-ai/$(basename "$(pwd)")}"
PRIVATE_HOST="${PRIVATE_HOST:-<private-git-host>}"
DATE="$(date +%Y-%m-%d)"
if [ -f "$SCRIPT_DIR/../VERSION" ]; then
    GITX_VERSION="$(cat "$SCRIPT_DIR/../VERSION")"
else
    GITX_VERSION="unknown"
fi
TARGET=".gitx/GITHUB_RELEASE_SOP.md"

# These values are interpolated into sed expressions below; an unvalidated
# '|;w FILE;#' in a dir name would let sed write files (or run commands on GNU sed).
_invalid() { echo "❌ invalid $1: '$2'" >&2; exit 2; }
# `case` matches the WHOLE string; a per-line grep would accept 'ok<LF>|;w X;#'
# because one line passes.
case "$PROJECT" in ''|*[!A-Za-z0-9._\&/-]*) _invalid project "$PROJECT" ;; esac
case "$REPO" in ''|*[!A-Za-z0-9._\&/-]*) _invalid repo "$REPO" ;; esac
case "$PRIVATE_HOST" in ''|*[!A-Za-z0-9._\<\>-]*) _invalid private-host "$PRIVATE_HOST" ;; esac

# _sed_esc — escape the sed replacement metachars for the '|' delimiter.
_sed_esc() { printf '%s' "$1" | sed -e 's/[|&\\]/\\&/g'; }

# _refuse_symlink_path — fail if PATH or any parent component is a symlink, so a
# planted link cannot redirect the write onto a file outside the project.
_refuse_symlink_path() {
    local d="$1"
    while [ -n "$d" ] && [ "$d" != "." ] && [ "$d" != "/" ]; do
        if [ -L "$d" ]; then
            echo "❌ $d is a symlink — refusing to write through it" >&2
            return 1
        fi
        d="$(dirname "$d")"
    done
    return 0
}

if [ "$DRY_RUN" -eq 1 ]; then
    echo "project: $PROJECT / repo: $REPO"
    echo "would write: $(pwd)/$TARGET"
    exit 0
fi

# Checked before the exists-guard so --force can never write through a link.
_refuse_symlink_path "$TARGET" || exit 5

if [ -f "$TARGET" ] && [ "$FORCE" -eq 0 ]; then
    echo "❌ $TARGET already exists at $(pwd)/$TARGET" >&2
    echo "   Re-run with --force to overwrite" >&2
    exit 4
fi

mkdir -p .gitx
_p="$(_sed_esc "$PROJECT")"
_r="$(_sed_esc "$REPO")"
_h="$(_sed_esc "$PRIVATE_HOST")"
_v="$(_sed_esc "$GITX_VERSION")"
sed -e "s|{{PROJECT}}|$_p|g" \
    -e "s|{{REPO}}|$_r|g" \
    -e "s|{{PRIVATE_GIT_HOST}}|$_h|g" \
    -e "s|{{DATE}}|$DATE|g" \
    -e "s|{{GITX_VERSION}}|$_v|g" \
    "$REFS_DIR/GITHUB_RELEASE_SOP.template.md" > "$TARGET"
exit 0
