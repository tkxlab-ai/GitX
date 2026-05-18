#!/bin/bash
# codex-HIGH guard: root references/readme/ must be byte-identical to the
# SHIPPED skill-tree copy (release.sh ships skills/gitx-release/references;
# sync-dual-source.sh covers only scripts/*.sh, so references parity has no
# auto-sync — assert it, improving on gitx-sop's implicit-only enforcement).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  ✅ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_readme_template_parity.sh ══"
for f in README.template.md README_CN.template.md; do
  a="$ROOT/references/readme/$f"; b="$ROOT/skills/gitx-release/references/readme/$f"
  if [ -f "$a" ] && [ -f "$b" ]; then
    cmp -s "$a" "$b" && ok "$f root↔skill byte-identical" || fail "$f drifted root vs skill tree"
  else
    fail "$f missing (root=$([ -f "$a" ]&&echo y||echo n) skill=$([ -f "$b" ]&&echo y||echo n))"
  fi
done
sf=test_readme_numeric_accuracy.sh.template
sa="$ROOT/references/readme/$sf"; sb="$ROOT/skills/gitx-release/references/readme/$sf"
if [ ! -e "$sa" ] && [ ! -e "$sb" ]; then
  echo "  ➖ $sf not yet created (Task 7) — parity n/a"
elif [ -f "$sa" ] && [ -f "$sb" ] && cmp -s "$sa" "$sb"; then
  ok "$sf root↔skill byte-identical"
else
  fail "$sf half-shipped or drifted (root=$([ -f "$sa" ]&&echo y||echo n) skill=$([ -f "$sb" ]&&echo y||echo n))"
fi
# --- T12: docs-contract dual-tree parity (sync-dual-source covers scripts/ only) ---
for f in docs-contract/manifest.txt docs-contract/cjk-allow.txt; do
  a="$ROOT/references/$f"; b="$ROOT/skills/gitx-release/references/$f"
  if [ -f "$a" ] && [ -f "$b" ]; then
    if [ "$f" = "docs-contract/manifest.txt" ]; then
      # `hero_asset:` is a root-origin-only declaration. The bundled generic
      # skill ships no README/showcase, so requiring an asset it does not
      # carry would make its own docs-audit fail after install. This ONE
      # declaration line is an intentional, documented divergence; the rest
      # of the manifest mirror MUST stay byte-identical. (Codex review,
      # post-v1.11.0 docs reconciliation.)
      if diff <(grep -v '^hero_asset:' "$a") <(grep -v '^hero_asset:' "$b") >/dev/null 2>&1; then
        ok "$f root↔skill identical (modulo root-only hero_asset:)"
      else
        fail "$f drifted root vs skill tree (beyond hero_asset: carve-out)"
      fi
    else
      cmp -s "$a" "$b" && ok "$f root↔skill byte-identical" || fail "$f drifted root vs skill tree"
    fi
  else
    fail "$f missing (root=$([ -f "$a" ]&&echo y||echo n) skill=$([ -f "$b" ]&&echo y||echo n))"
  fi
done

# --- T12: signed-template folds (C1/C3/F1/F2/F3 + --force, Gotcha #60) ---
EN="$ROOT/references/readme/README.template.md"
CN="$ROOT/references/readme/README_CN.template.md"
MAN="$ROOT/references/docs-contract/manifest.txt"
# C1: Special Thanks relocated to bottom (in last 40 lines, NOT the first ## section)
tail -40 "$EN" | grep -q '^## Special Thanks$' && ok "C1 EN Special Thanks at bottom" || fail "C1 EN Special Thanks not relocated"
tail -40 "$CN" | grep -q '^## 特别致谢$' && ok "C1 CN 特别致谢 at bottom" || fail "C1 CN 特别致谢 not relocated"
[ "$(grep -nE '^## ' "$EN" | head -1 | grep -c 'Special Thanks')" -eq 0 ] && ok "C1 EN Special Thanks not first section" || fail "C1 EN Special Thanks still first"
# manifest: special-thanks immediately before license
grep -A1 '^section: special-thanks' "$MAN" | grep -q '^section: license' && ok "C1 manifest special-thanks before license" || fail "C1 manifest order wrong"
# C3: Real-Machine Test Results present, EN + CN
grep -q 'Real-Machine Test Results' "$EN" && ok "C3 EN Real-Machine block" || fail "C3 EN missing"
grep -q '真机测试结果' "$CN" && ok "C3 CN 真机测试结果 block" || fail "C3 CN missing"
# F1: CN must NOT reference CONTRIBUTING_CN.md (out of locked bilingual scope)
grep -q 'CONTRIBUTING_CN\.md' "$CN" && fail "F1 CN still references CONTRIBUTING_CN.md" || ok "F1 CN → CONTRIBUTING.md"
# F2: EN Testing has the Suite coverage lead-in (CN already had 套件覆盖：)
grep -qF '**Suite coverage:**' "$EN" && ok "F2 EN Suite coverage lead-in" || fail "F2 EN missing"
grep -qF '**套件覆盖：**' "$CN" && ok "F2 CN 套件覆盖 lead-in" || fail "F2 CN missing"
# F3: EN Configuration files-row names _CN.md
grep -qF '`Release/CHANGELOG.md` / `_CN.md`' "$EN" && ok "F3 EN _CN.md row" || fail "F3 EN missing _CN.md row"
# Gotcha #60: install.sh --force documented in BOTH locales (data-loss op)
grep -q 'install\.sh --force' "$EN" && ok "--force documented EN" || fail "--force missing EN"
grep -q 'install\.sh --force' "$CN" && ok "--force documented CN" || fail "--force missing CN"
# rot-proof: no static exact suite-count outside the managed region in either template
for tf in "$EN" "$CN"; do
  if grep -nE '[0-9]+ / 0 (fail|failed|失败)|[0-9]+ (BDD suites|BDD 套件)' "$tf" \
     | grep -vE 'gitx:managed|console|▸ ' >/dev/null 2>&1; then
    fail "rot: static exact suite-count outside region in $(basename "$tf")"
  else
    ok "no static suite-count rot outside region in $(basename "$tf")"
  fi
done

# --- T13: reusable templates must NOT hardcode the GitX hero <img> (Codex) ---
# The hero showcase is origin-specific; a downstream scaffold from these
# templates must not emit a broken docs/assets/release-demo.* image. The
# host-specific hero lives only in the origin's live README, never here.
for tf in "$ROOT/references/readme/README.template.md" \
          "$ROOT/references/readme/README_CN.template.md" \
          "$ROOT/skills/gitx-release/references/readme/README.template.md" \
          "$ROOT/skills/gitx-release/references/readme/README_CN.template.md"; do
  if [ -f "$tf" ] && grep -q '<img src="docs/assets/release-demo' "$tf"; then
    fail "reusable template hardcodes hero <img> (downstream broken-image risk): $tf"
  else
    ok "$(basename "$(dirname "$(dirname "$tf")")")/$(basename "$tf") omits hardcoded hero <img>"
  fi
done

echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && echo PASS && exit 0
echo FAIL; exit 1
