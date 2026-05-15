#!/bin/bash
# glossary-loader.sh — parse .i18n-glossary and answer queries
#
# usage: glossary-loader.sh [--glossary PATH] <subcommand> [args]
#
# subcommands:
#   lookup <zh>            → echo en (exit 1 if missing)
#   list terms             → one line per entry: zh|en
#   list no-translate      → one pattern per line
#   is-no-translate <tok>  → exit 0 if matches NO_TRANSLATE glob, else 1
#   emit-few-shot          → markdown prompt prefix for LLM (terms table + NO_TRANSLATE)
#   detect-conflicts       → exit 1 if any zh has 2+ different en mappings
#
# Glossary format (.i18n-glossary):
#   <zh>|<en>|<context>          # term entry
#   [NO_TRANSLATE]                # section marker
#     pattern1                    # globs / literal tokens to never translate
#
# exit: 0 success / 1 detection signal (lookup miss / conflict found) / 2 usage error

set -euo pipefail

GLOSSARY=""
if [ "${1:-}" = "--glossary" ]; then
    GLOSSARY=$2
    shift 2
elif [ -n "${PROJECT_ROOT:-}" ] && [ -f "$PROJECT_ROOT/.i18n-glossary" ]; then
    GLOSSARY="$PROJECT_ROOT/.i18n-glossary"
elif [ -f "./.i18n-glossary" ]; then
    GLOSSARY="./.i18n-glossary"
fi

SUBCMD=${1:-}
[ -z "$SUBCMD" ] && { echo "usage: glossary-loader.sh [--glossary PATH] <lookup|list|is-no-translate|emit-few-shot|detect-conflicts> [args]" >&2; exit 2; }
shift || true

# ── Parse glossary into TERMS array (zh|en lines) and NO_TRANS array ────
TERMS=()
NO_TRANS=()

if [ -n "$GLOSSARY" ] && [ -f "$GLOSSARY" ]; then
    in_no_translate=0
    while IFS= read -r rawline || [ -n "$rawline" ]; do
        line=${rawline%$'\r'}
        # Strip leading whitespace for blank/comment detection but keep original for indented items
        trimmed=${line#"${line%%[![:space:]]*}"}
        # Skip blank / comment
        case "$trimmed" in
            ''|\#*) continue ;;
        esac
        # Section marker
        if [ "$trimmed" = "[NO_TRANSLATE]" ]; then
            in_no_translate=1
            continue
        fi
        if [ "$in_no_translate" = "1" ]; then
            # Indented or top-level, all lines until EOF or another section are NO_TRANS patterns
            # Strip inline comment
            item=${trimmed%%#*}
            item=${item%"${item##*[![:space:]]}"}
            [ -z "$item" ] && continue
            NO_TRANS+=("$item")
            continue
        fi
        # Term entry: zh|en|context — keep only zh|en
        if [[ "$trimmed" == *"|"* ]]; then
            zh=${trimmed%%|*}
            rest=${trimmed#*|}
            en=${rest%%|*}
            zh=${zh%"${zh##*[![:space:]]}"}
            en=${en#"${en%%[![:space:]]*}"}
            en=${en%"${en##*[![:space:]]}"}
            [ -z "$zh" ] || [ -z "$en" ] && continue
            TERMS+=("${zh}|${en}")
        fi
    done < "$GLOSSARY"
fi

# ── Sub-command dispatch ─────────────────────────────────────────────────
case "$SUBCMD" in
    lookup)
        zh=${1:-}
        [ -z "$zh" ] && { echo "usage: lookup <zh>" >&2; exit 2; }
        for entry in "${TERMS[@]:-}"; do
            ezh=${entry%%|*}
            een=${entry#*|}
            if [ "$ezh" = "$zh" ]; then
                printf '%s\n' "$een"
                exit 0
            fi
        done
        exit 1
        ;;
    list)
        which=${1:-}
        case "$which" in
            terms)
                [ ${#TERMS[@]} -gt 0 ] && printf '%s\n' "${TERMS[@]}"
                ;;
            no-translate)
                [ ${#NO_TRANS[@]} -gt 0 ] && printf '%s\n' "${NO_TRANS[@]}"
                ;;
            *)
                echo "unknown list: $which (expected terms|no-translate)" >&2
                exit 2
                ;;
        esac
        ;;
    is-no-translate)
        token=${1:-}
        [ -z "$token" ] && { echo "usage: is-no-translate <token>" >&2; exit 2; }
        for pat in "${NO_TRANS[@]:-}"; do
            # shellcheck disable=SC2254
            case "$token" in
                $pat) exit 0 ;;
            esac
        done
        exit 1
        ;;
    emit-few-shot)
        # Output a prompt prefix for LLM. Empty if no glossary.
        if [ ${#TERMS[@]} -eq 0 ] && [ ${#NO_TRANS[@]} -eq 0 ]; then
            exit 0
        fi
        cat <<'HDR'
## Translation glossary (use these mappings consistently)

| zh | en |
|---|---|
HDR
        for entry in "${TERMS[@]:-}"; do
            ezh=${entry%%|*}
            een=${entry#*|}
            printf '| %s | %s |\n' "$ezh" "$een"
        done
        if [ ${#NO_TRANS[@]} -gt 0 ]; then
            cat <<'NTHDR'

## Do NOT translate these tokens (preserve verbatim — paths, env vars, flags, code symbols)

NTHDR
            for pat in "${NO_TRANS[@]}"; do
                printf -- '- `%s`\n' "$pat"
            done
        fi
        ;;
    detect-conflicts)
        # Bail if any zh has 2+ distinct en mappings
        # Build temp file of zh:en pairs sorted by zh
        tmp=$(mktemp)
        for entry in "${TERMS[@]:-}"; do
            ezh=${entry%%|*}
            een=${entry#*|}
            printf '%s\t%s\n' "$ezh" "$een"
        done | LC_ALL=C sort -u > "$tmp"
        # If after dedup the same zh appears 2+ times → distinct en mappings exist
        dup_zh=$(awk -F'\t' '{print $1}' "$tmp" | LC_ALL=C uniq -d)
        rm -f "$tmp"
        if [ -n "$dup_zh" ]; then
            echo "Conflicting glossary entries (same zh, multiple en):" >&2
            echo "$dup_zh" >&2
            exit 1
        fi
        exit 0
        ;;
    *)
        echo "unknown subcommand: $SUBCMD" >&2
        exit 2
        ;;
esac
