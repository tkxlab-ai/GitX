#!/bin/bash
# sync-dual-source.sh — sync scripts/ to skills/<skill_name>/scripts/
# P0-1: Auto-detects SKILL_NAME via detect-project.sh instead of hardcoding.
# Usage: bash scripts/sync-dual-source.sh [--dry-run]
#
# Keeps the dual-source layout in sync (TKX policy v2.3 §8.1 #14).
# Run this after modifying any script in scripts/.
# The CI also checks this consistency (ci.yml dual-source step).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$PROJECT_ROOT/scripts"

# P0-1: Auto-detect SKILL_NAME (was hardcoded to "gitx-release")
source "$SCRIPT_DIR/lib/detect-project.sh" 2>/dev/null || {
    echo "❌ Cannot auto-detect SKILL_NAME. Set SKILL_NAME=xxx and retry."
    exit 1
}

DST="$PROJECT_ROOT/skills/$SKILL_NAME/scripts"

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
fi

if [ ! -d "$DST" ]; then
    echo "❌ Destination not found: $DST"
    echo "   This script is for flat-layout projects that maintain a dual-source mirror."
    exit 1
fi

CHANGES=0
for f in "$SRC"/*.sh; do
    [ -f "$f" ] || continue
    bn="$(basename "$f")"
    # Skip release-specific scripts that aren't in the skill bundle
    if [ "$bn" = "sync-dual-source.sh" ]; then
        continue
    fi
    target="$DST/$bn"
    if [ ! -f "$target" ] || ! diff -q "$f" "$target" >/dev/null 2>&1; then
        if [ "$DRY_RUN" = "1" ]; then
            echo "  [dry-run] Would sync: $bn"
        else
            cp "$f" "$target"
            echo "  ✅ Synced: $bn"
        fi
        CHANGES=$((CHANGES+1))
    fi
done

if [ "$CHANGES" -eq 0 ]; then
    echo "✅ Dual-source already in sync"
else
    if [ "$DRY_RUN" = "1" ]; then
        echo "📝 $CHANGES file(s) would be synced"
    else
        echo "✅ Synced $CHANGES file(s)"
    fi
fi
