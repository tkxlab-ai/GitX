#!/bin/bash
# test_docs_pipeline.sh — TDD for T2: docs-pipeline.sh core
# Assertions: file exists+executable, --print-regions exact 5-region set,
# SC2010-free (no ls|grep), shellcheck clean (or skip), --help contains --check
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/../scripts/docs-pipeline.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_docs_pipeline.sh ══"

# --- T1: file exists and is executable ---
if [ -f "$PIPELINE" ]; then
  ok "scripts/docs-pipeline.sh exists"
else
  fail "scripts/docs-pipeline.sh does NOT exist"
fi

if [ -x "$PIPELINE" ]; then
  ok "scripts/docs-pipeline.sh is executable"
else
  fail "scripts/docs-pipeline.sh is NOT executable"
fi

# --- T2: --print-regions emits exactly the 5 contracted regions (§2a frozen spec) ---
# sorted+space-joined must equal exactly: "badges build-metrics command-surface suite-count whats-new "
# version and install are NOT managed regions (they fold at T12/template work, not T2).
if [ -f "$PIPELINE" ]; then
  REGIONS_RAW=$(bash "$PIPELINE" --print-regions 2>/dev/null || true)
  # sort each whitespace-separated token and rejoin with a trailing space
  REGIONS_SORTED=$(printf '%s\n' $REGIONS_RAW | sort | tr '\n' ' ')
  EXPECTED="badges build-metrics command-surface suite-count whats-new "
  if [ "$REGIONS_SORTED" = "$EXPECTED" ]; then
    ok "--print-regions emits exactly the 5 contracted regions (sorted: $REGIONS_SORTED)"
  else
    fail "--print-regions output wrong: got '$REGIONS_SORTED' expected '$EXPECTED'"
  fi
else
  fail "--print-regions: script missing, skipping assertion"
fi

# --- T3: SC2010-free — no ls ... | ... grep pattern ---
if [ -f "$PIPELINE" ]; then
  SC2010_HITS=$(grep -nE 'ls[^|]*\|[^|]*grep' "$PIPELINE" 2>/dev/null || true)
  if [ -z "$SC2010_HITS" ]; then
    ok "SC2010-free: no 'ls ... | ... grep' pattern found"
  else
    fail "SC2010 violation found in docs-pipeline.sh:
$SC2010_HITS"
  fi
else
  fail "SC2010 check: script missing, skipping"
fi

# --- T4: shellcheck clean (skip if not installed) ---
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "$PIPELINE" 2>/dev/null; then
    ok "shellcheck -S warning clean"
  else
    fail "shellcheck -S warning found issues"
  fi
else
  echo "  ⏭  shellcheck not installed — skipping SC lint (non-fatal)"
fi

# --- T5: --help output contains --check ---
if [ -f "$PIPELINE" ]; then
  HELP_OUT=$(bash "$PIPELINE" --help 2>/dev/null || true)
  if printf '%s\n' "$HELP_OUT" | grep -qF -- '--check'; then
    ok "--help output contains '--check'"
  else
    fail "--help output does NOT contain '--check'"
  fi
else
  fail "--help check: script missing, skipping"
fi

# --- T3-locale: --locale flag parsed; inventory locale-invariant; --print-target ---
# --locale cn accepted (not a usage-error exit 2)
bash "$PIPELINE" --locale cn --print-regions >/tmp/dp_lc.out 2>/tmp/dp_lc.err && rc=0 || rc=$?
[ "$rc" -eq 0 ] && ok "--locale cn accepted (rc=0)" || fail "--locale cn rc=$rc (expected 0)"
# inventory must be the same 5 regions regardless of locale
lc=$(tr ' ' '\n' </tmp/dp_lc.out | sort | tr '\n' ' ')
[ "$lc" = "badges build-metrics command-surface suite-count whats-new " ] \
  && ok "inventory locale-invariant under cn" || fail "inventory changed under cn: '$lc'"
bash "$PIPELINE" --locale en --print-regions >/dev/null 2>&1 && ok "--locale en accepted" || fail "--locale en rc=$?"
# unknown locale must fail-closed with usage exit 2
bash "$PIPELINE" --locale bogus --print-regions >/dev/null 2>&1 && rc=$? || rc=$?
[ "$rc" -eq 2 ] && ok "unknown --locale → usage exit 2 (fail-closed)" || fail "unknown locale rc=$rc (expected 2)"
# --print-target: cn → README_CN.md, en → README.md
bash "$PIPELINE" --locale cn --print-target >/tmp/dp_tgt.out 2>/dev/null && \
  grep -qx 'README_CN.md' /tmp/dp_tgt.out && ok "cn → README_CN.md" || fail "cn target wrong: $(cat /tmp/dp_tgt.out 2>/dev/null)"
bash "$PIPELINE" --locale en --print-target 2>/dev/null | grep -qx 'README.md' \
  && ok "en → README.md" || fail "en target wrong"
# bare --print-target (no --locale) → exactly two lines: README.md then README_CN.md
bash "$PIPELINE" --print-target >/tmp/dp_tgt_bare.out 2>/dev/null && rc_bare=0 || rc_bare=$?
if [ "$rc_bare" -eq 0 ] \
  && grep -qx 'README.md' /tmp/dp_tgt_bare.out \
  && grep -qx 'README_CN.md' /tmp/dp_tgt_bare.out \
  && [ "$(wc -l < /tmp/dp_tgt_bare.out)" -eq 2 ]; then
  ok "bare --print-target → two lines: README.md and README_CN.md"
else
  fail "bare --print-target wrong: rc=$rc_bare output='$(cat /tmp/dp_tgt_bare.out 2>/dev/null)'"
fi
# --locale with no value → exit 2 (missing-value fail-closed)
bash "$PIPELINE" --locale >/dev/null 2>&1 && rc_noval=0 || rc_noval=$?
[ "$rc_noval" -eq 2 ] && ok "--locale (no value) → exit 2 (missing-value fail-closed)" \
  || fail "--locale (no value) rc=$rc_noval (expected 2)"
rm -f /tmp/dp_lc.out /tmp/dp_lc.err /tmp/dp_tgt.out /tmp/dp_tgt_bare.out

# --- T4-changelog-parity: --changelog-parity mode ---
P="$PIPELINE"
# absent CN file → must exit 0 with 'absent' in output (unconditional scratch;
# immune to T13 adding CHANGELOG_CN.md to the live repo later)
TMPD=$(mktemp -d)
mkdir -p "$TMPD/Release"
printf '## v1.0.0 — 2026-01-01\n\n### Added\n- x\n' > "$TMPD/Release/CHANGELOG.md"
# no CHANGELOG_CN.md created → absent case
out=$(PROJECT_ROOT="$TMPD" bash "$P" --changelog-parity 2>&1) && rc=0 || rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qi 'absent'; } \
  && ok "changelog-parity clean-absent (rc=0, 'absent' msg)" \
  || fail "changelog-parity absent-handling wrong (rc=$rc, out=$out)"
rm -rf "$TMPD"
# synthetic mismatch detection: scratch dir with deliberately divergent CN → exit 1
TMPD=$(mktemp -d)
mkdir -p "$TMPD/Release"
printf '## v1.0.0 — 2026-01-01\n\n### Added\n- x\n' > "$TMPD/Release/CHANGELOG.md"
printf '## v1.0.0 — 2026-01-01\n\n### 修复\n- y\n'   > "$TMPD/Release/CHANGELOG_CN.md"
PROJECT_ROOT="$TMPD" bash "$P" --changelog-parity >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -eq 1 ] && ok "changelog-parity detects subsection-set mismatch (exit 1)" || fail "parity missed mismatch (rc=$rc)"
# synthetic match: identical structure (different prose) → exit 0
printf '## v1.0.0 — 2026-01-01\n\n### Added\n- english text\n' > "$TMPD/Release/CHANGELOG.md"
printf '## v1.0.0 — 2026-01-01\n\n### Added\n- 中文文本\n'        > "$TMPD/Release/CHANGELOG_CN.md"
PROJECT_ROOT="$TMPD" bash "$P" --changelog-parity >/dev/null 2>&1 && ok "changelog-parity passes structural match (prose differs)" || fail "parity false-negative on structural match"
rm -rf "$TMPD"

# --- T2.5: badges + build-metrics @machine SUB-TOKEN rewrite (§2b/H4) ---
# refresh mode calls dp_rewrite_file on the existing README directly (no
# template needed). Fixture carries ONLY badges+build-metrics regions with
# deliberately-stale sub-tokens + curated content that MUST survive.
TT=$(mktemp -d)
mkdir -p "$TT/tests" "$TT/Release"
: > "$TT/tests/test_a.sh"; : > "$TT/tests/test_b.sh"; : > "$TT/tests/test_c.sh"   # 3 live suites
echo "v9.9.9" > "$TT/VERSION"
printf '## v9.9.9 — 2030-12-31\n\n### Added\n- x\n' > "$TT/Release/CHANGELOG.md"
cat > "$TT/README.md" <<'EOF'
<!-- gitx:managed:badges -->
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-77%20suites%20%2F%200%20fail-brightgreen.svg)](tests/run_all.sh)
[![Release](https://img.shields.io/github/v/release/x/y?sort=semver)](z)
<!-- /gitx:managed:badges -->

<!-- gitx:managed:build-metrics -->
> 🛠 **Live build metrics** — Version **v0.0.1** · Released **2000-01-01** · Engineered with **Claude · Codex** · Span **~58 releases**
<!-- /gitx:managed:build-metrics -->
EOF
PROJECT_ROOT="$TT" bash "$P" --locale en >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -eq 0 ] && ok "T2.5 refresh rc0 on badges+build-metrics fixture" || fail "T2.5 refresh rc=$rc"
grep -q 'tests-3%20suites%20%2F%200%20fail' "$TT/README.md" \
  && ok "T2.5 badges Tests shield → live count (3)" || fail "T2.5 badges Tests shield not @machine ($(grep -o 'tests-[0-9]*%20suites' "$TT/README.md"))"
grep -q 'Version \*\*v9.9.9\*\*' "$TT/README.md" \
  && ok "T2.5 build-metrics version → VERSION" || fail "T2.5 build-metrics version not @machine"
grep -q 'Released \*\*2030-12-31\*\*' "$TT/README.md" \
  && ok "T2.5 build-metrics date → top CHANGELOG date" || fail "T2.5 build-metrics date not @machine"
{ grep -q 'license-MIT-green' "$TT/README.md" \
  && grep -q 'Engineered with \*\*Claude · Codex\*\*' "$TT/README.md" \
  && grep -q 'github/v/release/x/y' "$TT/README.md" \
  && grep -q 'Span \*\*~58 releases\*\*' "$TT/README.md"; } \
  && ok "T2.5 curated shields/prose preserved (no whole-region replace)" || fail "T2.5 curated content destroyed"
cp "$TT/README.md" "$TT/README.once"
PROJECT_ROOT="$TT" bash "$P" --locale en >/dev/null 2>&1 && rc2=0 || rc2=$?
{ [ "$rc2" -eq 0 ] && cmp -s "$TT/README.md" "$TT/README.once"; } \
  && ok "T2.5 sub-token rewrite idempotent" || fail "T2.5 not idempotent (rc2=$rc2)"
rm -rf "$TT"

# --- T-resolvers: dp_* library-source assertions (coverage parity for vacuous
# gr_* blocks removed from test_gitx_readme.sh in v1.11.0 shim refactor).
# Pattern: export PROJECT_ROOT DOCS_PIPELINE_LIB=1 BEFORE sourcing (set -u
# in docs-pipeline.sh fires on unbound PROJECT_ROOT at dp_suite_count line 78).
# Each sub-block is proved RED→GREEN: wrong input fails, correct input passes.
echo "§ dp_* resolver library (DOCS_PIPELINE_LIB=1)"

_dp_lib_test(){
  # $1=PROJECT_ROOT, rest=shell code to eval after source
  local _pr="$1"; shift
  # Hermetic: release.sh and CI export SKILL_NAME / PROJECT_NAME for
  # packaging; dp_skill_name gives the SKILL_NAME env var TOP precedence, so
  # an inherited SKILL_NAME silently overrides the scratch-layout resolution
  # these assertions test (dogfood failure: green standalone, red inside the
  # release pipeline). unset them so each _dp_lib_test isolates the scratch
  # PROJECT_ROOT's own layout. The env-override path is covered separately by
  # test (b), which deliberately sets SKILL_NAME and does NOT use this helper.
  bash -c "unset SKILL_NAME PROJECT_NAME; export PROJECT_ROOT='$_pr' DOCS_PIPELINE_LIB=1; . '$PIPELINE'; $*" 2>&1
}

# (a) dp_skill_name: frontmatter-only — body "name:" MUST be ignored
_WF=$(mktemp -d)
printf -- '---\nname: fm-name\n---\n# heading\nname: body-name should be ignored\n' > "$_WF/SKILL.md"
_dp_lib_test "$_WF" '[ "$(dp_skill_name)" = fm-name ]' >/dev/null 2>&1 \
  && ok  "dp_skill_name: frontmatter-only, body name: ignored (a)" \
  || fail "dp_skill_name: frontmatter-only, body name: ignored (a)"
rm -rf "$_WF"

# (b) dp_skill_name: SKILL_NAME env wins over skills/ + root SKILL.md
_WEN=$(mktemp -d); mkdir -p "$_WEN/skills/otherdir"
printf -- '---\nname: rootname\n---\n' > "$_WEN/SKILL.md"
printf -- '---\nname: x\n---\n' > "$_WEN/skills/otherdir/SKILL.md"
bash -c "export PROJECT_ROOT='$_WEN' SKILL_NAME=envskill DOCS_PIPELINE_LIB=1; . '$PIPELINE'; [ \"\$(dp_skill_name)\" = envskill ]" >/dev/null 2>&1 \
  && ok  "dp_skill_name: SKILL_NAME env wins over skills/ + root SKILL.md (b)" \
  || fail "dp_skill_name: SKILL_NAME env wins over skills/ + root SKILL.md (b)"
rm -rf "$_WEN"

# (c) dp_skill_name: standard-layout skills/<name>/SKILL.md → dir-basename
_WSL=$(mktemp -d); mkdir -p "$_WSL/skills/demo-skill"
printf -- '---\nname: ignored-frontmatter\n---\n' > "$_WSL/skills/demo-skill/SKILL.md"
_dp_lib_test "$_WSL" '[ "$(dp_skill_name)" = demo-skill ]' >/dev/null 2>&1 \
  && ok  "dp_skill_name: standard-layout skills/<name>/ → dir-basename (c)" \
  || fail "dp_skill_name: standard-layout skills/<name>/ → dir-basename (c)"
rm -rf "$_WSL"

# (d) dp_skill_name: *-workspace excluded from skills/ scan
_WPX=$(mktemp -d); mkdir -p "$_WPX/skills/realskill" "$_WPX/skills/foo-workspace"
printf -- '---\nname: a\n---\n' > "$_WPX/skills/realskill/SKILL.md"
printf -- '---\nname: b\n---\n' > "$_WPX/skills/foo-workspace/SKILL.md"
_dp_lib_test "$_WPX" '
  n=$(dp_skill_name)
  [ "$n" = realskill ] && [ "$n" != foo-workspace ]
' >/dev/null 2>&1 \
  && ok  "dp_skill_name: *-workspace dir excluded from skills/ scan (d)" \
  || fail "dp_skill_name: *-workspace dir excluded from skills/ scan (d)"
rm -rf "$_WPX"

# (e) dp_skill_name: ambiguous >1 skills/ → safe basename fallback, NO file write
_WAMB=$(mktemp -d); mkdir -p "$_WAMB/skills/skillA" "$_WAMB/skills/skillB"
printf -- '---\nname: a\n---\n' > "$_WAMB/skills/skillA/SKILL.md"
printf -- '---\nname: b\n---\n' > "$_WAMB/skills/skillB/SKILL.md"
_dp_lib_test "$_WAMB" '
  n=$(dp_skill_name)
  [ "$n" != skillA ] && [ "$n" != skillB ] && [ -n "$n" ] \
  && [ ! -f "$PROJECT_ROOT/GitX_Upgrade_Guideline.md" ]
' >/dev/null 2>&1 \
  && ok  "dp_skill_name: ambiguous >1 skills/ → safe fallback, no file write (e)" \
  || fail "dp_skill_name: ambiguous >1 skills/ → safe fallback, no file write (e)"
rm -rf "$_WAMB"

# (f) dp_command_surface: standard-layout skills/<skill>/commands/ enumerated
_WCS=$(mktemp -d); mkdir -p "$_WCS/skills/demo-skill/commands"
printf -- '---\nname: ignored\n---\n' > "$_WCS/skills/demo-skill/SKILL.md"
touch "$_WCS/skills/demo-skill/commands/demo-skill-init.md"
touch "$_WCS/skills/demo-skill/commands/demo-skill-sop.md"
_dp_lib_test "$_WCS" '
  dp_command_surface | grep -qF "/demo-skill\` — the skill" &&
  dp_command_surface | grep -qF "/demo-skill-init" &&
  dp_command_surface | grep -qF "/demo-skill-sop"
' >/dev/null 2>&1 \
  && ok  "dp_command_surface: standard-layout skills/<skill>/commands/ shims listed (f)" \
  || fail "dp_command_surface: standard-layout skills/<skill>/commands/ shims listed (f)"
rm -rf "$_WCS"

# (g) dp_install: marketplace + plugin install when .claude-plugin present
_WG=$(mktemp -d); mkdir -p "$_WG/.claude-plugin"
printf '{\n  "name": "myplugin"\n}\n' > "$_WG/.claude-plugin/plugin.json"
_dp_lib_test "$_WG" '
  dp_install | grep -q "marketplace add" &&
  dp_install | grep -q "myplugin@tkx-skills"
' >/dev/null 2>&1 \
  && ok  "dp_install: marketplace-add + plugin install <name>@tkx-skills when plugin present (g)" \
  || fail "dp_install: marketplace-add + plugin install <name>@tkx-skills when plugin present (g)"
rm -rf "$_WG"

# (h) dp_install: generic-safe (no .claude-plugin) → bash install.sh, no marketplace
_WH=$(mktemp -d)
_dp_lib_test "$_WH" '
  dp_install | grep -q "bash install.sh" &&
  ! dp_install | grep -qi "marketplace"
' >/dev/null 2>&1 \
  && ok  "dp_install: generic-safe (no .claude-plugin) → bash install.sh, no marketplace (h)" \
  || fail "dp_install: generic-safe (no .claude-plugin) → bash install.sh, no marketplace (h)"
rm -rf "$_WH"

# (i) dp_suite_count: test_suite_structure.sh excluded from count
_WI=$(mktemp -d); mkdir -p "$_WI/tests"
touch "$_WI/tests/test_a.sh" "$_WI/tests/test_b.sh" "$_WI/tests/test_suite_structure.sh"
_dp_lib_test "$_WI" '[ "$(dp_suite_count)" = 2 ]' >/dev/null 2>&1 \
  && ok  "dp_suite_count: test_suite_structure.sh excluded from count (i)" \
  || fail "dp_suite_count: test_suite_structure.sh excluded from count (i)"
rm -rf "$_WI"

# (j) dp_version: reads VERSION file verbatim
_WJ=$(mktemp -d); echo "v3.7.2" > "$_WJ/VERSION"
_dp_lib_test "$_WJ" '[ "$(dp_version)" = v3.7.2 ]' >/dev/null 2>&1 \
  && ok  "dp_version: reads VERSION file verbatim (j)" \
  || fail "dp_version: reads VERSION file verbatim (j)"
rm -rf "$_WJ"

# (k-1) dp_whats_new: correct top entry, no next-entry bleed
_WK=$(mktemp -d)
printf '## v9.9.9 — 2026-09-09\n\n### Added\n- alpha bullet\n- beta thing\n\n### Changed\n- gamma thing\n\n## v9.9.8 — 2026-08-08\n- old\n' > "$_WK/CHANGELOG.md"
_dp_lib_test "$_WK" '
  dp_whats_new | head -1 | grep -q "v9.9.9 — 2026-09-09" &&
  dp_whats_new | grep -q "alpha bullet" &&
  dp_whats_new | grep -q "gamma thing" &&
  ! dp_whats_new | grep -q "## v9.9.8" &&
  ! dp_whats_new | grep -q "^old$"
' >/dev/null 2>&1 \
  && ok  "dp_whats_new: top entry correct, no next-entry bleed (k)" \
  || fail "dp_whats_new: top entry correct, no next-entry bleed (k)"
rm -rf "$_WK"

# (k-2) dp_whats_new: >=7 bullets caps at exactly 6 (6th in, 7th out)
_WK7=$(mktemp -d)
printf '## v9.9.9 — 2026-09-09\n- one\n- two\n- three\n- four\n- five\n- six\n- seven\n- eight\n\n## v9.9.8 — 2026-08-08\n- nextentry\n' > "$_WK7/CHANGELOG.md"
_dp_lib_test "$_WK7" '
  cnt=$(dp_whats_new | grep -c "^- ")
  [ "$cnt" = 6 ] &&
  dp_whats_new | grep -q "^- six" &&
  ! dp_whats_new | grep -q "^- seven" &&
  ! dp_whats_new | grep -q "nextentry"
' >/dev/null 2>&1 \
  && ok  "dp_whats_new: >=7 bullets caps at exactly 6 (6th in, 7th out) (k)" \
  || fail "dp_whats_new: >=7 bullets caps at exactly 6 (6th in, 7th out) (k)"
rm -rf "$_WK7"

# (k-3) dp_whats_new: CRLF CHANGELOG → zero \r in output
_WKR=$(mktemp -d)
printf '## v9.9.9 — 2026-09-09\r\n\r\n- crlf bullet one\r\n- crlf bullet two\r\n' > "$_WKR/CHANGELOG.md"
_dp_lib_test "$_WKR" '
  ! dp_whats_new | LC_ALL=C grep -q $'"'"'\r'"'"' &&
  dp_whats_new | grep -q "crlf bullet one" &&
  dp_whats_new | grep -q "crlf bullet two"
' >/dev/null 2>&1 \
  && ok  "dp_whats_new: CRLF CHANGELOG → zero \\r in output (k)" \
  || fail "dp_whats_new: CRLF CHANGELOG → zero \\r in output (k)"
rm -rf "$_WKR"

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && { echo PASS; exit 0; } || { echo FAIL; exit 1; }
