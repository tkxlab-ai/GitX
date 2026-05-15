#!/bin/bash
# test_sanitize_output_format.sh — regression armor for v1.1.5 sanity-scan UX fixes
#
# Locks in the 4 bug fixes surfaced by the multi-project release log audit
# (ClaudeMeX / Handoff / 1by1 → gitx-release v1.1.5):
#
#   Bug A — every credential finding line carries its file path (not just the
#           first hit per file)
#   Bug B — findings show project-relative paths (not staging mktemp absolute
#           paths)
#   Bug C — --label flag distinguishes the two sanity-scan passes that
#           release.sh runs (staging vs .skill bundle)
#   Bug D — public IPs are HARD FAIL with ❌ icon (not ⚠️); RFC 5737
#           documentation IPs and common DNS placeholders are exempted
set -u

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANITIZE="$PROJECT_ROOT/scripts/release-sanitize.sh"

PASS=0
FAIL=0

assert() {
    local desc="$1" expected_exit="$2"; shift 2
    local out actual_exit
    out=$("$@" 2>&1)
    actual_exit=$?
    if [ "$actual_exit" = "$expected_exit" ]; then
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    else
        echo "  ❌ $desc — expected exit $expected_exit, got $actual_exit"
        echo "  ----- output -----"
        printf '%s\n' "$out" | sed 's/^/  | /'
        echo "  ------------------"
        FAIL=$((FAIL+1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2"; shift 2
    local out
    out=$("$@" 2>&1)
    if printf '%s' "$out" | grep -qF -- "$needle"; then
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    else
        echo "  ❌ $desc — expected to contain '$needle'"
        echo "  ----- output -----"
        printf '%s\n' "$out" | sed 's/^/  | /'
        echo "  ------------------"
        FAIL=$((FAIL+1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2"; shift 2
    local out
    out=$("$@" 2>&1)
    if printf '%s' "$out" | grep -qF -- "$needle"; then
        echo "  ❌ $desc — should NOT contain '$needle'"
        echo "  ----- output -----"
        printf '%s\n' "$out" | sed 's/^/  | /'
        echo "  ------------------"
        FAIL=$((FAIL+1))
    else
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    fi
}

assert_count() {
    local desc="$1" needle="$2" expected="$3"; shift 3
    local actual
    actual=$("$@" 2>&1 | grep -cF -- "$needle")
    if [ "$actual" = "$expected" ]; then
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    else
        echo "  ❌ $desc — expected $expected '$needle' lines, got $actual"
        FAIL=$((FAIL+1))
    fi
}

# ============================================================================
# Bug A — every credential hit carries its file path
# ============================================================================
echo "Bug A: per-hit file path in credential output"
A_DIR=$(mktemp -d)
mkdir -p "$A_DIR/sub"
# Same file, multiple credential types — assemble token strings to avoid
# secret-scanner self-flagging on this very test file.
SK="sk_"; GHP="ghp_"
{
    echo "harmless line"
    echo "${SK}live_51ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz123456789012"
    echo "${GHP}AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
} > "$A_DIR/sub/multi.txt"

# Both findings must reference sub/multi.txt explicitly.
assert_count "two credential hits both prefixed with file path" "sub/multi.txt:" 2 \
    bash "$SANITIZE" "$A_DIR"
assert_contains "GitHub PAT line carries file prefix" "sub/multi.txt:" \
    bash -c "bash '$SANITIZE' '$A_DIR' 2>&1 | grep -F 'GitHub personal token'"
assert_contains "Stripe key line carries file prefix" "sub/multi.txt:" \
    bash -c "bash '$SANITIZE' '$A_DIR' 2>&1 | grep -F 'Stripe secret key'"
rm -rf "$A_DIR"

# ============================================================================
# Bug B — findings show project-relative paths (not staging absolute)
# ============================================================================
echo ""
echo "Bug B: project-relative paths in all categories"
B_DIR=$(mktemp -d)
echo "Look at /Users/jarvis/work/file.txt" > "$B_DIR/abs-paths.md"
echo "Email contact: real.person@megacorp.io" > "$B_DIR/email.md"
echo "Server at 198.18.0.5 in production" > "$B_DIR/ip.md"

# Output must NOT contain the staging mktemp absolute path
assert_not_contains "abs-paths finding does not leak staging dir" "$B_DIR/abs-paths.md:" \
    bash "$SANITIZE" "$B_DIR"
assert_not_contains "email finding does not leak staging dir" "$B_DIR/email.md:" \
    bash "$SANITIZE" "$B_DIR"
assert_not_contains "IP finding does not leak staging dir" "$B_DIR/ip.md:" \
    bash "$SANITIZE" "$B_DIR"

# But the relative path MUST be present for each
assert_contains "abs-paths finding shows relative path" "abs-paths.md:1:" \
    bash "$SANITIZE" "$B_DIR"
assert_contains "email finding shows relative path" "email.md:1:" \
    bash "$SANITIZE" "$B_DIR"
assert_contains "IP finding shows relative path" "ip.md:1:" \
    bash "$SANITIZE" "$B_DIR"
rm -rf "$B_DIR"

# ============================================================================
# Bug C — --label flag annotates output
# ============================================================================
echo ""
echo "Bug C: --label distinguishes scan passes"
C_CLEAN=$(mktemp -d); echo "ok content" > "$C_CLEAN/file.md"
C_DIRTY=$(mktemp -d); echo "Look at /Users/jarvis/foo" > "$C_DIRTY/file.md"

assert_contains "clean scan with --label staging includes (staging) suffix" "(staging)" \
    bash "$SANITIZE" --label staging "$C_CLEAN"
assert_contains "clean scan with --label .skill includes (.skill) suffix" "(.skill)" \
    bash "$SANITIZE" --label .skill "$C_CLEAN"
assert_not_contains "clean scan without label has no parens suffix" "(staging)" \
    bash "$SANITIZE" "$C_CLEAN"
assert_contains "failed scan with label puts label in count line" "敏感信息 (staging)" \
    bash "$SANITIZE" --label staging "$C_DIRTY"
assert_contains "--label=value POSIX form is accepted" "(.skill bundle)" \
    bash "$SANITIZE" "--label=.skill bundle" "$C_CLEAN"
assert "empty --label value is rejected with exit 2" 2 \
    bash "$SANITIZE" --label "" "$C_CLEAN"
assert "unknown flag is rejected with exit 2" 2 \
    bash "$SANITIZE" --bogus "$C_CLEAN"
rm -rf "$C_CLEAN" "$C_DIRTY"

# ============================================================================
# Bug D — public IPs are HARD FAIL with ❌, RFC 5737 + DNS allowlist preserved
# ============================================================================
echo ""
echo "Bug D: public IPs hard-fail with ❌; RFC 5737 + DNS allowlist preserved"
D_DIR=$(mktemp -d)
{
    echo "Production VPS at 103.117.103.30 (must FAIL — real public IP)"
    echo "Documentation example uses 192.0.2.1 (RFC 5737 — must NOT fail)"
    echo "Another doc example: 198.51.100.42 (RFC 5737 — must NOT fail)"
    echo "Third RFC range: 203.0.113.99 (RFC 5737 — must NOT fail)"
    echo "Cloudflare DNS: 1.1.1.1 (industry placeholder — must NOT fail)"
    echo "Google DNS: 8.8.8.8 (industry placeholder — must NOT fail)"
    echo "Loopback: 127.0.0.1 (private — must NOT fail)"
    echo "Private LAN: 192.168.1.42 (private — must NOT fail)"
    echo "Link-local: 169.254.169.254 (private — must NOT fail)"
} > "$D_DIR/ips.md"

assert "real public IP causes exit 1" 1 \
    bash "$SANITIZE" "$D_DIR"
assert_contains "PUBLIC IP ADDRESSES category uses ❌ icon" "❌ PUBLIC IP ADDRESSES" \
    bash "$SANITIZE" "$D_DIR"
assert_not_contains "PUBLIC IP ADDRESSES does NOT use ⚠️ icon" "⚠️  PUBLIC IP ADDRESSES" \
    bash "$SANITIZE" "$D_DIR"
assert_contains "real public IP 103.117.103.30 is reported" "103.117.103.30" \
    bash "$SANITIZE" "$D_DIR"
assert_not_contains "RFC 5737 192.0.2.x not reported" "192.0.2.1" \
    bash "$SANITIZE" "$D_DIR"
assert_not_contains "RFC 5737 198.51.100.x not reported" "198.51.100.42" \
    bash "$SANITIZE" "$D_DIR"
assert_not_contains "RFC 5737 203.0.113.x not reported" "203.0.113.99" \
    bash "$SANITIZE" "$D_DIR"
assert_not_contains "Cloudflare 1.1.1.1 not reported" "1.1.1.1" \
    bash "$SANITIZE" "$D_DIR"
assert_not_contains "Google 8.8.8.8 not reported" "8.8.8.8" \
    bash "$SANITIZE" "$D_DIR"
assert_not_contains "loopback 127.0.0.1 not reported" "127.0.0.1" \
    bash "$SANITIZE" "$D_DIR"
assert_not_contains "RFC 1918 192.168.1.42 not reported" "192.168.1.42" \
    bash "$SANITIZE" "$D_DIR"
assert_not_contains "link-local 169.254.x not reported" "169.254.169.254" \
    bash "$SANITIZE" "$D_DIR"
rm -rf "$D_DIR"

# ============================================================================
# Cross-cutting: clean dir → exit 0 with success line, no FAILED box
# ============================================================================
echo ""
echo "Cross-cutting: clean dir behavior"
E_DIR=$(mktemp -d); echo "harmless markdown" > "$E_DIR/clean.md"
assert "clean dir exits 0" 0 \
    bash "$SANITIZE" "$E_DIR"
assert_contains "clean dir prints success" "Release sanity clean" \
    bash "$SANITIZE" "$E_DIR"
assert_not_contains "clean dir does not print FAILED box" "PRE-RELEASE SANITY CHECK FAILED" \
    bash "$SANITIZE" "$E_DIR"
rm -rf "$E_DIR"

echo ""
echo "════════════"
echo "  ─── $PASS passed, $FAIL failed"
echo "════════════"
[ "$FAIL" -eq 0 ]
