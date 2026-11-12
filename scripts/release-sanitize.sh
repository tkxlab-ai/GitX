#!/bin/bash
# release-sanitize.sh — scan a staged release directory for personal info / secrets / fingerprints
# usage: release-sanitize.sh [--label <name>] <dir>
# exit:  0 clean, 1 findings (blocks release), 2 usage / dir not found
#
# 扫描维度：
#   1. 凭证（调用 scan-credentials.sh）
#   2. 绝对用户路径（/Users/<user>/ / /home/<user>/ / C:\Users\<user>\）—— 放行占位符 <user> / <your-user> / <name> 等
#   3. 真实邮箱 —— 放行 example.com / example.org / test.com / localhost 等文档域，以及 anthropic / github 的 noreply 身份
#   （注释里的示例一律用占位符写法：本文件会随 skill 发到下游被扫描）
#   4. 公网 IP —— 政策上 publish 不允许出现真实公网 IP；仅放行 RFC 5737
#      文档保留段（192.0.2.0/24、198.51.100.0/24、203.0.113.0/24）、私网段
#      （127/10/192.168/172.16-31）、以及 1.1.1.1、8.8.8.8/4.4、9.9.9.9 几个
#      行业惯例的公共 DNS 占位
#   5. MAC 地址
#   6. SSH/GPG 指纹（SHA256:, ssh-rsa AAAA..., ssh-ed25519 AAAA...）
#
# 豁免目录：仅当扫描对象是 gitx-release 自身（SKILL.md name: gitx-release）时，
#   tests/fixtures/、evals/data/、evals/fixtures/ 及本扫描器自测文档才豁免
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
# Why: with a trailing '/', every rel path kept a leading '/', which broke
# .sanitize-ignore matching and let a `/*` line exempt the whole tree.
while [ "$DIR" != "/" ] && [ "${DIR%/}" != "$DIR" ]; do DIR="${DIR%/}"; done

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
        # Why: a non-leading wildcard in the first segment (`x*`, `R*`, `.*`)
        # still exempts near-whole trees. A glob there needs a '/' and >=2
        # literal leading chars (keeps `.syncthing-quarantine-*/*` valid).
        _seg="${line%%/*}"; case "$_seg" in *'*'*|*'?'*|*'['*) _lit="${_seg%%[*?[]*}"; if [ "$_seg" = "$line" ] || [ "${#_lit}" -lt 2 ]; then echo "❌ .sanitize-ignore: '$line' — first path segment must be literal (a glob there needs >=2 literal leading chars and a '/')" >&2; exit 1; fi ;; esac
        # Why: patterns match paths relative to $DIR; an absolute or dot-segment
        # pattern never names a real rel path and `/*` slipped the rule above.
        case "$line" in
            /*|.|..|./*|../*|*/.|*/..|*/./*|*/../*)
                echo "❌ .sanitize-ignore: '$line' — must be a relative path without '.' or '..' segments" >&2
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
# Why root-first + line-1 `---` (fix round 1): a host repo that vendors
# skills/gitx-release/ must not inherit GitX's exemptions for its whole
# tree, and a SKILL.md without frontmatter must not be read to EOF where a
# body line could claim the name.
_SELF_SCAN=0
_SELF_SRC=root
_sk="$DIR/SKILL.md"
if [ ! -f "$_sk" ]; then _sk="$DIR/skills/gitx-release/SKILL.md"; _SELF_SRC=fallback; fi
if [ -f "$_sk" ] && [ "$(head -n 1 "$_sk")" = "---" ] \
   && sed -n '2,/^---$/p' "$_sk" | grep -qE '^name:[[:space:]]*gitx-release[[:space:]]*$'; then
    _SELF_SCAN=1
fi

# Why gated on _SELF_SCAN: these paths hold GitX's own planted detector test
# data. Exempting them in every downstream project let a real secret hide in
# any skill's tests/fixtures/ or references/TEST-SCENARIOS.md.
# Why anchored to $DIR (follow-up S2): `*/tests/fixtures/*` matched at any
# depth, so a nested docs/tests/fixtures/ — or, under fallback detection, the
# host repo's own root tests/fixtures/ — was exempt too. Exemptions now name
# the exact locations GitX ships them; fallback detection exempts only the
# vendored skills/gitx-release/ copies. $DIR is glob-escaped for find -path.
_SELF_EXEMPT=()
if [ "$_SELF_SCAN" -eq 1 ]; then
    _dq=$(printf '%s' "$DIR" | sed 's/[][*?\\]/\\&/g')
    _SELF_REL=(
        'tests/fixtures/*'
        'evals/data/*'
        'evals/fixtures/*'
        'scripts/release-sanitize.sh'
        'scripts/scan-credentials.sh'
        'tests/test_release_sanitize.sh'
        'tests/test_scan_credentials.sh'
        'tests/test_credential_patterns.sh'
        'references/TKX_Git_Release_policy_and_process.md'
        'references/TEST-SCENARIOS.md'
    )
    if [ "$_SELF_SRC" = root ]; then
        _SELF_PFX=("$_dq/" "$_dq/skills/*/")
        _SELF_EXEMPT=(
            ! -path "$_dq/Release/*/references/TKX_Git_Release_policy_and_process.md"
            ! -path "$_dq/Release/*/references/TEST-SCENARIOS.md"
        )
    else
        _SELF_PFX=("$_dq/skills/gitx-release/")
    fi
    for _p in "${_SELF_PFX[@]}"; do
        for _r in "${_SELF_REL[@]}"; do
            _SELF_EXEMPT+=(! -path "$_p$_r")
        done
    done
fi

# Why no -name allowlist / -size cap: an extension allowlist missed dotfiles
# and source files (.npmrc, *.rb, id_ed25519), and any size cap is a silent
# bypass. Binary files are skipped per-file by _is_text_file in the noisy
# detectors only; the credential pass scans every regular file.
find_text_files() {
    find "$DIR" -type f ! -path '*/.git/*' ${_SELF_EXEMPT[@]+"${_SELF_EXEMPT[@]}"} "$@" 2>/dev/null
}

# Text = no NUL byte in the first 4 KiB (same heuristic git/grep use).
_is_text_file() { local n1 n2; n1=$(head -c 4096 "$1" | wc -c | tr -d ' '); n2=$(head -c 4096 "$1" | LC_ALL=C tr -d '\000' | wc -c | tr -d ' '); [ "$n1" -eq "$n2" ]; }

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
        # Why no _is_text_file gate here (follow-up S1): a token inside a
        # .p12 / sqlite / mixed blob is still a leak; scan-credentials.sh greps
        # byte-wise (-a, LC_ALL=C). Known residual: UTF-16 text interleaves
        # NULs between characters, so ASCII regexes cannot match it — not
        # transcoded on purpose.
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

# grep_files <pattern> [<match-allow-regex>] [<line-context-regex>]
# 用 find -print0 + while read -d '' 安全迭代，支持含空格文件名（S2-1）
# .sanitize-ignore 白名单在这里统一豁免（S3-1）
# Output: "relpath:line:<first non-allowed match>" — project-relative (Bug B),
# never the staging mktemp absolute path.
# Why match-level: the old whole-line `grep -v <allowlist>` let one
# placeholder (user@example.com, 10.0.0.1, /Users/<user>/) hide a real value
# on the same line, and an unanchored `\b10\.` allowed any public IP whose
# second octet is 10. Each match is now tested on its own against an
# anchored allowlist; only the line-context regex (op:// / vault://
# references) skips a whole line.
# P1-1: caps (10 lines/file, 200 total) bound memory on evil inputs. Why
# applied after filtering: capping first let 10 allowed placeholder lines
# push a real hit on line 11 out of view.
# Why one pipeline per file (fix round 1): a per-line loop forked 2-3
# processes per matching line, so caps no longer bounded the work (20k
# allowed emails took ~80 s), and bash `read` truncated a line at its first
# NUL, hiding any secret after it. `grep -aon` emits "N:match" per match;
# NULs are mapped to spaces; allow regexes are re-anchored past "N:".
grep_files() {
    local pattern="$1" allow="${2:-}" ctx="${3:-}"
    local allow_n="${allow//^/^[0-9]+:}"
    local results=""
    local total_lines=0
    local MAX_PER_FILE=10
    local MAX_TOTAL=200
    while IFS= read -r -d '' f; do
        local rel="${f#$DIR/}"
        is_ignored "$rel" && continue
        _is_text_file "$f" || continue
        local skip="" hits nfile
        if [ -n "$ctx" ]; then
            skip=$(LC_ALL=C grep -anE -e "$ctx" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ' ')
        fi
        # -a: _is_text_file only inspects 4 KiB; a later NUL would otherwise
        # turn grep's output into "Binary file matches" and drop every hit.
        hits=$(LC_ALL=C grep -aonE -e "$pattern" "$f" 2>/dev/null \
            | LC_ALL=C tr '\000' ' ' \
            | if [ -n "$allow" ]; then LC_ALL=C grep -vE -e "$allow_n"; else cat; fi \
            | R="$rel" LC_ALL=C awk -F: -v skip=" $skip " \
                'index(skip, " " $1 " ") == 0 && !seen[$1]++ { print ENVIRON["R"] ":" $0 }' \
            | head -n $MAX_PER_FILE)
        if [ -n "$hits" ]; then
            nfile=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
            results="$results
$hits"
            total_lines=$((total_lines + nfile))
            [ "$total_lines" -ge "$MAX_TOTAL" ] && break
        fi
    done < <(find_text_files -print0)
    printf '%s' "$results" | head -n $MAX_TOTAL
}

# ---------- 2. Absolute user paths ----------
# /Users/<user>/ /home/<user>/ C:\Users\<user>\  (<user> 处是实际用户名字符)
# 放行 <user> / <your-user> / <name> / <username> / <your-name> 占位符
path_hits=$(grep_files \
    '(/Users/[a-zA-Z0-9_.-]+/|/home/[a-zA-Z0-9_.-]+/|C:\\+Users\\+[a-zA-Z0-9_.-]+)' \
    '^(/Users/<|/home/<|C:\\+Users\\+<|/Users/\[|/home/\[)' \
    | head -20 || true)
if [ -n "$path_hits" ]; then
    append_report "❌ ABSOLUTE USER PATHS:
$path_hits"
fi

# ---------- 3. Email addresses ----------
# 放行明显的文档示例域 + anthropic/github 的 noreply 身份（按 match 锚定）
email_hits=$(grep_files \
    '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' \
    '@(example\.(com|org|net)|test\.(com|org)|localhost|foo\.bar|(your-?(domain|email|co)|mydomain|yourco|placeholder|xxx|somewhere)\.[a-z]{2,})$|^noreply@(anthropic|github)\.com$' \
    'op://|vault://' \
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
    '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.|192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|255\.255\.)|^(0\.0\.0\.0|1\.1\.1\.1|8\.8\.8\.8|8\.8\.4\.4|9\.9\.9\.9)$' \
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
    echo "（豁免目录仅限 gitx-release 自扫：tests/fixtures/、evals/data/、evals/fixtures/；显式白名单：.sanitize-ignore）"
    exit 1
fi

echo "✅ Release sanity clean${LABEL_SUFFIX} — 无个人信息/凭证/指纹泄漏"
exit 0
