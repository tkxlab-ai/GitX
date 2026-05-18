#!/bin/bash
# test_docs_audit.sh — TDD for T6: docs-audit.sh H1 (sections present+ordered)
# and H2 (EN/CN structural parity). Gotcha #51: generic-safe SKIP when manifest
# absent. Gotcha #62: audit owns structure only, never PASS/FAIL/SKIP tallies.
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT="$SCRIPT_DIR/../scripts/docs-audit.sh"
MANIFEST="$SCRIPT_DIR/../references/docs-contract/manifest.txt"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_docs_audit.sh ══"

# --- T1: script exists and is executable ---
if [ -f "$AUDIT" ]; then
  ok "scripts/docs-audit.sh exists"
else
  fail "scripts/docs-audit.sh does NOT exist"
fi

if [ -x "$AUDIT" ]; then
  ok "scripts/docs-audit.sh is executable"
else
  fail "scripts/docs-audit.sh is NOT executable"
fi

# --- T2: generic-safe SKIP — no manifest → exit 0 (Gotcha #51) ---
TMP_GENERIC=$(mktemp -d)
trap 'rm -rf "$TMP_GENERIC"' EXIT
# Temp dir has no references/docs-contract/manifest.txt
PROJECT_ROOT="$TMP_GENERIC" bash "$AUDIT" >/dev/null 2>&1 && rc_g=0 || rc_g=$?
if [ "$rc_g" -eq 0 ]; then
  ok "generic-safe SKIP: no manifest → exit 0 (Gotcha #51)"
else
  fail "generic-safe SKIP: no manifest → expected exit 0, got $rc_g"
fi

# --- T3: clean real repo → H1+H2+H3+H4 pass, exit 0 ---
# Only run if both scripts exist (otherwise blocked by T1 failures)
if [ -f "$AUDIT" ] && [ -f "$MANIFEST" ]; then
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" bash "$AUDIT" >/dev/null 2>&1 && rc_clean=0 || rc_clean=$?
  if [ "$rc_clean" -eq 0 ]; then
    ok "clean real repo → H1+H2+H3+H4 pass, exit 0"
  else
    fail "clean real repo → expected exit 0, got $rc_clean"
  fi
else
  fail "T3 skipped: audit or manifest missing"
fi

# --- T4: H1 fires — delete one ## section from scratch README.md → non-zero ---
# Build a minimal scratch environment with the real manifest + scripts so
# docs-audit.sh can source docs-pipeline.sh helpers and parse the manifest.
TMP_H1=$(mktemp -d)
trap 'rm -rf "$TMP_H1"' EXIT

# Copy real manifest
mkdir -p "$TMP_H1/references/docs-contract"
cp "$MANIFEST" "$TMP_H1/references/docs-contract/manifest.txt"

# Build a valid EN README with all contract sections present, then remove one.
# Section IDs from manifest.txt (ordered): whats-new table-of-contents cli-in-action
# why-gitx comparison command-surface pipeline-audit-gates quick-start configuration
# architecture symbol-state testing development-journey audits-code-review
# multi-model-ai research-references security faq compatibility roadmap
# acknowledgments contributing special-thanks license
# We map to EN headings matching the fixed table in docs-audit.sh / docs-pipeline.sh.
# Use the real README.md as the base for EN (guaranteed valid structure).
REAL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cp "$REAL_ROOT/README.md" "$TMP_H1/README.md"
cp "$REAL_ROOT/README_CN.md" "$TMP_H1/README_CN.md"

# Remove the "## Testing" section heading from EN README → H1 must fire
# (section-id "testing" is absent)
sed -i.bak '/^## Testing$/d' "$TMP_H1/README.md"

if [ -f "$AUDIT" ]; then
  PROJECT_ROOT="$TMP_H1" bash "$AUDIT" >/dev/null 2>&1 && rc_h1=0 || rc_h1=$?
  if [ "$rc_h1" -ne 0 ]; then
    ok "H1 fires on missing section in EN README (exit $rc_h1 ≠ 0)"
  else
    fail "H1 should have fired on missing section but got exit 0"
  fi
else
  fail "T4 skipped: audit script missing"
fi
rm -rf "$TMP_H1"
trap - EXIT
TMP_H1=""

# --- T5: H2 fires — EN/CN section-id lists diverge → non-zero ---
TMP_H2=$(mktemp -d)
trap 'rm -rf "$TMP_H2"' EXIT

mkdir -p "$TMP_H2/references/docs-contract"
cp "$MANIFEST" "$TMP_H2/references/docs-contract/manifest.txt"

cp "$REAL_ROOT/README.md"    "$TMP_H2/README.md"
cp "$REAL_ROOT/README_CN.md" "$TMP_H2/README_CN.md"

# Remove "## 测试" (the CN equivalent of Testing) from README_CN.md
# so CN section-id list no longer includes "testing" → H2 divergence.
sed -i.bak '/^## 测试$/d' "$TMP_H2/README_CN.md"

if [ -f "$AUDIT" ]; then
  PROJECT_ROOT="$TMP_H2" bash "$AUDIT" >/dev/null 2>&1 && rc_h2=0 || rc_h2=$?
  if [ "$rc_h2" -ne 0 ]; then
    ok "H2 fires on EN/CN section-id divergence (exit $rc_h2 ≠ 0)"
  else
    fail "H2 should have fired on section-id divergence but got exit 0"
  fi
else
  fail "T5 skipped: audit script missing"
fi
rm -rf "$TMP_H2"
trap - EXIT

# --- T6: H3 fires — inject 9-word EN run into scratch README_CN.md → non-zero ---
TMP_H3=$(mktemp -d)
trap 'rm -rf "$TMP_H3"' EXIT

mkdir -p "$TMP_H3/references/docs-contract"
cp "$MANIFEST" "$TMP_H3/references/docs-contract/manifest.txt"
cp "$REAL_ROOT/references/docs-contract/cjk-allow.txt" "$TMP_H3/references/docs-contract/cjk-allow.txt"
cp "$REAL_ROOT/README.md"    "$TMP_H3/README.md"
cp "$REAL_ROOT/README_CN.md" "$TMP_H3/README_CN.md"
# H4 also runs on these files and needs VERSION, CHANGELOG, and test files.
cp "$REAL_ROOT/VERSION" "$TMP_H3/VERSION"
mkdir -p "$TMP_H3/Release"
cp "$REAL_ROOT/Release/CHANGELOG.md" "$TMP_H3/Release/CHANGELOG.md"
[ -f "$REAL_ROOT/Release/CHANGELOG_CN.md" ] && cp "$REAL_ROOT/Release/CHANGELOG_CN.md" "$TMP_H3/Release/CHANGELOG_CN.md" || true
ln -s "$REAL_ROOT/tests" "$TMP_H3/tests"

# Inject a 9-word all-ASCII run into CN README body (must trip H3, threshold=8).
# Appended after all managed regions so it is body text, not inside a region.
printf '\n这是一个测试行 alpha bravo charlie delta echo foxtrot golf hotel india\n' \
  >> "$TMP_H3/README_CN.md"

if [ -f "$AUDIT" ]; then
  PROJECT_ROOT="$TMP_H3" bash "$AUDIT" >/dev/null 2>&1 && rc_h3=0 || rc_h3=$?
  if [ "$rc_h3" -ne 0 ]; then
    ok "H3 fires on 9-word English run in README_CN.md (exit $rc_h3 ≠ 0)"
  else
    fail "H3 should have fired on 9-word EN run in CN file but got exit 0"
  fi
else
  fail "T6 skipped: audit script missing"
fi
rm -rf "$TMP_H3"
trap - EXIT

# --- T7: H3 passes — whitelist-only run in README_CN.md → exit 0 ---
# Uses the tar methodology (includes tests/ + full tree) so H6 --check has an
# accurate command-surface and does not produce spurious drift on this scratch.
TMP_H3W=$(mktemp -d)
trap 'rm -rf "$TMP_H3W"' EXIT

tar -cf - --exclude='Release/git_release_skill-v0.9*' \
  references scripts VERSION Release README.md README_CN.md tests \
  -C "$REAL_ROOT" . 2>/dev/null \
  | (cd "$TMP_H3W" && tar -xf - 2>/dev/null) || true

# A run of ≥8 tokens that are ALL in the cjk-allow whitelist:
# GitX shellcheck CHANGELOG SemVer SBOM CycloneDX Claude Codex (8 tokens)
printf '\n这是白名单行 GitX shellcheck CHANGELOG SemVer SBOM CycloneDX Claude Codex\n' \
  >> "$TMP_H3W/README_CN.md"

if [ -f "$AUDIT" ]; then
  PROJECT_ROOT="$TMP_H3W" bash "$AUDIT" >/dev/null 2>&1 && rc_h3w=0 || rc_h3w=$?
  if [ "$rc_h3w" -eq 0 ]; then
    ok "H3 passes on whitelist-only run in README_CN.md (exit 0)"
  else
    fail "H3 incorrectly fired on whitelist-only run (exit $rc_h3w ≠ 0)"
  fi
else
  fail "T7 skipped: audit script missing"
fi
rm -rf "$TMP_H3W"
trap - EXIT

# --- T8: H4 fires — tamper tests-N badge count in README.md → non-zero ---
TMP_H4B=$(mktemp -d)
trap 'rm -rf "$TMP_H4B"' EXIT

mkdir -p "$TMP_H4B/references/docs-contract"
cp "$MANIFEST" "$TMP_H4B/references/docs-contract/manifest.txt"
cp "$REAL_ROOT/references/docs-contract/cjk-allow.txt" "$TMP_H4B/references/docs-contract/cjk-allow.txt"
cp "$REAL_ROOT/README.md"    "$TMP_H4B/README.md"
cp "$REAL_ROOT/README_CN.md" "$TMP_H4B/README_CN.md"
cp "$REAL_ROOT/VERSION"      "$TMP_H4B/VERSION"
mkdir -p "$TMP_H4B/Release"
cp "$REAL_ROOT/Release/CHANGELOG.md" "$TMP_H4B/Release/CHANGELOG.md"
[ -f "$REAL_ROOT/Release/CHANGELOG_CN.md" ] && cp "$REAL_ROOT/Release/CHANGELOG_CN.md" "$TMP_H4B/Release/CHANGELOG_CN.md" || true
ln -s "$REAL_ROOT/tests" "$TMP_H4B/tests"

# Tamper the badge count to a wrong value (9999 suites)
sed -i.bak 's/tests-[0-9]*%20suites%20%2F%200%20fail/tests-9999%20suites%20%2F%200%20fail/g' \
  "$TMP_H4B/README.md"

if [ -f "$AUDIT" ]; then
  PROJECT_ROOT="$TMP_H4B" bash "$AUDIT" >/dev/null 2>&1 && rc_h4b=0 || rc_h4b=$?
  if [ "$rc_h4b" -ne 0 ]; then
    ok "H4 fires on tampered badge suite count (exit $rc_h4b ≠ 0)"
  else
    fail "H4 should have fired on tampered badge count but got exit 0"
  fi
else
  fail "T8 skipped: audit script missing"
fi
rm -rf "$TMP_H4B"
trap - EXIT

# --- T9: H4 fires — tamper VERSION in scratch repo → non-zero ---
TMP_H4V=$(mktemp -d)
trap 'rm -rf "$TMP_H4V"' EXIT

mkdir -p "$TMP_H4V/references/docs-contract"
cp "$MANIFEST" "$TMP_H4V/references/docs-contract/manifest.txt"
cp "$REAL_ROOT/references/docs-contract/cjk-allow.txt" "$TMP_H4V/references/docs-contract/cjk-allow.txt"
cp "$REAL_ROOT/README.md"    "$TMP_H4V/README.md"
cp "$REAL_ROOT/README_CN.md" "$TMP_H4V/README_CN.md"
mkdir -p "$TMP_H4V/Release"
cp "$REAL_ROOT/Release/CHANGELOG.md" "$TMP_H4V/Release/CHANGELOG.md"
[ -f "$REAL_ROOT/Release/CHANGELOG_CN.md" ] && cp "$REAL_ROOT/Release/CHANGELOG_CN.md" "$TMP_H4V/Release/CHANGELOG_CN.md" || true
ln -s "$REAL_ROOT/tests" "$TMP_H4V/tests"

# Write a mismatched VERSION — README still says the real version
printf 'v99.99.99\n' > "$TMP_H4V/VERSION"

if [ -f "$AUDIT" ]; then
  PROJECT_ROOT="$TMP_H4V" bash "$AUDIT" >/dev/null 2>&1 && rc_h4v=0 || rc_h4v=$?
  if [ "$rc_h4v" -ne 0 ]; then
    ok "H4 fires on mismatched VERSION vs build-metrics (exit $rc_h4v ≠ 0)"
  else
    fail "H4 should have fired on VERSION mismatch but got exit 0"
  fi
else
  fail "T9 skipped: audit script missing"
fi
rm -rf "$TMP_H4V"
trap - EXIT

# --- T10: H4 fires — tamper suite-count region body in README.md → non-zero ---
TMP_H4SC=$(mktemp -d)
trap 'rm -rf "$TMP_H4SC"' EXIT

mkdir -p "$TMP_H4SC/references/docs-contract"
cp "$MANIFEST" "$TMP_H4SC/references/docs-contract/manifest.txt"
cp "$REAL_ROOT/references/docs-contract/cjk-allow.txt" "$TMP_H4SC/references/docs-contract/cjk-allow.txt"
cp "$REAL_ROOT/README.md"    "$TMP_H4SC/README.md"
cp "$REAL_ROOT/README_CN.md" "$TMP_H4SC/README_CN.md"
cp "$REAL_ROOT/VERSION"      "$TMP_H4SC/VERSION"
mkdir -p "$TMP_H4SC/Release"
cp "$REAL_ROOT/Release/CHANGELOG.md" "$TMP_H4SC/Release/CHANGELOG.md"
[ -f "$REAL_ROOT/Release/CHANGELOG_CN.md" ] && cp "$REAL_ROOT/Release/CHANGELOG_CN.md" "$TMP_H4SC/Release/CHANGELOG_CN.md" || true
ln -s "$REAL_ROOT/tests" "$TMP_H4SC/tests"

# Tamper the suite-count region body in README.md to a wrong value
sed -i.bak '/^<!-- gitx:managed:suite-count -->/{n; s/[0-9][0-9]*/9999/;}' \
  "$TMP_H4SC/README.md"

if [ -f "$AUDIT" ]; then
  PROJECT_ROOT="$TMP_H4SC" bash "$AUDIT" >/dev/null 2>&1 && rc_h4sc=0 || rc_h4sc=$?
  if [ "$rc_h4sc" -ne 0 ]; then
    ok "H4 fires on tampered suite-count region body (exit $rc_h4sc ≠ 0)"
  else
    fail "H4 should have fired on tampered suite-count body but got exit 0"
  fi
else
  fail "T10 skipped: audit script missing"
fi
rm -rf "$TMP_H4SC"
trap - EXIT

# --- T11: H5 — CHANGELOG parity passes on clean repo (CN absent = generic-safe) ---
# On this repo CHANGELOG_CN.md is absent; docs-pipeline --changelog-parity exits 0.
# docs-audit H5 must therefore also exit 0 (pass) and emit an H5 line.
if [ -f "$AUDIT" ] && [ -f "$MANIFEST" ]; then
  out_h5=$(PROJECT_ROOT="$REAL_ROOT" bash "$AUDIT" 2>&1) && rc_h5=0 || rc_h5=$?
  if [ "$rc_h5" -eq 0 ]; then
    ok "H5 passes on clean repo — CHANGELOG_CN absent is generic-safe"
  else
    fail "H5 should pass on clean repo (CN absent), got exit $rc_h5"
  fi
  if printf '%s\n' "$out_h5" | grep -q "H5"; then
    ok "H5 line present in docs-audit output"
  else
    fail "H5 line missing from docs-audit output"
  fi
else
  fail "T11 skipped: audit or manifest missing"
  fail "T11b skipped: audit or manifest missing"
fi

# --- T12: H6 — tamper a managed region → docs-audit exits non-zero with H6 line ---
# Build a proper scratch copy that includes tests/ so dp_suite_count is accurate.
TMP_H6=$(mktemp -d)
trap 'rm -rf "$TMP_H6"' EXIT

tar -cf - --exclude='Release/git_release_skill-v0.9*' \
  references scripts VERSION Release README.md README_CN.md tests \
  -C "$REAL_ROOT" . 2>/dev/null \
  | (cd "$TMP_H6" && tar -xf - 2>/dev/null) || true

# Tamper the badges managed region in the scratch README.md to simulate drift:
# Replace the suite count with a wrong value so --check will detect drift.
sed -i.bak 's/tests-[0-9]*%20suites%20%2F%200%20fail/tests-8888%20suites%20%2F%200%20fail/g' \
  "$TMP_H6/README.md"

if [ -f "$AUDIT" ]; then
  out_h6=$(PROJECT_ROOT="$TMP_H6" bash "$AUDIT" 2>&1) && rc_h6=0 || rc_h6=$?
  if [ "$rc_h6" -ne 0 ]; then
    ok "H6 fires on managed-region drift (exit $rc_h6 ≠ 0)"
  else
    fail "H6 should have fired on managed-region drift but got exit 0"
  fi
  if printf '%s\n' "$out_h6" | grep -q "H6"; then
    ok "H6 line present in docs-audit output on drift"
  else
    fail "H6 line missing from docs-audit output on drift"
  fi
else
  fail "T12 skipped: audit script missing"
  fail "T12b skipped: audit script missing"
fi
rm -rf "$TMP_H6"
trap - EXIT

# --- T12c: H6 — clean scratch copy → exit 0 ---
TMP_H6C=$(mktemp -d)
trap 'rm -rf "$TMP_H6C"' EXIT

tar -cf - --exclude='Release/git_release_skill-v0.9*' \
  references scripts VERSION Release README.md README_CN.md tests \
  -C "$REAL_ROOT" . 2>/dev/null \
  | (cd "$TMP_H6C" && tar -xf - 2>/dev/null) || true

if [ -f "$AUDIT" ]; then
  PROJECT_ROOT="$TMP_H6C" bash "$AUDIT" >/dev/null 2>&1 && rc_h6c=0 || rc_h6c=$?
  if [ "$rc_h6c" -eq 0 ]; then
    ok "H6 passes on clean scratch copy (exit 0)"
  else
    fail "H6 should pass on clean scratch copy but got exit $rc_h6c"
  fi
else
  fail "T12c skipped: audit script missing"
fi
rm -rf "$TMP_H6C"
trap - EXIT

# --- T13: H7 — shellcheck clean on clean repo (or informational skip if absent) ---
if [ -f "$AUDIT" ] && [ -f "$MANIFEST" ]; then
  out_h7=$(PROJECT_ROOT="$REAL_ROOT" bash "$AUDIT" 2>&1) && rc_h7=0 || rc_h7=$?
  if command -v shellcheck >/dev/null 2>&1; then
    # when the shellcheck tool is present: H7 should pass on clean repo
    if [ "$rc_h7" -eq 0 ]; then
      ok "H7 passes (shellcheck clean at -S warning)"
    else
      fail "H7 should pass with shellcheck present and clean scripts (exit $rc_h7)"
    fi
    if printf '%s\n' "$out_h7" | grep -q "H7"; then
      ok "H7 line present in docs-audit output"
    else
      fail "H7 line missing from docs-audit output"
    fi
  else
    # when the shellcheck tool is absent: H7 must emit a skip line, not fail
    if [ "$rc_h7" -eq 0 ]; then
      ok "H7 generic-safe: shellcheck absent → non-fatal skip, exit 0"
    else
      fail "H7 shellcheck absent should not fail docs-audit (exit $rc_h7)"
    fi
  fi
else
  fail "T13 skipped: audit or manifest missing"
fi

# --- T14: H10 fires — inject non-allowlisted broken local ref into scratch README.md ---
# Uses a full tar-clone (Gotcha: incomplete scratch spuriously trips other H-checks).
TMP_H10B=$(mktemp -d)
trap 'rm -rf "$TMP_H10B"' EXIT

tar -cf - --exclude='Release/git_release_skill-v0.9*' \
  -C "$REAL_ROOT" . 2>/dev/null \
  | (cd "$TMP_H10B" && tar -xf - 2>/dev/null) || true

# Inject a non-allowlisted broken local ref that does not exist.
printf '\n[broken link](docs/assets/does-not-exist.svg)\n' \
  >> "$TMP_H10B/README.md"

if [ -f "$AUDIT" ]; then
  out_h10b=$(PROJECT_ROOT="$TMP_H10B" bash "$AUDIT" 2>&1) && rc_h10b=0 || rc_h10b=$?
  if [ "$rc_h10b" -ne 0 ]; then
    ok "H10 fires on non-allowlisted broken local ref in README.md (exit $rc_h10b ≠ 0)"
  else
    fail "H10 should have fired on broken local ref but got exit 0"
  fi
  if printf '%s\n' "$out_h10b" | grep -q "H10"; then
    ok "H10 line present in docs-audit output on broken ref"
  else
    fail "H10 line missing from docs-audit output on broken ref"
  fi
else
  fail "T14 skipped: audit script missing"
  fail "T14b skipped: audit script missing"
fi
rm -rf "$TMP_H10B"
trap - EXIT

# --- T15: H10 passes — clean real repo (all refs resolve; hero asset committed, no allow-list) ---
if [ -f "$AUDIT" ] && [ -f "$MANIFEST" ]; then
  out_h10c=$(PROJECT_ROOT="$REAL_ROOT" bash "$AUDIT" 2>&1) && rc_h10c=0 || rc_h10c=$?
  if [ "$rc_h10c" -eq 0 ]; then
    ok "H10 passes on clean real repo — all refs resolve, hero asset present (exit 0)"
  else
    fail "H10 should pass on clean real repo but got exit $rc_h10c"
  fi
  if printf '%s\n' "$out_h10c" | grep -q "H10"; then
    ok "H10 token present in clean-repo docs-audit success line"
  else
    fail "H10 token missing from clean-repo docs-audit success line"
  fi
else
  fail "T15 skipped: audit or manifest missing"
  fail "T15b skipped: audit or manifest missing"
fi

# --- T15-hero: H10 model — STRICT refs + manifest-driven origin gate ---
# (a)  declared hero_asset + asset absent + still referenced → HARD-FAIL.
# (a') declared + absent + NOT referenced                    → STILL HARD-FAIL
#      (standalone gate is unconditional, not contingent on a link).
# (b)  undeclared + README references a MISSING hero          → HARD-FAIL
#      (H10 is strict — a *referenced* missing local ref always fails; the
#       Codex no-silent-broken-image guarantee).
# (b') undeclared + README references NO hero                 → CLEAN
#      (a downstream scaffold from the hero-less reusable template emits no
#       broken ref in the first place — not silently skipped by H10).
# (c)  near-miss with no extension                            → HARD-FAIL.
CA=$(mktemp -d); CB=$(mktemp -d)
trap 'rm -rf "$CA" "$CB"' EXIT
for D in "$CA" "$CB"; do
  tar -cf - --exclude='Release/git_release_skill-v0.9*' -C "$REAL_ROOT" . 2>/dev/null \
    | (cd "$D" && tar -xf - 2>/dev/null) || true
  rm -rf "$D/docs/assets"
done
if [ -f "$AUDIT" ] && [ -f "$MANIFEST" ] && [ -f "$CA/references/docs-contract/manifest.txt" ]; then
  # CLONE-A keeps the declared hero_asset (as in the real repo).
  # (a) declared + asset removed + README still references it → hard-fail
  out_ha=$(PROJECT_ROOT="$CA" bash "$AUDIT" 2>&1) && rc_ha=0 || rc_ha=$?
  if [ "$rc_ha" -ne 0 ] && printf '%s\n' "$out_ha" | grep -q 'declared hero_asset missing'; then
    ok "H10 hard-fails when declared hero_asset absent (origin enforcement)"
  else
    fail "H10 must enforce declared hero_asset presence but did not (exit $rc_ha)"
  fi
  # (a') strip the README refs (symmetric EN+CN) → STILL hard-fail (unconditional)
  sed -i.bak '/<img src="docs\/assets\/release-demo/d' "$CA/README.md" "$CA/README_CN.md" 2>/dev/null
  rm -f "$CA/README.md.bak" "$CA/README_CN.md.bak"
  out_hap=$(PROJECT_ROOT="$CA" bash "$AUDIT" 2>&1) && rc_hap=0 || rc_hap=$?
  if [ "$rc_hap" -ne 0 ] && printf '%s\n' "$out_hap" | grep -q 'declared hero_asset missing'; then
    ok "H10 enforces declared hero_asset even when unreferenced (unconditional)"
  else
    fail "H10 declared-hero enforcement contingent on a reference (exit $rc_hap)"
  fi
  # CLONE-B: strip the declaration → undeclared (downstream-adopter) manifest.
  sed -i.bak '/^hero_asset:/d' "$CB/references/docs-contract/manifest.txt" \
    && rm -f "$CB/references/docs-contract/manifest.txt.bak"
  # (b) undeclared + README still references the (missing) hero → STRICT hard-fail
  out_hb=$(PROJECT_ROOT="$CB" bash "$AUDIT" 2>&1) && rc_hb=0 || rc_hb=$?
  if [ "$rc_hb" -ne 0 ] && printf '%s\n' "$out_hb" | grep -q 'unresolved local ref.*release-demo'; then
    ok "H10 hard-fails on a referenced missing hero, undeclared (no silent broken image)"
  else
    fail "H10 silently passed a referenced missing hero (exit $rc_hb) — Codex no-ship"
  fi
  # (b') strip the hero refs (symmetric EN+CN) → hero-less scaffold is CLEAN
  sed -i.bak '/<img src="docs\/assets\/release-demo/d' "$CB/README.md" "$CB/README_CN.md" 2>/dev/null
  rm -f "$CB/README.md.bak" "$CB/README_CN.md.bak"
  out_hbp=$(PROJECT_ROOT="$CB" bash "$AUDIT" 2>&1) && rc_hbp=0 || rc_hbp=$?
  if [ "$rc_hbp" -eq 0 ]; then
    ok "H10 clean — undeclared + no hero referenced (hero-less scaffold safe)"
  else
    fail "H10 wrongly failed a hero-less undeclared scaffold (exit $rc_hbp): $(printf '%s' "$out_hbp" | grep H10 | head -1)"
  fi
  # (c) near-miss with no extension still hard-fails (non-vacuous)
  printf '\n[nearmiss](docs/assets/release-demo)\n' >> "$CB/README.md"
  out_hc=$(PROJECT_ROOT="$CB" bash "$AUDIT" 2>&1) && rc_hc=0 || rc_hc=$?
  if [ "$rc_hc" -ne 0 ] && printf '%s\n' "$out_hc" | grep -q 'release-demo'; then
    ok "H10 still hard-fails on near-miss release-demo (no ext) — non-vacuous"
  else
    fail "H10 non-vacuity broken: near-miss release-demo did not hard-fail (exit $rc_hc)"
  fi
else
  fail "T15-hero(a) skipped: audit/manifest missing"
  fail "T15-hero(a') skipped: audit/manifest missing"
  fail "T15-hero(b) skipped: audit/manifest missing"
  fail "T15-hero(b') skipped: audit/manifest missing"
  fail "T15-hero(c) skipped: audit/manifest missing"
fi
rm -rf "$CA" "$CB"
trap - EXIT

# --- T15-mirror: bundled skill self-audit (Codex review) ---
# hero_asset is root-origin-only; it must NOT be mirrored into the bundled
# generic skill, else `PROJECT_ROOT=skills/gitx-release docs-audit` hard-fails
# on a hero the skill does not ship. (Documented divergence — see
# test_readme_template_parity.sh T12 modulo-hero_asset carve-out.)
SK="$REAL_ROOT/skills/gitx-release"
if [ -f "$SK/scripts/docs-audit.sh" ] && [ -f "$SK/references/docs-contract/manifest.txt" ]; then
  out_sk=$(PROJECT_ROOT="$SK" bash "$SK/scripts/docs-audit.sh" 2>&1) && rc_sk=0 || rc_sk=$?
  if [ "$rc_sk" -eq 0 ] && ! printf '%s\n' "$out_sk" | grep -q 'declared hero_asset missing'; then
    ok "bundled skill self-audit clean — hero_asset not mirrored (Codex regression)"
  else
    fail "bundled skill self-audit broken by mirrored hero_asset (exit $rc_sk): $(printf '%s' "$out_sk" | grep -i hero | head -1)"
  fi
  if ! grep -q '^hero_asset:' "$SK/references/docs-contract/manifest.txt"; then
    ok "skill mirror manifest omits root-only hero_asset: declaration"
  else
    fail "skill mirror manifest wrongly declares hero_asset (root-only carve-out violated)"
  fi
else
  fail "T15-mirror skipped: bundled skill audit/manifest missing"
  fail "T15-mirror-b skipped: bundled skill audit/manifest missing"
fi

# --- T16: non-counting guarantee — output has no Deep-Audit-shaped tally (Gotcha #62) ---
if [ -f "$AUDIT" ] && [ -f "$MANIFEST" ]; then
  out_nc=$(PROJECT_ROOT="$REAL_ROOT" bash "$AUDIT" 2>&1)
  if printf '%s\n' "$out_nc" | grep -qE '[0-9]+ / [❌➖✅] *[0-9]+|✅ *[0-9]+ */ *❌ *[0-9]+ */ *➖ *[0-9]+'; then
    fail "non-counting violated: docs-audit output contains a Deep-Audit-style tally"
  else
    ok "non-counting holds: docs-audit output contains no tally (Gotcha #62)"
  fi
else
  fail "T16 skipped: audit or manifest missing"
fi

# --- T17: release.sh wires docs-audit as a fail-closed gate (T11 gate) ---
# Verify release.sh calls docs-audit.sh and aborts on failure (exit 1 present).
RELEASE_SH="$SCRIPT_DIR/../scripts/release.sh"
if grep -q 'docs-audit' "$RELEASE_SH" 2>/dev/null; then
  ok "release.sh invokes docs-audit.sh (gate wired)"
else
  fail "release.sh does NOT invoke docs-audit.sh — gate missing"
fi
if grep -A5 'docs-audit' "$RELEASE_SH" 2>/dev/null | grep -q 'exit 1'; then
  ok "release.sh aborts (exit 1) on docs-audit failure"
else
  fail "release.sh does not abort on docs-audit failure — exit 1 missing near gate"
fi

# --- T18: release-audit.sh invokes docs-audit.sh after §0j, non-counting (T11 gate) ---
# Non-counting: must NOT be wrapped in _track_start / _track_end machinery.
RELEASE_AUDIT_SH="$SCRIPT_DIR/../scripts/release-audit.sh"
if grep -q 'docs-audit' "$RELEASE_AUDIT_SH" 2>/dev/null; then
  ok "release-audit.sh invokes docs-audit.sh (informational non-counting call wired)"
else
  fail "release-audit.sh does NOT invoke docs-audit.sh — non-counting call missing"
fi
# Confirm no _track_start call referencing docs-audit (Gotcha #62)
if grep '_track_start.*docs.audit\|_track_start.*docs-audit' "$RELEASE_AUDIT_SH" 2>/dev/null | grep -q .; then
  fail "release-audit.sh has _track_start wrapped around docs-audit — violates non-counting (Gotcha #62)"
else
  ok "release-audit.sh docs-audit call is non-counting (no _track_start wrapper)"
fi

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && { echo PASS; exit 0; } || { echo FAIL; exit 1; }
