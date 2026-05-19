#!/bin/bash
# test_changelog_root_mirror_parity.sh — the durable gate for Codex v1.12.2
# round-2 [high]: README links users to the FLAT root CHANGELOG.md /
# CHANGELOG_CN.md, but the non-destructive staging-only inject (Codex
# round-2/3) deliberately stopped the pipeline from writing the working
# tree — so the COMMITTED root mirrors can silently lag Release/CHANGELOG*.md
# (the source-of-truth) while the README advertises a newer version. The
# tarball parity gate (test_changelog_tarball_parity.sh) only protects the
# shipped artifact, NOT the committed branch view a reader sees on GitHub.
# This converts "an independent reviewer caught it" into "a gate catches it"
# (the post-mortem principle).
#
# Contract: when a repo ships BOTH Release/CHANGELOG.md (source-of-truth)
# AND a root CHANGELOG.md (the flat mirror README links to), they MUST be
# byte-identical; same for the CN parallel. Generic-safe: a project that
# does not use the flat-mirror pattern (no root CHANGELOG.md) is SKIPped,
# never failed — same prevent-without-breaking-dependents posture as
# §0f/§0l and the H3 cnscan gate.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=1; }
skip() { echo "  ➖ $1"; }

# ---- functional: this repo (real) ----
_src="$ROOT/Release/CHANGELOG.md"
_dst="$ROOT/CHANGELOG.md"
if [ ! -f "$_src" ]; then
  skip "Release/CHANGELOG.md absent — flat-mirror parity not applicable (generic-safe)"
elif [ ! -f "$_dst" ]; then
  skip "root CHANGELOG.md absent — project does not use the flat-mirror pattern (generic-safe)"
else
  cmp -s "$_src" "$_dst" \
    && ok "root CHANGELOG.md byte-identical to Release/CHANGELOG.md (committed mirror current)" \
    || fail "root CHANGELOG.md != Release/CHANGELOG.md — committed flat mirror is STALE vs source-of-truth (regenerate: cp Release/CHANGELOG.md CHANGELOG.md)"
fi
# CN parallel — only enforced when BOTH the CN source and CN root exist.
_csrc="$ROOT/Release/CHANGELOG_CN.md"
_cdst="$ROOT/CHANGELOG_CN.md"
if [ -f "$_csrc" ] && [ -f "$_cdst" ]; then
  cmp -s "$_csrc" "$_cdst" \
    && ok "root CHANGELOG_CN.md byte-identical to Release/CHANGELOG_CN.md (committed mirror current)" \
    || fail "root CHANGELOG_CN.md != Release/CHANGELOG_CN.md — committed CN flat mirror STALE (regenerate: cp Release/CHANGELOG_CN.md CHANGELOG_CN.md)"
else
  skip "CN flat-mirror parity not applicable (CHANGELOG_CN source/root absent — generic-safe)"
fi

# ---- functional non-vacuity: the predicate actually flags a stale mirror ----
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf 'v9.9.9 SOURCE\n' > "$T/src.md"
printf 'v9.9.8 STALE-MIRROR\n' > "$T/dst.md"
if cmp -s "$T/src.md" "$T/dst.md"; then
  fail "parity predicate VACUOUS: a stale mirror was not detected"
else
  ok "parity predicate non-vacuous: a stale root mirror is detected"
fi
cp "$T/src.md" "$T/dst.md"
cmp -s "$T/src.md" "$T/dst.md" \
  && ok "parity predicate passes a byte-identical mirror (no false positive)" \
  || fail "parity predicate false-fails an identical mirror"

echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo PASS || { echo FAIL; exit 1; }
