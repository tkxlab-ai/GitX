#!/bin/bash
# test_audit_published_layout.sh — guards release-audit.sh §0l, the
# published-layout ref gate (Gotcha #80: docs-audit H10 resolves README
# refs against the PRIVATE tree where Release/CHANGELOG*.md exist, but the
# published source tarball flattens Release/ away → a private-valid link
# 404s publicly). Two halves:
#   A. STATIC contract: §0l exists, is non-counting (no _track_* in its
#      block — Gotcha #62, TOTAL invariant) and PUBLAYOUT_FAIL is wired
#      into the final Deep-Audit decision.
#   B. FUNCTIONAL non-vacuity: the exact ref-resolution §0l performs flags a
#      stale `Release/CHANGELOG.md` link as unresolved in a flattened
#      (public-shape) tree, while the flattened `CHANGELOG.md` resolves.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RA="$ROOT/scripts/release-audit.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=1; }

# ---- A. static contract ----
if [ -f "$RA" ]; then
    _blk=$(awk '/^# --- §0l published-layout ref gate/,/^# Per-section summary/' "$RA")
    [ -n "$_blk" ] && ok "§0l block present in release-audit.sh" \
        || fail "§0l block missing from release-audit.sh"
    if printf '%s\n' "$_blk" | grep -qE '_track_(start|end)'; then
        fail "§0l is NOT non-counting — contains _track_* (Gotcha #62 TOTAL-rot)"
    else
        ok "§0l non-counting — no _track_* in its block (TOTAL invariant)"
    fi
    printf '%s\n' "$_blk" | grep -q 'PUBLAYOUT_FAIL=0' \
        && ok "§0l declares PUBLAYOUT_FAIL standalone flag" \
        || fail "§0l missing PUBLAYOUT_FAIL declaration"
    grep -qE 'if \[ "\$FAIL" -eq 0 \].*PUBLAYOUT_FAIL:-0.*-eq 0 \]; then' "$RA" \
        && ok "PUBLAYOUT_FAIL wired into final Deep-Audit decision" \
        || fail "PUBLAYOUT_FAIL NOT in final-exit condition (gate is vacuous)"
    printf '%s\n' "$_blk" | grep -q 'generic-safe SKIP' \
        && ok "§0l is generic-safe (SKIP when no source tarball — Gotcha #51)" \
        || fail "§0l missing generic-safe SKIP path"
else
    fail "release-audit.sh not found"
fi

# ---- B. functional non-vacuity (same ref-extraction §0l uses) ----
extract_refs() {  # mirrors §0l / H10 awk
    LC_ALL=C awk '
      { line=$0
        while (match(line,/src="[^"]+"/)>0){ v=substr(line,RSTART+5,RLENGTH-6); sub(/#.*$/,"",v);
          if(v!="" && v!~/^https?:\/\// && v!~/^mailto:/ && v!~/^#/) print v; line=substr(line,RSTART+RLENGTH) } }
      { line=$0
        while (match(line,/\]\([^)]+\)/)>0){ v=substr(line,RSTART+2,RLENGTH-3); sub(/#.*$/,"",v);
          if(v!="" && v!~/^https?:\/\// && v!~/^mailto:/ && v!~/^#/) print v; line=substr(line,RSTART+RLENGTH) } }
    ' "$1" | sort -u
}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# Public-shape tree: flattened root, NO Release/ dir, CHANGELOG.md at root.
mkdir -p "$T/pub"; : > "$T/pub/CHANGELOG.md"; : > "$T/pub/LICENSE"
cat > "$T/pub/README.md" <<'MD'
[Changelog](CHANGELOG.md) · [License](LICENSE)
Full history → [`Release/CHANGELOG.md`](Release/CHANGELOG.md).
MD
_bad=0
while IFS= read -r r; do [ -n "$r" ] || continue; [ -e "$T/pub/$r" ] || _bad=1; done < <(extract_refs "$T/pub/README.md")
[ "$_bad" -eq 1 ] && ok "§0l logic non-vacuous: stale Release/CHANGELOG.md flagged in flattened tree" \
    || fail "§0l logic VACUOUS: stale Release/CHANGELOG.md NOT flagged (Gotcha #80 regression)"
# Same tree with the link fixed to the flattened path → clean.
cat > "$T/pub/README.md" <<'MD'
[Changelog](CHANGELOG.md) · [License](LICENSE)
Full history → [`CHANGELOG.md`](CHANGELOG.md).
MD
_bad=0
while IFS= read -r r; do [ -n "$r" ] || continue; [ -e "$T/pub/$r" ] || _bad=1; done < <(extract_refs "$T/pub/README.md")
[ "$_bad" -eq 0 ] && ok "§0l logic passes a correct flattened-path README (no false positive)" \
    || fail "§0l logic false-fails a valid flattened README"

echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo PASS || { echo FAIL; exit 1; }
