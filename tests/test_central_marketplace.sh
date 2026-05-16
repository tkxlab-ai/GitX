#!/bin/bash
# test_central_marketplace.sh — central tkxlab-ai/marketplace manifest template.
#
# The central repo lets users run ONE:
#   /plugin marketplace add tkxlab-ai/marketplace
# then /plugin install <skill>@tkx-skills for any TKX skill. Each plugin's
# source is a github object pointing at that skill's OWN repo.
# This validates the checked-in template the controller renders + pushes.
#
# exit: 0=all pass, 1=any fail
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_central_marketplace.sh ══"

TPL="$ROOT/references/marketplace/marketplace.json.template"

# 1: template exists + valid JSON
if [ -f "$TPL" ] && python3 -c "import json;json.load(open('$TPL'))" 2>/dev/null; then
    ok "marketplace.json.template exists + valid JSON"
else
    fail "marketplace.json.template missing or invalid JSON"
    echo "Results: ✅$PASS passed / ❌$FAIL failed"
    echo "FAIL"; exit 1
fi

# 2: name kebab-case == tkx-skills
if python3 -c "
import json,re
m=json.load(open('$TPL'))
n=m['name']
assert re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', n), 'name not kebab: '+n
assert n=='tkx-skills', 'name != tkx-skills: '+n
" 2>/dev/null; then
    ok "name kebab-case == tkx-skills"
else
    fail "name not kebab-case / != tkx-skills"
fi

# 3: every plugins[] entry has kebab name + github-object source w/ valid repo
if python3 -c "
import json,re
m=json.load(open('$TPL'))
ps=m['plugins']
assert isinstance(ps,list) and ps, 'plugins not a non-empty array'
for p in ps:
    assert re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', p['name']), 'plugin name not kebab: '+p['name']
    s=p['source']
    assert isinstance(s,dict), 'source not object: '+repr(s)
    assert s.get('source')=='github', 'source.source != github: '+repr(s)
    assert re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', s.get('repo','')), 'bad repo: '+repr(s)
" 2>/dev/null; then
    ok "every plugins[] entry kebab name + github-object source + valid repo"
else
    fail "a plugins[] entry has bad name/source/repo"
fi

# 4: gitx plugin present + source.repo == tkxlab-ai/GitX
if python3 -c "
import json
m=json.load(open('$TPL'))
g=[p for p in m['plugins'] if p['name']=='gitx']
assert g, 'gitx plugin missing'
assert g[0]['source']['repo']=='tkxlab-ai/GitX', g[0]['source']
" 2>/dev/null; then
    ok "gitx plugin present + source.repo == tkxlab-ai/GitX"
else
    fail "gitx plugin missing or wrong source.repo"
fi

# 4b: gitx plugin version == repo VERSION with leading 'v' stripped
# (doc-rot guard: a future VERSION bump that forgets the template FAILS here)
REPO_VER="$(sed -n '1s/^v//p' "$ROOT/VERSION")"
if python3 -c "
import json
m=json.load(open('$TPL'))
g=[p for p in m['plugins'] if p['name']=='gitx'][0]
assert g['version']=='$REPO_VER', 'gitx version '+g['version']+' != repo VERSION $REPO_VER'
" 2>/dev/null; then
    ok "gitx plugin version == repo VERSION ($REPO_VER, v-stripped)"
else
    fail "gitx plugin version != repo VERSION ($REPO_VER) — template drift"
fi

# 5: owner has name, NO owner.email (trips this repo's secret scanner)
if python3 -c "
import json
m=json.load(open('$TPL'))
o=m['owner']
assert isinstance(o,dict) and o.get('name'), 'owner.name missing'
assert 'email' not in o, 'owner.email present (secret-scanner trip)'
" 2>/dev/null; then
    ok "owner has name + NO owner.email"
else
    fail "owner missing name or contains email"
fi

# 6: _pending entries (if present) are kebab names — advisory if absent
if python3 -c "
import json,re,sys
m=json.load(open('$TPL'))
pend=m.get('_pending')
if pend is None:
    sys.exit(2)
for e in pend:
    assert re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', e['name']), 'pending name not kebab: '+e['name']
" 2>/dev/null; then
    ok "_pending entries are kebab names"
else
    rc=$?
    if [ "$rc" = 2 ]; then
        ok "_pending absent (advisory — ok)"
    else
        fail "_pending contains non-kebab name"
    fi
fi

echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -gt 0 ] && { echo "FAIL"; exit 1; } || { echo "PASS"; exit 0; }
