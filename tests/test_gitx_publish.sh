#!/usr/bin/env bash
# tests/test_gitx_publish.sh — gitx-publish.sh: the one human-gated command that
# makes an approved release public (GitHub Release → central marketplace → npm).
#
# Zero network: GH_BIN / NPM_BIN / MARKETPLACE_BIN point at recording mocks whose
# behaviour is driven by MOCK_* env vars and a per-case state dir, so reruns see
# what the previous run "published". `npm pack` is the one call delegated to the
# real npm (local-only, --ignore-scripts) so the pack whitelist / prepack cases
# test real packing; those cases are skipped when npm is not installed.
#
# Why these cases: npm versions are irreversible and the same version is often
# re-cut, so every check must finish before the first remote write, and every
# step must be resumable by rerunning the same command.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PUB="$ROOT/scripts/gitx-publish.sh"

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }
skip() { SKIP=$((SKIP+1)); echo "  ➖ $1"; }

VER='v1.2.3'
NUM='1.2.3'
PKG='@tkxlabai/gitx-opencode'
SKILL='demo-skill'

echo "══ test_gitx_publish.sh ══"

unset PROJECT_NAME SKILL_NAME PROJECT_ROOT MOCK_NPM_WHOAMI MOCK_NPM_VIEW MOCK_NPM_PUBLISH MOCK_MKT MOCK_MKT_DRY MOCK_GH_LATEST CASE_MKT
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd)"
REAL_NPM=$(command -v npm || true)
mkdir -p "$T/bin" "$T/home"
export HOME="$T/home" NPM_CONFIG_UPDATE_NOTIFIER=false NPM_CONFIG_FUND=false NPM_CONFIG_AUDIT=false

# ---- recording mocks (state in $MOCK_STATE, call log in $MOCK_LOG) ----
cat > "$T/bin/gh" <<'MOCK'
#!/bin/sh
printf 'gh %s\n' "$*" >> "$MOCK_LOG"
S="$MOCK_STATE"
case "$1 $2" in
"release view")
    [ -f "$S/gh_release" ] || { echo "release not found" >&2; exit 1; }
    d=true; [ "$(cat "$S/gh_release")" = public ] && d=false
    a=""; for f in "$S/remote_assets"/*; do
        [ -n "$a" ] && a="$a,"; a="$a{\"name\":\"$(basename "$f")\"}"; done
    printf '{"isDraft":%s,"assets":[%s]}\n' "$d" "$a" ;;
"release download")
    dir=""; prev=""; for x in "$@"; do [ "$prev" = --dir ] && dir="$x"; prev="$x"; done
    mkdir -p "$dir" && cp "$S/remote_assets"/* "$dir"/ ;;
"release edit")
    # MOCK_GH_LATEST=fail: GitHub keeps Latest where it was and a bare
    # `--latest` re-assert fails — the Release itself still goes public.
    case "$*" in *--draft=false*) echo public > "$S/gh_release" ;; esac
    if [ "${MOCK_GH_LATEST:-ok}" = fail ]; then
        case "$*" in *--draft=false*) ;; *) echo "HTTP 502" >&2; exit 1 ;; esac
    else
        case "$*" in *--latest*) echo "$3" > "$S/gh_latest" ;; esac
    fi ;;
"release list")
    d=true; [ "$(cat "$S/gh_release" 2>/dev/null)" = public ] && d=false
    l=$(cat "$S/gh_latest")
    o=false; [ "$l" = v1.0.0 ] && o=true
    c=false; [ "$l" = "$MOCK_VER" ] && c=true
    printf '[{"tagName":"v1.0.0","isDraft":false,"isPrerelease":false,"isLatest":%s},' "$o"
    printf '{"tagName":"%s","isDraft":%s,"isPrerelease":false,"isLatest":%s}]\n' "$MOCK_VER" "$d" "$c" ;;
"api "*)
    case "$*" in
        *contents/VERSION*) cat "$S/main_version" ;;
        *tarball/*) cat "$S/tag.tar.gz" ;;
        *) exit 1 ;;
    esac ;;
*) exit 1 ;;
esac
MOCK
cat > "$T/bin/npm" <<'MOCK'
#!/bin/sh
printf 'npm %s\n' "$*" >> "$MOCK_LOG"
S="$MOCK_STATE"
case "$1" in
whoami)
    [ "${MOCK_NPM_WHOAMI:-ok}" = ok ] && { echo tester; exit 0; }
    echo "npm error code E401" >&2; exit 1 ;;
view)
    [ -f "$S/npm_published" ] && { cat "$S/npm_published"; exit 0; }
    if [ "${MOCK_NPM_VIEW:-e404}" = e404 ]; then echo "npm error code E404" >&2
    else echo "npm error code ECONNRESET" >&2; fi
    exit 1 ;;
pack) exec "$REAL_NPM" "$@" ;;
publish)
    [ "${MOCK_NPM_PUBLISH:-ok}" = ok ] || { echo "npm error code EOTP" >&2; exit 1; }
    cp "$2" "$S/published.tgz" && printf '%s\n' "${MOCK_VER#v}" > "$S/npm_published" ;;
*) exit 1 ;;
esac
MOCK
cat > "$T/bin/mkt" <<'MOCK'
#!/bin/sh
printf 'mkt %s\n' "$*" >> "$MOCK_LOG"
# --dry-run is the read-only preflight probe (MOCK_MKT_DRY); MOCK_MKT drives the real bump.
case "$*" in *--dry-run*)
    [ "${MOCK_MKT_DRY:-ok}" = ok ] || { echo "error: entry 'demo' NOT in example-org/marketplace; run 'gitx-marketplace register --repo example-org/marketplace' first" >&2; exit 3; }
    echo "Intended branch: bump-demo-$3"; exit 0 ;;
esac
[ "${MOCK_MKT:-ok}" = ok ] || { echo "error: marketplace PR flow failed" >&2; exit 1; }
[ -f "$MOCK_STATE/mkt_done" ] && { echo "no-op: marketplace already at $3 (url source)"; exit 0; }
touch "$MOCK_STATE/mkt_done"; echo "bumped to $3"
MOCK
chmod +x "$T/bin/gh" "$T/bin/npm" "$T/bin/mkt"
export REAL_NPM MOCK_VER="$VER"

# mk_src DIR — the release's source tree (what the source tarball and tag hold).
mk_src() {
    mkdir -p "$1/opencode" "$1/skills/$SKILL" "$1/.claude-plugin"
    cat > "$1/package.json" <<EOF
{ "name": "$PKG", "version": "$NUM", "license": "MIT",
  "files": ["opencode", "skills/$SKILL"] }
EOF
    printf 'export default {}\n' > "$1/opencode/index.ts"
    printf -- '---\nname: %s\ndescription: fixture skill\n---\n# demo\n' "$SKILL" > "$1/skills/$SKILL/SKILL.md"
    printf '# demo\n' > "$1/README.md"
    printf 'MIT\n' > "$1/LICENSE"
    printf '%s\n' "$VER" > "$1/VERSION"
    printf '{"repository":"https://github.com/example-org/demo"}\n' > "$1/.claude-plugin/plugin.json"
}

# pack_local C — rebuild the local source tarball + checksums from $C/src.
pack_local() {
    local rd="$1/demo/Release/demo-$VER"
    tar -czf "$rd/demo-$VER-source.tar.gz" -C "$1/src" "demo-$VER"
    ( cd "$rd" && { shasum -a 256 "demo-$VER.skill" "demo-$VER-source.tar.gz" sbom.cyclonedx.json 2>/dev/null \
        || sha256sum "demo-$VER.skill" "demo-$VER-source.tar.gz" sbom.cyclonedx.json; } > checksums.txt )
}

# pack_tag C — GitHub's tag tarball (top dir OWNER-REPO-SHA/) from $C/tagsrc.
pack_tag() {
    tar -czf "$1/state/tag.tar.gz" -C "$1/tagsrc" example-org-demo-abc1234
}

# mk_case NAME — a ready-to-publish project: draft with matching assets, main
# VERSION and tag snapshot current, both switches on, npm version unpublished.
mk_case() {
    local c="$T/$1" p="$T/$1/demo"
    mkdir -p "$p/.gitx" "$p/Release/demo-$VER" "$c/state/remote_assets" "$c/src" "$c/tagsrc"
    mk_src "$c/src/demo-$VER"
    mk_src "$p"
    cp -R "$c/src/demo-$VER" "$c/tagsrc/example-org-demo-abc1234"
    printf 'skill-bytes\n' > "$p/Release/demo-$VER/demo-$VER.skill"
    printf '{"bomFormat":"CycloneDX"}\n' > "$p/Release/demo-$VER/sbom.cyclonedx.json"
    pack_local "$c"
    pack_tag "$c"
    # The GitHub SOP (7.1) uploads exactly these three — never the source tarball.
    cp "$p/Release/demo-$VER/demo-$VER.skill" "$p/Release/demo-$VER/checksums.txt" \
        "$p/Release/demo-$VER/sbom.cyclonedx.json" "$c/state/remote_assets/"
    echo draft > "$c/state/gh_release"
    echo v1.0.0 > "$c/state/gh_latest"
    printf '%s\n' "$VER" > "$c/state/main_version"
    printf '%s\n' "$PKG" > "$p/.gitx/npm-target"
    printf 'example-org/marketplace\n' > "$p/.gitx/marketplace-target"
    : > "$c/calls.log"
    CASE="$c"
}

# run_pub [ARGS…] — run in $CASE/demo; sets RC, output in $CASE/out.
run_pub() {
    RC=0
    ( cd "$CASE/demo" && GH_BIN="$T/bin/gh" NPM_BIN="$T/bin/npm" MARKETPLACE_BIN="${CASE_MKT:-$T/bin/mkt}" \
        MOCK_STATE="$CASE/state" MOCK_LOG="$CASE/calls.log" "$PUB" "$@" ) > "$CASE/out" 2>&1 || RC=$?
}

# no_writes — 0 when the call log holds no remote write of any kind
# (a `mkt … --dry-run` preflight probe is read-only and does not count).
no_writes() {
    ! awk '/^(gh release edit|npm publish)/ || (/^mkt / && !/--dry-run/) {f=1} END {exit !f}' "$CASE/calls.log"
}
has_out()  { grep -qF -- "$1" "$CASE/out"; }
has_call() { grep -qE -- "$1" "$CASE/calls.log"; }
need_npm() { [ -n "$REAL_NPM" ] || { skip "$1 — npm not installed"; return 1; }; }

if [ ! -f "$PUB" ]; then
    fail "scripts/gitx-publish.sh missing"
    echo "Results: ✅$PASS passed / ❌$FAIL failed / ➖$SKIP skipped"; exit 1
fi

echo "── usage"
mk_case usage
run_pub --help
[ "$RC" = 0 ] && has_out "--version" && ok "--help → rc 0 with usage" || fail "--help rc=$RC"
run_pub
[ "$RC" = 2 ] && ok "no --version → rc 2" || fail "no --version rc=$RC"
run_pub --version 1.2
[ "$RC" = 2 ] && ok "malformed version → rc 2" || fail "malformed version rc=$RC"
run_pub --version "$VER" --bogus
[ "$RC" = 2 ] && no_writes && ok "unknown flag → rc 2" || fail "unknown flag rc=$RC"

echo "── a: no GitHub Release"
mk_case a; rm -f "$CASE/state/gh_release"
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && ok "a: missing release → rc 1, no writes" || fail "a: rc=$RC"

echo "── b: draft asset differs from local"
mk_case b; printf 'other\n' > "$CASE/state/remote_assets/demo-$VER.skill"
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "demo-$VER.skill" && ok "b: asset mismatch → rc 1" || fail "b: rc=$RC"
mk_case b2; rm -f "$CASE/state/remote_assets/demo-$VER.skill"
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "demo-$VER.skill" && ok "b: draft missing .skill → rc 1, no writes" || fail "b2: rc=$RC"
mk_case b3; cp "$CASE/demo/Release/demo-$VER/demo-$VER-source.tar.gz" "$CASE/state/remote_assets/"
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "demo-$VER-source.tar.gz" && ok "b: unexpected extra asset (byte-identical local file) → rc 1, no writes" || fail "b3: rc=$RC"
mk_case b4; printf 'tampered\n' > "$CASE/demo/Release/demo-$VER/demo-$VER-source.tar.gz"
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "checksums.txt" && ok "b: local release dir fails checksums.txt → rc 1, no writes" || fail "b4: rc=$RC"

echo "── c: tag snapshot npm files differ"
mk_case c; printf 'export default {tampered}\n' > "$CASE/tagsrc/example-org-demo-abc1234/opencode/index.ts"; pack_tag "$CASE"
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "opencode" && ok "c: tag snapshot mismatch → rc 1" || fail "c: rc=$RC"

echo "── d: happy path order"
if need_npm "d"; then
    mk_case d
    run_pub --version "$VER"
    order=$(awk '/^mkt bump --version v1\.2\.3 --dry-run$/{print "D"} /^npm whoami/{print "W"} /^npm view/{print "V"} /^npm pack --ignore-scripts/{print "P"}
        /^gh release edit v1\.2\.3 .*--draft=false --latest/{print "G"} /^mkt bump --version v1\.2\.3$/{print "M"}
        /^npm publish .*\.tgz --ignore-scripts --access public/{print "U"}' "$CASE/calls.log" | tr -d '\n')
    [ "$RC" = 0 ] && ok "d: rc 0" || { fail "d: rc=$RC"; cat "$CASE/out"; }
    [ "$order" = WVPDGMU ] && ok "d: call order whoami→view→pack→bump dry-run→release edit→bump→publish" || fail "d: order '$order'"
    n_bump=$(grep -c '^mkt bump --version v1\.2\.3$' "$CASE/calls.log" || true)
    [ "$n_bump" = 1 ] && ok "d: real marketplace bump called exactly once, after promotion" || fail "d: real bump called $n_bump times"
    n_npm=$(grep -c '^npm ' "$CASE/calls.log" || true)
    n_reg=$(grep -c '^npm .*--registry https://registry\.npmjs\.org/' "$CASE/calls.log" || true)
    [ "$n_npm" -gt 0 ] && [ "$n_npm" = "$n_reg" ] && ok "d: every npm call carries --registry" || fail "d: $n_reg/$n_npm npm calls with --registry"
    ! has_call '--otp' && ok "d: no --otp passed" || fail "d: --otp passed"
    has_out "▶ 第 0 步" && has_out "▶ 第 3 步" && ok "d: step banners printed" || fail "d: step banners missing"

    echo "── e: rerun after completion"
    : > "$CASE/calls.log"
    run_pub --version "$VER"
    [ "$RC" = 0 ] && grep -q '^ℹ️.*GitHub' "$CASE/out" && grep -q '^ℹ️.*中央市场' "$CASE/out" \
        && grep -q '^ℹ️.*npm' "$CASE/out" && ok "e: rerun rc 0, three steps ℹ️" || { fail "e: rc=$RC"; cat "$CASE/out"; }
    ! has_call '^gh release edit' && ! has_call '^npm (pack|publish)' && ok "e: no release edit / pack / publish" || fail "e: publish-class call on rerun"
fi

echo "── f: both switches off"
mk_case f; rm -f "$CASE/demo/.gitx/npm-target" "$CASE/demo/.gitx/marketplace-target"
run_pub --version "$VER"
n_skip=$(grep -c '^➖' "$CASE/out" || true)
[ "$RC" = 0 ] && [ "$n_skip" = 2 ] && ! has_call '^(npm|mkt) ' && ok "f: ➖ marketplace + ➖ npm, rc 0" || fail "f: rc=$RC skip=$n_skip"

echo "── g: npm version already published"
mk_case g; printf '%s\n' "$NUM" > "$CASE/state/npm_published"
run_pub --version "$VER"
[ "$RC" = 0 ] && ! has_call '^npm (pack|publish)' && grep -q '^ℹ️.*npm' "$CASE/out" && ok "g: npm ℹ️, no pack/publish" || fail "g: rc=$RC"

echo "── h: npm whoami fails"
mk_case h
MOCK_NPM_WHOAMI=fail run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "npm login" && has_out "重跑" && ok "h: rc 1, no writes, tells npm login + rerun" || fail "h: rc=$RC"

echo "── i: package name / version mismatch"
mk_case i; printf '@other/pkg\n' > "$CASE/demo/.gitx/npm-target"
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && ok "i: name mismatch → rc 1, no writes" || fail "i: name rc=$RC"
mk_case i2; sed "s/\"$NUM\"/\"1.2.2\"/" "$CASE/src/demo-$VER/package.json" > "$CASE/pj" && mv "$CASE/pj" "$CASE/src/demo-$VER/package.json"
cp "$CASE/src/demo-$VER/package.json" "$CASE/tagsrc/example-org-demo-abc1234/package.json"
pack_local "$CASE"; pack_tag "$CASE"
cp "$CASE/demo/Release/demo-$VER/checksums.txt" "$CASE/state/remote_assets/"
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "1.2.2" && ok "i: version mismatch → rc 1, no writes" || fail "i: version rc=$RC"

echo "── j: pack outside whitelist / sanitize failure"
if need_npm "j"; then
    mk_case j
    for d in "$CASE/src/demo-$VER" "$CASE/tagsrc/example-org-demo-abc1234"; do
        printf '# private\n' > "$d/HANDOFFX.md"
        sed 's/"opencode",/"opencode", "HANDOFFX.md",/' "$d/package.json" > "$CASE/pj" && mv "$CASE/pj" "$d/package.json"
    done
    pack_local "$CASE"; pack_tag "$CASE"; cp "$CASE/demo/Release/demo-$VER/checksums.txt" "$CASE/state/remote_assets/"
    run_pub --version "$VER"
    [ "$RC" = 1 ] && no_writes && has_out "HANDOFFX.md" && ok "j: non-whitelisted member → rc 1, no writes" || fail "j: whitelist rc=$RC"
    mk_case j2
    U=Users
    for d in "$CASE/src/demo-$VER" "$CASE/tagsrc/example-org-demo-abc1234"; do
        printf 'const p = "/%s/%s/work";\n' "$U" "alicebob" >> "$d/opencode/index.ts"
    done
    pack_local "$CASE"; pack_tag "$CASE"; cp "$CASE/demo/Release/demo-$VER/checksums.txt" "$CASE/state/remote_assets/"
    run_pub --version "$VER"
    [ "$RC" = 1 ] && no_writes && has_out "sanitize" && ok "j: sanitize finding → rc 1, no writes" || fail "j: sanitize rc=$RC"
fi

echo "── k: --dry-run"
if need_npm "k"; then
    mk_case k
    run_pub --version "$VER" --dry-run
    [ "$RC" = 0 ] && no_writes && has_out "dry-run" && ok "k: plan printed, no writes" || fail "k: rc=$RC"
fi

echo "── l: marketplace bump fails, rerun resumes"
if need_npm "l"; then
    mk_case l
    MOCK_MKT=fail run_pub --version "$VER"
    [ "$RC" = 1 ] && has_out "已完成到第 1 步" && [ "$(cat "$CASE/state/gh_release")" = public ] && ! has_call '^npm publish' \
        && ok "l: rc 1 after step 1, no npm publish" || fail "l: rc=$RC"
    : > "$CASE/calls.log"
    run_pub --version "$VER"
    [ "$RC" = 0 ] && ! has_call '^gh release edit' && has_call '^mkt bump' && has_call '^npm publish' \
        && grep -q '^ℹ️.*GitHub' "$CASE/out" && ok "l: rerun → step 1 ℹ️, bump retried, npm published" || fail "l: rerun rc=$RC"
fi

echo "── m: same-version re-cut differs from GitHub tag"
mk_case m; printf -- '---\nname: %s\ndescription: re-cut\n---\n# demo\n' "$SKILL" > "$CASE/src/demo-$VER/skills/$SKILL/SKILL.md"
pack_local "$CASE"; cp "$CASE/demo/Release/demo-$VER/checksums.txt" "$CASE/state/remote_assets/"
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "skills/$SKILL" && ok "m: local re-cut ≠ tag snapshot → rc 1, no writes" || fail "m: rc=$RC"

echo "── n: prepack script never runs"
if need_npm "n"; then
    mk_case n
    for d in "$CASE/src/demo-$VER" "$CASE/tagsrc/example-org-demo-abc1234"; do
        sed "s|\"license\": \"MIT\",|\"license\": \"MIT\", \"scripts\": {\"prepack\": \"touch $CASE/prepack-ran \&\& echo x > opencode/injected.txt\"},|" \
            "$d/package.json" > "$CASE/pj" && mv "$CASE/pj" "$d/package.json"
    done
    pack_local "$CASE"; pack_tag "$CASE"; cp "$CASE/demo/Release/demo-$VER/checksums.txt" "$CASE/state/remote_assets/"
    run_pub --version "$VER"
    members=$(tar -tzf "$CASE/state/published.tgz" 2>/dev/null || true)
    [ "$RC" = 0 ] && [ ! -e "$CASE/prepack-ran" ] && grep -q 'package/opencode/index.ts' <<<"$members" \
        && ! grep -q 'injected' <<<"$members" && ok "n: prepack not run, no injected file" || fail "n: rc=$RC"
fi

echo "── o: npm view network error"
mk_case o
MOCK_NPM_VIEW=neterr run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && ! has_call '^npm pack' && ok "o: non-E404 view error → rc 1, no writes" || fail "o: rc=$RC"

echo "── p: GitHub main VERSION stale"
mk_case p; printf 'v1.2.2\n' > "$CASE/state/main_version"
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "main" && ok "p: stale main VERSION → rc 1, no writes" || fail "p: rc=$RC"

echo "── q: npm publish fails, rerun redoes only step 3"
if need_npm "q"; then
    mk_case q
    MOCK_NPM_PUBLISH=fail run_pub --version "$VER"
    [ "$RC" = 1 ] && has_out "已完成到第 2 步" && [ -f "$CASE/state/mkt_done" ] && [ "$(cat "$CASE/state/gh_release")" = public ] \
        && ok "q: rc 1 with steps 1-2 done" || fail "q: rc=$RC"
    : > "$CASE/calls.log"
    run_pub --version "$VER"
    [ "$RC" = 0 ] && ! has_call '^gh release edit' && grep -q '^ℹ️.*GitHub' "$CASE/out" \
        && grep -q '^ℹ️.*中央市场' "$CASE/out" && has_call '^npm publish' \
        && ok "q: rerun → steps 1-2 ℹ️, only npm publish redone" || fail "q: rerun rc=$RC"
fi

echo "── r: npm README / LICENSE must equal the public tag"
if need_npm "r"; then
    # npm adds root README.md on its own, from the un-redacted local tarball.
    mk_case r; printf '# demo\ninternal notes\n' > "$CASE/src/demo-$VER/README.md"
    pack_local "$CASE"; cp "$CASE/demo/Release/demo-$VER/checksums.txt" "$CASE/state/remote_assets/"
    run_pub --version "$VER"
    [ "$RC" = 1 ] && no_writes && has_out "README.md" && ok "r: local README ≠ tag snapshot → rc 1, no writes" || { fail "r: rc=$RC"; cat "$CASE/out"; }
    mk_case r2; rm -f "$CASE/tagsrc/example-org-demo-abc1234/LICENSE"; pack_tag "$CASE"
    run_pub --version "$VER"
    [ "$RC" = 1 ] && no_writes && has_out "LICENSE" && ok "r: LICENSE absent from tag → rc 1, no writes" || { fail "r2: rc=$RC"; cat "$CASE/out"; }
fi

echo "── s: GitHub repo without plugin.json .repository"
mk_case s; printf '{"name":"demo"}\n' > "$CASE/demo/.claude-plugin/plugin.json"
rm -f "$CASE/demo/.gitx/npm-target" "$CASE/demo/.gitx/marketplace-target"
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "--repo" && ok "s: no .repository, no origin → rc 1, names --repo" || { fail "s: rc=$RC"; cat "$CASE/out"; }
# AT keeps scp/ssh remotes out of the source: user@host trips release-sanitize's EMAIL scan (Gotcha #83).
AT='@'
( cd "$CASE/demo" && git init -q && git remote add origin "git${AT}github.com:example-org/demo.git" )
run_pub --version "$VER"
[ "$RC" = 0 ] && has_call '^gh release view v1\.2\.3 --repo example-org/demo ' && ok "s: falls back to github.com origin (scp form)" || { fail "s: origin rc=$RC"; cat "$CASE/out"; }
mk_case s2; printf '{"name":"demo"}\n' > "$CASE/demo/.claude-plugin/plugin.json"
rm -f "$CASE/demo/.gitx/npm-target" "$CASE/demo/.gitx/marketplace-target"
( cd "$CASE/demo" && git init -q && git remote add origin "ssh://git${AT}git.example.internal:2222/team/demo.git" )
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "--repo" && ok "s: non-github origin → rc 1, names --repo" || { fail "s2: rc=$RC"; cat "$CASE/out"; }
run_pub --version "$VER" --repo example-org/demo
[ "$RC" = 0 ] && has_call '^gh release view v1\.2\.3 --repo example-org/demo ' && ok "s: --repo OWNER/REPO used" || { fail "s2: --repo rc=$RC"; cat "$CASE/out"; }
: > "$CASE/calls.log"
for bad in 'https://github.com/example-org/demo' 'example-org/../x' 'example-org' "$(printf 'example-org/demo\nevil/x')" "$(printf 'example-org/de\033mo')"; do
    run_pub --version "$VER" --repo "$bad"
    [ "$RC" = 2 ] || { fail "s: --repo '$bad' rc=$RC (want 2)"; continue; }
done
[ ! -s "$CASE/calls.log" ] && ok "s: malformed / control-char --repo → rc 2, nothing called" || fail "s: malformed --repo reached a remote call"

echo "── t: marketplace preconditions are checked before going public"
mk_case t
MOCK_MKT_DRY=fail run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && [ "$(cat "$CASE/state/gh_release")" = draft ] && has_out "register" \
    && ok "t: bump --dry-run fails → rc 1, still draft, no writes" || { fail "t: rc=$RC"; cat "$CASE/out"; }
mk_case t2; printf '#!/bin/sh\nexit 0\n' > "$CASE/mkt-noexec"
CASE_MKT="$CASE/mkt-noexec" run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "not executable" && ok "t: marketplace tool not executable → rc 1, no writes" || { fail "t2: rc=$RC"; cat "$CASE/out"; }

echo "── u: Latest re-assert fails after the Release went public"
mk_case u; rm -f "$CASE/demo/.gitx/npm-target"
MOCK_GH_LATEST=fail run_pub --version "$VER"
[ "$RC" = 1 ] && [ "$(cat "$CASE/state/gh_release")" = public ] && has_out "已完成到第 1 步" && ! has_out "已完成到第 0 步" \
    && ! has_call '^mkt bump --version v1\.2\.3$' && ok "u: rc 1, reports step 1 done (Release is public)" || { fail "u: rc=$RC"; cat "$CASE/out"; }

echo "── v: every shipped artifact must be listed in checksums.txt"
mk_case v
( cd "$CASE/demo/Release/demo-$VER" && grep -v 'sbom.cyclonedx.json' checksums.txt > c.tmp && mv c.tmp checksums.txt )
cp "$CASE/demo/Release/demo-$VER/checksums.txt" "$CASE/state/remote_assets/"
run_pub --version "$VER"
[ "$RC" = 1 ] && no_writes && has_out "sbom.cyclonedx.json" && ok "v: SBOM not in checksums.txt → rc 1, no writes" || { fail "v: rc=$RC"; cat "$CASE/out"; }

echo "Results: ✅$PASS passed / ❌$FAIL failed / ➖$SKIP skipped"
[ "$FAIL" = 0 ]
