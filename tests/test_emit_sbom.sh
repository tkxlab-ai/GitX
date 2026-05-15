#!/bin/bash
# test_emit_sbom.sh — tests for scripts/emit-sbom.sh (extracted from release.sh §2.7)
# exit: 0=all pass, 1=any fail

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_emit_sbom.sh ══"

# ── Test 1: emit-sbom.sh exists ────────────────────────────────────────────
if [ -f "$PROJECT_ROOT/scripts/emit-sbom.sh" ]; then
    ok "scripts/emit-sbom.sh exists"
else
    fail "scripts/emit-sbom.sh does not exist"
fi

# ── Test 2: emit-sbom.sh is executable ─────────────────────────────────────
if [ -x "$PROJECT_ROOT/scripts/emit-sbom.sh" ]; then
    ok "scripts/emit-sbom.sh is executable"
else
    fail "scripts/emit-sbom.sh is not executable"
fi

# ── Test 3: emit-sbom.sh interface — no args → exit 1 ─────────────────────
set +e
OUT=$("$PROJECT_ROOT/scripts/emit-sbom.sh" 2>&1)
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
    ok "emit-sbom.sh with no args exits non-zero"
else
    fail "emit-sbom.sh with no args exits 0 (should fail)"
fi

# ── Test 4: emit-sbom.sh produces valid SBOM JSON ─────────────────────────
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

# Create fake artifacts
mkdir -p "$FIXTURE/release"
echo "fake-skill-content" > "$FIXTURE/release/myproj-v1.0.0.skill"
echo "fake-tarball" > "$FIXTURE/release/myproj-v1.0.0-source.tar.gz"
echo '#!/bin/bash' > "$FIXTURE/release/install.sh"
chmod +x "$FIXTURE/release/install.sh"

set +e
OUT=$("$PROJECT_ROOT/scripts/emit-sbom.sh" "$FIXTURE/release" "myproj" "v1.0.0" "my-skill" 2>&1)
RC=$?
set -e
if [ "$RC" -eq 0 ]; then
    ok "emit-sbom.sh exits 0 on success"
else
    fail "emit-sbom.sh exits $RC on success (expected 0)"
    echo "   output: $OUT"
fi

if [ -f "$FIXTURE/release/sbom.cyclonedx.json" ]; then
    ok "emit-sbom.sh produces sbom.cyclonedx.json"
else
    fail "emit-sbom.sh did not produce sbom.cyclonedx.json"
fi

# ── Test 5: SBOM has correct CycloneDX structure ──────────────────────────
SBOM="$FIXTURE/release/sbom.cyclonedx.json"
if [ -f "$SBOM" ]; then
    if grep -q '"bomFormat"' "$SBOM" && grep -q '"CycloneDX"' "$SBOM"; then
        ok "SBOM has bomFormat: CycloneDX"
    else
        fail "SBOM missing bomFormat: CycloneDX"
    fi
    if grep -q '"specVersion"' "$SBOM" && grep -q '"1.5"' "$SBOM"; then
        ok "SBOM has specVersion: 1.5"
    else
        fail "SBOM missing specVersion: 1.5"
    fi
    if grep -q '"serialNumber"' "$SBOM"; then
        ok "SBOM has serialNumber"
    else
        fail "SBOM missing serialNumber"
    fi
    if grep -q '"SHA-256"' "$SBOM"; then
        ok "SBOM contains SHA-256 hashes"
    else
        fail "SBOM missing SHA-256 hashes"
    fi
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import json; json.load(open('$SBOM'))" 2>/dev/null; then
            ok "SBOM is valid JSON"
        else
            fail "SBOM is not valid JSON"
        fi
    else
        ok "(skip) no python3 to validate JSON"
    fi
fi

# ── Test 6: SBOM components list the artifacts ────────────────────────────
if [ -f "$SBOM" ]; then
    if grep -q 'myproj-v1.0.0.skill' "$SBOM"; then
        ok "SBOM lists .skill artifact"
    else
        fail "SBOM missing .skill artifact"
    fi
    if grep -q 'myproj-v1.0.0-source.tar.gz' "$SBOM"; then
        ok "SBOM lists source tarball"
    else
        fail "SBOM missing source tarball"
    fi
fi

# ── Test 7: emit-sbom.sh is self-contained (resolves SHA_CMD internally) ──
if grep -qE 'shasum|sha256sum' "$PROJECT_ROOT/scripts/emit-sbom.sh"; then
    ok "emit-sbom.sh resolves SHA_CMD internally"
else
    fail "emit-sbom.sh does not resolve SHA_CMD"
fi

# ── Test 8: release.sh calls emit-sbom.sh ─────────────────────────────────
if grep -q 'emit-sbom.sh' "$PROJECT_ROOT/scripts/release.sh"; then
    ok "release.sh calls emit-sbom.sh"
else
    fail "release.sh does not call emit-sbom.sh"
fi

# ── Test 9: release.sh no longer has inline SBOM generation ───────────────
# After extraction, release.sh should NOT contain the SBOM heredoc directly
if grep -q '"bomFormat".*"CycloneDX"' "$PROJECT_ROOT/scripts/release.sh"; then
    fail "release.sh still has inline SBOM generation (should delegate to emit-sbom.sh)"
else
    ok "release.sh no longer has inline SBOM generation"
fi

# ── Test 10: emit-sbom.sh honors SOURCE_DATE_EPOCH ────────────────────────
if grep -q 'SOURCE_DATE_EPOCH' "$PROJECT_ROOT/scripts/emit-sbom.sh"; then
    ok "emit-sbom.sh honors SOURCE_DATE_EPOCH"
else
    fail "emit-sbom.sh missing SOURCE_DATE_EPOCH support"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
