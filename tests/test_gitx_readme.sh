#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SH="$ROOT/scripts/gitx-readme.sh"
PASS=0; FAIL=0
ok(){ echo "  ✅ $1"; PASS=$((PASS+1)); }
no(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_gitx_readme.sh ══"
# interface (Task 1)
test -x "$SH" && ok "executable" || no "executable"
grep -qE '^set -euo pipefail' "$SH" && ok "set -euo pipefail" || no "set -euo pipefail"
bash "$SH" --help >/dev/null 2>&1 && ok "--help exit 0" || no "--help exit 0"
( bash "$SH" --bogus >/dev/null 2>&1; [ $? -eq 2 ] ) && ok "unknown flag exit 2" || no "unknown flag exit 2"
grep -qE '(^|[^[:alnum:]_])(git|gh)[[:space:]]' "$SH" && no "no git/gh" || ok "no git/gh"
grep -qiE '(curl|anthropic|openai|claude)[[:space:]]' "$SH" && no "no LLM" || ok "no LLM"
# resolvers (sourced as lib — exercised under the script's own set -euo via subshell calls below)
echo "§ resolvers"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/tests" "$W/.claude-plugin"
: > "$W/tests/test_a.sh"; : > "$W/tests/test_b.sh"; : > "$W/tests/test_suite_structure.sh"
echo "v9.9.9" > "$W/VERSION"
printf '{\n  "name": "demoskill",\n  "version": "9.9.9"\n}\n' > "$W/.claude-plugin/plugin.json"
printf '## v9.9.9 — 2026-01-01\n- x\n' > "$W/CHANGELOG.md"
( cd "$W" && GITX_README_LIB=1 . "$SH" && [ "$(gr_suite_count)" = "2" ] ) && ok "suite_count=2 (excl suite_structure)" || no "suite_count"
( cd "$W" && GITX_README_LIB=1 . "$SH" && [ "$(gr_version)" = "v9.9.9" ] ) && ok "version" || no "version"
( cd "$W" && GITX_README_LIB=1 . "$SH" && gr_install | grep -q 'marketplace add tkxlab-ai/marketplace' ) && ok "install marketplace add" || no "install add"
( cd "$W" && GITX_README_LIB=1 . "$SH" && gr_install | grep -q 'plugin install demoskill@tkx-skills' ) && ok "install name" || no "install name"
( cd "$W" && GITX_README_LIB=1 . "$SH" && gr_whats_new | grep -q 'v9.9.9 — 2026-01-01' ) && ok "whats_new" || no "whats_new"
( cd "$W" && rm -rf .claude-plugin && GITX_README_LIB=1 . "$SH" && gr_install >/dev/null 2>&1 ) && ok "install exit0 non-plugin (errexit-safe)" || no "install errexit"
( cd "$W" && GITX_README_LIB=1 . "$SH" && gr_install | grep -q 'marketplace add' ) && no "non-plugin must omit marketplace" || ok "install generic-safe non-plugin"
# validator: fail-closed exit 5, NO write, on malformed regions
echo "§ validator (fail-closed)"
mkf(){ printf '%s\n' "$@"; }
V="$(mktemp -d)"; mkdir -p "$V/tests"; : > "$V/tests/test_suite_structure.sh"; echo v1 > "$V/VERSION"
# missing closer
mkf 'pre' '<!-- gitx:managed:version -->' 'BODY' 'post-prose' > "$V/README.md"
cp "$V/README.md" "$V/README.md.bak"
( cd "$V" && bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) && ok "missing closer → exit 5" || no "missing closer exit5"
cmp -s "$V/README.md" "$V/README.md.bak" && ok "missing closer → file untouched (no prose loss)" || no "missing closer mutated file"
# duplicate opener
mkf '<!-- gitx:managed:version -->' 'a' '<!-- /gitx:managed:version -->' '<!-- gitx:managed:version -->' 'b' '<!-- /gitx:managed:version -->' > "$V/README.md"
( cd "$V" && bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) && ok "duplicate opener → exit 5" || no "dup opener exit5"
# inline (same-line) markers rejected
echo '- v: <!-- gitx:managed:version -->x<!-- /gitx:managed:version -->' > "$V/README.md"
( cd "$V" && bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) && ok "inline same-line markers → exit 5" || no "inline exit5"
# leading content before marker rejected
echo 'JUNK <!-- gitx:managed:version -->' > "$V/README.md"; printf '<!-- /gitx:managed:version -->\n' >> "$V/README.md"
( cd "$V" && bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) && ok "leading content before marker → exit 5" || no "leading-content exit5"
# NEW-I-a: trailing whitespace / CR on marker line TOLERATED (no false exit 5, no prose loss)
printf 'pre\n<!-- gitx:managed:suite-count --> \nOLD\n<!-- /gitx:managed:suite-count -->\t\npost\n' > "$V/README.md"
( cd "$V" && bash "$SH" >/dev/null 2>&1 ) && ok "trailing ws/CR on marker tolerated (exit 0, NEW-I-a)" || no "trailing ws falsely rejected"
grep -qx 'pre' "$V/README.md" && grep -qx 'post' "$V/README.md" && ok "prose intact under ws-tolerant markers" || no "prose lost (ws case)"
echo "§ modes"
M="$(mktemp -d)"
mkdir -p "$M/tests" "$M/.claude-plugin"
: > "$M/tests/test_x.sh"; : > "$M/tests/test_suite_structure.sh"
echo v2.0.0 > "$M/VERSION"
printf '{\n  "name": "demox"\n}\n' > "$M/.claude-plugin/plugin.json"
printf '## v2.0.0 — 2026-02-02\n- hi\n' > "$M/CHANGELOG.md"
{
  echo '# Demo'
  echo 'PROSE-ABOVE-verbatim'
  echo '<!-- gitx:managed:suite-count -->'
  echo 'OLD'
  echo '<!-- /gitx:managed:suite-count -->'
  echo '## Install'
  echo '<!-- gitx:managed:install -->'
  echo 'OLD'
  echo '<!-- /gitx:managed:install -->'
  echo 'PROSE-BELOW-verbatim'
} > "$M/README.md"
cp "$M/README.md" "$M/README_CN.md"
( cd "$M" && bash "$SH" >/dev/null 2>&1 ) && ok "refresh exit 0" || no "refresh exit0"
awk '/gitx:managed:suite-count/{f=1;next}/\/gitx:managed:suite-count/{f=0}f' "$M/README.md" | grep -qx '1' && ok "suite-count → 1" || no "suite-count rewrite"
grep -qx 'PROSE-ABOVE-verbatim' "$M/README.md" && grep -qx 'PROSE-BELOW-verbatim' "$M/README.md" && ok "prose verbatim around regions" || no "prose lost"
awk '/gitx:managed:install/{f=1;next}/\/gitx:managed:install/{f=0}f' "$M/README.md" | grep -q 'plugin install demox@tkx-skills' && ok "multi-line install via temp-file (not awk -v)" || no "multi-line install"
cp "$M/README.md" /tmp/r1; ( cd "$M" && bash "$SH" >/dev/null 2>&1 ); diff -q /tmp/r1 "$M/README.md" >/dev/null && ok "idempotent" || no "not idempotent"
( cd "$M" && bash "$SH" --check >/dev/null 2>&1 ) && ok "--check exit 0 in sync" || no "--check false-drift"
printf '\nhand-written paragraph outside any managed region\n' >> "$M/README.md"
( cd "$M" && bash "$SH" --check >/dev/null 2>&1 ) && ok "--check exit 0 after unmanaged-prose edit (contract)" || no "--check false-drift on unmanaged prose"
perl -0pi -e 's{(<!-- gitx:managed:suite-count -->\n).*?(\n<!-- /gitx:managed:suite-count -->)}{${1}999STALE${2}}s' "$M/README.md"
( cd "$M" && bash "$SH" --check >/dev/null 2>&1; [ $? -eq 1 ] ) && ok "--check exit 1 on managed-region drift" || no "--check missed managed drift"
( cd "$M" && bash "$SH" >/dev/null 2>&1 && bash "$SH" --check >/dev/null 2>&1 ) && ok "refresh re-syncs the stale managed region" || no "refresh did not resync"
I="$(mktemp -d)"; ( cd "$I" && bash "$SH" --init >/dev/null 2>&1 ) && test -f "$I/README.md" && ok "--init scaffolds" || no "--init"
( cd "$I" && bash "$SH" --init >/dev/null 2>&1; [ $? -eq 4 ] ) && ok "--init exit 4 when exists" || no "--init no-clobber"
( cd "$I" && bash "$SH" --init --force >/dev/null 2>&1 ) && ok "--init --force" || no "--init force"
( cd "$I" && bash "$SH" --check >/dev/null 2>&1 ) && ok "scaffold self-consistent (no exit 5)" || no "scaffold malformed"
rm -rf "$M" "$I" /tmp/r1
# unknown managed region → fail-closed exit 5 (FIX B: gr_validate_regions
# must reject any NAME not in {suite-count,version,install,whats-new})
echo "§ unknown managed region (FIX B)"
U="$(mktemp -d)"; mkdir -p "$U/tests"; : > "$U/tests/test_suite_structure.sh"; echo v1 > "$U/VERSION"
printf '<!-- gitx:managed:bogus -->\nbody\n<!-- /gitx:managed:bogus -->\n' > "$U/README.md"
cp "$U/README.md" "$U/README.md.bak"
( cd "$U" && bash "$SH" >/dev/null 2>&1; [ $? -eq 5 ] ) \
  && ok "unknown managed name 'bogus' → exit 5 (fail-closed)" \
  || no "unknown managed name 'bogus' should exit 5 but did not"
cmp -s "$U/README.md" "$U/README.md.bak" \
  && ok "unknown name → file untouched (fail-closed, no write)" \
  || no "unknown name → file was mutated (should be untouched)"
rm -rf "$U"

echo "§ v1.10.1 whats-new(rich) + command-surface"
WX="$(mktemp -d)"  # NEW-2: do NOT add a 2nd EXIT trap (would shadow the file's existing $W trap); clean WX explicitly at section end instead
mkdir -p "$WX/tests" "$WX/.claude-plugin" "$WX/commands" "$WX/gitx-plugin-commands"
: > "$WX/tests/test_suite_structure.sh"; echo v9.9.9 > "$WX/VERSION"
# REAL GitX case: skill name (SKILL.md) != plugin name (plugin.json) — C2/HIGH-1
printf -- '---\nname: demo-skill\n---\n' > "$WX/SKILL.md"
printf '{\n  "name": "demoP",\n  "commands": ["./gitx-plugin-commands/"]\n}\n' > "$WX/.claude-plugin/plugin.json"
: > "$WX/commands/demo-skill-init.md"; : > "$WX/commands/demo-skill-sop.md"
: > "$WX/gitx-plugin-commands/release.md"; : > "$WX/gitx-plugin-commands/audit.md"
# wrapped CHANGELOG bullets (continuation indented) — MEDIUM finding
printf '## v9.9.9 — 2026-09-09\n\n### Added\n- alpha bullet that wraps\n  onto a second line with the core detail\n- beta thing\n\n### Changed\n- gamma thing\n\n## v9.9.8 — 2026-08-08\n- old\n' > "$WX/CHANGELOG.md"
( cd "$WX" && GITX_README_LIB=1 . "$SH" \
  && gr_whats_new | head -1 | grep -q 'v9.9.9 — 2026-09-09' \
  && gr_whats_new | grep -q 'alpha bullet that wraps onto a second line with the core detail' \
  && gr_whats_new | grep -q 'gamma thing' \
  && ! gr_whats_new | grep -q '## v9.9.8' && ! gr_whats_new | grep -q '^old$' ) \
  && ok "whats_new rich: complete wrapped items, not next entry" || no "whats_new rich"
# spec-review regression: top entry with >=7 bullets must cap at EXACTLY 6
# (the 6th present, the 7th/8th + next entry excluded). Locks the off-by-one
# where the deferred-print awk emitted only 5 and destroyed the 6th bullet.
W7="$(mktemp -d)"; printf '## v9.9.9 — 2026-09-09\n- one\n- two\n- three\n- four\n- five\n- six\n- seven\n- eight\n\n## v9.9.8 — 2026-08-08\n- nextentry\n' > "$W7/CHANGELOG.md"
( cd "$W7" && GITX_README_LIB=1 . "$SH" \
  && [ "$(gr_whats_new | grep -c '^- ')" -eq 6 ] \
  && gr_whats_new | grep -qxF -- '- six' \
  && ! gr_whats_new | grep -qxF -- '- seven' \
  && ! gr_whats_new | grep -qxF -- '- eight' \
  && ! gr_whats_new | grep -q 'nextentry' && ! gr_whats_new | grep -q '## v9.9.8' ) \
  && ok "whats_new >=7 bullets: caps at exactly 6 (6th in, 7th/8th + next entry out)" || no "whats_new >=7 cap off-by-one"
# I-1: a CRLF CHANGELOG must NOT leak literal \r into the bullets. The header
# path strips CR (head -1 | sed) and sibling gr_skill_name does tr -d '\r',
# but the bullet awk had no CR handling → dependent skills with a CRLF
# CHANGELOG got '- bullet\r' written verbatim, corrupting diff/grep + --check.
WR="$(mktemp -d)"; printf '## v9.9.9 — 2026-09-09\r\n\r\n- crlf bullet one\r\n- crlf bullet two\r\n' > "$WR/CHANGELOG.md"
( cd "$WR" && GITX_README_LIB=1 . "$SH" \
  && ! gr_whats_new | LC_ALL=C grep -q $'\r' \
  && gr_whats_new | grep -qxF -- '- crlf bullet one' \
  && gr_whats_new | grep -qxF -- '- crlf bullet two' ) \
  && ok "whats_new CRLF CHANGELOG: zero \\r in output, bullets clean" || no "whats_new CRLF \\r leak"
( cd "$WX" && GITX_README_LIB=1 . "$SH" \
  && gr_command_surface | grep -qF '/demo-skill` — the skill' \
  && gr_command_surface | grep -qF '/demo-skill-init' \
  && gr_command_surface | grep -qF '/demoP:release' \
  && ! gr_command_surface | grep -qF '/demoP:demo-skill-init' \
  && gr_command_surface | grep -qi 'plugin-only' ) \
  && ok "command_surface: skill(/demo-skill) vs plugin(/demoP:release) NOT conflated, no fabrication" || no "command_surface name-split"
# C2/HIGH-2 (round-2 codex-HIGH): no .claude-plugin → ZERO colon-token, ZERO
# 'marketplace' word anywhere (footer also gated), explicit N/A.
( cd "$WX" && rm -rf .claude-plugin && GITX_README_LIB=1 . "$SH" \
  && gr_command_surface >/dev/null 2>&1 \
  && gr_command_surface | grep -q '/demo-skill' \
  && ! gr_command_surface | grep -qiE 'marketplace' \
  && ! gr_command_surface | grep -qE ':[^[:space:]]' \
  && gr_command_surface | grep -qi 'no .claude-plugin\|N/A' ) \
  && ok "command_surface non-plugin: install.sh-only, no fabricated colon/marketplace" || no "command_surface non-plugin"
# generic-safe: no commands/ either → still renders skill line, exit 0
( cd "$WX" && rm -rf commands gitx-plugin-commands && GITX_README_LIB=1 . "$SH" \
  && gr_command_surface >/dev/null 2>&1 && gr_command_surface | grep -q '/demo-skill' ) \
  && ok "command_surface generic-safe (no dirs)" || no "command_surface generic-safe"
# codex round-4 [medium]: the plugin command dir is DECLARED in
# .claude-plugin/plugin.json `commands[]` (GitX uses ./gitx-plugin-commands/;
# a dependent plugin may declare a different path). gr_command_surface MUST
# enumerate the manifest-declared dir(s), not a hard-coded gitx-plugin-commands/
# — else a dependent plugin's README omits/misstates its /<plug>:* commands
# while --check stays green (deterministic-blind, section-B analog of r1/r2).
WPC="$(mktemp -d)"; mkdir -p "$WPC/.claude-plugin" "$WPC/plugcmds"
printf -- '---\nname: depskill\n---\n' > "$WPC/SKILL.md"
printf '{\n  "name": "depplug",\n  "commands": ["./plugcmds/"]\n}\n' > "$WPC/.claude-plugin/plugin.json"
: > "$WPC/plugcmds/depplug-foo.md"; : > "$WPC/plugcmds/depplug-bar.md"
( cd "$WPC" && GITX_README_LIB=1 . "$SH" \
  && gr_command_surface | grep -qF '/depplug:depplug-foo' \
  && gr_command_surface | grep -qF '/depplug:depplug-bar' \
  && ! gr_command_surface | grep -qiE 'gitx-plugin-commands' \
  && gr_command_surface | grep -qi 'plugin-only' ) \
  && ok "command_surface: plugin cmds from plugin.json commands[] (non-gitx-plugin-commands path) (codex r4 [medium] fixed)" \
  || no "command_surface hard-codes gitx-plugin-commands/ ignoring plugin.json commands[]"
rm -rf "$WPC"
# manifest-authoritative: plugin.json with NO commands[] → MUST NOT fabricate
# /<plug>:* from an undeclared dir (footer still states colon cmds plugin-only).
WPN="$(mktemp -d)"; mkdir -p "$WPN/.claude-plugin" "$WPN/gitx-plugin-commands"
printf -- '---\nname: nplug-skill\n---\n' > "$WPN/SKILL.md"
printf '{\n  "name": "nplug"\n}\n' > "$WPN/.claude-plugin/plugin.json"
: > "$WPN/gitx-plugin-commands/should-not-appear.md"
( cd "$WPN" && GITX_README_LIB=1 . "$SH" \
  && ! gr_command_surface | grep -qF '/nplug:should-not-appear' \
  && gr_command_surface | grep -qi 'plugin-only' ) \
  && ok "command_surface: plugin.json without commands[] → no fabricated colon cmds (manifest-authoritative)" \
  || no "command_surface fabricates colon cmds when plugin.json has no commands[]"
rm -rf "$WPN"
# round-3 N-2: gr_skill_name MUST read ONLY frontmatter — a body `name:` line
# (common: SKILL.md body prose) must be IGNORED (locks the codex-MEDIUM-r2 fix)
WF="$(mktemp -d)"; printf -- '---\nname: fm-name\n---\n# heading\nname: body-name should be ignored\n' > "$WF/SKILL.md"
( cd "$WF" && GITX_README_LIB=1 . "$SH" && [ "$(gr_skill_name)" = "fm-name" ] ) \
  && ok "gr_skill_name: frontmatter only, body name: ignored" || no "gr_skill_name body-leak"
# round-3 codex-MEDIUM: missing frontmatter + hostile basename → NEVER empty/invalid
for b in '!!!' '.bad' 'Git_Release_Skill'; do
  HB="$(mktemp -d)/$b"; mkdir -p "$HB"   # no SKILL.md → fallback path
  nm=$( cd "$HB" && GITX_README_LIB=1 . "$SH" && gr_skill_name )
  printf '%s' "$nm" | grep -qE '^[a-z0-9][a-z0-9._-]*$' \
    && ok "gr_skill_name fallback valid+nonempty for basename '$b' → '$nm'" \
    || no "gr_skill_name fallback invalid/empty for '$b' → '$nm'"
  rm -rf "$(dirname "$HB")"
done
# v1.10.1 closure (codex adversarial [high]): gr_skill_name MUST resolve the
# STANDARD GitX layout (skills/<name>/SKILL.md) + honor SKILL_NAME env, exactly
# like the release pipeline's detect-project.sh _detect_skill_name — else a
# standard-layout dependent skill (no root SKILL.md) gets the WRONG primary
# command in command-surface while --check deterministically passes (§0g blind).
WSL="$(mktemp -d)"; mkdir -p "$WSL/skills/demo-skill"
printf -- '---\nname: ignored-frontmatter\n---\n' > "$WSL/skills/demo-skill/SKILL.md"
( cd "$WSL" && GITX_README_LIB=1 . "$SH" \
  && [ "$(gr_skill_name)" = "demo-skill" ] \
  && gr_command_surface | grep -qF '/demo-skill` — the skill' ) \
  && ok "gr_skill_name: standard layout skills/<name>/ → /demo-skill (codex [high] fixed)" \
  || no "gr_skill_name standard-layout regression (root-only resolver)"
rm -rf "$WSL"
WEN="$(mktemp -d)"; mkdir -p "$WEN/skills/otherdir"
printf -- '---\nname: x\n---\n' > "$WEN/skills/otherdir/SKILL.md"
printf -- '---\nname: rootname\n---\n' > "$WEN/SKILL.md"
( cd "$WEN" && export SKILL_NAME=envskill && GITX_README_LIB=1 . "$SH" \
  && [ "$(gr_skill_name)" = "envskill" ] ) \
  && ok "gr_skill_name: SKILL_NAME env wins over skills/ + root SKILL.md (pipeline precedence)" \
  || no "gr_skill_name ignores SKILL_NAME env"
rm -rf "$WEN"
WPX="$(mktemp -d)"; mkdir -p "$WPX/skills/realskill" "$WPX/skills/foo-workspace"
printf -- '---\nname: a\n---\n' > "$WPX/skills/realskill/SKILL.md"
printf -- '---\nname: b\n---\n' > "$WPX/skills/foo-workspace/SKILL.md"
( cd "$WPX" && GITX_README_LIB=1 . "$SH" && [ "$(gr_skill_name)" = "realskill" ] ) \
  && ok "gr_skill_name: skills/ exclude (*-workspace) honored → realskill" \
  || no "gr_skill_name exclude-pattern not honored"
rm -rf "$WPX"
WAMB="$(mktemp -d)"; mkdir -p "$WAMB/skills/aa" "$WAMB/skills/bb"
printf -- '---\nname: a\n---\n' > "$WAMB/skills/aa/SKILL.md"
printf -- '---\nname: b\n---\n' > "$WAMB/skills/bb/SKILL.md"
amb=$( cd "$WAMB" && GITX_README_LIB=1 . "$SH" && gr_skill_name )
( printf '%s' "$amb" | grep -qE '^[a-z0-9][a-z0-9._-]*$' \
  && [ ! -f "$WAMB/GitX_Upgrade_Guideline.md" ] ) \
  && ok "gr_skill_name: ambiguous >1 skills/ → safe deterministic fallback, NO guideline written (generate-safe) → '$amb'" \
  || no "gr_skill_name ambiguous-skills unsafe (invalid name or wrote GitX_Upgrade_Guideline.md)"
rm -rf "$WAMB"
# v1.10.1 closure round-2 (codex adversarial [medium]): gr_command_surface
# must enumerate the STANDARD-LAYOUT commands dir (skills/<skill>/commands/,
# the release.sh $SKILL_SRC_DIR/commands flatten source) when there is no
# root commands/ — else a standard-layout dependent skill publishes a
# command surface that omits its actual installed shims (--check blind).
WCS="$(mktemp -d)"; mkdir -p "$WCS/skills/demo-skill/commands"
printf -- '---\nname: ignored\n---\n' > "$WCS/skills/demo-skill/SKILL.md"
: > "$WCS/skills/demo-skill/commands/demo-skill-init.md"
: > "$WCS/skills/demo-skill/commands/demo-skill-sop.md"
( cd "$WCS" && GITX_README_LIB=1 . "$SH" \
  && gr_command_surface | grep -qF '/demo-skill` — the skill' \
  && gr_command_surface | grep -qF '/demo-skill-init' \
  && gr_command_surface | grep -qF '/demo-skill-sop' ) \
  && ok "gr_command_surface: standard-layout skills/<skill>/commands/ shims listed (codex r2 [medium] fixed)" \
  || no "gr_command_surface omits standard-layout command shims"
rm -rf "$WCS"
# Task 2: a scaffold (--init from the dual-tree template) MUST inherit BOTH
# own-line managed regions (whats-new + command-surface), and --check must
# pass on it — so every dependent skill (Decision 0019) gets the §0g guard.
# grep -qx below is INTENTIONALLY stricter than gr_validate_regions' whitespace-tolerant marker match — the §0g/scaffold guard wants zero marker rot; do not relax to a tolerant grep.
SC="$(mktemp -d)"
( cd "$SC" && bash "$SH" --init --force >/dev/null 2>&1 ) \
  && grep -qx '<!-- gitx:managed:whats-new -->' "$SC/README.md" \
  && grep -qx '<!-- gitx:managed:command-surface -->' "$SC/README.md" \
  && ( cd "$SC" && bash "$SH" --check >/dev/null 2>&1 ) \
  && ok "scaffold inherits own-line whats-new + command-surface, --check exit 0" \
  || no "scaffold missing whats-new/command-surface region or --check drift"
rm -rf "$SC"
rm -rf "$WX" "$WF" "$W7" "$WR"   # NEW-2: explicit cleanup (no EXIT-trap shadowing of the file's $W trap)

echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && echo PASS && exit 0
echo FAIL; exit 1
