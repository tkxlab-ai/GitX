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

# --- v1.14.0: generic templates follow references/RELEASE_PAGE_STANDARD.md ---
# The old C1/C3/F1/F2/F3/--force folds asserted GitX's own README copied into
# the templates; v1.14.0 replaced them with generic scaffolds, so the checks
# now lock the standard's structure instead of GitX-specific prose.
EN="$ROOT/references/readme/README.template.md"
CN="$ROOT/references/readme/README_CN.template.md"
MAN="$ROOT/references/docs-contract/manifest.txt"
# manifest: license is the last README section (v1.13.1 moved thanks into docs/JOURNEY.md)
[ "$(grep -E '^section:' "$MAN" | tail -1 | awk '{print $2}')" = "license" ] && ok "manifest ends with license" || fail "manifest order wrong"
for tf in "$EN" "$CN"; do
  b=$(basename "$tf")
  grep -qF '{{PROJECT}}' "$tf" && ok "$b uses {{PROJECT}}" || fail "$b missing {{PROJECT}}"
  grep -qF '{{PROJECT_SLUG}}' "$tf" && ok "$b uses {{PROJECT_SLUG}} anchors" || fail "$b missing {{PROJECT_SLUG}}"
  grep -qE '^## 1\. ' "$tf" && ok "$b body headings numbered" || fail "$b headings not numbered"
  grep -q '^> 🔄 ' "$tf" && ok "$b has 🔄 callout" || fail "$b missing 🔄 callout"
  grep -qx '<!-- gitx:managed:metrics -->' "$tf" && ok "$b has metrics region" || fail "$b missing metrics region"
  grep -qF 'OWNER/REPO/issues' "$tf" && ok "$b links bar has issues link" || fail "$b links bar missing issues link"
  # standard row 9: copyable install block right under the links bar
  grep -qxE '\*\*(Install|安装)\*\*' "$tf" && grep -qF '/plugin install PLUGIN-NAME@' "$tf" \
    && ok "$b has the install block" || fail "$b missing the install block"
  _body=$(grep -vE "^<!--|gitx:managed" "$tf" || true)
  grep -qi gitx <<<"$_body" && fail "$b still carries GitX branding" || ok "$b is brand-free"
done
# standard §3: the CN page links the CN contributing guide
grep -qF 'CONTRIBUTING_CN.md' "$CN" && ok "CN template links CONTRIBUTING_CN.md" || fail "CN template missing CONTRIBUTING_CN.md"
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
