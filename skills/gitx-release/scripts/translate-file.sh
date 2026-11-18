#!/bin/bash
# translate-file.sh — translate a single markdown file via claude-code subprocess
#
# usage: translate-file.sh <src> <dst> <target_lang>
#
# Env:
#   CLAUDE_CMD          Path to claude binary (default: claude)
#   GLOSSARY_PATH       Path to .i18n-glossary (default: auto-detect)
#   SKILL_PROJECT_ROOT  Where to find scripts/glossary-loader.sh (default: auto)
#
# Reads glossary → emits few-shot prompt prefix → invokes `$CLAUDE_CMD -p`
# → writes translated markdown to dst.
#
# Never overwrites dst on LLM failure.
#
# exit: 0 success / 1 runtime error / 2 usage error.

set -euo pipefail

# ── Argument parsing ────────────────────────────────────────────────────
if [ "$#" -lt 3 ]; then
    echo "usage: translate-file.sh <src> <dst> <target_lang>" >&2
    exit 2
fi

SRC=$1
DST=$2
TARGET_LANG=$3

if [ ! -f "$SRC" ]; then
    echo "❌ src file not found: $SRC" >&2
    exit 1
fi

# ── Locate sibling tools ────────────────────────────────────────────────
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="${SKILL_PROJECT_ROOT:-$(cd "$SELF_DIR/.." && pwd)}"
GLOSSARY_LOADER="$SELF_DIR/glossary-loader.sh"

# ── Check claude binary ─────────────────────────────────────────────────
CLAUDE_CMD=${CLAUDE_CMD:-claude}
# Resolve if it's a path vs PATH lookup
if [ -x "$CLAUDE_CMD" ]; then
    :   # explicit path, OK
elif command -v "$CLAUDE_CMD" >/dev/null 2>&1; then
    :   # on PATH
else
    echo "❌ CLAUDE_CMD not found or not executable: $CLAUDE_CMD" >&2
    echo "   install claude-code or set CLAUDE_CMD to a working path" >&2
    exit 1
fi

# ── Detect source language heuristically (for prompt clarity) ───────────
# Count non-ASCII bytes as CJK indicator
TOTAL_BYTES=$(wc -c < "$SRC" | tr -d ' ')
NONASCII=$(LC_ALL=C tr -d '\000-\177' < "$SRC" | wc -c | tr -d ' ')
if [ "$TOTAL_BYTES" -gt 0 ] && [ "$((NONASCII * 100 / TOTAL_BYTES))" -ge 15 ]; then
    SRC_LANG="zh"
else
    SRC_LANG="en"
fi

# ── Build LLM prompt ────────────────────────────────────────────────────
TMP_PROMPT=$(mktemp)
TMP_OUT=$(mktemp)
cleanup() { rm -f "$TMP_PROMPT" "$TMP_OUT"; }
trap cleanup EXIT

# Human-friendly language name for the prompt
case "$TARGET_LANG" in
    en) TARGET_NAME="English" ;;
    zh) TARGET_NAME="Chinese (Simplified)" ;;
    ja) TARGET_NAME="Japanese" ;;
    *)  TARGET_NAME="$TARGET_LANG" ;;
esac
case "$SRC_LANG" in
    en) SRC_NAME="English" ;;
    zh) SRC_NAME="Chinese (Simplified)" ;;
    *)  SRC_NAME="$SRC_LANG" ;;
esac

{
cat <<EOF
You are a professional technical translator.

Task: translate the markdown document below from $SRC_NAME to $TARGET_NAME (target-lang: $TARGET_LANG).

Rules:
1. Output ONLY the translated markdown. No preamble, no commentary, no code fences around the whole output.
2. Preserve all markdown structure: headings (# ##), lists, tables, code blocks, links, emojis.
3. Preserve code blocks VERBATIM (do NOT translate code, commands, identifiers).
4. Preserve inline \`code spans\` verbatim.
5. Keep URLs, file paths, env var names, CLI flags unchanged.
6. Translate heading text, but DO NOT change heading levels.
7. Preserve YAML/TOML frontmatter values where they are technical identifiers.

EOF

# Inject glossary few-shot (if available)
if [ -x "$GLOSSARY_LOADER" ]; then
    # Resolve glossary path
    if [ -n "${GLOSSARY_PATH:-}" ]; then
        "$GLOSSARY_LOADER" --glossary "$GLOSSARY_PATH" emit-few-shot 2>/dev/null || true
    elif [ -f "$SKILL_ROOT/.i18n-glossary" ]; then
        "$GLOSSARY_LOADER" --glossary "$SKILL_ROOT/.i18n-glossary" emit-few-shot 2>/dev/null || true
    fi
fi

# Source content wrapped in markers the post-pass can recognize
cat <<EOF

Translate the markdown between <SOURCE> and </SOURCE>, output the translation only.

<SOURCE>
EOF
cat "$SRC"
cat <<EOF
</SOURCE>
EOF
} > "$TMP_PROMPT"

# ── Invoke LLM ──────────────────────────────────────────────────────────
PROMPT_TEXT=$(cat "$TMP_PROMPT")
if ! "$CLAUDE_CMD" -p "$PROMPT_TEXT" > "$TMP_OUT" 2>/dev/null; then
    echo "❌ translator invocation failed: $CLAUDE_CMD -p <prompt>" >&2
    exit 1
fi

if [ ! -s "$TMP_OUT" ]; then
    echo "❌ translator returned empty output" >&2
    exit 1
fi

# ── Write to dst (only after LLM succeeded) ─────────────────────────────
mkdir -p "$(dirname "$DST")"
cp "$TMP_OUT" "$DST"
echo "   → $DST ($SRC_LANG → $TARGET_LANG, $(wc -c < "$DST" | tr -d ' ') bytes)" >&2
