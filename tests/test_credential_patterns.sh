#!/bin/bash
# test_credential_patterns.sh — RED→GREEN: scan-credentials.sh must detect
# Stripe live/test keys, GCP service account JSON, JWT bearer tokens,
# AWS keys, GitHub PATs, Azure SAS, and SSH ed25519 private key headers.
# TDD P1-6 + v1.0.8 hardening (extended coverage)
#
# Note on string assembly: every credential token is split across multiple
# variables (no literal `eyJ`, `sk_live_`, `ghp_`, `ASIA<16 chars>` etc.
# appears in source) so secret-scanners (semgrep, trufflehog) running on
# this test file don't false-positive. Strings are reassembled at runtime
# and piped to the scanner under test — behaviour is identical, source is
# clean.
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$ROOT/scripts/scan-credentials.sh"
echo "=== test_credential_patterns: extended credential detection ==="

# check_detected <desc> <content> <expected-label>
# Why exit==1 AND label (not "any non-zero"): exit 2 is a usage error, and a
# hit under the wrong label means a different pattern masked a blind spot.
check_detected() {
    local desc="$1" content="$2" want="$3" out rc
    out=$(printf '%s\n' "$content" | "$SCAN" 2>&1) && rc=0 || rc=$?
    if [ "$rc" -ne 1 ]; then
        fail "$desc: exit $rc (want 1)"
    elif ! grep -qF -- "$want" <<<"$out"; then
        fail "$desc: label '$want' missing (got: $out)"
    else
        ok "$desc: detected as '$want'"
    fi
}

check_clean() {
    local desc="$1" content="$2" rc
    printf '%s\n' "$content" | "$SCAN" > /dev/null 2>&1 && rc=0 || rc=$?
    if [ "$rc" -eq 0 ]; then ok "$desc: clean (exit 0)"; else fail "$desc: exit $rc (want 0)"; fi
}

# Helper: assemble base64-url JWT segments without `eyJ` literal in source.
# Each segment is split between "ey" and "J<rest>" so no single literal
# matches the JWT regex on its own.
JWT_HDR_A='ey'; JWT_HDR_B='J'; JWT_HDR_C='hbGciOiJIUzI1NiJ9'
JWT_PL_A='ey';  JWT_PL_B='J';  JWT_PL_C='zdWIiOiIxMjM0NTY3ODkwIn0'
JWT_SIG='SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c'
JWT_BODY="${JWT_HDR_A}${JWT_HDR_B}${JWT_HDR_C}.${JWT_PL_A}${JWT_PL_B}${JWT_PL_C}.${JWT_SIG}"

# --- v1.0.5 baseline patterns ---
# Stripe live/test keys (split between sk_ and live_/test_)
SK_PFX='sk_'
check_detected "Stripe live key" "${SK_PFX}live_51ABCDEFGHIJKLMNOPQabcdefghijklmn" "Stripe secret key"
check_detected "Stripe test key" "${SK_PFX}test_4eC39HqLyjWDarjtT1zdp7dc12345678" "Stripe secret key"

# JWT with Bearer prefix
check_detected "JWT bearer (with prefix)" "Bearer ${JWT_BODY}" "JWT bearer token (with Bearer prefix)"

# SSH/PEM private key header
PEM_HDR='-----BEGIN OPENSSH PRIVATE'
check_detected "SSH ed25519 private key" "${PEM_HDR} KEY-----" "Private key header"

# --- v1.0.8 hardening: extended coverage ---
# AWS temporary STS access key (split ASIA prefix)
AWS_A='ASI'; AWS_B='A'
check_detected "AWS ASIA STS key" "${AWS_A}${AWS_B}XXXXXXXXXXXXXXXX" "AWS temporary access key ID (STS)"

# AWS secret access key in env-style key=value (40 base64-ish chars)
AWS_KV_KEY='aws_secret_access''_key'
check_detected "AWS secret key=value" "${AWS_KV_KEY} = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" "AWS secret access key"

# GitHub fine-grained PAT (82 chars after github_pat_)
GH_PFX='github''_pat_'
check_detected "GitHub fine-grained PAT" "${GH_PFX}$(printf 'A%.0s' {1..82})" "GitHub fine-grained PAT"

# GitHub user-to-server token (ghu_)
GH_USRV='gh''u_'
check_detected "GitHub user-to-server token" "${GH_USRV}$(printf '0%.0s' {1..36})" "GitHub user-to-server token"

# Bare JWT (no Bearer prefix — common in env files / JSON config)
check_detected "JWT bare" "${JWT_BODY}" "JWT bearer token (bare)"

# GCP service-account JSON marker
GCP_TYPE='"type"'
GCP_VAL='"service_account"'
check_detected "GCP service-account JSON" "{${GCP_TYPE}: ${GCP_VAL}, \"project_id\": \"my-proj\"}" "GCP service-account JSON marker"

# Azure storage connection string
AZ_PFX='DefaultEndpointsProtocol=https;AccountName=mystore'
AZ_KEY=";AccountKey=$(printf 'a%.0s' {1..88})=="
check_detected "Azure connection string" "${AZ_PFX}${AZ_KEY};EndpointSuffix=core.windows.net" "Azure storage connection string"

# --- v1.13.0 remediation: modern formats (review: PKCS#8 / PGP / mixed-case
# fine-grained PAT / uppercase env AWS secret / Anthropic OAuth / OpenAI svcacct)
DASH5='-----'; BEG='BEGIN'
check_detected "PKCS#8 private key" "${DASH5}${BEG} PRIVATE KEY${DASH5}" "Private key header"
check_detected "PGP private key block" "${DASH5}${BEG} PGP PRIVATE KEY BLOCK${DASH5}" "Private key header"
check_detected "OpenSSH private key" "${DASH5}${BEG} OPENSSH PRIVATE KEY${DASH5}" "Private key header"
MIX82="$(printf 'aB3_%.0s' {1..20})xY"
check_detected "GitHub fine-grained PAT (mixed case)" "${GH_PFX}${MIX82}" "GitHub fine-grained PAT"
B64_40="$(printf 'wJal%.0s' {1..10})"
AWS_ENV='AWS_SECRET_ACCESS''_KEY'
check_detected "AWS secret (uppercase env)" "${AWS_ENV}=${B64_40}" "AWS secret access key"
check_detected "AWS secret (yaml quoted)" "${AWS_KV_KEY}: \"${B64_40}\"" "AWS secret access key"
# Fix round 1 (M3): JSON puts the key's closing quote before the colon
check_detected "AWS secret (JSON)" "{\"${AWS_ENV}\": \"${B64_40}\"}" "AWS secret access key"
ANT='sk-''ant-oat01-'
check_detected "Anthropic OAuth token" "${ANT}$(printf 'Ab_-%.0s' {1..10})" "Anthropic API key"
SVC='sk-''svcacct-'
check_detected "OpenAI service-account key" "${SVC}$(printf 'Ab12%.0s' {1..10})" "OpenAI service-account key"

# Negatives
check_clean "certificate header" "${DASH5}${BEG} CERTIFICATE${DASH5}"
check_clean "clean line" "nothing to see here"
check_clean "short github_pat_" "${GH_PFX}short"

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
