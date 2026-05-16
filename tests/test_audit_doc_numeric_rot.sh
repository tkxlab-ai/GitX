#!/bin/bash
# test_audit_doc_numeric_rot.sh — v1.9.8 systemic doc numeric-rot guard.
#
# Root cause: README cited the Deep-Audit count in THREE places (shields
# badge `deep audit-N/0/1`, prose `~N checks`, status table `N PASS`).
# A release bumped one and not the others (badge said 227 while the table
# said 228) — §0e catches version *strings*, NOT semantic numbers, so it
# rotted silently and shipped to the public mirror. §0f is the generic
# cross-project floor: all README Deep-Audit citations MUST agree and a
# public README must never advertise a non-green audit (0 FAIL).
#
# exit: 0=all pass, 1=any fail
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_doc_numeric_rot.sh ══"

# STATIC: release-audit.sh (root + bundle) defines the §0f numeric-rot gate
for a in "$ROOT/scripts/release-audit.sh" "$ROOT/skills/gitx-release/scripts/release-audit.sh"; do
    [ -f "$a" ] || continue
    label="$(basename "$(dirname "$(dirname "$a")")")"
    if grep -qE '^audit_section_0_doc_numeric_rot\(\)' "$a" \
       && grep -q '§0f' "$a" \
       && grep -q '_track_start "§0f_doc_numeric_rot"' "$a"; then
        ok "release-audit.sh has §0f doc-numeric-rot gate ($label)"
    else
        fail "$a missing §0f doc-numeric-rot gate"
    fi
done

# DUAL-SOURCE: §0f byte-identical across root + bundle
if cmp -s "$ROOT/scripts/release-audit.sh" "$ROOT/skills/gitx-release/scripts/release-audit.sh"; then
    ok "release-audit.sh root vs bundle byte-identical (§0f included)"
else
    fail "release-audit.sh dual-source drift"
fi

# BEHAVIORAL: a README with disagreeing Deep-Audit numbers must be caught
# by the same extraction logic §0f uses (badge 227 vs table 228 = rot).
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/README.md" <<'EOF'
[![Deep Audit](https://img.shields.io/badge/deep%20audit-227%2F0%2F1-brightgreen.svg)](x)
release-audit.sh runs ~14 sections / 228 checks
| Deep Audit | static | **228 PASS / 0 FAIL / 1 SKIP** |
EOF
nums=$( {
    grep -oE 'deep%20audit-[0-9]+%2F[0-9]+%2F[0-9]+' "$TMP/README.md" | grep -oE '^deep%20audit-[0-9]+' | grep -oE '[0-9]+$'
    grep -oE '[0-9]+ checks' "$TMP/README.md" | grep -oE '^[0-9]+'
    grep -oE '[0-9]+ PASS' "$TMP/README.md" | grep -oE '^[0-9]+'
} | sort -u )
if [ "$(printf '%s\n' "$nums" | grep -c .)" -gt 1 ]; then
    ok "numeric-rot logic flags disagreeing citations (227 vs 228)"
else
    fail "numeric-rot logic FAILED to flag a known disagreeing README"
fi
# clean (all-agree) README must NOT be flagged
cat > "$TMP/ok.md" <<'EOF'
[![Deep Audit](https://img.shields.io/badge/deep%20audit-228%2F0%2F1-brightgreen.svg)](x)
~14 sections / 228 checks
| Deep Audit | **228 PASS / 0 FAIL / 1 SKIP** |
EOF
nums2=$( {
    grep -oE 'deep%20audit-[0-9]+%2F[0-9]+%2F[0-9]+' "$TMP/ok.md" | grep -oE '^deep%20audit-[0-9]+' | grep -oE '[0-9]+$'
    grep -oE '[0-9]+ checks' "$TMP/ok.md" | grep -oE '^[0-9]+'
    grep -oE '[0-9]+ PASS' "$TMP/ok.md" | grep -oE '^[0-9]+'
} | sort -u )
if [ "$(printf '%s\n' "$nums2" | grep -c .)" -le 1 ]; then
    ok "numeric-rot logic passes a consistent README (all cite 228)"
else
    fail "numeric-rot logic false-positives on a consistent README"
fi

# GENERIC-SAFE: §0f must SKIP (not FAIL) when README absent or cites no
# Deep-Audit count — else every minimal/fixture project releasing via
# gitx-release would fail its Deep Audit (regression: v1.9.8 first cut
# FAILed test_release_pipeline_smoke + test_audit_install_dependencies).
for a in "$ROOT/scripts/release-audit.sh" "$ROOT/skills/gitx-release/scripts/release-audit.sh"; do
    [ -f "$a" ] || continue
    label="$(basename "$(dirname "$(dirname "$a")")")"
    # whole-file unique-phrase grep (function-body sed extraction breaks on
    # the `} | sort -u )` line which starts with `}`).
    if grep -qF 'no README.md — numeric-rot guard not applicable' "$a" \
       && grep -qF 'README cites no Deep-Audit count — numeric-rot guard not applicable' "$a" \
       && grep -qF 'SKIP=$((SKIP+1)); return' "$a" \
       && grep -qF '|| true' "$a" \
       && ! grep -qE 'check "README\.md present for numeric-rot' "$a"; then
        ok "§0f is generic-safe: absent/citation-less README → SKIP not FAIL ($label)"
    else
        fail "$a §0f would FAIL a no-README/no-citation project (breaks dependent skills)"
    fi
done

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
