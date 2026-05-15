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

check_detected() {
    local label="$1" content="$2"
    if echo "$content" | "$SCAN" > /dev/null 2>&1; then
        fail "$label: not detected (exit 0 when should have found credential)"
    else
        ok "$label: correctly detected"
    fi
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
check_detected "Stripe live key" "${SK_PFX}live_51ABCDEFGHIJKLMNOPQabcdefghijklmn"
check_detected "Stripe test key" "${SK_PFX}test_4eC39HqLyjWDarjtT1zdp7dc12345678"

# JWT with Bearer prefix
check_detected "JWT bearer (with prefix)" "Bearer ${JWT_BODY}"

# SSH/PEM private key header
PEM_HDR='-----BEGIN OPENSSH PRIVATE'
check_detected "SSH ed25519 private key" "${PEM_HDR} KEY-----"

# --- v1.0.8 hardening: extended coverage ---
# AWS temporary STS access key (split ASIA prefix)
AWS_A='ASI'; AWS_B='A'
check_detected "AWS ASIA STS key" "${AWS_A}${AWS_B}XXXXXXXXXXXXXXXX"

# AWS secret access key in env-style key=value (40 base64-ish chars)
AWS_KV_KEY='aws_secret_access''_key'
check_detected "AWS secret key=value" "${AWS_KV_KEY} = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

# GitHub fine-grained PAT (82 chars after github_pat_)
GH_PFX='github''_pat_'
check_detected "GitHub fine-grained PAT" "${GH_PFX}$(printf 'A%.0s' {1..82})"

# GitHub user-to-server token (ghu_)
GH_USRV='gh''u_'
check_detected "GitHub user-to-server token" "${GH_USRV}$(printf '0%.0s' {1..36})"

# Bare JWT (no Bearer prefix — common in env files / JSON config)
check_detected "JWT bare" "${JWT_BODY}"

# GCP service-account JSON marker
GCP_TYPE='"type"'
GCP_VAL='"service_account"'
check_detected "GCP service-account JSON" "{${GCP_TYPE}: ${GCP_VAL}, \"project_id\": \"my-proj\"}"

# Azure storage connection string
AZ_PFX='DefaultEndpointsProtocol=https;AccountName=mystore'
AZ_KEY=";AccountKey=$(printf 'a%.0s' {1..88})=="
check_detected "Azure connection string" "${AZ_PFX}${AZ_KEY};EndpointSuffix=core.windows.net"

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
