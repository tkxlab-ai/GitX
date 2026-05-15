#!/bin/bash
# translate-cached.sh — content-hash cache + human-review gate on top of
#                       translate-file.sh + anchor-rewrite.sh
#
# usage: translate-cached.sh <src> <dst> <target_lang>
#        translate-cached.sh list-unreviewed
#
# Flow (normal call):
#   1. hash = sha256(src)
#   2. cache = $CACHE_DIR/<hash>.<lang>.md
#   3. if `cache` exists (approved) → cp to dst, exit 0
#   4. if `cache.unreviewed` exists → warn "still pending review", exit 1
#   5. else → invoke translate-file.sh + anchor-rewrite.sh
#            → write to cache.unreviewed, warn, exit 1
#
# Approval:
#   Reviewer: `mv $CACHE_DIR/<hash>.<lang>.md.unreviewed
#              $CACHE_DIR/<hash>.<lang>.md`
#
# Env:
#   CACHE_DIR        default: $PROJECT_ROOT/.i18n-cache
#   CLAUDE_CMD       passthrough (default: claude)
#   GLOSSARY_PATH    passthrough
#   SKILL_PROJECT_ROOT passthrough
#
# exit: 0 cache hit / 1 miss or pending review / 2 usage / other >1 runtime error

set -euo pipefail

SUBCMD=${1:-}

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="${SKILL_PROJECT_ROOT:-$(cd "$SELF_DIR/.." && pwd)}"
TRANSLATE="$SELF_DIR/translate-file.sh"
ANCHOR="$SELF_DIR/anchor-rewrite.sh"
CACHE_DIR=${CACHE_DIR:-$SKILL_ROOT/.i18n-cache}

# ── Subcommand: list-unreviewed ─────────────────────────────────────────
if [ "$SUBCMD" = "list-unreviewed" ]; then
    if [ -d "$CACHE_DIR" ]; then
        find "$CACHE_DIR" -maxdepth 1 -name '*.unreviewed' -type f 2>/dev/null | LC_ALL=C sort
    fi
    exit 0
fi

# ── Normal usage ────────────────────────────────────────────────────────
if [ "$#" -lt 3 ]; then
    echo "usage: translate-cached.sh <src> <dst> <target_lang>" >&2
    echo "       translate-cached.sh list-unreviewed" >&2
    exit 2
fi

SRC=$1
DST=$2
TARGET_LANG=$3

if [ ! -f "$SRC" ]; then
    echo "❌ src not found: $SRC" >&2
    exit 1
fi

mkdir -p "$CACHE_DIR"

# ── Compute content hash ────────────────────────────────────────────────
if command -v shasum >/dev/null 2>&1; then
    SHA_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    SHA_CMD="sha256sum"
else
    echo "❌ need shasum or sha256sum" >&2
    exit 1
fi

SRC_HASH=$($SHA_CMD "$SRC" | awk '{print $1}')
CACHE_FILE="$CACHE_DIR/${SRC_HASH}.${TARGET_LANG}.md"
UNREVIEWED="$CACHE_FILE.unreviewed"

# ── Step 3: approved cache hit → cp to dst ──────────────────────────────
if [ -f "$CACHE_FILE" ]; then
    cp "$CACHE_FILE" "$DST"
    echo "   ↪ cache hit: $CACHE_FILE → $DST" >&2
    exit 0
fi

# ── Step 4: existing .unreviewed → still pending ────────────────────────
if [ -f "$UNREVIEWED" ]; then
    echo "⏳ translation pending review: $UNREVIEWED" >&2
    echo "   review + approve: mv $UNREVIEWED $CACHE_FILE" >&2
    exit 1
fi

# ── Step 5: fresh miss → translate + anchor-rewrite → write .unreviewed ─
TMP=$(mktemp)
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT

if ! "$TRANSLATE" "$SRC" "$TMP" "$TARGET_LANG"; then
    echo "❌ translate-file.sh failed" >&2
    exit 1
fi

# Anchor rewrite aligns translated headings' slugs
if ! "$ANCHOR" "$SRC" "$TMP" 2>/dev/null; then
    echo "⚠️  anchor-rewrite.sh reported issues; translation still cached" >&2
fi

cp "$TMP" "$UNREVIEWED"
echo "📝 NEW translation at: $UNREVIEWED" >&2
echo "   review carefully, then approve: mv $UNREVIEWED $CACHE_FILE" >&2
echo "   (release.sh will FAIL while .unreviewed suffix remains)" >&2
exit 1
