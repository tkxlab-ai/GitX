#!/bin/bash
# i18n-config-loader.sh — parse .i18n-config and answer queries
#
# usage:
#   i18n-config-loader.sh [--config PATH] <subcommand> [args]
#
# subcommands:
#   primary                → echo primary-language (default: zh)
#   list targets           → echo target languages, one per line
#   list strict            → echo strict-list files, one per line
#   list warn              → echo warn-list files, one per line
#   list lock              → echo lock-list files (declared + hardcoded), one per line
#   strictness <file>      → echo strict | warn | lock | none
#
# Config format (.i18n-config):
#   key: value              (single-line)
#   key:                    (multi-line list follows)
#     item1
#     item2
#   # comment
#
# Supported keys:
#   primary-language, target-languages,
#   strict, strict-glob, warn, warn-glob, lock
#
# Hardcoded lock defaults (always enforced regardless of config):
#   LICENSE, CODE_OF_CONDUCT.md
#
# exit: 0 success (even if config missing — falls back to defaults),
#       2 usage error, 1 internal error.

set -euo pipefail

CONFIG=""
# Default config path search: $PROJECT_ROOT/.i18n-config, else cwd/.i18n-config
if [ "${1:-}" = "--config" ]; then
    CONFIG=$2
    shift 2
elif [ -n "${PROJECT_ROOT:-}" ] && [ -f "$PROJECT_ROOT/.i18n-config" ]; then
    CONFIG="$PROJECT_ROOT/.i18n-config"
elif [ -f "./.i18n-config" ]; then
    CONFIG="./.i18n-config"
fi

SUBCMD=${1:-}
if [ -z "$SUBCMD" ]; then
    echo "usage: i18n-config-loader.sh [--config PATH] <primary|list|strictness> [args]" >&2
    exit 2
fi
shift || true

# ── Parse config into arrays ─────────────────────────────────────────────
PRIMARY="zh"
TARGETS="en"
STRICT_LIST=()
STRICT_GLOB=()
WARN_LIST=()
WARN_GLOB=()
LOCK_LIST=()

HARDCODED_LOCK=("LICENSE" "CODE_OF_CONDUCT.md")

if [ -n "$CONFIG" ] && [ -f "$CONFIG" ]; then
    current_list=""
    while IFS= read -r rawline || [ -n "$rawline" ]; do
        # Strip trailing CR (cross-platform safety)
        line=${rawline%$'\r'}
        # Skip blank / comment lines
        case "$line" in
            ''|\#*) continue ;;
        esac
        # Strip leading whitespace to detect indented items
        trimmed=${line#"${line%%[![:space:]]*}"}
        # Line indented (starts with whitespace) and not a top-level key → list item
        if [ "$line" != "$trimmed" ] && [ -n "$current_list" ]; then
            # Also handle inline comments on list items
            item=${trimmed%%#*}
            item=${item%"${item##*[![:space:]]}"}
            [ -z "$item" ] && continue
            case "$current_list" in
                strict)      STRICT_LIST+=("$item") ;;
                strict-glob) STRICT_GLOB+=("$item") ;;
                warn)        WARN_LIST+=("$item") ;;
                warn-glob)   WARN_GLOB+=("$item") ;;
                lock)        LOCK_LIST+=("$item") ;;
            esac
            continue
        fi
        # Top-level line: try to match "key: value" or "key:"
        case "$trimmed" in
            primary-language:*)
                PRIMARY=${trimmed#primary-language:}
                PRIMARY=${PRIMARY#"${PRIMARY%%[![:space:]]*}"}
                PRIMARY=${PRIMARY%"${PRIMARY##*[![:space:]]}"}
                current_list=""
                ;;
            target-languages:*)
                val=${trimmed#target-languages:}
                val=${val#"${val%%[![:space:]]*}"}
                val=${val%"${val##*[![:space:]]}"}
                # comma or whitespace separated → space separated
                TARGETS=$(printf '%s' "$val" | tr ',' ' ' | tr -s ' ')
                current_list=""
                ;;
            strict:)      current_list="strict" ;;
            strict-glob:) current_list="strict-glob" ;;
            warn:)        current_list="warn" ;;
            warn-glob:)   current_list="warn-glob" ;;
            lock:)        current_list="lock" ;;
            *)            current_list="" ;;
        esac
    done < "$CONFIG"
fi

# Merge hardcoded locks into LOCK_LIST (dedup)
for h in "${HARDCODED_LOCK[@]}"; do
    already=0
    for x in "${LOCK_LIST[@]:-}"; do
        [ "$x" = "$h" ] && already=1 && break
    done
    [ "$already" = "0" ] && LOCK_LIST+=("$h")
done

# ── Sub-command dispatch ─────────────────────────────────────────────────
case "$SUBCMD" in
    primary)
        printf '%s\n' "$PRIMARY"
        ;;
    list)
        which=${1:-}
        case "$which" in
            targets) printf '%s\n' $TARGETS ;;
            strict)  [ ${#STRICT_LIST[@]} -gt 0 ] && printf '%s\n' "${STRICT_LIST[@]}" ;;
            warn)    [ ${#WARN_LIST[@]} -gt 0 ]   && printf '%s\n' "${WARN_LIST[@]}" ;;
            lock)    [ ${#LOCK_LIST[@]} -gt 0 ]   && printf '%s\n' "${LOCK_LIST[@]}" ;;
            *)       echo "unknown list: $which (expected targets|strict|warn|lock)" >&2; exit 2 ;;
        esac
        ;;
    strictness)
        file=${1:-}
        [ -z "$file" ] && { echo "usage: strictness <file>" >&2; exit 2; }
        # Check lock first (highest precedence)
        for x in "${LOCK_LIST[@]:-}"; do
            if [ "$x" = "$file" ]; then echo "lock"; exit 0; fi
        done
        # strict exact
        for x in "${STRICT_LIST[@]:-}"; do
            if [ "$x" = "$file" ]; then echo "strict"; exit 0; fi
        done
        # strict-glob
        for pat in "${STRICT_GLOB[@]:-}"; do
            # shellcheck disable=SC2254
            case "$file" in
                $pat) echo "strict"; exit 0 ;;
            esac
        done
        # warn exact
        for x in "${WARN_LIST[@]:-}"; do
            if [ "$x" = "$file" ]; then echo "warn"; exit 0; fi
        done
        # warn-glob
        for pat in "${WARN_GLOB[@]:-}"; do
            # shellcheck disable=SC2254
            case "$file" in
                $pat) echo "warn"; exit 0 ;;
            esac
        done
        echo "none"
        ;;
    *)
        echo "unknown subcommand: $SUBCMD" >&2
        exit 2
        ;;
esac
