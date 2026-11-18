#!/bin/bash
# test_wrapper_manifest_version_sync.sh — gitx-release.sh bumps every
# version-managed file (VERSION sidecars, .claude-plugin/{plugin,marketplace}.json,
# the npm-target package.json) and rolls all of them back on failure.
# Why: the wrapper used to bump only VERSION files, so Codex (reads plugin.json),
# the marketplace manifest and the npm package shipped the previous version.
# exit: 0 all pass, 1 any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$REAL/scripts/gitx-release.sh"

PASS=0
FAIL=0
ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== test_wrapper_manifest_version_sync.sh ==="

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# $1 = case dir. Project lives at $1/proj; the stub release.sh records the
# dirty allowance it was handed and fails (exit 7) when $1/fail exists.
mkfix() {
    local d="$1" p="$1/proj"
    mkdir -p "$d/scripts/lib" "$p/skills/demo-skill" "$p/Release" "$p/.claude-plugin" "$p/.gitx"
    cp "$WRAPPER" "$d/scripts/gitx-release.sh"
    cp "$REAL/scripts/lib/detect-project.sh" "$d/scripts/lib/detect-project.sh"
    cat > "$d/scripts/release.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "${_GITX_WRAPPER_DIRTY_OK:-}" > "$PROJECT_ROOT/../dirty_ok.txt"
[ -f "$PROJECT_ROOT/../fail" ] && { echo "stub release failure"; exit 7; }
mkdir -p "$PROJECT_ROOT/Release/proj-$1"
exit 0
EOF
    printf -- '---\nname: demo-skill\ndescription: Demo skill.\n---\n' > "$p/skills/demo-skill/SKILL.md"
    printf 'v0.0.1\n' > "$p/skills/demo-skill/VERSION"
    printf 'v0.0.1\n' > "$p/VERSION"
    printf '# Proj — Release History\n\n## v0.0.1 — 2026-01-01\n\nBaseline.\n\n---\n' > "$p/Release/CHANGELOG.md"
    printf '{\n  "name": "gitx",\n  "version": "0.0.1"\n}\n' > "$p/.claude-plugin/plugin.json"
    cat > "$p/.claude-plugin/marketplace.json" <<'EOF'
{
  "name": "tkxlab",
  "plugins": [
    { "name": "gitx", "source": "./", "version": "0.0.1" },
    { "name": "other", "source": "./other", "version": "0.1.0" }
  ],
  "version": "0.0.1"
}
EOF
    printf '{\n  "name": "@x/pkg",\n  "version": "0.0.1"\n}\n' > "$p/package.json"
    printf '@x/pkg\n' > "$p/.gitx/npm-target"
}

# Runs the wrapper; output → $1/out; returns its exit code. Extra args pass through.
runw() {
    local d="$1" rc; shift
    set +e
    env -u PROJECT_NAME -u SKILL_NAME -u _GITX_WRAPPER_DIRTY_OK PROJECT_ROOT="$d/proj" \
        bash "$d/scripts/gitx-release.sh" --version v9.9.9 --skip-marketplace --skip-gitea-release "$@" \
        > "$d/out" 2>&1
    rc=$?
    set -e
    return "$rc"
}

FILES="VERSION skills/demo-skill/VERSION Release/CHANGELOG.md .claude-plugin/plugin.json .claude-plugin/marketplace.json package.json"
# Snapshot "path cksum" lines for every managed file (absent → "absent").
snap() {
    local p f
    for f in $FILES; do
        p="$1/proj/$f"
        if [ -e "$p" ]; then printf '%s %s\n' "$f" "$(cksum < "$p")"; else printf '%s absent\n' "$f"; fi
    done
}
jv() { jq -r "$2" "$1" 2>/dev/null || echo "jq-error"; }

# ── a + b: plugin.json / marketplace.json / matching package.json bumped ────
D="$TMPROOT/ab"; mkfix "$D"; P="$D/proj"
chmod 644 "$P/.claude-plugin/plugin.json"
rc=0; runw "$D" || rc=$?
if [ "$rc" -eq 0 ]; then ok "a: wrapper exits 0"; else fail "a: wrapper exited $rc"; tail -20 "$D/out"; fi
# mktemp creates 0600; the rewrite must not narrow the shipped file's mode.
mode=$(ls -l "$P/.claude-plugin/plugin.json" | cut -c1-10)
[ "$mode" = "-rw-r--r--" ] && ok "a: plugin.json keeps mode 644 after the rewrite" || fail "a: plugin.json mode now $mode"
[ "$(jv "$P/.claude-plugin/plugin.json" .version)" = "9.9.9" ] \
    && ok "a: plugin.json version = 9.9.9" || fail "a: plugin.json version = $(jv "$P/.claude-plugin/plugin.json" .version)"
M="$P/.claude-plugin/marketplace.json"
if [ "$(jv "$M" .version)" = "9.9.9" ] \
    && [ "$(jv "$M" '.plugins[]|select(.name=="gitx")|.version')" = "9.9.9" ] \
    && [ "$(jv "$M" '.plugins[]|select(.name=="other")|.version')" = "0.1.0" ]; then
    ok "a: marketplace.json top-level + gitx entry = 9.9.9, other entry untouched"
else
    fail "a: marketplace.json wrong: $(jq -c '[.version, [.plugins[].version]]' "$M" 2>&1)"
fi
[ "$(jv "$P/package.json" .version)" = "9.9.9" ] \
    && ok "b: package.json named like .gitx/npm-target → 9.9.9" \
    || fail "b: package.json version = $(jv "$P/package.json" .version)"
DOK=$(cat "$D/dirty_ok.txt" 2>/dev/null || true)
missing=""
for f in VERSION skills/demo-skill/VERSION .claude-plugin/plugin.json .claude-plugin/marketplace.json package.json Release/CHANGELOG.md; do
    grep -qxF "$f" <<<"$DOK" || missing="$missing $f"
done
[ -z "$missing" ] && ok "b: dirty allowance lists every managed file + CHANGELOG" \
    || fail "b: dirty allowance missing:$missing"

# ── c: package.json not managed (no npm-target / name mismatch) ─────────────
eval "$(awk '/^_managed_json_error\(\) *\{/,/^\}/' "$WRAPPER")"
eval "$(awk '/^version_managed_files\(\) *\{/,/^\}/' "$WRAPPER")"
for variant in no-target mismatch; do
    D="$TMPROOT/c-$variant"; mkfix "$D"; P="$D/proj"
    if [ "$variant" = "no-target" ]; then rm "$P/.gitx/npm-target"; else printf '@x/other\n' > "$P/.gitx/npm-target"; fi
    sum0=$(cksum < "$P/package.json")
    rc=0; runw "$D" || rc=$?
    DOK=$(cat "$D/dirty_ok.txt" 2>/dev/null || true)
    if [ "$rc" -eq 0 ] && [ "$(cksum < "$P/package.json")" = "$sum0" ] && ! grep -qxF package.json <<<"$DOK"; then
        ok "c($variant): package.json bytes unchanged and absent from dirty allowance"
    else
        fail "c($variant): rc=$rc or package.json touched / allowed"
    fi
    LIST=""
    if type version_managed_files >/dev/null 2>&1; then
        LIST=$(PROJECT_ROOT="$P" SKILL_NAME=demo-skill version_managed_files 2>/dev/null || true)
    fi
    if grep -qxF .claude-plugin/plugin.json <<<"$LIST" && ! grep -qxF package.json <<<"$LIST"; then
        ok "c($variant): version_managed_files omits package.json"
    else
        fail "c($variant): version_managed_files output: $(tr '\n' ' ' <<<"$LIST")"
    fi
done

# ── d: an unparsable managed JSON → controlled error before any write ───────
for bad in .claude-plugin/plugin.json .claude-plugin/marketplace.json package.json; do
    D="$TMPROOT/d-$(basename "$bad")"; mkfix "$D"; P="$D/proj"
    printf '{ "name": \n' > "$P/$bad"
    s0=$(snap "$D")
    rc=0; runw "$D" || rc=$?
    if [ "$rc" -ne 0 ] && [ "$(snap "$D")" = "$s0" ] && [ ! -e "$D/dirty_ok.txt" ] && grep -qF "$bad" "$D/out"; then
        ok "d: broken $bad → exit $rc naming it, all managed files byte-identical, release.sh never ran"
    else
        fail "d: broken $bad → rc=$rc, bytes $([ "$(snap "$D")" = "$s0" ] && echo same || echo CHANGED)"
        tail -10 "$D/out"
    fi
done

# ── e: release fails after the writes → every file restored; absent stays absent
D="$TMPROOT/e"; mkfix "$D"; P="$D/proj"; touch "$D/fail"
rm "$P/VERSION" "$P/Release/CHANGELOG.md"
s0=$(snap "$D")
rc=0; runw "$D" || rc=$?
if [ "$rc" -eq 7 ] && [ -e "$D/dirty_ok.txt" ] && [ "$(snap "$D")" = "$s0" ]; then
    ok "e: failed release rolls back all managed files; root VERSION + CHANGELOG still absent"
else
    fail "e: rc=$rc; after rollback: $(snap "$D" | tr '\n' ';')"
fi

# ── f: .claude-plugin is a symlink outside the project → refused before write
D="$TMPROOT/f"; mkfix "$D"; P="$D/proj"
mv "$P/.claude-plugin" "$D/outside"; ln -s "$D/outside" "$P/.claude-plugin"
touch -t 200001010000 "$D/outside/plugin.json"
sum0=$(cksum < "$D/outside/plugin.json"); s0=$(snap "$D")
mt0=$(stat -c %Y "$D/outside/plugin.json" 2>/dev/null || stat -f %m "$D/outside/plugin.json")
rc=0; runw "$D" || rc=$?
mt1=$(stat -c %Y "$D/outside/plugin.json" 2>/dev/null || stat -f %m "$D/outside/plugin.json")
if [ "$rc" -eq 5 ] && grep -q symlink "$D/out" && [ "$(cksum < "$D/outside/plugin.json")" = "$sum0" ] \
    && [ "$mt0" = "$mt1" ] && [ "$(snap "$D")" = "$s0" ]; then
    ok "f: symlinked .claude-plugin → exit 5, outside target bytes + mtime unchanged"
else
    fail "f: rc=$rc (expected 5 + no write through the link)"
fi

# ── h: CHANGELOG got a new entry, then release fails → original bytes back ──
D="$TMPROOT/h"; mkfix "$D"; P="$D/proj"; touch "$D/fail"
sum0=$(cksum < "$P/Release/CHANGELOG.md")
rc=0; runw "$D" || rc=$?
if [ "$rc" -eq 7 ] && [ "$(cksum < "$P/Release/CHANGELOG.md")" = "$sum0" ]; then
    ok "h: CHANGELOG with an inserted v9.9.9 entry is restored byte-for-byte"
else
    fail "h: rc=$rc; CHANGELOG has v9.9.9: $(grep -c '## v9.9.9' "$P/Release/CHANGELOG.md" || true)"
fi

# ── i: jq missing while a managed JSON exists → fail, never skip ────────────
D="$TMPROOT/i"; mkfix "$D"; NOJQ="$TMPROOT/nojq-bin"; mkdir -p "$NOJQ"
for dir in /usr/bin /bin; do
    for t in "$dir"/*; do
        n=$(basename "$t")
        [ "$n" = "jq" ] || [ -e "$NOJQ/$n" ] || ln -s "$t" "$NOJQ/$n"
    done
done
s0=$(snap "$D")
set +e
env -u PROJECT_NAME -u SKILL_NAME PATH="$NOJQ" PROJECT_ROOT="$D/proj" \
    "$NOJQ/bash" "$D/scripts/gitx-release.sh" --version v9.9.9 --skip-marketplace --skip-gitea-release > "$D/out" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ] && grep -q 'jq' "$D/out" && [ "$(snap "$D")" = "$s0" ] && [ ! -e "$D/dirty_ok.txt" ]; then
    ok "i: no jq + managed JSON present → exit $rc before any write"
else
    fail "i: rc=$rc (expected a jq failure with no writes)"
fi

echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
