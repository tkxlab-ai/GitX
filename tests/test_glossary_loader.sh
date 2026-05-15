#!/bin/bash
# test_glossary_loader.sh — Sprint A-2 (v0.9.12)
#
# .i18n-glossary 是术语表文件，让 translate-file.sh 以 few-shot 强制术语一致。
#
# 格式:
#   # comment
#   <zh>|<en>|<context/note>           # 普通术语条目
#
#   [NO_TRANSLATE]                      # 段首标记，后面是禁译 pattern (glob)
#     scripts/*
#     $SOURCE_DATE_EPOCH
#     --force
#
# 解析器 scripts/glossary-loader.sh 提供:
#   emit-few-shot            → 生成 LLM prompt prefix (markdown 表 + NO_TRANSLATE 列表)
#   lookup <zh>              → echo 对应 en (missing → exit 1)
#   is-no-translate <token>  → exit 0 if matches NO_TRANSLATE glob, else 1
#   list terms               → one line per entry: zh|en (for audit §11n reverse check)
#   list no-translate        → one pattern per line
#
# exit: 0 pass / 1 fail

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOADER="$PROJECT_ROOT/scripts/glossary-loader.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_glossary_loader.sh ══"

# ── Test 1: loader exists ────────────────────────────────────────────────
if [ -x "$LOADER" ]; then
    ok "scripts/glossary-loader.sh exists and is executable"
else
    fail "scripts/glossary-loader.sh missing or not executable"
fi

# Build fixture
FIXTURE=$(mktemp)
trap 'rm -f "$FIXTURE"' EXIT

cat > "$FIXTURE" <<'GLOSSARY'
# TKX Git Release Skill glossary
# format: <zh>|<en>|<optional context>

发版|release|verb action; prefer over "publish" in release.sh context
打包|package|noun; use "packaging" for the action (gerund)
政策|policy|
审计|audit|
脱敏|sanitize|verb; scanning for secrets/PII
版本|version|
签名|signing|GPG signing in v1.0+

[NO_TRANSLATE]
  scripts/*
  *.sh
  $SOURCE_DATE_EPOCH
  $VERSION
  --force
  --dry-run
  SKILL.md
GLOSSARY

# ── Test 2: lookup existing term ─────────────────────────────────────────
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --glossary "$FIXTURE" lookup 发版 2>/dev/null || echo MISS)
    if [ "$result" = "release" ]; then
        ok "lookup 发版 → release"
    else
        fail "lookup 发版 expected 'release', got '$result'"
    fi
else
    fail "skipped"
fi

# ── Test 3: lookup missing term → exit 1 ─────────────────────────────────
if [ -x "$LOADER" ]; then
    if "$LOADER" --glossary "$FIXTURE" lookup 不存在的词 2>/dev/null; then
        fail "lookup missing term should exit 1"
    else
        ok "lookup missing term exits non-zero"
    fi
else
    fail "skipped"
fi

# ── Test 4: list terms emits zh|en pairs ─────────────────────────────────
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --glossary "$FIXTURE" list terms 2>/dev/null)
    if echo "$result" | grep -qE '^发版\|release$' \
       && echo "$result" | grep -qE '^打包\|package$' \
       && echo "$result" | grep -qE '^签名\|signing$'; then
        ok "list terms emits all zh|en pairs"
    else
        fail "list terms missing entries; got:\n$result"
    fi
else
    fail "skipped"
fi

# ── Test 5: is-no-translate matches glob ─────────────────────────────────
if [ -x "$LOADER" ]; then
    if "$LOADER" --glossary "$FIXTURE" is-no-translate "scripts/release.sh" >/dev/null 2>&1; then
        ok "is-no-translate scripts/release.sh matches scripts/* glob"
    else
        fail "is-no-translate scripts/release.sh expected match"
    fi
else
    fail "skipped"
fi

# ── Test 6: is-no-translate exact env var ────────────────────────────────
if [ -x "$LOADER" ]; then
    if "$LOADER" --glossary "$FIXTURE" is-no-translate '$SOURCE_DATE_EPOCH' >/dev/null 2>&1; then
        ok "is-no-translate \$SOURCE_DATE_EPOCH exact match"
    else
        fail "is-no-translate \$SOURCE_DATE_EPOCH expected match"
    fi
else
    fail "skipped"
fi

# ── Test 7: is-no-translate regular word → no match ──────────────────────
if [ -x "$LOADER" ]; then
    if "$LOADER" --glossary "$FIXTURE" is-no-translate "随便一个普通词" >/dev/null 2>&1; then
        fail "is-no-translate random word should not match"
    else
        ok "is-no-translate 随便词 → no match (correct)"
    fi
else
    fail "skipped"
fi

# ── Test 8: emit-few-shot contains glossary table + NO_TRANSLATE list ────
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --glossary "$FIXTURE" emit-few-shot 2>/dev/null)
    # Must contain: some prompt instruction + 2+ glossary entries + NO_TRANSLATE patterns
    if echo "$result" | grep -qE '发版.*release' \
       && echo "$result" | grep -qE '打包.*package' \
       && echo "$result" | grep -qiE 'no.?translate|do not translate|禁译' \
       && echo "$result" | grep -qE 'scripts/\*|\\\$SOURCE_DATE_EPOCH'; then
        ok "emit-few-shot contains glossary entries + NO_TRANSLATE instructions"
    else
        fail "emit-few-shot output incomplete; got first 20 lines:"
        echo "$result" | head -20
    fi
else
    fail "skipped"
fi

# ── Test 9: comments + blank lines ignored ───────────────────────────────
COMMENTED=$(mktemp)
cat > "$COMMENTED" <<'G'
# Pure comment

发版|release|
# another comment
打包|package|

[NO_TRANSLATE]
  # comment inside
  scripts/*
G
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --glossary "$COMMENTED" list terms 2>/dev/null)
    if echo "$result" | grep -qE '^发版\|release$' \
       && echo "$result" | grep -qE '^打包\|package$' \
       && ! echo "$result" | grep -qE 'comment'; then
        ok "comments and blank lines ignored"
    else
        fail "comment handling broken; got:\n$result"
    fi
else
    fail "skipped"
fi
rm -f "$COMMENTED"

# ── Test 10: reverse-consistency detection — same zh → multiple en ───────
DUP=$(mktemp)
cat > "$DUP" <<'G'
发版|release|in release.sh
发版|publish|in marketing copy
打包|package|
G
if [ -x "$LOADER" ]; then
    # New subcommand: detect-conflicts → exit 1 if ambiguous
    if "$LOADER" --glossary "$DUP" detect-conflicts 2>/dev/null; then
        fail "detect-conflicts should report 发版 having two en mappings"
    else
        ok "detect-conflicts flags 发版 → release + publish as conflict"
    fi
else
    fail "skipped"
fi
rm -f "$DUP"

# ── Test 11: missing glossary → emit-few-shot returns empty but exits 0 ──
if [ -x "$LOADER" ]; then
    if "$LOADER" --glossary /nonexistent-glossary emit-few-shot >/dev/null 2>&1; then
        ok "missing glossary → emit-few-shot exits 0 (empty output OK)"
    else
        fail "missing glossary should not crash"
    fi
else
    fail "skipped"
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
echo "Results: ✅$PASS passed / ❌$FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 test_glossary_loader.sh — ALL GREEN"
    exit 0
else
    echo "💥 test_glossary_loader.sh — FAILURES"
    exit 1
fi
