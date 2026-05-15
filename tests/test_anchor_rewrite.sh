#!/bin/bash
# test_anchor_rewrite.sh — Sprint A-4 (v0.9.12)
#
# scripts/anchor-rewrite.sh <src.md> <dst.md>
#   Position-aligns headings between src and dst.
#   Rewrites links in dst that point to src-slugs → equivalent dst-slugs.
#
# GitHub slug algorithm subset:
#   - lowercase
#   - drop emoji + most punctuation
#   - replace whitespace with `-`
#   - CJK kept verbatim → percent-encoded by GitHub renderer
#   - duplicate headings get `-1`, `-2` suffixes
#
# Boundaries:
#   - code blocks (``` fences) protected
#   - external URLs (containing ://) protected
#   - inline `code spans` containing #anchor — protected
#
# Modifies dst in place. exit 0 success, 1 internal error, 2 usage.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REWRITE="$PROJECT_ROOT/scripts/anchor-rewrite.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_anchor_rewrite.sh ══"

WS=$(mktemp -d)
trap 'rm -rf "$WS"' EXIT

# ── Test 1: script exists + executable ───────────────────────────────────
if [ -x "$REWRITE" ]; then
    ok "scripts/anchor-rewrite.sh exists and is executable"
else
    fail "scripts/anchor-rewrite.sh missing or not executable"
fi

# ── Test 2: usage error with no args ─────────────────────────────────────
if [ -x "$REWRITE" ]; then
    if "$REWRITE" 2>/dev/null; then
        fail "no-args should exit 2"
    else
        rc=$?
        if [ "$rc" = "2" ]; then
            ok "no-args → exit 2"
        else
            fail "no-args expected 2, got $rc"
        fi
    fi
else
    fail "skipped"
fi

# ── Test 3: ASCII heading anchor rewrite (en→zh) ─────────────────────────
SRC="$WS/src.md"
DST="$WS/dst.md"
cat > "$SRC" <<'S'
# Title

See [installation](#installation) for details.

## Installation

Some text.
S
cat > "$DST" <<'D'
# 标题

详见 [installation](#installation) 安装说明。

## 安装

文本。
D
if [ -x "$REWRITE" ] && "$REWRITE" "$SRC" "$DST" 2>/dev/null; then
    if grep -qE '\(#%E5%AE%89%E8%A3%85\)' "$DST"; then
        ok "rewrite (#installation) → (#%E5%AE%89%E8%A3%85) when zh heading is 安装"
    else
        fail "anchor not rewritten; dst:"
        cat "$DST"
    fi
else
    fail "rewrite invocation failed"
fi

# ── Test 4: CJK heading anchor rewrite (zh→en) ───────────────────────────
SRC2="$WS/src2.md"
DST2="$WS/dst2.md"
cat > "$SRC2" <<'S'
# 文档

[查看待办](#%E5%BE%85%E5%8A%9E)

## 待办

- 任务 1
S
cat > "$DST2" <<'D'
# Document

[See TODO](#%E5%BE%85%E5%8A%9E)

## TODO

- Task 1
D
if [ -x "$REWRITE" ] && "$REWRITE" "$SRC2" "$DST2" 2>/dev/null; then
    if grep -qE '\(#todo\)' "$DST2"; then
        ok "rewrite CJK %E5%BE%85%E5%8A%9E → todo"
    else
        fail "CJK anchor rewrite failed; dst:"
        cat "$DST2"
    fi
else
    fail "rewrite invocation failed for CJK"
fi

# ── Test 5: code block protection ────────────────────────────────────────
SRC3="$WS/src3.md"
DST3="$WS/dst3.md"
cat > "$SRC3" <<'S'
## 安装

```bash
# example: link to #安装
echo "see (#%E5%AE%89%E8%A3%85)"
```
S
cat > "$DST3" <<'D'
## Installation

```bash
# example: link to #安装
echo "see (#%E5%AE%89%E8%A3%85)"
```
D
if [ -x "$REWRITE" ] && "$REWRITE" "$SRC3" "$DST3" 2>/dev/null; then
    # The literal `#%E5%AE%89%E8%A3%85` inside the code block must remain unchanged
    if grep -qE '#%E5%AE%89%E8%A3%85' "$DST3"; then
        ok "code block anchors NOT rewritten"
    else
        fail "code block content was incorrectly rewritten; dst:"
        cat "$DST3"
    fi
else
    fail "rewrite failed for code block test"
fi

# ── Test 6: external URL protection ──────────────────────────────────────
SRC4="$WS/src4.md"
DST4="$WS/dst4.md"
cat > "$SRC4" <<'S'
## 安装

[external](https://example.com/page#%E5%AE%89%E8%A3%85)

[internal](#%E5%AE%89%E8%A3%85)
S
cat > "$DST4" <<'D'
## Installation

[external](https://example.com/page#%E5%AE%89%E8%A3%85)

[internal](#%E5%AE%89%E8%A3%85)
D
if [ -x "$REWRITE" ] && "$REWRITE" "$SRC4" "$DST4" 2>/dev/null; then
    # External URL must keep its original fragment unchanged
    if grep -qE 'https://example.com/page#%E5%AE%89%E8%A3%85' "$DST4"; then
        # Internal must be rewritten to #installation
        if grep -qE '\[internal\]\(#installation\)' "$DST4"; then
            ok "external URL fragment preserved, internal rewritten"
        else
            fail "internal anchor not rewritten correctly; dst:"
            cat "$DST4"
        fi
    else
        fail "external URL fragment was modified; dst:"
        cat "$DST4"
    fi
else
    fail "rewrite failed for external URL test"
fi

# ── Test 7: heading count mismatch → warn but proceed on matching prefix ─
SRC5="$WS/src5.md"
DST5="$WS/dst5.md"
cat > "$SRC5" <<'S'
## 安装

## 配置

## 调试
S
cat > "$DST5" <<'D'
## Installation

## Configuration

[ref](#%E5%AE%89%E8%A3%85)
D
if [ -x "$REWRITE" ] && "$REWRITE" "$SRC5" "$DST5" 2>/dev/null; then
    if grep -qE '\(#installation\)' "$DST5"; then
        ok "mismatched heading counts: prefix-aligned anchor still rewritten"
    else
        fail "mismatch handling broke prefix alignment; dst:"
        cat "$DST5"
    fi
else
    fail "rewrite invocation failed"
fi

# ── Test 8: duplicate heading slug with -N suffix ───────────────────────
SRC6="$WS/src6.md"
DST6="$WS/dst6.md"
cat > "$SRC6" <<'S'
## 章节

[一](#%E7%AB%A0%E8%8A%82)

## 章节

[二](#%E7%AB%A0%E8%8A%82-1)
S
cat > "$DST6" <<'D'
## Section

[one](#%E7%AB%A0%E8%8A%82)

## Section

[two](#%E7%AB%A0%E8%8A%82-1)
D
if [ -x "$REWRITE" ] && "$REWRITE" "$SRC6" "$DST6" 2>/dev/null; then
    if grep -qE '\[one\]\(#section\)' "$DST6" \
       && grep -qE '\[two\]\(#section-1\)' "$DST6"; then
        ok "duplicate slugs handled with -1 suffix"
    else
        fail "duplicate slug handling broken; dst:"
        cat "$DST6"
    fi
else
    fail "rewrite failed for duplicates"
fi

# ── Test 9: file with no headings → no error, dst unchanged ─────────────
SRC7="$WS/src7.md"
DST7="$WS/dst7.md"
echo "Just plain text, no headings, no anchors." > "$SRC7"
cp "$SRC7" "$DST7"
ORIG_HASH=$(shasum -a 256 "$DST7" | awk '{print $1}')
if [ -x "$REWRITE" ] && "$REWRITE" "$SRC7" "$DST7" 2>/dev/null; then
    NEW_HASH=$(shasum -a 256 "$DST7" | awk '{print $1}')
    if [ "$ORIG_HASH" = "$NEW_HASH" ]; then
        ok "no headings → dst byte-identical"
    else
        fail "no-heading file was modified unexpectedly"
    fi
else
    fail "rewrite failed on no-heading file"
fi

# ── Test 10: idempotency — running twice has no further effect ──────────
SRC8="$WS/src8.md"
DST8="$WS/dst8.md"
cat > "$SRC8" <<'S'
## 安装

[ref](#%E5%AE%89%E8%A3%85)
S
cat > "$DST8" <<'D'
## Installation

[ref](#%E5%AE%89%E8%A3%85)
D
if [ -x "$REWRITE" ] && "$REWRITE" "$SRC8" "$DST8" 2>/dev/null; then
    HASH1=$(shasum -a 256 "$DST8" | awk '{print $1}')
    "$REWRITE" "$SRC8" "$DST8" 2>/dev/null
    HASH2=$(shasum -a 256 "$DST8" | awk '{print $1}')
    if [ "$HASH1" = "$HASH2" ]; then
        ok "idempotent: 2nd run produces byte-identical dst"
    else
        fail "rewrite not idempotent (drift between runs)"
    fi
else
    fail "rewrite failed for idempotency test"
fi

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
echo "Results: ✅$PASS passed / ❌$FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 test_anchor_rewrite.sh — ALL GREEN"
    exit 0
else
    echo "💥 test_anchor_rewrite.sh — FAILURES"
    exit 1
fi
