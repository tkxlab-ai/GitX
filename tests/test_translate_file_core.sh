#!/bin/bash
# test_translate_file_core.sh — Sprint A-3 (v0.9.12)
#
# scripts/translate-file.sh 核心翻译引擎:
#   - usage: translate-file.sh <src> <dst> <target_lang>
#   - 读 glossary (via GLOSSARY_PATH env or default), 作为 few-shot 喂给 LLM
#   - 调 $CLAUDE_CMD (默认 `claude`) 子进程做实际翻译
#   - 写译文到 dst 文件
#
# 测试策略: 注入 FAKE_CLAUDE_CMD 替身,避免真调 LLM + 烧钱 + 非确定性。
# 用 FAKE_CLAUDE_LOG 捕获 prompt 内容做断言。
#
# exit: 0 pass / 1 fail

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TRANSLATE="$PROJECT_ROOT/scripts/translate-file.sh"
FAKE_CLAUDE="$SCRIPT_DIR/fixtures/fake-claude.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_translate_file_core.sh ══"

# Workspace + canned fixtures
WS=$(mktemp -d)
trap 'rm -rf "$WS"' EXIT

SRC="$WS/README.md"
cat > "$SRC" <<'SRC'
# 测试文档

这是发版流水线的 README。使用 `scripts/release.sh v1.0.0` 触发。

不要翻译 $SOURCE_DATE_EPOCH 和 --force 这样的 token。
SRC

GLOSSARY="$WS/.i18n-glossary"
cat > "$GLOSSARY" <<'G'
发版|release|
流水线|pipeline|
文档|document|

[NO_TRANSLATE]
  scripts/*
  $SOURCE_DATE_EPOCH
  --force
G

# ── Test 1: translate-file.sh exists + executable ────────────────────────
if [ -x "$TRANSLATE" ]; then
    ok "scripts/translate-file.sh exists and is executable"
else
    fail "scripts/translate-file.sh missing or not executable"
fi

# ── Test 2: usage error with no args ─────────────────────────────────────
if [ -x "$TRANSLATE" ]; then
    if "$TRANSLATE" 2>/dev/null; then
        fail "no-args should exit 2"
    else
        rc=$?
        if [ "$rc" = "2" ]; then
            ok "no-args → exit 2 (usage)"
        else
            fail "no-args expected exit 2, got $rc"
        fi
    fi
else
    fail "skipped"
fi

# ── Test 3: missing src file → exit 1 ────────────────────────────────────
if [ -x "$TRANSLATE" ]; then
    if CLAUDE_CMD="$FAKE_CLAUDE" "$TRANSLATE" "$WS/nonexistent.md" "$WS/out.md" en 2>/dev/null; then
        fail "missing src should fail"
    else
        ok "missing src → exit non-zero"
    fi
else
    fail "skipped"
fi

# ── Test 4: missing claude binary → exit 1 with clear error ──────────────
if [ -x "$TRANSLATE" ]; then
    if CLAUDE_CMD=/definitely/not/a/claude "$TRANSLATE" "$SRC" "$WS/out.md" en 2>/dev/null; then
        fail "missing CLAUDE_CMD should fail"
    else
        ok "missing claude binary → exit non-zero"
    fi
else
    fail "skipped"
fi

# ── Test 5: happy path with fake claude produces dst file ────────────────
if [ -x "$TRANSLATE" ]; then
    out="$WS/out.md"
    rm -f "$out"
    if CLAUDE_CMD="$FAKE_CLAUDE" \
       GLOSSARY_PATH="$GLOSSARY" \
       "$TRANSLATE" "$SRC" "$out" en >/dev/null 2>&1 \
       && [ -s "$out" ]; then
        ok "happy path writes non-empty dst"
    else
        fail "happy path failed to produce dst"
    fi
else
    fail "skipped"
fi

# ── Test 6: glossary few-shot is embedded in the LLM prompt ──────────────
if [ -x "$TRANSLATE" ]; then
    log="$WS/claude.log"
    rm -f "$log"
    if CLAUDE_CMD="$FAKE_CLAUDE" \
       GLOSSARY_PATH="$GLOSSARY" \
       FAKE_CLAUDE_LOG="$log" \
       "$TRANSLATE" "$SRC" "$WS/out2.md" en >/dev/null 2>&1 \
       && grep -qE '发版.*release' "$log" \
       && grep -qE '流水线.*pipeline' "$log"; then
        ok "glossary few-shot appears in LLM prompt"
    else
        fail "glossary few-shot missing from prompt; log head:"
        [ -f "$log" ] && head -30 "$log"
    fi
else
    fail "skipped"
fi

# ── Test 7: NO_TRANSLATE section reaches the prompt ──────────────────────
if [ -x "$TRANSLATE" ]; then
    log="$WS/claude2.log"
    rm -f "$log"
    if CLAUDE_CMD="$FAKE_CLAUDE" \
       GLOSSARY_PATH="$GLOSSARY" \
       FAKE_CLAUDE_LOG="$log" \
       "$TRANSLATE" "$SRC" "$WS/out3.md" en >/dev/null 2>&1 \
       && grep -qiE 'no.?translate|preserve.*verbatim|do not translate' "$log" \
       && grep -qE 'scripts/\*' "$log"; then
        ok "NO_TRANSLATE section embedded in prompt"
    else
        fail "NO_TRANSLATE section missing from prompt"
    fi
else
    fail "skipped"
fi

# ── Test 8: target language reaches prompt (en / ja differentiated) ─────
if [ -x "$TRANSLATE" ]; then
    log="$WS/claude3.log"
    rm -f "$log"
    if CLAUDE_CMD="$FAKE_CLAUDE" \
       GLOSSARY_PATH="$GLOSSARY" \
       FAKE_CLAUDE_LOG="$log" \
       "$TRANSLATE" "$SRC" "$WS/out4.md" ja >/dev/null 2>&1 \
       && grep -qiE '(to|target)[: ]+ja|japanese' "$log"; then
        ok "target-lang ja reaches prompt"
    else
        fail "target-lang ja missing from prompt"
    fi
else
    fail "skipped"
fi

# ── Test 9: source content reaches prompt via <SOURCE>..</SOURCE> ────────
if [ -x "$TRANSLATE" ]; then
    log="$WS/claude4.log"
    rm -f "$log"
    if CLAUDE_CMD="$FAKE_CLAUDE" \
       GLOSSARY_PATH="$GLOSSARY" \
       FAKE_CLAUDE_LOG="$log" \
       "$TRANSLATE" "$SRC" "$WS/out5.md" en >/dev/null 2>&1 \
       && grep -q '^<SOURCE>$' "$log" \
       && grep -q '^</SOURCE>$' "$log" \
       && grep -q '这是发版流水线的 README' "$log"; then
        ok "source content wrapped in <SOURCE>..</SOURCE> markers"
    else
        fail "source markers / content missing; log:"
        [ -f "$log" ] && tail -15 "$log"
    fi
else
    fail "skipped"
fi

# ── Test 10: LLM failure → exit non-zero + dst not overwritten ──────────
if [ -x "$TRANSLATE" ]; then
    out="$WS/preserve.md"
    echo "PRESERVED_CONTENT" > "$out"
    if FAKE_CLAUDE_FAIL=1 \
       CLAUDE_CMD="$FAKE_CLAUDE" \
       GLOSSARY_PATH="$GLOSSARY" \
       "$TRANSLATE" "$SRC" "$out" en >/dev/null 2>&1; then
        fail "LLM failure should cause non-zero exit"
    else
        if grep -q "PRESERVED_CONTENT" "$out"; then
            ok "LLM failure → exit non-zero + dst preserved"
        else
            fail "LLM failure corrupted existing dst"
        fi
    fi
else
    fail "skipped"
fi

# ── Test 11: dst contains the fake-translation marker (end-to-end) ──────
if [ -x "$TRANSLATE" ]; then
    out="$WS/e2e.md"
    if CLAUDE_CMD="$FAKE_CLAUDE" \
       GLOSSARY_PATH="$GLOSSARY" \
       "$TRANSLATE" "$SRC" "$out" en >/dev/null 2>&1 \
       && grep -q 'FAKE_TRANSLATION' "$out"; then
        ok "fake translation marker written to dst (plumbing works end-to-end)"
    else
        fail "end-to-end plumbing broken"
    fi
else
    fail "skipped"
fi

# ── Test 12: missing glossary is not fatal (empty few-shot OK) ──────────
if [ -x "$TRANSLATE" ]; then
    if CLAUDE_CMD="$FAKE_CLAUDE" \
       GLOSSARY_PATH=/nonexistent-glossary \
       "$TRANSLATE" "$SRC" "$WS/out6.md" en >/dev/null 2>&1 \
       && [ -s "$WS/out6.md" ]; then
        ok "missing glossary → translate still succeeds (empty few-shot)"
    else
        fail "missing glossary should not block translation"
    fi
else
    fail "skipped"
fi

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
echo "Results: ✅$PASS passed / ❌$FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 test_translate_file_core.sh — ALL GREEN"
    exit 0
else
    echo "💥 test_translate_file_core.sh — FAILURES"
    exit 1
fi
