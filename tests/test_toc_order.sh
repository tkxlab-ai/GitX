#!/bin/bash
# test_toc_order.sh — the Table-of-Contents list MUST enumerate sections in
# the SAME order they appear in the body. docs-audit H1 enforces body
# section order vs the docs-contract manifest, but the ToC is static prose
# H1/H10 do not order-check — so a manifest/section reorder (e.g. v1.12.1
# moving Quick Start between Why and Comparison) could leave the ToC stale
# and H1 would still pass. This guard closes that gap (Codex review #5):
# ToC link-text sequence == body `## ` heading sequence (for sections the
# ToC lists). Compares displayed TEXT (no GitHub-anchor-slug math → robust).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=1; }

check() {
    local f="$1" toc_h="$2"
    [ -f "$f" ] || { fail "$(basename "$f") missing"; return; }
    # ToC link texts, in order: lines '- [TEXT](#...)' between the ToC
    # heading and the next '## ' heading.
    local toc
    toc=$(awk -v h="## $toc_h" '
        $0==h {inb=1; next}
        inb && /^## / {exit}
        inb && /^- \[[^]]+\]\(#/ {
            s=$0; sub(/^- \[/,"",s); sub(/\].*$/,"",s); print s
        }' "$f")
    # Body section headings, in order, restricted to those the ToC lists.
    local body
    body=$(grep -E '^## ' "$f" | sed -E 's/^## //' \
           | grep -Fxf <(printf '%s\n' "$toc") || true)
    if [ -z "$toc" ]; then fail "$(basename "$f"): no ToC entries parsed"; return; fi
    if [ "$toc" = "$body" ]; then
        ok "$(basename "$f"): ToC order == body section order ($(printf '%s\n' "$toc" | grep -c .) entries)"
    else
        fail "$(basename "$f"): ToC order ≠ body order — first divergence:
   ToC : $(diff <(printf '%s\n' "$toc") <(printf '%s\n' "$body") | grep -m1 '^<' | sed 's/^< //')
   body: $(diff <(printf '%s\n' "$toc") <(printf '%s\n' "$body") | grep -m1 '^>' | sed 's/^> //')"
    fi
}

check "$ROOT/README.md"     "Table of Contents"
check "$ROOT/README_CN.md"  "目录"

echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo PASS || { echo FAIL; exit 1; }
