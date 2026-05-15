#!/bin/bash
# fake-claude.sh — test double for `claude -p <prompt>`
#
# Usage (mirrors real claude-code): fake-claude.sh -p "<prompt>"
#
# Behaviors:
#   - Logs the prompt to $FAKE_CLAUDE_LOG if set (for test inspection)
#   - Output a canned deterministic "translation" containing probe markers
#     that tests can grep for:
#       [FAKE_TRANSLATION]
#       [LANG=$TARGET_LANG_PROBE]  (if env var set by test)
#   - Exit codes:
#     0 = normal
#     1 = if FAKE_CLAUDE_FAIL=1 (simulates LLM error)

set -euo pipefail

if [ "${FAKE_CLAUDE_FAIL:-0}" = "1" ]; then
    echo "fake-claude: simulated failure" >&2
    exit 1
fi

if [ "${1:-}" != "-p" ]; then
    echo "fake-claude: expected -p <prompt>, got: $*" >&2
    exit 2
fi
prompt=${2:-}

# Log prompt verbatim for test assertions
if [ -n "${FAKE_CLAUDE_LOG:-}" ]; then
    printf '%s' "$prompt" > "$FAKE_CLAUDE_LOG"
fi

# Emit probe + echo back the content portion of the prompt so tests can verify
# translate-file.sh properly embeds the source.
echo "[FAKE_TRANSLATION lang=${FAKE_CLAUDE_LANG_PROBE:-unknown}]"
# Extract content between <SOURCE> and </SOURCE> markers in the prompt
printf '%s\n' "$prompt" | awk '/^<SOURCE>$/,/^<\/SOURCE>$/ { if (!/^<\/?SOURCE>$/) print }'
