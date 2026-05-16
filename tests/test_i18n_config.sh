#!/bin/bash
# test_i18n_config.sh — Sprint A-1 (v0.9.12)
#
# .i18n-config 是项目级 i18n 配置文件，定义:
#   - primary-language: 源文语言 (ISO 639-1)
#   - target-languages: 目标语言列表 (逗号分隔)
#   - strict:  翻译清单，缺失/陈旧 → release FAIL
#   - warn:    翻译清单，缺失/陈旧 → release WARN
#   - lock:    禁译清单 (如 LICENSE，法律文件)
#   - strict-glob / warn-glob: 通配形式
#
# 解析器 scripts/i18n-config-loader.sh 提供 CLI 子命令:
#   parse          → emit shell-evalable env vars
#   strictness F   → strict|warn|lock|none
#   list strict    → one-per-line
#   list warn / list lock / list targets
#   primary        → primary-language value
#
# 硬性默认: LICENSE 与 CODE_OF_CONDUCT.md 永远在 lock，即使 config 未声明。
# 配置文件缺失 → 用全默认 (primary=zh, targets=en, 无 strict/warn)，stderr 打 warning 但不 exit 1。
#
# exit: 0 all pass / 1 any fail

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOADER="$PROJECT_ROOT/scripts/i18n-config-loader.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_i18n_config.sh ══"

# ── Test 1: loader exists and executable ─────────────────────────────────
if [ -x "$LOADER" ]; then
    ok "scripts/i18n-config-loader.sh exists and is executable"
else
    fail "scripts/i18n-config-loader.sh missing or not executable"
fi

# Build a tmp fixture .i18n-config
FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

cat > "$FIXTURE_DIR/.i18n-config" <<'CONFIG'
# .i18n-config — project-level i18n declarations
primary-language: zh
target-languages: en, ja

strict:
  README.md
  RELEASE_NOTES.md
  TOKEN_USAGE.md
  SKILL.md

strict-glob:
  references/*.md

warn:
  CONTRIBUTING.md
  ROADMAP.md

lock:
  LICENSE
  CUSTOM_LOCKED.md
CONFIG

# ── Test 2: primary-language parsed correctly ────────────────────────────
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --config "$FIXTURE_DIR/.i18n-config" primary 2>/dev/null || echo ERROR)
    if [ "$result" = "zh" ]; then
        ok "primary returns 'zh'"
    else
        fail "primary expected 'zh', got '$result'"
    fi
else
    fail "skipped (loader missing)"
fi

# ── Test 3: target-languages parsed as list ──────────────────────────────
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --config "$FIXTURE_DIR/.i18n-config" list targets 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')
    if echo "$result" | grep -q "en" && echo "$result" | grep -q "ja"; then
        ok "list targets contains en + ja"
    else
        fail "list targets expected 'en ja', got '$result'"
    fi
else
    fail "skipped"
fi

# ── Test 4: strict list enumeration ──────────────────────────────────────
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --config "$FIXTURE_DIR/.i18n-config" list strict 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')
    if echo "$result" | grep -q "README.md" \
       && echo "$result" | grep -q "RELEASE_NOTES.md" \
       && echo "$result" | grep -q "TOKEN_USAGE.md" \
       && echo "$result" | grep -q "SKILL.md"; then
        ok "list strict contains all 4 strict files"
    else
        fail "list strict missing expected entries, got '$result'"
    fi
else
    fail "skipped"
fi

# ── Test 5: warn list enumeration ────────────────────────────────────────
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --config "$FIXTURE_DIR/.i18n-config" list warn 2>/dev/null)
    if echo "$result" | grep -q "CONTRIBUTING.md" && echo "$result" | grep -q "ROADMAP.md"; then
        ok "list warn contains CONTRIBUTING.md + ROADMAP.md"
    else
        fail "list warn missing entries, got '$result'"
    fi
else
    fail "skipped"
fi

# ── Test 6: lock list includes declared + hardcoded defaults ─────────────
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --config "$FIXTURE_DIR/.i18n-config" list lock 2>/dev/null)
    if echo "$result" | grep -q "LICENSE" \
       && echo "$result" | grep -q "CUSTOM_LOCKED.md" \
       && echo "$result" | grep -q "CODE_OF_CONDUCT.md"; then
        ok "list lock contains declared + hardcoded (CODE_OF_CONDUCT.md)"
    else
        fail "list lock missing CODE_OF_CONDUCT.md default, got '$result'"
    fi
else
    fail "skipped"
fi

# ── Test 7: strictness classifier — strict file ──────────────────────────
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --config "$FIXTURE_DIR/.i18n-config" strictness README.md 2>/dev/null)
    if [ "$result" = "strict" ]; then
        ok "strictness README.md = strict"
    else
        fail "strictness README.md expected 'strict', got '$result'"
    fi
else
    fail "skipped"
fi

# ── Test 8: strictness classifier — lock file (even without declared) ───
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --config "$FIXTURE_DIR/.i18n-config" strictness LICENSE 2>/dev/null)
    if [ "$result" = "lock" ]; then
        ok "strictness LICENSE = lock"
    else
        fail "strictness LICENSE expected 'lock', got '$result'"
    fi
else
    fail "skipped"
fi

# ── Test 9: strictness — unknown file = none ─────────────────────────────
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --config "$FIXTURE_DIR/.i18n-config" strictness random-foo.md 2>/dev/null)
    if [ "$result" = "none" ]; then
        ok "strictness random-foo.md = none"
    else
        fail "strictness random-foo.md expected 'none', got '$result'"
    fi
else
    fail "skipped"
fi

# ── Test 10: glob support for references/*.md ────────────────────────────
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --config "$FIXTURE_DIR/.i18n-config" strictness "references/TKX_Policy.md" 2>/dev/null)
    if [ "$result" = "strict" ]; then
        ok "strictness references/TKX_Policy.md = strict (via glob)"
    else
        fail "strictness references/*.md glob expected 'strict', got '$result'"
    fi
else
    fail "skipped"
fi

# ── Test 11: missing config file → emit defaults, not exit 1 ─────────────
if [ -x "$LOADER" ]; then
    if "$LOADER" --config /nonexistent-config primary >/dev/null 2>&1; then
        result=$("$LOADER" --config /nonexistent-config primary 2>/dev/null)
        if [ "$result" = "zh" ]; then
            ok "missing config → primary defaults to zh (no crash)"
        else
            fail "missing config primary expected 'zh', got '$result'"
        fi
    else
        fail "missing config should not crash (exit 0 expected)"
    fi
else
    fail "skipped"
fi

# ── Test 12: LICENSE always in lock even with empty config ───────────────
EMPTY_CONFIG=$(mktemp)
cat > "$EMPTY_CONFIG" <<'EOF'
primary-language: zh
target-languages: en
EOF
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --config "$EMPTY_CONFIG" strictness LICENSE 2>/dev/null)
    if [ "$result" = "lock" ]; then
        ok "LICENSE always lock (hardcoded default even with empty lock list)"
    else
        fail "LICENSE expected 'lock' even with empty config, got '$result'"
    fi
else
    fail "skipped"
fi
rm -f "$EMPTY_CONFIG"

# ── Test 13: comment lines + blank lines ignored ─────────────────────────
COMMENTED_CONFIG=$(mktemp)
cat > "$COMMENTED_CONFIG" <<'EOF'
# This is a comment

primary-language: zh

# Another comment
target-languages: en

strict:
  # inline comment
  README.md

  # blank line above should not break parse
  SKILL.md
EOF
if [ -x "$LOADER" ]; then
    result=$("$LOADER" --config "$COMMENTED_CONFIG" list strict 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')
    if echo "$result" | grep -q "README.md" && echo "$result" | grep -q "SKILL.md"; then
        ok "comments and blank lines ignored correctly"
    else
        fail "comment/blank parse broken, got '$result'"
    fi
else
    fail "skipped"
fi
rm -f "$COMMENTED_CONFIG"

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
echo "Results: ✅$PASS passed / ❌$FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 test_i18n_config.sh — ALL GREEN"
    exit 0
else
    echo "💥 test_i18n_config.sh — FAILURES"
    exit 1
fi
