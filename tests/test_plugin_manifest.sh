#!/bin/bash
# test_plugin_manifest.sh — v1.8.0 Claude Code plugin distribution.
#
# Makes the repo installable via:
#   /plugin marketplace add tkxlab-ai/GitX
#   /plugin install gitx-release@GitX
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

# 2: plugin name == skill dir == gitx-release (namespace contract)
if [ -f "$PJ" ]; then
    [ "$(jget "$PJ" name)" = "gitx-release" ] \
        && ok "plugin.json name = gitx-release (matches skills/gitx-release/)" \
        || fail "plugin.json name != gitx-release (got '$(jget "$PJ" name)')"
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
assert any(p.get('name')=='gitx-release' and p.get('source') in ('.','./') for p in ps), ps
" 2>/dev/null; then
        ok "marketplace.json lists gitx-release with source '.'"
    else
        fail "marketplace.json does not list gitx-release@source='.'"
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
   && grep -q 'gitx-release:gitx-sop' "$ROOT/README.md" \
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
CURTB="$ROOT/Release/git_release_skill-v$(tr -d 'v\n' < "$ROOT/VERSION")/git_release_skill-v$(tr -d 'v\n' < "$ROOT/VERSION")-source.tar.gz"
if [ -f "$CURTB" ]; then
    tar tzf "$CURTB" 2>/dev/null | grep -q '/.claude-plugin/marketplace.json' \
        && ok "current-version tarball ships .claude-plugin/marketplace.json" \
        || fail "current-version tarball missing .claude-plugin/"
fi

echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -gt 0 ] && { echo "FAIL"; exit 1; } || { echo "PASS"; exit 0; }
