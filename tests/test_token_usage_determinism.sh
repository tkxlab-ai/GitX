#!/bin/bash
# test_token_usage_determinism.sh — RED→GREEN: emit-token-usage.sh must use
# SOURCE_DATE_EPOCH for the "Generated:" timestamp, not wall-clock date.
# TDD P0-1: wall-clock TS → SOURCE_DATE_EPOCH ladder (like emit-sbom.sh)
set -euo pipefail

PASS=0; FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMIT_SH="$ROOT/scripts/emit-token-usage.sh"

echo "══ test_token_usage_determinism.sh ══"

# Build minimal fixture
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

cat > "$FIXTURE/SKILL.md" <<'MD'
---
name: demo-skill
description: Demo skill for determinism testing
---
# Demo Skill
MD

mkdir -p "$FIXTURE/references"
echo "# Policy ref" > "$FIXTURE/references/POLICY.md"

OUT1="$FIXTURE/out1.md"
OUT2="$FIXTURE/out2.md"

# epoch 1000000000 == 2001-09-09T01:46:40Z
EPOCH=1000000000
EXPECTED_TS="2001-09-09T01:46:40Z"

# ── Test 1: SOURCE_DATE_EPOCH timestamp appears in output ────────────────
if SOURCE_DATE_EPOCH="$EPOCH" "$EMIT_SH" "$FIXTURE" "$OUT1" >/dev/null 2>&1; then
    if grep -qF "$EXPECTED_TS" "$OUT1"; then
        ok "SOURCE_DATE_EPOCH=$EPOCH → timestamp $EXPECTED_TS in output"
    else
        ACTUAL=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$OUT1" | head -1 || echo "(none)")
        fail "timestamp mismatch: expected $EXPECTED_TS, got $ACTUAL"
    fi
else
    fail "emit-token-usage.sh invocation failed"
fi

# ── Test 2: two runs with same SOURCE_DATE_EPOCH are identical ───────────
if SOURCE_DATE_EPOCH="$EPOCH" "$EMIT_SH" "$FIXTURE" "$OUT2" >/dev/null 2>&1; then
    if diff -q "$OUT1" "$OUT2" >/dev/null 2>&1; then
        ok "two runs with same SOURCE_DATE_EPOCH produce identical output"
    else
        fail "two runs with same SOURCE_DATE_EPOCH differ (non-deterministic)"
    fi
else
    fail "second emit-token-usage.sh invocation failed"
fi

# ── Test 3: timestamp NOT same as today's wall-clock date ────────────────
TODAY=$(date -u "+%Y-%m-%d")
if [ -f "$OUT1" ] && ! grep -q "$TODAY" "$OUT1"; then
    ok "output does not embed today's wall-clock date when SOURCE_DATE_EPOCH set"
else
    fail "output embeds today's wall-clock date despite SOURCE_DATE_EPOCH set"
fi

echo ""
echo "──────────────────────────────────────────"
echo "Results: ✅$PASS passed / ❌$FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 test_token_usage_determinism.sh — ALL GREEN"
    exit 0
else
    echo "💥 test_token_usage_determinism.sh — FAILURES"
    exit 1
fi
