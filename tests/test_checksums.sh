#!/bin/bash
# test_checksums.sh — checksums.txt generation + audit contract
# Asserts:
#   - release.sh emits checksums.txt after building .skill + tarball
#   - release-audit.sh §11h verifies checksums.txt presence + sha256 match
# exit: 0=all pass, 1=any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
RELEASE_SH="$ROOT/scripts/release.sh"
AUDIT_SH="$ROOT/scripts/release-audit.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_checksums.sh ══"

# ── Test 1: release.sh writes checksums.txt ──────────────────────────────
if grep -qE 'checksums\.txt' "$RELEASE_SH"; then
    ok "release.sh references checksums.txt"
else
    fail "release.sh MISSING checksums.txt emission"
fi

# ── Test 2: release.sh uses shasum or sha256sum ──────────────────────────
if grep -qE 'shasum|sha256sum' "$RELEASE_SH"; then
    ok "release.sh uses shasum / sha256sum for hashing"
else
    fail "release.sh MISSING sha256 hashing tool"
fi

# ── Test 3: checksums cover every shipped file (behavioral) ──────────────
# Why behavioral: the manifest is now "every regular file in the release dir"
# rather than a named allowlist, so run the real generate_checksums() against
# a fake release dir and assert actual membership/exclusions.
GC_FN=$(awk '/^generate_checksums\(\) \{/,/^}/' "$RELEASE_SH")
GC_DIR=$(mktemp -d)
mkdir -p "$GC_DIR/scripts/lib"
for f in p-v1.skill p-v1-source.tar.gz p-v1-full.tar.gz install.sh SKILL.md \
         scripts/lib/install-output-style.sh build.log x.sha256; do
    echo "$f" > "$GC_DIR/$f"
done
    # shellcheck disable=SC2034  # DRY_RUN/RELEASE_DIR are read by the eval'd generate_checksums
(DRY_RUN=0; RELEASE_DIR="$GC_DIR"; eval "$GC_FN"; generate_checksums) >/dev/null 2>&1 || true
GC_NAMES=$(awk '{print $2}' "$GC_DIR/checksums.txt" 2>/dev/null || true)
GC_MISS=""
for want in p-v1.skill p-v1-source.tar.gz install.sh SKILL.md scripts/lib/install-output-style.sh; do
    grep -qxF "$want" <<<"$GC_NAMES" || GC_MISS="$GC_MISS $want"
done
GC_EXTRA=$(grep -E 'full\.tar\.gz$|\.log$|\.sha256$|^checksums\.txt$' <<<"$GC_NAMES" || true)
if [ -n "$GC_FN" ] && [ -z "$GC_MISS" ] && [ -z "$GC_EXTRA" ]; then
    ok "generate_checksums hashes .skill + tarball + install.sh + loose files, skips full/log/sha256"
else
    fail "generate_checksums coverage wrong (missing:${GC_MISS:- none}; extra: ${GC_EXTRA:-none})"
fi
rm -rf "$GC_DIR"

# ── Test 3b: exclusions are TOP-LEVEL only ───────────────────────────────
# Why: install.sh copies references/ scripts/vendored/ assets/ recursively, so
# a nested *.log / *.sha256 is installed and must be hashed; only the
# release-dir's own log/sidecar/manifest/full tarball are excluded.
GC_DIR=$(mktemp -d)
mkdir -p "$GC_DIR/scripts/vendored" "$GC_DIR/references"
for f in scripts/vendored/dep.sha256 references/notes.log gitx-release-x.log x.sha256 SKILL.md; do
    echo "$f" > "$GC_DIR/$f"
done
# shellcheck disable=SC2034  # DRY_RUN/RELEASE_DIR are read by the eval'd generate_checksums
(DRY_RUN=0; RELEASE_DIR="$GC_DIR"; eval "$GC_FN"; generate_checksums) >/dev/null 2>&1 || true
GC_NAMES=$(awk '{print $2}' "$GC_DIR/checksums.txt" 2>/dev/null || true)
if grep -qxF 'scripts/vendored/dep.sha256' <<<"$GC_NAMES" \
   && grep -qxF 'references/notes.log' <<<"$GC_NAMES" \
   && ! grep -qxE 'gitx-release-x\.log|x\.sha256' <<<"$GC_NAMES"; then
    ok "nested *.sha256 / *.log hashed; top-level log / sha256 excluded"
else
    fail "exclusions not top-level-only (got: $(printf '%s ' $GC_NAMES))"
fi
rm -rf "$GC_DIR"

# ── Test 4: audit.sh checks for checksums.txt presence ───────────────────
if grep -qE 'checksums\.txt' "$AUDIT_SH"; then
    ok "release-audit.sh references checksums.txt"
else
    fail "release-audit.sh MISSING checksums.txt check"
fi

# ── Test 5: audit.sh verifies hash (not just existence) ──────────────────
if grep -qE 'shasum -c|sha256sum -c|shasum.*--check|sha256sum.*--check' "$AUDIT_SH"; then
    ok "release-audit.sh verifies sha256 digests (shasum -c / sha256sum -c)"
else
    fail "release-audit.sh does NOT verify checksum digests"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
