#!/bin/bash
# test_sanitize.sh — unit tests for release-sanitize.sh's 6 detection categories
# Tests each category with: TRUE POSITIVE (must be caught) + TRUE NEGATIVE (must be clean)
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SANITIZE="$SCRIPT_DIR/../scripts/release-sanitize.sh"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_sanitize.sh ══"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── Category 1: Credentials (via scan-credentials.sh) ──────────────────────

# TRUE POSITIVE: file with real-looking OpenAI key
mkdir -p "$TMP/tp_cred"
cat > "$TMP/tp_cred/config.md" <<'EOF'
OPENAI_KEY=sk-proj-TestFakeKeyABCDEFGHIJ1234567890abcdef
EOF
if ! bash "$SANITIZE" "$TMP/tp_cred" > /dev/null 2>&1; then
    ok "Cred TRUE POSITIVE: OpenAI key pattern detected"
else
    fail "Cred TRUE POSITIVE: OpenAI key NOT detected — scanner missed it"
fi

# TRUE NEGATIVE: placeholder only
mkdir -p "$TMP/tn_cred"
cat > "$TMP/tn_cred/config.md" <<'EOF'
OPENAI_KEY=<your-openai-key-here>
EOF
if bash "$SANITIZE" "$TMP/tn_cred" > /dev/null 2>&1; then
    ok "Cred TRUE NEGATIVE: placeholder not flagged"
else
    fail "Cred TRUE NEGATIVE: placeholder wrongly flagged as credential"
fi

# TRUE POSITIVE: classic OpenAI key (sk-[48 alnum])
mkdir -p "$TMP/tp_classic_openai"
cat > "$TMP/tp_classic_openai/config.md" <<'EOF'
OPENAI_KEY=sk-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuv
EOF
if ! bash "$SANITIZE" "$TMP/tp_classic_openai" > /dev/null 2>&1; then
    ok "Cred TRUE POSITIVE: classic OpenAI key (sk-[48]) detected"
else
    fail "Cred TRUE POSITIVE: classic OpenAI key NOT detected — scanner blind spot"
fi

# TRUE POSITIVE: npm auth token
mkdir -p "$TMP/tp_npm"
cat > "$TMP/tp_npm/config.md" <<'EOF'
NPM_TOKEN=npm_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij
EOF
if ! bash "$SANITIZE" "$TMP/tp_npm" > /dev/null 2>&1; then
    ok "Cred TRUE POSITIVE: npm token detected"
else
    fail "Cred TRUE POSITIVE: npm token NOT detected"
fi

# TRUE POSITIVE: .pem file with private key
mkdir -p "$TMP/tp_pem"
cat > "$TMP/tp_pem/server.pem" <<'EOF'
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA0Z3VS5JJcds3xfn/ygWYF2TDOuZTAIOHEE0J
-----END RSA PRIVATE KEY-----
EOF
if ! bash "$SANITIZE" "$TMP/tp_pem" > /dev/null 2>&1; then
    ok "File ext TRUE POSITIVE: .pem file with private key detected"
else
    fail "File ext TRUE POSITIVE: .pem file NOT scanned — extension missing from find_text_files"
fi

# TRUE POSITIVE: .env file with credential
mkdir -p "$TMP/tp_env"
cat > "$TMP/tp_env/.env" <<'EOF'
OPENAI_KEY=sk-proj-TestFakeKeyABCDEFGHIJ1234567890abcdef
EOF
if ! bash "$SANITIZE" "$TMP/tp_env" > /dev/null 2>&1; then
    ok "File ext TRUE POSITIVE: .env file with credential detected"
else
    fail "File ext TRUE POSITIVE: .env file NOT scanned — extension missing from find_text_files"
fi

# ── Category 2: Absolute user paths ────────────────────────────────────────

mkdir -p "$TMP/tp_path"
echo "See /Users/jarvis/myproject/docs for details" > "$TMP/tp_path/README.md"
if ! bash "$SANITIZE" "$TMP/tp_path" > /dev/null 2>&1; then
    ok "Path TRUE POSITIVE: /Users/jarvis/ detected"
else
    fail "Path TRUE POSITIVE: /Users/jarvis/ NOT detected"
fi

mkdir -p "$TMP/tn_path"
echo "See ~/myproject/docs or <user>/myproject for details" > "$TMP/tn_path/README.md"
if bash "$SANITIZE" "$TMP/tn_path" > /dev/null 2>&1; then
    ok "Path TRUE NEGATIVE: ~/ and <user> placeholder not flagged"
else
    fail "Path TRUE NEGATIVE: ~/ or <user> wrongly flagged as absolute path"
fi

# ── Category 3: Real email addresses ───────────────────────────────────────

mkdir -p "$TMP/tp_email"
echo "Contact: jarvis@realdomain.io" > "$TMP/tp_email/CONTRIBUTING.md"
if ! bash "$SANITIZE" "$TMP/tp_email" > /dev/null 2>&1; then
    ok "Email TRUE POSITIVE: real email detected"
else
    fail "Email TRUE POSITIVE: real email NOT detected"
fi

mkdir -p "$TMP/tn_email"
echo "Contact: user@example.com or noreply@anthropic.com" > "$TMP/tn_email/CONTRIBUTING.md"
if bash "$SANITIZE" "$TMP/tn_email" > /dev/null 2>&1; then
    ok "Email TRUE NEGATIVE: example.com/anthropic.com not flagged"
else
    fail "Email TRUE NEGATIVE: example.com wrongly flagged as real email"
fi

# ── Category 8: Dockerfile/Makefile/cfg/ini/conf file types (S2-3) ──────────

mkdir -p "$TMP/tp_docker"
cat > "$TMP/tp_docker/Dockerfile" <<'EOF'
FROM ubuntu:22.04
# Contact: jarvis@realdomain.io
EOF
if ! bash "$SANITIZE" "$TMP/tp_docker" > /dev/null 2>&1; then
    ok "Dockerfile TRUE POSITIVE: real email detected in Dockerfile"
else
    fail "Dockerfile TRUE POSITIVE: email NOT detected — Dockerfile not scanned"
fi

mkdir -p "$TMP/tp_makefile"
cat > "$TMP/tp_makefile/Makefile" <<'EOF'
all:
	echo "/Users/jarvis/project"
EOF
if ! bash "$SANITIZE" "$TMP/tp_makefile" > /dev/null 2>&1; then
    ok "Makefile TRUE POSITIVE: abs path detected in Makefile"
else
    fail "Makefile TRUE POSITIVE: abs path NOT detected — Makefile not scanned"
fi

mkdir -p "$TMP/tp_ini"
cat > "$TMP/tp_ini/config.ini" <<'EOF'
[settings]
path=/Users/jarvis/config
EOF
if ! bash "$SANITIZE" "$TMP/tp_ini" > /dev/null 2>&1; then
    ok "INI TRUE POSITIVE: abs path detected in config.ini"
else
    fail "INI TRUE POSITIVE: abs path NOT detected — .ini not scanned"
fi

mkdir -p "$TMP/tp_cfg"
cat > "$TMP/tp_cfg/app.cfg" <<'EOF'
host=server@realdomain.io
EOF
if ! bash "$SANITIZE" "$TMP/tp_cfg" > /dev/null 2>&1; then
    ok "CFG TRUE POSITIVE: real email detected in app.cfg"
else
    fail "CFG TRUE POSITIVE: email NOT detected — .cfg not scanned"
fi

mkdir -p "$TMP/tp_conf"
cat > "$TMP/tp_conf/nginx.conf" <<'EOF'
root /Users/jarvis/www;
EOF
if ! bash "$SANITIZE" "$TMP/tp_conf" > /dev/null 2>&1; then
    ok "CONF TRUE POSITIVE: abs path detected in nginx.conf"
else
    fail "CONF TRUE POSITIVE: abs path NOT detected — .conf not scanned"
fi

# ── Category 9: evals/ exemption scope (S2-4) ───────────────────────────────
# evals/data/ and evals/fixtures/ should be exempt; evals root files should be scanned

mkdir -p "$TMP/evals_root/evals"
cat > "$TMP/evals_root/evals/eval_runner.sh" <<'EOF'
# Contact: jarvis@realdomain.io
EOF
if ! bash "$SANITIZE" "$TMP/evals_root" > /dev/null 2>&1; then
    ok "evals root TRUE POSITIVE: email detected in evals/eval_runner.sh (not exempt)"
else
    fail "evals root TRUE POSITIVE: evals/eval_runner.sh wrongly exempt — should be scanned"
fi

mkdir -p "$TMP/evals_data/evals/data"
cat > "$TMP/evals_data/evals/data/sample.txt" <<'EOF'
jarvis@realdomain.io
EOF
if bash "$SANITIZE" "$TMP/evals_data" > /dev/null 2>&1; then
    ok "evals/data/ TRUE NEGATIVE: exempt from scanning"
else
    fail "evals/data/ TRUE NEGATIVE: evals/data/ should be exempt but was flagged"
fi

mkdir -p "$TMP/evals_fixtures/evals/fixtures"
cat > "$TMP/evals_fixtures/evals/fixtures/fake_cred.txt" <<'EOF'
jarvis@realdomain.io
EOF
if bash "$SANITIZE" "$TMP/evals_fixtures" > /dev/null 2>&1; then
    ok "evals/fixtures/ TRUE NEGATIVE: exempt from scanning"
else
    fail "evals/fixtures/ TRUE NEGATIVE: evals/fixtures/ should be exempt but was flagged"
fi

# ── Category 7: Files with spaces in their names (S2-1) ─────────────────────

mkdir -p "$TMP/tp_spacepath"
# 파일명에 공백 포함 — xargs 방식에서는 조용히 건너뜀
cat > "$TMP/tp_spacepath/my file.md" <<'EOF'
See /Users/jarvis/secret for details
EOF
if ! bash "$SANITIZE" "$TMP/tp_spacepath" > /dev/null 2>&1; then
    ok "Space filename TRUE POSITIVE: /Users/jarvis/ detected in 'my file.md'"
else
    fail "Space filename TRUE POSITIVE: /Users/jarvis/ NOT detected — xargs split bug"
fi

mkdir -p "$TMP/tn_spacepath"
cat > "$TMP/tn_spacepath/my file.md" <<'EOF'
See ~/myproject or <user>/project for details
EOF
if bash "$SANITIZE" "$TMP/tn_spacepath" > /dev/null 2>&1; then
    ok "Space filename TRUE NEGATIVE: placeholder not flagged in 'my file.md'"
else
    fail "Space filename TRUE NEGATIVE: placeholder wrongly flagged in 'my file.md'"
fi

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
