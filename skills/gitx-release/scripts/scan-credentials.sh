#!/bin/bash
# scan-credentials.sh — detect plaintext credentials in file or stdin
# usage: scan-credentials.sh [file]  OR  cat file | scan-credentials.sh
#        (no arg + no stdin → 默认扫 ./HANDOFF.md)
# exit:  0 clean, 1 credential found, 2 usage error
set -u

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [file]   OR   cat file | $0"
        echo "  no arg + no stdin → 默认扫 ./HANDOFF.md"
        echo "Exit: 0 clean / 1 credential found / 2 usage error"
        exit 0
        ;;
esac

# Stream-based scanner (post-v1.0.7 hardening): each pattern is grep'd directly
# against the source (file or stdin), no whole-file slurp into a shell var.
# This avoids RSS bloat on large inputs and is also marginally faster.
SRC=""
TMP_INPUT=""
if [ $# -ge 1 ]; then
    if [ ! -f "$1" ]; then
        echo "❌ file not found: $1" >&2
        echo "   Usage: $0 [file]   OR   cat file | $0" >&2
        exit 2
    fi
    SRC="$1"
elif [ ! -t 0 ]; then
    # Buffer stdin to a tempfile so we can run multiple passes without re-reading
    TMP_INPUT=$(mktemp)
    trap 'rm -f "${TMP_INPUT:-}"' EXIT
    cat > "$TMP_INPUT"
    SRC="$TMP_INPUT"
elif [ -f "HANDOFF.md" ]; then
    SRC="HANDOFF.md"
else
    echo "Usage: $0 [file]   OR   cat file | $0" >&2
    echo "  (no arg, no stdin, no ./HANDOFF.md in cwd)" >&2
    exit 2
fi

# Why LABELS is index-parallel: the loop reads LABELS[$i] under set -u, so
# every PATTERNS entry needs a label at the same index.
PATTERNS=(
    'sk-proj-[A-Za-z0-9_-]{20,}'
    'sk-[A-Za-z0-9]{48,}'
    'sk-ant-[a-z]+[0-9]+-[A-Za-z0-9_-]{20,}'
    'ghp_[A-Za-z0-9]{36,}'
    'gho_[A-Za-z0-9]{36,}'
    'ghs_[A-Za-z0-9]{36,}'
    'ghu_[A-Za-z0-9]{36,}'
    'github_pat_[A-Za-z0-9_]{82}'
    'AKIA[0-9A-Z]{16}'
    'ASIA[0-9A-Z]{16}'
    '[Aa][Ww][Ss]_?[Ss][Ee][Cc][Rr][Ee][Tt]_?[Aa][Cc][Cc][Ee][Ss][Ss]_?[Kk][Ee][Yy]["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9/+=]{40}'
    'xox[baprs]-[A-Za-z0-9-]{10,}'
    'sbp_[A-Za-z0-9]{32,}'
    'npm_[A-Za-z0-9]{36,}'
    'pypi-[A-Za-z0-9_-]{16,}'
    '-----BEGIN [A-Z ]*PRIVATE KEY( BLOCK)?-----'
    'sk_(live|test)_[A-Za-z0-9]{24,}'
    'Bearer[[:space:]]+eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'
    '\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b'
    '"type"[[:space:]]*:[[:space:]]*"service_account"'
    'DefaultEndpointsProtocol=https;AccountName=[A-Za-z0-9]+;AccountKey=[A-Za-z0-9/+=]{60,}'
    'sk-svcacct-[A-Za-z0-9_-]{20,}'
)
LABELS=(
    'OpenAI project key'
    'OpenAI classic key'
    'Anthropic API key / OAuth token'
    'GitHub personal token'
    'GitHub OAuth token'
    'GitHub server token'
    'GitHub user-to-server token'
    'GitHub fine-grained PAT'
    'AWS access key ID'
    'AWS temporary access key ID (STS)'
    'AWS secret access key (key=value / key: value)'
    'Slack token'
    'Supabase service role key'
    'npm auth token'
    'PyPI API token'
    'Private key header (PEM / PKCS#8 / OpenSSH / PGP)'
    'Stripe secret key'
    'JWT bearer token (with Bearer prefix)'
    'JWT bearer token (bare)'
    'GCP service-account JSON marker'
    'Azure storage connection string'
    'OpenAI service-account key'
)

FOUND=0
for i in "${!PATTERNS[@]}"; do
    pattern="${PATTERNS[$i]}"
    label="${LABELS[$i]}"
    # -a + LC_ALL=C: search binary input byte-wise (release-sanitize.sh feeds
    # every regular file here, binaries included); without them grep reports
    # "Binary file matches" or stops at invalid UTF-8.
    if LC_ALL=C grep -aqE -- "$pattern" "$SRC"; then
        line=$(LC_ALL=C grep -anE -- "$pattern" "$SRC" | head -1 | LC_ALL=C cut -d: -f1)
        printf '⚠️  %s detected (line %s)\n' "$label" "$line" >&2
        FOUND=1
    fi
done

exit $FOUND
