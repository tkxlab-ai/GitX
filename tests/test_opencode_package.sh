#!/bin/bash
# test_opencode_package.sh — OpenCode channel: the repo root is also an npm
# package (@tkxlabai/gitx-opencode) whose V2 plugin registers the bundled
# gitx-release skill. Guards the manifest contract that the publish step relies
# on: fixed name, version == VERSION, a `files` whitelist (nothing private can
# ride along), and NO `scripts` field — an install must never run our code.
#
# exit: 0=all pass, 1=any fail
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
skip() { echo "  ➖ SKIP $1"; SKIP=$((SKIP+1)); }

echo "══ test_opencode_package.sh ══"

PJ="$ROOT/package.json"
IDX="$ROOT/opencode/index.ts"
VER="$(tr -d '[:space:]' < "$ROOT/VERSION")"
VER="${VER#v}"

# 1: package.json exists + valid JSON
if [ -f "$PJ" ] && jq -e . "$PJ" >/dev/null 2>&1; then
    ok "package.json exists + valid JSON"
else
    fail "package.json missing or invalid JSON"
fi

# 2: manifest fields (each a separate assertion so a failure names the field)
jcheck() { # $1=label $2=jq boolean expression
    if [ -f "$PJ" ] && [ "$(jq -r "$2" "$PJ" 2>/dev/null)" = "true" ]; then
        ok "$1"
    else
        fail "$1"
    fi
}
jcheck "name = @tkxlabai/gitx-opencode" '.name == "@tkxlabai/gitx-opencode"'
jcheck "version = VERSION without v ($VER)" ".version == \"$VER\""
jcheck "type = module" '.type == "module"'
jcheck "exports . and ./server -> ./opencode/index.ts" \
    '.exports["."] == "./opencode/index.ts" and .exports["./server"] == "./opencode/index.ts"'
jcheck "files = [opencode, skills/gitx-release]" '.files == ["opencode","skills/gitx-release"]'
jcheck "peerDependencies has @opencode/plugin" '.peerDependencies["@opencode/plugin"] != null'
jcheck "publishConfig.access = public" '.publishConfig.access == "public"'
jcheck "publishConfig.registry = npmjs" '.publishConfig.registry == "https://registry.npmjs.org/"'
jcheck "repository.url points at tkxlab-ai/GitX" '(.repository.url // "") | contains("tkxlab-ai/GitX")'
jcheck "no scripts field (no lifecycle scripts on install)" 'has("scripts") == false'

# 3: plugin entry wires the bundled skill via the V2 API
if [ -f "$IDX" ]; then
    for needle in '../skills/gitx-release/SKILL.md' 'ctx.skill.transform' 'Plugin.define'; do
        if grep -qF "$needle" "$IDX"; then ok "index.ts contains $needle"; else fail "index.ts missing $needle"; fi
    done
else
    fail "opencode/index.ts missing"
fi

# 3b: run the frontmatter parser itself (not just grep it) on the real
# SKILL.md and on edge-case fixtures. Needs a node that can strip TS types.
FM="$ROOT/opencode/frontmatter.ts"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cat > "$T/drive.mjs" <<'JS'
const { load } = await import(process.argv[2])
const { readFileSync } = await import("node:fs")
try { console.log(JSON.stringify(load(readFileSync(process.argv[3], "utf8")))) }
catch (e) { console.log(JSON.stringify({ error: e.message })) }
JS
fmrun() { node --experimental-strip-types --no-warnings "$T/drive.mjs" "$FM" "$1" 2>/dev/null || true; }
if ! command -v node >/dev/null 2>&1; then
    skip "frontmatter parser runtime checks (node not on PATH)"
elif [ ! -f "$FM" ]; then
    fail "opencode/frontmatter.ts missing"
elif [ -z "$(fmrun "$ROOT/skills/gitx-release/SKILL.md")" ]; then
    skip "frontmatter parser runtime checks (node cannot strip TS types)"
else
    fmcheck() { # $1=label $2=fixture $3=jq boolean expression
        out="$(fmrun "$2")"
        if [ "$(jq -r "$3" <<<"$out" 2>/dev/null)" = "true" ]; then ok "$1"; else fail "$1 (got: $out)"; fi
    }
    real_desc="$(grep -m1 '^description: ' "$ROOT/skills/gitx-release/SKILL.md" | sed 's/^description: //')"
    fmcheck "real SKILL.md: name gitx-release, full description, body after frontmatter" \
        "$ROOT/skills/gitx-release/SKILL.md" \
        "(.name == \"gitx-release\") and (.description == $(jq -Rn --arg d "$real_desc" '$d')) and (.body | startswith(\"# GitX\")) and .autoinvoke == true"
    printf 'no frontmatter here\n' > "$T/nofm.md"
    fmcheck "missing frontmatter -> clear error" "$T/nofm.md" '.error | contains("name")'
    printf -- '---\ndescription: d\n---\nbody\n' > "$T/noname.md"
    fmcheck "missing name -> clear error" "$T/noname.md" '.error | contains("\"name\"")'
    printf -- '---\nname: x\ndescription:\n---\nbody\n' > "$T/nodesc.md"
    fmcheck "empty description -> clear error" "$T/nodesc.md" '.error | contains("\"description\"")'
    printf -- '---\nname: x\ndescription: a: b — c\n---\nbody\n' > "$T/colon.md"
    fmcheck "description with ':' and '—' kept whole" "$T/colon.md" '.description == "a: b — c"'
    printf -- '---\nname: "x"\ndescription: '"'"'q: d'"'"'\ndisable-model-invocation: true\n---\nbody\n' > "$T/quoted.md"
    fmcheck "quoted values unquoted; disable-model-invocation -> autoinvoke false" "$T/quoted.md" \
        '.name == "x" and .description == "q: d" and .autoinvoke == false'
    printf -- '---\r\nname: x\r\ndescription: d\r\n---\r\nline1\r\nline2\r\n' > "$T/crlf.md"
    fmcheck "CRLF frontmatter parsed, no stray CR" "$T/crlf.md" \
        '.name == "x" and .description == "d" and .body == "line1\nline2"'
fi

# 4: no private markers. The regex lives only in the local (gitignored) SOP —
# copying it here would put the very strings it guards into a public file.
SOP="$ROOT/.gitx/GITHUB_RELEASE_SOP.md"
PRIV_RE=""
if [ -f "$SOP" ]; then
    PRIV_RE="$(grep -m1 '^PRIV_RE=' "$SOP" | sed -e "s/^PRIV_RE='//" -e "s/'$//" || true)"
fi
if [ -z "$PRIV_RE" ]; then
    skip "private-marker scan (no local SOP PRIV_RE)"
elif [ ! -f "$PJ" ] || [ ! -f "$IDX" ] || [ ! -f "$FM" ]; then
    fail "private-marker scan: package.json or opencode/*.ts missing"
else
    # grep: 0 = match, 1 = clean, anything else = the scan itself broke
    # (e.g. a mangled regex) and must not read as clean.
    rc=0; grep -qE "$PRIV_RE" "$PJ" "$IDX" "$FM" 2>/dev/null || rc=$?
    case "$rc" in
        0) fail "package.json / opencode/*.ts contain a private marker" ;;
        1) ok "package.json / opencode/*.ts free of private markers" ;;
        *) fail "private-marker scan broken (grep exit $rc; check PRIV_RE extraction)" ;;
    esac
fi

# 5: the packed file list stays inside the whitelist
if command -v npm >/dev/null 2>&1; then
    packjson="$(cd "$ROOT" && npm pack --ignore-scripts --dry-run --json 2>/dev/null || true)"
    paths="$(jq -r '.[0].files[].path' <<<"$packjson" 2>/dev/null || true)"
    if [ -z "$paths" ]; then
        fail "npm pack --dry-run produced no file list"
    else
        bad=""
        while IFS= read -r p; do
            case "$p" in
                opencode/*|skills/gitx-release/*|package.json|README.md|LICENSE) ;;
                *) bad="$bad $p" ;;
            esac
        done <<<"$paths"
        if [ -z "$bad" ]; then ok "npm pack file list within whitelist"; else fail "npm pack ships non-whitelisted:$bad"; fi
        if grep -qx 'skills/gitx-release/SKILL.md' <<<"$paths"; then
            ok "npm pack includes skills/gitx-release/SKILL.md"
        else
            fail "npm pack misses skills/gitx-release/SKILL.md"
        fi
    fi
else
    skip "npm pack checks (npm not on PATH)"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed / ➖$SKIP skipped"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
