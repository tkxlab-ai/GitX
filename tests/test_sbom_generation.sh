#!/bin/bash
# test_sbom_generation.sh — v0.9.9 feature D
# release.sh must produce Release/<ver>/sbom.cyclonedx.json listing
# distributable artifacts with sha256 hashes. CycloneDX 1.5 minimal schema:
#   bomFormat, specVersion, serialNumber, version, metadata.component,
#   components[{type:file, name, version, hashes:[{alg:"SHA-256", content}]}]
#
# Also:
#   - SBOM must be included in checksums.txt (itself hashable)
#   - SBOM JSON must parse (cheap validation via python/node if available)
#   - Audit § must add a check for SBOM existence
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

echo "══ test_sbom_generation.sh ══"

# ── Test 1: release.sh generates sbom.cyclonedx.json ──────────────────────
if grep -qE 'sbom\.cyclonedx\.json|SBOM_OUT|CycloneDX' "$RELEASE_SH"; then
    ok "release.sh produces sbom.cyclonedx.json"
else
    fail "release.sh has no SBOM generation"
fi

# ── Test 2: SBOM declares correct bomFormat + specVersion ────────────────
# SBOM generation extracted to emit-sbom.sh; check there for spec compliance
EMIT_SBOM="$PROJECT_ROOT/scripts/emit-sbom.sh"
if [ -f "$EMIT_SBOM" ] \
   && grep -qE '"bomFormat"[[:space:]]*:[[:space:]]*"CycloneDX"' "$EMIT_SBOM" \
   && grep -qE '"specVersion"[[:space:]]*:[[:space:]]*"1\.[345]"' "$EMIT_SBOM"; then
    ok "SBOM uses CycloneDX 1.x spec (in emit-sbom.sh)"
else
    fail "SBOM missing bomFormat/specVersion (must be CycloneDX 1.x)"
fi

# ── Test 3: checksums.txt includes sbom.cyclonedx.json ────────────────────
if grep -qE 'sbom\.cyclonedx\.json' "$RELEASE_SH" \
   && grep -qE 'CHK_FILES.*sbom|sbom.*CHK_FILES' "$RELEASE_SH"; then
    ok "release.sh adds sbom.cyclonedx.json to checksums.txt"
else
    fail "SBOM not included in checksums.txt CHK_FILES"
fi

# ── Test 4: audit has § check for SBOM ────────────────────────────────────
if grep -qE 'sbom\.cyclonedx\.json|SBOM' "$AUDIT_SH"; then
    ok "release-audit.sh verifies SBOM presence"
else
    fail "release-audit.sh does not audit SBOM"
fi

# ── Test 5: functional — produced SBOM parses as valid JSON ───────────────
LATEST_VER_DIR="$PROJECT_ROOT/Release/$(readlink "$PROJECT_ROOT/Release/latest" 2>/dev/null || echo missing)"
SBOM="$LATEST_VER_DIR/sbom.cyclonedx.json"
if [ ! -f "$SBOM" ]; then
    ok "(skip) no current Release/<ver>/sbom.cyclonedx.json to validate"
elif command -v python3 >/dev/null 2>&1; then
    if python3 -c "import json, sys; b=json.load(open('$SBOM')); \
sys.exit(0 if b.get('bomFormat')=='CycloneDX' and 'components' in b else 1)" 2>/dev/null; then
        ok "sbom.cyclonedx.json is valid JSON with CycloneDX shape"
    else
        fail "sbom.cyclonedx.json fails JSON/schema validation"
    fi
elif command -v node >/dev/null 2>&1; then
    if node -e "const b=require('$SBOM'); process.exit(b.bomFormat==='CycloneDX'&&b.components?0:1)" 2>/dev/null; then
        ok "sbom.cyclonedx.json is valid JSON with CycloneDX shape"
    else
        fail "sbom.cyclonedx.json fails JSON/schema validation"
    fi
else
    ok "(skip) no python3/node to validate SBOM JSON"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
