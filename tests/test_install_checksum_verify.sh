#!/bin/bash
# test_install_checksum_verify.sh — v1.0.8 hardening (Sec #6, P0).
# When end users extract a release tarball that contains both `install.sh`
# and `checksums.txt`, install.sh must verify the checksums BEFORE copying
# any scripts to ~/.agents/skills/. A tampered tarball (MITM, mirror
# compromise) would otherwise install silently.
#
# Behaviour contract (verified here):
#   1. install.sh from a release dir WITH checksums.txt → verify all entries
#   2. Mismatch → abort with non-zero exit before any filesystem write
#   3. Match → install proceeds (existing dev behaviour preserved)
#   4. No checksums.txt next to install.sh → skip verification (dev-tree mode)
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL="$ROOT/install.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_install_checksum_verify.sh ══"

# Static: install.sh references checksums.txt verification
if grep -qE 'checksums\.txt|shasum.*-c|sha256sum.*-c' "$INSTALL"; then
    ok "install.sh references checksum verification"
else
    fail "install.sh does NOT reference checksum verification"
fi

build_fixture() {
    # Build a minimal release-style dir: install.sh + the required files +
    # checksums.txt covering them. Caller passes a flag to optionally
    # tamper one of the files after checksums are computed.
    local tamper="$1"
    local fix; fix=$(mktemp -d)
    cp "$INSTALL" "$fix/install.sh"
    cp "$ROOT/SKILL.md" "$fix/SKILL.md"
    cp "$ROOT/VERSION" "$fix/VERSION"
    mkdir -p "$fix/scripts"
    cp "$ROOT/scripts/"*.sh "$fix/scripts/"
    if [ -d "$ROOT/scripts/lib" ]; then
        mkdir -p "$fix/scripts/lib"
        cp "$ROOT/scripts/lib/"* "$fix/scripts/lib/"
    fi
    # Compute checksums for a representative subset (matching what the
    # real release pipeline puts in Release/<ver>/checksums.txt).
    (cd "$fix" && shasum -a 256 install.sh SKILL.md VERSION | LC_ALL=C sort > checksums.txt)
    if [ "$tamper" = "tamper" ]; then
        # Tamper after checksums computed
        echo "# tampered after sign-off" >> "$fix/install.sh"
    fi
    echo "$fix"
}

# ── Test 1: matching checksums → install proceeds (verify --dry-run path) ──
GOOD=$(build_fixture "")
DRY_HOME=$(mktemp -d)
out=$(HOME="$DRY_HOME" bash "$GOOD/install.sh" --dry-run 2>&1 || true)
rc=$(HOME="$DRY_HOME" bash "$GOOD/install.sh" --dry-run >/dev/null 2>&1; echo $?)
if [ "$rc" = "0" ]; then
    ok "matching checksums + --dry-run → exit 0"
else
    fail "matching checksums + --dry-run → exit $rc (expected 0)"
    echo "$out" | tail -5 | sed 's/^/       /'
fi
rm -rf "$GOOD" "$DRY_HOME"

# ── Test 2: tampered file → install aborts non-zero before write ──────
BAD=$(build_fixture "tamper")
DRY_HOME=$(mktemp -d)
TAMPER_OUT=$(HOME="$DRY_HOME" bash "$BAD/install.sh" 2>&1 || true)
# Note: we run NOT --dry-run, but with HOME redirected, so even if write
# happens, it lands in $DRY_HOME, not the user's real home.
if echo "$TAMPER_OUT" | grep -qiE 'checksum|sha256|integrity|tamper|mismatch'; then
    ok "tampered file → install.sh prints checksum failure message"
else
    fail "tampered file → install.sh did not mention checksum failure"
    echo "$TAMPER_OUT" | tail -5 | sed 's/^/       /'
fi
# Verify install aborted before writing to $DRY_HOME/.agents
if [ ! -d "$DRY_HOME/.agents/skills/gitx-release" ]; then
    ok "tampered file → install aborted before any filesystem write"
else
    fail "tampered file → install wrote to disk anyway (no abort)"
fi
rm -rf "$BAD" "$DRY_HOME"

# ── Test 3: no checksums.txt → install behaves as dev-tree (no verification) ──
NOCK=$(mktemp -d)
cp "$INSTALL" "$NOCK/install.sh"
cp "$ROOT/SKILL.md" "$NOCK/SKILL.md"
cp "$ROOT/VERSION" "$NOCK/VERSION"
mkdir -p "$NOCK/scripts"
cp "$ROOT/scripts/"*.sh "$NOCK/scripts/"
if [ -d "$ROOT/scripts/lib" ]; then
    mkdir -p "$NOCK/scripts/lib"
    cp "$ROOT/scripts/lib/"* "$NOCK/scripts/lib/"
fi
# Note: NO checksums.txt
DRY_HOME=$(mktemp -d)
NOCK_RC=$(HOME="$DRY_HOME" bash "$NOCK/install.sh" --dry-run >/dev/null 2>&1; echo $?)
if [ "$NOCK_RC" = "0" ]; then
    ok "no checksums.txt → install --dry-run succeeds (dev-tree mode preserved)"
else
    fail "no checksums.txt → install failed unexpectedly (rc=$NOCK_RC)"
fi
rm -rf "$NOCK" "$DRY_HOME"

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
