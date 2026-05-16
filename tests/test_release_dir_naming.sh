#!/bin/bash
# test_release_dir_naming.sh — v0.9.10
# Release dirs must be Release/<PROJECT_NAME>-<VERSION>/, not the legacy
# Release/<VERSION>/. Names without project prefix are ambiguous in
# multi-project contexts and don't match the artifact naming convention
# (`<PROJECT_NAME>-<VERSION>.skill` / `<PROJECT_NAME>-<VERSION>-source.tar.gz`).
#
# exit: 0=all pass, 1=any fail

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$PROJECT_ROOT/scripts/release.sh"
AUDIT_SH="$PROJECT_ROOT/scripts/release-audit.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_release_dir_naming.sh ══"

# ── Test 1: release.sh RELEASE_DIR includes PROJECT_NAME ──────────────────
if grep -qE 'RELEASE_DIR="?\$PROJECT_ROOT/Release/\$\{?PROJECT_NAME\}?-\$\{?VERSION\}?"?' "$RELEASE_SH"; then
    ok "release.sh RELEASE_DIR uses \$PROJECT_NAME-\$VERSION"
else
    fail "release.sh RELEASE_DIR is still Release/\$VERSION (legacy naming)"
fi

# ── Test 2: release-audit.sh DIR matches new format ───────────────────────
if grep -qE 'DIR="?\$PROJECT_ROOT/Release/\$\{?PROJECT_NAME\}?-\$\{?VERSION\}?"?' "$AUDIT_SH"; then
    ok "release-audit.sh DIR uses \$PROJECT_NAME-\$VERSION"
else
    fail "release-audit.sh DIR is still Release/\$VERSION (legacy naming)"
fi

# ── Test 3: release.sh latest symlink target also includes PROJECT_NAME ──
# `ln -sfn <target> latest` — target arg must use $PROJECT_NAME-$VERSION
if grep -qE 'ln -sfn .*\$\{?PROJECT_NAME\}?-\$\{?VERSION\}?.*latest' "$RELEASE_SH"; then
    ok "release.sh latest symlink target uses \$PROJECT_NAME-\$VERSION"
else
    fail "release.sh latest symlink target still uses bare \$VERSION"
fi

# ── Test 4: audit §8 latest expectation matches new target format ─────────
# audit reads readlink(latest); new value should be matched against
# ${PROJECT_NAME}-${VERSION}, not bare ${VERSION}.
block=$(awk '/^# --- §8 Release\/latest/,/^# --- §9/' "$AUDIT_SH")
if echo "$block" | grep -qE '\$\{?PROJECT_NAME\}?-\$\{?VERSION\}?|\$\{PROJECT_NAME\}-\$\{VERSION\}'; then
    ok "audit §8 compares latest against \$PROJECT_NAME-\$VERSION"
else
    fail "audit §8 still compares against bare \$VERSION"
fi

# ── Test 5: functional — current Release/latest follows new format ───────
LATEST_TARGET=$(readlink "$PROJECT_ROOT/Release/latest" 2>/dev/null || echo "")
if [ -z "$LATEST_TARGET" ]; then
    ok "(skip) Release/latest absent — cannot verify post-release format"
elif echo "$LATEST_TARGET" | grep -qE '^[a-z_][a-z0-9_]*-v[0-9]+\.[0-9]+'; then
    ok "Release/latest target '$LATEST_TARGET' follows new <name>-<version> format"
else
    fail "Release/latest target '$LATEST_TARGET' uses legacy bare-version format"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
