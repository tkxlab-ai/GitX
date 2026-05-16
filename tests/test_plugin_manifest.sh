#!/bin/bash
# test_plugin_manifest.sh — v1.8.0 Claude Code plugin distribution.
#
# Makes the repo installable via:
#   /plugin marketplace add tkxlab-ai/marketplace
#   /plugin install gitx@tkx-skills
# Dual-path: plugin manifests are ADDED; install.sh stays (flat /gitx-sop).
#
# exit: 0=all pass, 1=any fail
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
jget() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],''))" "$1" "$2" 2>/dev/null; }

echo "══ test_plugin_manifest.sh ══"

PJ="$ROOT/.claude-plugin/plugin.json"
MJ="$ROOT/.claude-plugin/marketplace.json"

# 1: plugin.json exists at the official path + valid JSON
if [ -f "$PJ" ] && python3 -c "import json;json.load(open('$PJ'))" 2>/dev/null; then
    ok ".claude-plugin/plugin.json exists + valid JSON"
else
    fail ".claude-plugin/plugin.json missing or invalid JSON"
fi

# 2: plugin name = gitx (v1.9.0 — namespace → /gitx:release, /gitx:sop ...).
# This is the PLUGIN layer only; SKILL.md name / canonical install /
# dual-source stay `gitx-release` (test_rebrand contract untouched).
if [ -f "$PJ" ]; then
    [ "$(jget "$PJ" name)" = "gitx" ] \
        && ok "plugin.json name = gitx (commands namespace /gitx:*)" \
        || fail "plugin.json name != gitx (got '$(jget "$PJ" name)')"
fi

# 2b: plugin.json declares a custom commands path with short-named shims
# (release/sop/init/audit/scan) so the plugin exposes /gitx:release etc.
# (custom path replaces the default commands/ scan — official rule).
if [ -f "$PJ" ]; then
    cdir="$ROOT/gitx-plugin-commands"
    decl="$(python3 -c "import json;d=json.load(open('$PJ'));print(' '.join(d.get('commands',[])) if isinstance(d.get('commands'),list) else d.get('commands',''))" 2>/dev/null)"
    case "$decl" in *gitx-plugin-commands*) cdok=1 ;; *) cdok=0 ;; esac
    miss=""
    for c in release sop init audit scan; do
        [ -f "$cdir/$c.md" ] || miss="$miss $c"
    done
    if [ "$cdok" = 1 ] && [ -z "$miss" ]; then
        ok "plugin.json commands→gitx-plugin-commands/ + release/sop/init/audit/scan present"
    else
        fail "custom commands path not wired (decl=$cdok missing:$miss)"
    fi
fi

# 3: plugin.json version tracks VERSION sidecar (no doc-rot)
if [ -f "$PJ" ]; then
    want="$(tr -d 'v\n' < "$ROOT/VERSION")"
    got="$(jget "$PJ" version)"
    [ "$got" = "$want" ] && ok "plugin.json version $got == VERSION" \
        || fail "plugin.json version '$got' != VERSION '$want' (doc-rot)"
fi

# 4: marketplace.json exists + valid + lists the plugin pointing at repo root
if [ -f "$MJ" ] && python3 -c "import json;json.load(open('$MJ'))" 2>/dev/null; then
    ok ".claude-plugin/marketplace.json exists + valid JSON"
    if python3 -c "
import json,sys
m=json.load(open('$MJ'))
ps=m.get('plugins',[])
assert any(p.get('name')=='gitx' and p.get('source') in ('.','./') for p in ps), ps
" 2>/dev/null; then
        ok "marketplace.json lists gitx with source '.'"
    else
        fail "marketplace.json does not list gitx@source='.'"
    fi
else
    fail ".claude-plugin/marketplace.json missing or invalid JSON"
fi

# 4b: Claude's own validator rules (codex stop-gate v1.8.1): marketplace +
# plugin names MUST be kebab-case (lowercase/digits/hyphens — uppercase or
# spaces are rejected by Claude.ai marketplace sync), and a relative
# plugin source MUST start with "./".
if [ -f "$MJ" ] && python3 -c "
import json,re
m=json.load(open('$MJ'))
assert re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', m['name']), 'mp name not kebab: '+m['name']
for p in m['plugins']:
    assert re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', p['name']), 'plugin name not kebab: '+p['name']
    s=p['source']
    assert isinstance(s,str) and s.startswith('./'), 'source must start ./ : '+repr(s)
" 2>/dev/null; then
    ok "names kebab-case + source starts ./ (Claude validator clean)"
else
    fail "marketplace.json fails Claude validator (kebab name / source ./)"
fi

# 5: plugin-discoverable component dirs at repo root (NOT under .claude-plugin/)
for d in skills commands agents; do
    [ -d "$ROOT/$d" ] && ok "plugin root has $d/" || fail "plugin root missing $d/"
done
[ ! -d "$ROOT/.claude-plugin/skills" ] \
    && ok ".claude-plugin/ holds only manifests (no nested component dirs)" \
    || fail "component dir wrongly nested under .claude-plugin/"

# 6: README documents BOTH install paths (plugin + install.sh) + namespacing
if grep -q '/plugin marketplace add' "$ROOT/README.md" \
   && grep -q 'gitx:sop' "$ROOT/README.md" \
   && grep -q -- './install.sh' "$ROOT/README.md"; then
    ok "README documents plugin install + namespaced cmd + install.sh"
else
    fail "README missing plugin-install / namespaced-command / install.sh docs"
fi

# 7: release.sh staging must NOT exclude .claude-plugin/ — static invariant
# (asserting a *built* tarball here would be a chicken-and-egg: run_tests
# runs BEFORE the tarball is built, cf. Gotcha #7). Post-build inclusion is
# enforced by release-audit §5; here we guarantee the staging recipe keeps
# it. Bonus: if a current-VERSION tarball already exists, verify it too.
if grep -qE "exclude=.*['\"]?/?\.claude-plugin" "$ROOT/scripts/release.sh"; then
    fail "release.sh staging excludes .claude-plugin/ (public mirror not installable)"
else
    ok "release.sh staging keeps .claude-plugin/ (ships in source tarball)"
fi
if grep -qE "exclude=.*['\"]?/?gitx-plugin-commands" "$ROOT/scripts/release.sh"; then
    fail "release.sh staging excludes gitx-plugin-commands/ (/gitx:* shims not shipped)"
else
    ok "release.sh staging keeps gitx-plugin-commands/ (ships in source tarball)"
fi
CURTB="$ROOT/Release/git_release_skill-v$(tr -d 'v\n' < "$ROOT/VERSION")/git_release_skill-v$(tr -d 'v\n' < "$ROOT/VERSION")-source.tar.gz"
if [ -f "$CURTB" ]; then
    tar tzf "$CURTB" 2>/dev/null | grep -q '/.claude-plugin/marketplace.json' \
        && ok "current-version tarball ships .claude-plugin/marketplace.json" \
        || fail "current-version tarball missing .claude-plugin/"
fi

# 8: internal design docs (docs/superpowers/{plans,specs}) must NOT ship to
# the public mirror — they reference internal/sibling project naming and are
# internal records (same class as HANDOFF). Static staging invariant.
if grep -qE "exclude=.*docs/superpowers" "$ROOT/scripts/release.sh"; then
    ok "release.sh staging excludes docs/superpowers (internal design docs not public)"
else
    fail "release.sh does NOT exclude docs/superpowers (internal docs leak to public mirror)"
fi

# 9: public docs must NOT reference internal-only files excluded from the
# public mirror (HANDOFF*, REVIEW.md, docs/superpowers, .memory,
# GitHub_STANDARD_ANALYSIS) — such links 404 on GitHub. Code-enforced.
_pub_rot=0
for _d in README.md README_CN.md RELEASE_NOTES.md; do
    [ -f "$ROOT/$_d" ] || continue
    if grep -qE 'HANDOFF(\.md|\.archive)|REVIEW\.md|docs/superpowers|(^|[^.a-z])\.memory|GitHub_STANDARD_ANALYSIS' "$ROOT/$_d"; then
        fail "$_d references an internal-only file (broken on public mirror): $(grep -nE 'HANDOFF|REVIEW\.md|docs/superpowers|GitHub_STANDARD_ANALYSIS' "$ROOT/$_d" | head -1)"
        _pub_rot=1
    fi
done
[ "$_pub_rot" -eq 0 ] && ok "public docs reference no internal-only excluded files"

# 10: the legacy per-repo marketplace-add form must not ship in any
# manifest / public doc. The needle is assembled with a regex bracket
# class so THIS file never contains the banned literal verbatim — hence
# no self-exemption is needed and the guard protects every shipped file,
# including itself. CHANGELOG history + generated Release/ artifacts are
# the project record and are exempt. Central form: tkxlab-ai/marketplace.
_stale=0
_needle='marketplace add tkxlab-ai/Git[X]'   # matches the real literal; not itself the literal
while IFS= read -r _f; do
    case "$_f" in */Release/*|*/CHANGELOG.md|*/.git/*) continue ;; esac
    _stale=1; fail "stale per-repo marketplace add in $_f"
done < <(grep -rlE "$_needle" \
            --include='*.md' --include='*.json' --include='*.sh' --include='*.txt' \
            "$ROOT" 2>/dev/null | grep -vE '/Release/|/\.git/|CHANGELOG\.md')
[ "$_stale" -eq 0 ] && ok "no stale per-repo marketplace-add command ships (central only)"

echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -gt 0 ] && { echo "FAIL"; exit 1; } || { echo "PASS"; exit 0; }
