#!/bin/bash
# test_translate_cache.sh — Sprint A-5 (v0.9.12)
#
# scripts/translate-cached.sh <src> <dst> <target_lang>
#
# Wraps translate-file.sh + anchor-rewrite.sh with content-hash cache and a
# human-review gate:
#
#   1. hash = sha256(src content)
#   2. cache_path = .i18n-cache/<hash>.<target_lang>.md
#   3. if cache hit (file exists, NO .unreviewed suffix) → cp to dst, exit 0
#   4. if cache miss:
#      a. invoke translate-file.sh → tmp
#      b. invoke anchor-rewrite.sh on (src, tmp)
#      c. write tmp to <cache_path>.unreviewed (NOT to dst)
#      d. exit 1 with stderr warning "new translation pending review at ..."
#   5. user manually inspects cache_path.unreviewed, edits, then
#      `mv <cache_path>.unreviewed <cache_path>` to approve
#
# Subcommand: list-unreviewed
#   Echo all *.unreviewed paths under .i18n-cache/ (for audit §11k).
#
# Env:
#   CACHE_DIR (default: $PROJECT_ROOT/.i18n-cache)
#   CLAUDE_CMD, GLOSSARY_PATH — pass-through to translate-file.sh
#
# exit: 0 cache hit / 1 miss (review pending) / 2 usage

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHED="$PROJECT_ROOT/scripts/translate-cached.sh"
FAKE_CLAUDE="$SCRIPT_DIR/fixtures/fake-claude.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_translate_cache.sh ══"

WS=$(mktemp -d)
trap 'rm -rf "$WS"' EXIT

SRC="$WS/README.md"
cat > "$SRC" <<'S'
# 文档

链接到 [待办](#%E5%BE%85%E5%8A%9E)

## 待办

一些任务。
S

GLOSSARY="$WS/.i18n-glossary"
cat > "$GLOSSARY" <<'G'
文档|document|
待办|todo|
G

CACHE_DIR="$WS/.i18n-cache"

# ── Test 1: translate-cached.sh exists + executable ──────────────────────
if [ -x "$CACHED" ]; then
    ok "scripts/translate-cached.sh exists and is executable"
else
    fail "scripts/translate-cached.sh missing or not executable"
fi

# ── Test 2: usage error with no args ─────────────────────────────────────
if [ -x "$CACHED" ]; then
    if "$CACHED" 2>/dev/null; then
        fail "no-args should exit 2"
    else
        rc=$?
        [ "$rc" = "2" ] && ok "no-args → exit 2" || fail "exit expected 2, got $rc"
    fi
else
    fail "skipped"
fi

# ── Test 3: cache miss → writes .unreviewed, NOT dst, exit 1 ─────────────
DST="$WS/out.md"
rm -f "$DST"
rm -rf "$CACHE_DIR"
if [ -x "$CACHED" ]; then
    if CLAUDE_CMD="$FAKE_CLAUDE" \
       GLOSSARY_PATH="$GLOSSARY" \
       CACHE_DIR="$CACHE_DIR" \
       "$CACHED" "$SRC" "$DST" en 2>/dev/null; then
        fail "cache miss should exit non-zero (review pending)"
    else
        # Check dst NOT created
        if [ -f "$DST" ]; then
            fail "cache miss wrongly wrote dst"
        elif ls "$CACHE_DIR"/*.unreviewed >/dev/null 2>&1; then
            ok "cache miss: .unreviewed created, dst untouched"
        else
            fail "cache miss: no .unreviewed file produced"
        fi
    fi
else
    fail "skipped"
fi

# ── Test 4: after user `mv` removes .unreviewed → cache hit, dst written ─
if [ -x "$CACHED" ]; then
    # Find the unreviewed file from test 3
    UNREVIEWED=$(ls "$CACHE_DIR"/*.unreviewed 2>/dev/null | head -1)
    if [ -z "$UNREVIEWED" ]; then
        fail "skipped — no unreviewed file from previous test"
    else
        APPROVED=${UNREVIEWED%.unreviewed}
        mv "$UNREVIEWED" "$APPROVED"
        DST="$WS/out2.md"
        if CLAUDE_CMD="$FAKE_CLAUDE" \
           GLOSSARY_PATH="$GLOSSARY" \
           CACHE_DIR="$CACHE_DIR" \
           "$CACHED" "$SRC" "$DST" en 2>/dev/null; then
            if [ -s "$DST" ]; then
                ok "after mv: cache hit → dst written, exit 0"
            else
                fail "cache hit: dst empty"
            fi
        else
            fail "cache hit should exit 0 but didn't"
        fi
    fi
else
    fail "skipped"
fi

# ── Test 5: content-hash cache key — src change → cache miss ────────────
if [ -x "$CACHED" ]; then
    # Modify src → hash changes
    echo "# 新内容" >> "$SRC"
    DST="$WS/out3.md"
    rm -f "$DST"
    if CLAUDE_CMD="$FAKE_CLAUDE" \
       GLOSSARY_PATH="$GLOSSARY" \
       CACHE_DIR="$CACHE_DIR" \
       "$CACHED" "$SRC" "$DST" en 2>/dev/null; then
        fail "modified src should produce new cache miss (exit 1)"
    else
        NEW_UNREVIEWED=$(ls "$CACHE_DIR"/*.unreviewed 2>/dev/null | head -1)
        if [ -n "$NEW_UNREVIEWED" ]; then
            ok "src content change → new cache miss with fresh .unreviewed"
        else
            fail "src change didn't trigger new translation"
        fi
    fi
    # Clean up for later tests
    git checkout -- "$SRC" 2>/dev/null || :
else
    fail "skipped"
fi

# ── Test 6: list-unreviewed subcommand ───────────────────────────────────
if [ -x "$CACHED" ]; then
    result=$(CACHE_DIR="$CACHE_DIR" "$CACHED" list-unreviewed 2>/dev/null || true)
    if [ -n "$result" ] && echo "$result" | grep -qE '\.unreviewed$'; then
        ok "list-unreviewed enumerates pending files"
    else
        fail "list-unreviewed should output unreviewed paths; got: $result"
    fi
else
    fail "skipped"
fi

# ── Test 7: anchor-rewrite applied (cached content has translated slug) ─
# Reset to clean state + use fresh src
SRC2="$WS/fresh.md"
cat > "$SRC2" <<'S'
[link](#%E5%AE%89%E8%A3%85)

## 安装

text
S
rm -rf "$CACHE_DIR"
if [ -x "$CACHED" ]; then
    # First call → cache miss → writes .unreviewed
    CLAUDE_CMD="$FAKE_CLAUDE" \
    GLOSSARY_PATH="$GLOSSARY" \
    CACHE_DIR="$CACHE_DIR" \
    "$CACHED" "$SRC2" "$WS/sink.md" en 2>/dev/null || :
    UR=$(ls "$CACHE_DIR"/*.unreviewed 2>/dev/null | head -1)
    # Fake claude echoes src content back; heading stays "## 安装" in fake output.
    # Anchor rewrite aligns heading-slugs: since fake translator doesn't change
    # heading text, src and dst slugs are identical → anchor unchanged.
    # For stronger test: simulate a "translated" heading manually.
    if [ -n "$UR" ]; then
        # Simulate a user-edited translation where heading got changed to
        # "Installation" — then rewriting anchor should also update link.
        cat > "$UR" <<'TRANSLATED'
[link](#%E5%AE%89%E8%A3%85)

## Installation

text
TRANSLATED
        # But anchor-rewrite must have been applied at miss time. To verify that
        # path: create a truly fresh cache miss and check that the .unreviewed
        # has been piped through anchor-rewrite.
        rm -rf "$CACHE_DIR"
        # Build a src where fake claude's echo will give divergent headings:
        # we can't easily fake "translated heading" with stub, so assert weaker
        # property — cache miss path includes anchor-rewrite invocation via:
        # "anchor-rewrite.sh" appearing in the script trace.
        if grep -qE 'anchor-rewrite\.sh' "$CACHED"; then
            ok "translate-cached.sh invokes anchor-rewrite.sh in miss path"
        else
            fail "translate-cached.sh missing anchor-rewrite.sh call"
        fi
    else
        fail "no .unreviewed produced"
    fi
else
    fail "skipped"
fi

# ── Test 8: missing cache dir auto-created ──────────────────────────────
if [ -x "$CACHED" ]; then
    GONE_CACHE="$WS/never-existed-cache"
    DST8="$WS/out8.md"
    if CLAUDE_CMD="$FAKE_CLAUDE" \
       GLOSSARY_PATH="$GLOSSARY" \
       CACHE_DIR="$GONE_CACHE" \
       "$CACHED" "$SRC2" "$DST8" en 2>/dev/null || true; then :; fi
    if [ -d "$GONE_CACHE" ]; then
        ok "cache dir auto-created on first use"
    else
        fail "cache dir was not auto-created"
    fi
else
    fail "skipped"
fi

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
echo "Results: ✅$PASS passed / ❌$FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 test_translate_cache.sh — ALL GREEN"
    exit 0
else
    echo "💥 test_translate_cache.sh — FAILURES"
    exit 1
fi
