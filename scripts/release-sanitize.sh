#!/bin/bash
# release-sanitize.sh — scan a staged release directory for personal info / secrets / fingerprints
# usage: release-sanitize.sh [--label <name>] <dir>
# exit:  0 clean, 1 findings (blocks release), 2 usage / dir not found
#
# 扫描维度：
#   1. 凭证（调用 scan-credentials.sh）
#   2. 绝对用户路径（/Users/X / /home/X / C:\Users\X）—— 放行占位符 <user> / <your-user> / <name> 等
#   3. 真实邮箱 —— 放行 example.com / example.org / test.com / localhost / noreply@anthropic.com 等文档域
#   4. 公网 IP —— 政策上 publish 不允许出现真实公网 IP；仅放行 RFC 5737
#      文档保留段（192.0.2.0/24、198.51.100.0/24、203.0.113.0/24）、私网段
#      （127/10/192.168/172.16-31）、以及 1.1.1.1、8.8.8.8/4.4、9.9.9.9 几个
#      行业惯例的公共 DNS 占位
#   5. MAC 地址
#   6. SSH/GPG 指纹（SHA256:, ssh-rsa AAAA..., ssh-ed25519 AAAA...）
#
# 豁免目录：tests/fixtures/（故意的测试数据）、evals/files/（demo 数据）
#
# 输出政策：每条 finding 都以项目相对路径 + 行号显示（不暴露 staging mktemp
# 绝对路径，避免 operator 心算路径映射；release.sh 会用 --label 区分两遍扫描）

# NOTE: this script uses `set -u` ONLY (no -e, no -o pipefail). Several
# helper functions rely on `[ -z "$x" ] && return 1` patterns which would
# abort the entire script under `set -e` (Gotcha #24). Do NOT add `set -e`
# without first converting all `[ ... ] && cmd` chains to if-form.
set -u

# ---------- argument parsing ----------
LABEL=""
while [ $# -gt 0 ]; do
    case "$1" in
        --label)
            LABEL="${2:-}"
            [ -z "$LABEL" ] && { echo "❌ --label requires a value" >&2; exit 2; }
            shift 2
            ;;
        --label=*)
            LABEL="${1#--label=}"
            [ -z "$LABEL" ] && { echo "❌ --label requires a value" >&2; exit 2; }
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "❌ Unknown flag: $1" >&2
            echo "   usage: $0 [--label <name>] <dir>" >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

DIR="${1:?Usage: $0 [--label <name>] <dir>}"
[ -d "$DIR" ] || { echo "❌ Dir not found: $DIR" >&2; exit 2; }

# Label suffix for messages: "" | " (staging)" | " (.skill bundle)"
LABEL_SUFFIX=""
[ -n "$LABEL" ] && LABEL_SUFFIX=" ($LABEL)"

# Resolve scripts sibling（本脚本在 scripts/ 下，scan-credentials.sh 也在 scripts/ 下）
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SCAN_CREDS="$SELF_DIR/scan-credentials.sh"

FINDINGS=0
REPORT=""

# ---------- .sanitize-ignore whitelist (S3-1) ----------
# Project-level escape hatch that replaces the deleted FORCE=1 bypass.
# Format: one path (relative to $DIR) per line; '#' starts a comment; blanks OK.
# Patterns are matched via `case` glob against the relative file path.
# Example entries:
#   docs/legacy-notes.md           # single file
#   references/examples/*          # glob
#   tests/demo/*.yaml              # ext glob
IGNORE_FILE="$DIR/.sanitize-ignore"
IGNORE_PATTERNS=""
if [ -f "$IGNORE_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        # strip comments + trim
        line="${line%%#*}"
        # trim leading/trailing whitespace (portable)
        line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        # Reject patterns starting with a wildcard — they have no literal path prefix
        # and can achieve near-total bypass of all detectors. Valid patterns must
        # begin with a literal directory or filename component (e.g. tests/fixture.txt).
        case "$line" in
            '*'*|'?'*|'['*)
                echo "❌ .sanitize-ignore: '$line' starts with wildcard — must begin with a literal path prefix" >&2
                exit 1
                ;;
        esac
        IGNORE_PATTERNS="${IGNORE_PATTERNS}${line}"$'\n'
    done < "$IGNORE_FILE"
fi

is_ignored() {
    # $1: file path relative to $DIR. Returns 0 if any pattern matches.
    [ -z "$IGNORE_PATTERNS" ] && return 1
    local rel="$1" p
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        # shellcheck disable=SC2254
        case "$rel" in
            $p) return 0 ;;
        esac
    done <<EOF
$IGNORE_PATTERNS
EOF
    return 1
}

# 收集所有要扫描的文本文件（排除 fixtures/evals/ 豁免目录 + 本扫描器自己的正则文档 + meta 测试 + policy/test-scenarios 文档）
# NOTE: '*/Release/*' is intentionally NOT excluded here.
# When called from release.sh on staging (rsync already excluded Release/), this rule
# was harmless. When called from audit §7 on Release/vX.Y.Z/, the old exclusion caused
# every file to be skipped — making the second sanity pass a vacuous no-op (Bug #6).
# find_text_files [-print0]
# 可选传入 -print0 以支持含空格文件名（S2-1）；不传则默认换行输出（向后兼容）
find_text_files() {
    find "$DIR" -type f \
        \( -name '*.md' -o -name '*.sh' -o -name '*.json' -o -name '*.txt' \
           -o -name '*.py' -o -name '*.yml' -o -name '*.yaml' -o -name '*.toml' \
           -o -name '*.html' -o -name '*.js' -o -name '*.ts' \
           -o -name 'Dockerfile' -o -name 'Makefile' \
           -o -name '*.cfg' -o -name '*.ini' -o -name '*.conf' \
           -o -name '*.env' -o -name '*.pem' -o -name '*.key' -o -name '*.p12' \) \
        ! -path '*/tests/fixtures/*' \
        ! -path '*/evals/data/*' \
        ! -path '*/evals/fixtures/*' \
        ! -path '*/.git/*' \
        ! -path '*/scripts/release-sanitize.sh' \
        ! -path '*/scripts/scan-credentials.sh' \
        ! -path '*/tests/test_release_sanitize.sh' \
        ! -path '*/tests/test_scan_credentials.sh' \
        ! -path '*/tests/test_credential_patterns.sh' \
        ! -path '*/references/TKX_Git_Release_policy_and_process.md' \
        ! -path '*/Release/*/references/TKX_Git_Release_policy_and_process.md' \
        ! -path '*/skills/*/references/TKX_Git_Release_policy_and_process.md' \
        ! -path '*/references/TEST-SCENARIOS.md' \
        ! -path '*/Release/*/references/TEST-SCENARIOS.md' \
        ! -path '*/skills/*/references/TEST-SCENARIOS.md' \
        "$@" \
        2>/dev/null
}

append_report() {
    REPORT="$REPORT
$1"
    FINDINGS=$((FINDINGS+1))
}

# ---------- 1. Credentials via scan-credentials.sh ----------
# Bug A fix: scan-credentials.sh emits "⚠️  <description> (line N)" — one line
# per detected pattern with NO file path. We MUST prefix the file path to every
# such line; otherwise multi-hit files lose context for all but the first hit.
if [ -x "$SCAN_CREDS" ]; then
    cred_hits=""
    while IFS= read -r -d '' f; do
        rel="${f#$DIR/}"
        is_ignored "$rel" && continue
        if ! bash "$SCAN_CREDS" "$f" > /dev/null 2>&1; then
            # Read each detail line and prefix EACH one with "  rel: ".
            # head -3 limits per-file noise; total cap is enforced by the
            # final report layer.
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                cred_hits="$cred_hits
  ${rel}: $line"
            done < <(bash "$SCAN_CREDS" "$f" 2>&1 | head -3)
        fi
    done < <(find_text_files -print0)
    if [ -n "$cred_hits" ]; then
        append_report "❌ CREDENTIAL PATTERNS:$cred_hits"
    fi
fi

# grep_files <pattern>
# 用 find -print0 + while read -d '' 安全迭代，支持含空格文件名（S2-1）
# .sanitize-ignore 白名单在这里统一豁免（S3-1）
# P1-1: Limit output to prevent memory exhaustion on large/evil inputs.
#       Each file capped at 10 match lines; total capped at 200 lines.
# Bug B fix: grep -EHn emits "<absfile>:line:content"; we strip the staging
# directory prefix via awk so operator sees project-relative paths instead of
# /var/folders/.../tmp.XXX/<project>-vX.Y.Z/<rel>. awk's substr-based prefix
# match avoids regex escaping hazards present in mktemp paths.
grep_files() {
    local pattern="$1"
    local results=""
    local total_lines=0
    local MAX_PER_FILE=10
    local MAX_TOTAL=200
    while IFS= read -r -d '' f; do
        local rel="${f#$DIR/}"
        is_ignored "$rel" && continue
        local hits
        hits=$(LC_ALL=C grep -EHn -e "$pattern" "$f" 2>/dev/null \
               | head -n $MAX_PER_FILE \
               | awk -v d="$DIR/" 'BEGIN{l=length(d)} {if (substr($0,1,l)==d) print substr($0,l+1); else print}' \
               || true)
        if [ -n "$hits" ]; then
            results="$results
$hits"
            local new_lines
            new_lines=$(echo "$hits" | wc -l)
            total_lines=$((total_lines + new_lines))
            [ "$total_lines" -ge "$MAX_TOTAL" ] && break
        fi
    done < <(find_text_files -print0)
    printf '%s' "$results" | head -n $MAX_TOTAL
}

# ---------- 2. Absolute user paths ----------
# /Users/X/ /home/X/ C:\Users\X\  (X 是实际用户名字符)
# 放行 <user> / <your-user> / <name> / <username> / <your-name> 占位符
path_hits=$(grep_files \
    '(/Users/[a-zA-Z0-9_.-]+/|/home/[a-zA-Z0-9_.-]+/|C:\\+Users\\+[a-zA-Z0-9_.-]+)' \
    | grep -vE '(/Users/<|/home/<|Users\\<|/Users/\[|/home/\[)' \
    | head -20 || true)
if [ -n "$path_hits" ]; then
    append_report "❌ ABSOLUTE USER PATHS:
$path_hits"
fi

# ---------- 3. Email addresses ----------
# 放行明显的文档示例域
email_hits=$(grep_files \
    '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' \
    | grep -vE '@(example\.(com|org|net)|test\.(com|org)|localhost|noreply@anthropic\.com|your-?(domain|email|co)|mydomain|yourco|placeholder|xxx|foo\.bar|somewhere)' \
    | grep -vE 'op://|vault://' \
    | head -20 || true)
if [ -n "$email_hits" ]; then
    append_report "❌ EMAIL ADDRESSES:
$email_hits"
fi

# ---------- 4. Public IP addresses ----------
# Policy (v1.1.5+): 真实公网 IP 一律禁止出现在 release 产物中——任何命中都按
# 硬失败处理（❌，与其他类别一致；不再用 ⚠️ 误导）。允许放行的仅限：
#   - 私网段：127/10/192.168/172.16-31/169.254 (link-local)
#   - 文档保留段：RFC 5737 — 192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24
#   - 行业惯例 DNS：1.1.1.1 / 8.8.8.8 / 8.8.4.4 / 9.9.9.9
#   - 边界占位：0.0.0.0 / 255.255.x.x
# 真要把别的 IP 留下，去 .sanitize-ignore 写明（policy escape hatch）。
ip_hits=$(grep_files \
    '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' \
    | grep -vE '\b(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.|0\.0\.0\.0|255\.255\.|1\.1\.1\.1|8\.8\.(8|4)\.(8|4)|9\.9\.9\.9|192\.0\.2\.|198\.51\.100\.|203\.0\.113\.)' \
    | head -10 || true)
if [ -n "$ip_hits" ]; then
    append_report "❌ PUBLIC IP ADDRESSES:
$ip_hits"
fi

# ---------- 5. MAC addresses ----------
mac_hits=$(grep_files \
    '\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b' \
    | head -10 || true)
if [ -n "$mac_hits" ]; then
    append_report "❌ MAC ADDRESSES:
$mac_hits"
fi

# ---------- 6. SSH/GPG fingerprints ----------
# SHA256:... long base64; ssh-rsa / ssh-ed25519 完整 key blob
fp_hits=$(grep_files \
    'SHA256:[A-Za-z0-9+/]{30,}|ssh-rsa AAAA[A-Za-z0-9+/]{50,}|ssh-ed25519 AAAA[A-Za-z0-9+/]{30,}' \
    | head -10 || true)
if [ -n "$fp_hits" ]; then
    append_report "❌ SSH/GPG FINGERPRINTS:
$fp_hits"
fi

# ---------- Summary ----------
if [ "$FINDINGS" -gt 0 ]; then
    echo ""
    echo "╔════════════════════════════════════════════╗"
    if [ -n "$LABEL" ]; then
        printf '║   ⚠️  PRE-RELEASE SANITY CHECK FAILED%-7s ║\n' " ($LABEL)"
    else
        echo "║   ⚠️  PRE-RELEASE SANITY CHECK FAILED      ║"
    fi
    echo "╚════════════════════════════════════════════╝"
    printf '%s\n' "$REPORT"
    echo ""
    echo "发现 $FINDINGS 类敏感信息${LABEL_SUFFIX}。修复后再发布。"
    echo "（豁免目录：tests/fixtures/、evals/files/；显式白名单：.sanitize-ignore）"
    exit 1
fi

echo "✅ Release sanity clean${LABEL_SUFFIX} — 无个人信息/凭证/指纹泄漏"
exit 0
