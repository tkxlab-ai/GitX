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
#   2 usage error (unknown flag)
#   4 .gitx/GITHUB_RELEASE_SOP.md already exists and --force was not passed

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
  2 usage error (unknown flag)
  4 .gitx/GITHUB_RELEASE_SOP.md already exists and --force was not passed
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

if [ "$DRY_RUN" -eq 1 ]; then
    echo "project: $PROJECT / repo: $REPO"
    echo "would write: $(pwd)/$TARGET"
    exit 0
fi

if [ -f "$TARGET" ] && [ "$FORCE" -eq 0 ]; then
    echo "❌ $TARGET already exists at $(pwd)/$TARGET" >&2
    echo "   Re-run with --force to overwrite" >&2
    exit 4
fi

mkdir -p .gitx
sed -e "s|{{PROJECT}}|$PROJECT|g" \
    -e "s|{{REPO}}|$REPO|g" \
    -e "s|{{PRIVATE_GIT_HOST}}|$PRIVATE_HOST|g" \
    -e "s|{{DATE}}|$DATE|g" \
    -e "s|{{GITX_VERSION}}|$GITX_VERSION|g" \
    "$REFS_DIR/GITHUB_RELEASE_SOP.template.md" > "$TARGET"
exit 0
