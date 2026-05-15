#!/bin/bash
# test_token_usage.sh — runtime context token analysis for packaged skills
#
# The skill being packaged carries hidden runtime cost for its end users:
# SKILL.md lands in AI context on every trigger; references/ land on-demand.
# This analysis must be produced as a release artifact (TOKEN_USAGE.md) so
# users see the per-invocation token budget BEFORE installing.
#
# Scope:
#   - emit-token-usage.sh scans a target skill dir (SKILL.md + references/)
#   - classifies files: always-loaded | on-demand | not-runtime-context
#   - emits TOKEN_USAGE.md with baseline + scenario table
#   - release.sh §2.7b invokes it; §2.8 checksums covers it
#   - release-audit.sh §11j validates the artifact
#
# exit: 0=all pass, 1=any fail

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$PROJECT_ROOT/scripts/release.sh"
AUDIT_SH="$PROJECT_ROOT/scripts/release-audit.sh"
EMIT_SH="$PROJECT_ROOT/scripts/emit-token-usage.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_token_usage.sh ══"

# ── Test 1: emit-token-usage.sh exists and is executable ──────────────────
if [ -x "$EMIT_SH" ]; then
    ok "scripts/emit-token-usage.sh exists and is executable"
else
    fail "scripts/emit-token-usage.sh missing or not executable"
fi

# Build a tmp fixture skill: SKILL.md + references/ + scripts/ + root docs
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

cat > "$FIXTURE/SKILL.md" <<'MD'
---
name: demo-skill
description: Demo skill for token usage analysis testing
---

# Demo Skill

This skill demonstrates runtime token consumption. For deep policy details
consult references/POLICY.md when the user asks about compliance rules.
MD

mkdir -p "$FIXTURE/references" "$FIXTURE/scripts" "$FIXTURE/assets"
# A mid-size reference file (~400 chars → ~200 tokens)
cat > "$FIXTURE/references/POLICY.md" <<'MD'
# Policy

Rule 1: Always lowercase.
Rule 2: Never bypass validation gates.
Rule 3: Keep scripts idempotent.
Rule 4: Log structured output to stderr.
Rule 5: Use exit 0/1/2 codes faithfully.
Rule 6: Document side effects in the header comment.
MD
cat > "$FIXTURE/scripts/run.sh" <<'SH'
#!/bin/bash
echo "demo"
SH
chmod +x "$FIXTURE/scripts/run.sh"
cat > "$FIXTURE/README.md" <<'MD'
# Demo README — human-facing, not runtime context.
MD
cat > "$FIXTURE/CHANGELOG.md" <<'MD'
# Changelog — bundle metadata only.
MD

OUT="$FIXTURE/TOKEN_USAGE.md"

# ── Test 2: emit produces TOKEN_USAGE.md with correct header ─────────────
if [ -x "$EMIT_SH" ]; then
    if "$EMIT_SH" "$FIXTURE" "$OUT" >/dev/null 2>&1 && [ -f "$OUT" ]; then
        if grep -qE '^#[[:space:]]+Token Usage Analysis' "$OUT"; then
            ok "TOKEN_USAGE.md has correct top-level header"
        else
            fail "TOKEN_USAGE.md missing '# Token Usage Analysis' header"
        fi
    else
        fail "emit-token-usage.sh failed to produce TOKEN_USAGE.md"
    fi
else
    fail "skipped (emit-token-usage.sh missing)"
fi

# ── Test 3: SKILL.md is classified as always-loaded baseline ─────────────
if [ -f "$OUT" ]; then
    if grep -qiE 'SKILL\.md' "$OUT" && grep -qiE 'baseline|always.?loaded|always loaded' "$OUT"; then
        ok "SKILL.md labeled as always-loaded baseline"
    else
        fail "SKILL.md not labeled as always-loaded baseline"
    fi
else
    fail "skipped (no output file)"
fi

# ── Test 4: references/ classified as on-demand with token count ─────────
if [ -f "$OUT" ]; then
    if grep -qE 'references/POLICY\.md' "$OUT" && grep -qiE 'on.?demand' "$OUT"; then
        ok "references/ labeled as on-demand"
    else
        fail "references/ not properly classified as on-demand"
    fi
else
    fail "skipped"
fi

# ── Test 5: scripts/ classified as NOT entering runtime context ──────────
if [ -f "$OUT" ]; then
    # scripts/run.sh must appear labeled with something like "not loaded",
    # "executed", "bundle-only" — anything that signals non-context
    if grep -qE 'scripts/run\.sh|scripts/' "$OUT" \
       && grep -qiE 'not[[:space:]]+loaded|executed|bundle.?only|not[[:space:]]+runtime' "$OUT"; then
        ok "scripts/ labeled as non-runtime (executed via Bash tool)"
    else
        fail "scripts/ missing or not labeled as non-runtime"
    fi
else
    fail "skipped"
fi

# ── Test 6: root docs (README/CHANGELOG) classified as bundle-only ───────
if [ -f "$OUT" ]; then
    if grep -qE 'README\.md|CHANGELOG\.md' "$OUT" \
       && grep -qiE 'bundle.?only|not.?loaded|not[[:space:]]+runtime' "$OUT"; then
        ok "root docs labeled as bundle-only (not runtime context)"
    else
        fail "root docs missing or not labeled as bundle-only"
    fi
else
    fail "skipped"
fi

# ── Test 7: TOKEN_USAGE.md contains scenario table with token counts ─────
# At least: baseline (trigger-only) + typical (+on-demand) + worst-case
if [ -f "$OUT" ]; then
    # Token count must be a real integer (≥ 10) attached to SKILL.md row
    if awk '
      /SKILL\.md/ {
        for (i=1; i<=NF; i++) {
          gsub(/[,|]/, "", $i)
          if ($i ~ /^[0-9]+$/ && $i+0 >= 10) { print "ok"; exit 0 }
        }
      }
    ' "$OUT" | grep -q ok; then
        ok "SKILL.md has quantitative token count (≥ 10)"
    else
        fail "SKILL.md row lacks numeric token count"
    fi
else
    fail "skipped"
fi

# ── Test 8: scenario table mentions Sonnet cost or per-call estimate ─────
if [ -f "$OUT" ]; then
    if grep -qiE 'Sonnet|Haiku|cost|\$[0-9]+\.[0-9]+|per.?call|per.?invocation' "$OUT"; then
        ok "TOKEN_USAGE.md includes cost / per-invocation estimate"
    else
        fail "TOKEN_USAGE.md missing cost or per-invocation estimate"
    fi
else
    fail "skipped"
fi

# ── Test 9: tokenizer methodology disclosed (±20% tier0 or tiktoken) ─────
if [ -f "$OUT" ]; then
    if grep -qiE 'tiktoken|cl100k|heuristic|±[0-9]+%|methodology|tokenizer' "$OUT"; then
        ok "TOKEN_USAGE.md discloses tokenizer / precision"
    else
        fail "TOKEN_USAGE.md missing tokenizer methodology"
    fi
else
    fail "skipped"
fi

# ── Test 10: release.sh §2.7b invokes emit-token-usage.sh ────────────────
if grep -qE 'emit-token-usage\.sh|TOKEN_USAGE\.md' "$RELEASE_SH"; then
    ok "release.sh §2.7b wires emit-token-usage.sh / TOKEN_USAGE.md"
else
    fail "release.sh does not produce TOKEN_USAGE.md"
fi

# ── Test 11: release.sh §2.8 checksums covers TOKEN_USAGE.md (5 files) ──
if awk '/2\.8 checksums/,/RELEASE_NOTES/' "$RELEASE_SH" | grep -qE 'TOKEN_USAGE\.md'; then
    ok "release.sh §2.8 checksums includes TOKEN_USAGE.md"
else
    fail "release.sh §2.8 checksums missing TOKEN_USAGE.md coverage"
fi

# ── Test 12: release-audit.sh §11j validates TOKEN_USAGE.md ──────────────
if grep -qE '§11j|TOKEN_USAGE\.md' "$AUDIT_SH"; then
    ok "release-audit.sh has §11j / references TOKEN_USAGE.md"
else
    fail "release-audit.sh missing §11j TOKEN_USAGE.md validation"
fi

# ── Test 13: §11j checks TOKEN_USAGE.md existence ────────────────────────
if awk '/§11j|§ *11j|TOKEN_USAGE/,/§11|^echo ""$|^# -/' "$AUDIT_SH" \
     | grep -qE 'test -f.*TOKEN_USAGE\.md|-f.*TOKEN_USAGE\.md'; then
    ok "§11j checks TOKEN_USAGE.md existence via test -f"
else
    fail "§11j does not check TOKEN_USAGE.md existence"
fi

# ── Test 14: §11j verifies checksums.txt covers TOKEN_USAGE.md ───────────
if awk '/§11j|TOKEN_USAGE/,/^echo ""$|# ---/' "$AUDIT_SH" \
     | grep -qE 'checksums\.txt.*TOKEN_USAGE|TOKEN_USAGE.*checksums'; then
    ok "§11j verifies checksums.txt covers TOKEN_USAGE.md"
else
    fail "§11j missing checksums coverage verification"
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
echo "Results: ✅$PASS passed / ❌$FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 test_token_usage.sh — ALL GREEN"
    exit 0
else
    echo "💥 test_token_usage.sh — FAILURES"
    exit 1
fi
