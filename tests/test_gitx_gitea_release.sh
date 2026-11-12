#!/usr/bin/env bash
# tests/test_gitx_gitea_release.sh — gitx-gitea-release.sh (Task 1: marker,
# checksum gate, SSH publish, dry-run, --force; Task 2: Gitea Release API phase;
# final-review fixes: pushed bytes = audited bytes, missing-asset re-upload).
#
# Zero network: GITX_GITEA_REMOTE_URL points every git network call at a local
# bare repo, so publish / idempotency / --force are proven against real git;
# GITX_GITEA_CURL points the API phase at a recording mock curl.
# The private host never appears here — fixtures use git.example.internal, and
# any user-at-host expectation is assembled from fragments (${AT}) because the
# release sanitizer scans tests/*.sh.
#
# Generic-safe: SKIP if scripts/gitx-gitea-release.sh is absent (public layout).

# The suite sources the script by variable path to reach its helpers, and sets
# PROJECT_NAME for the sourced functions to read.
# shellcheck disable=SC1090,SC2034
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GGR="$ROOT/scripts/gitx-gitea-release.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

AT='@'
HOSTX='git.example.internal'
VER='v1.2.3'

echo "══ test_gitx_gitea_release.sh ══"

if [ ! -f "$GGR" ]; then
    echo "  ➖ gitx-gitea-release.sh not present — generic-safe skip"
    echo "Results: ✅0 passed / ❌0 failed"; exit 0
fi

# The name-resolution contract lets explicit env win; a caller's env must not
# leak into the cases that rely on derivation from PROJECT_ROOT.
unset PROJECT_NAME SKILL_NAME GITX_GITEA_REMOTE_URL XDG_CONFIG_HOME

T=$(mktemp -d "${TMPDIR:-/tmp}/test_gitea_release.XXXXXX")
trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd)"

# git recorder shim first on PATH: every git invocation the script makes is
# logged, so the checksum-gate and dry-run cases can prove no network call ran.
REAL_GIT=$(command -v git)
mkdir -p "$T/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$T/git.log" "$REAL_GIT" > "$T/bin/git"
chmod +x "$T/bin/git"
export PATH="$T/bin:$PATH"
: > "$T/git.log"
# Identity-free git: no user .gitconfig, no system config — the script's own
# gitx identity is the only one available, so the asserts below lock it in.
mkdir -p "$T/home"
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1
# no_net_git — 0 when git.log records no push / fetch / ls-remote.
no_net_git() { ! grep -qE '(^| )(push|fetch|ls-remote)( |$)' "$T/git.log"; }

# shasum recorder shim: logs argv to shasum.log, then hashes with the real tool.
# A `-c MANIFEST` naming an absolute, `..` or `-` path exits 97 instead, so a
# regression in the pre-hash manifest gate fails fast rather than hanging.
REAL_SHASUM=$(command -v shasum || true)
cat > "$T/bin/shasum" <<SHIM
#!/bin/sh
printf '%s\n' "\$*" >> "$T/shasum.log"
prev=""
for a in "\$@"; do
    if [ "\$prev" = -c ] && awk '{ p = \$0; sub(/^[0-9a-fA-F]+ [ *]?/, "", p)
            if (p ~ /^\// || p == "-" || p ~ /(^|\/)\.\.(\/|\$)/) bad = 1 } END { exit !bad }' "\$a"; then
        exit 97
    fi
    prev="\$a"
done
if [ -n "$REAL_SHASUM" ]; then exec "$REAL_SHASUM" "\$@"; fi
[ "\$1" = -a ] && shift 2
exec sha256sum "\$@"
SHIM
chmod +x "$T/bin/shasum"
: > "$T/shasum.log"

sha_files() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"; else sha256sum "$@"; fi
}

# regen_sums DIR — rewrite checksums.txt over every other file in DIR.
regen_sums() {
    ( cd "$1" && rm -f checksums.txt && sha_files install.sh ./*.skill ./*.tar.gz ./*.md > checksums.txt )
}

# mk_project NAME VERSION [DIRNAME] — $T/<DIRNAME:-NAME> with a built
# Release/<NAME>-<VERSION>/ (DIRNAME ≠ NAME exercises the explicit-name override).
mk_project() {
    local p="$T/${3:-$1}" rd="$T/${3:-$1}/Release/$1-$2"
    mkdir -p "$p/.gitx" "$p/skills/$1" "$rd"
    printf '%s\n' "$2" > "$p/VERSION"
    printf '%s\n' "$2" > "$p/skills/$1/VERSION"
    printf -- '---\nname: %s\ndescription: fixture skill\n---\n# %s\n' "$1" "$1" > "$p/skills/$1/SKILL.md"
    printf '#!/bin/sh\necho ORIGINAL-INSTALL\n' > "$rd/install.sh"
    printf 'skill-%s\n' "$1" > "$rd/$1-$2.skill"
    printf 'tarball-%s\n' "$1" > "$rd/$1-$2-full.tar.gz"
    printf '# Changelog\n\n## %s — 2026-01-02\n\n- fixture\n' "$2" > "$rd/CHANGELOG.md"
    printf '# %s %s\n\nfixture notes\n' "$1" "$2" > "$rd/RELEASE_NOTES.md"
    regen_sums "$rd"
    printf '%s:2222/my-releases/%s\n' "$HOSTX" "$1" > "$p/.gitx/gitea-release-target"
}

mk_bare() {
    git init -q --bare "$1" && git -C "$1" symbolic-ref HEAD refs/heads/main
}

refs_n() { git -C "$1" for-each-ref | wc -l | tr -d ' '; }

# run_ggr PROJECT BARE ARGS… — sets OUT / RC. Inherited PROJECT_NAME/SKILL_NAME
# are cleared (the release pipeline exports them, Gotcha #103) so these cases
# really exercise basename derivation.
run_ggr() {
    local p="$1" b="$2"; shift 2
    OUT=$(cd "$p" && env -u PROJECT_NAME -u SKILL_NAME PROJECT_ROOT="$p" GITX_GITEA_REMOTE_URL="$b" \
          bash "$GGR" "$@" 2>&1) && RC=0 || RC=$?
}

has()     { grep -qF -- "$2" <<<"$1"; }
has_line() { grep -qxF -- "$2" <<<"$1"; }
show() { sed 's/^/    | /' <<<"$OUT" | head -20; }

NAME=demoapp
P="$T/$NAME"; RD="$P/Release/$NAME-$VER"
mk_project "$NAME" "$VER"
B="$T/bare.git"; mk_bare "$B"

# --- 1: --help ---
run_ggr "$P" "$B" --help
if [ "$RC" = 0 ] && has "$OUT" 'gitea-release-target'; then ok "1: --help exits 0 and names the marker"
else fail "1: --help (rc=$RC)"; show; fi

# --- 2: no marker → exit 2 naming the marker ---
mv "$P/.gitx/gitea-release-target" "$T/marker.keep"
run_ggr "$P" "$B" --skip-api
if [ "$RC" = 2 ] && has "$OUT" 'gitea-release-target'; then ok "2: no marker → exit 2, message names the marker"
else fail "2: no marker (rc=$RC)"; show; fi

# --- 3: invalid markers → exit 2 each ---
bad_ok=1
for bad in 'http://x/y/z' 'a b/c' 'h/o' 'h:1:2/o/r' "$HOSTX/o/r?token=abc" \
           "$HOSTX/password/r" "$HOSTX/o/token" "$HOSTX/o/r:1" ':22/o/r' "$HOSTX//r" "$HOSTX/o/" \
           "$HOSTX:/o/r" "$HOSTX:ab/o/r" "$HOSTX:0/o/r" "$HOSTX:65536/o/r" "$HOSTX/../r" "$HOSTX/o/.." \
           "$HOSTX/o/r"$'\n'"$HOSTX/o/r2"; do
    printf '%s\n' "$bad" > "$P/.gitx/gitea-release-target"
    run_ggr "$P" "$B" --skip-api
    if [ "$RC" != 2 ]; then bad_ok=0; fail "3: bad marker '$bad' → rc=$RC (want 2)"; show; fi
done
[ "$bad_ok" = 1 ] && ok "3: bad markers (://, whitespace, slashes, colons, token/password, empty part, port, .., 2 lines) → exit 2"

# --- 4: symlinked marker → exit 2 ---
rm -f "$P/.gitx/gitea-release-target"
ln -s "$T/marker.keep" "$P/.gitx/gitea-release-target"
run_ggr "$P" "$B" --skip-api
if [ "$RC" = 2 ] && [ "$(refs_n "$B")" = 0 ]; then ok "4: symlinked marker → exit 2"
else fail "4: symlinked marker (rc=$RC)"; show; fi
rm -f "$P/.gitx/gitea-release-target"
mv "$T/marker.keep" "$P/.gitx/gitea-release-target"

# --- 5: ggr_read_marker parsing (+ default port 22) ---
got=$(cd "$P" && . "$GGR" && ggr_read_marker 2>&1) || true
printf '%s/my-releases/%s\r\n' "$HOSTX" "$NAME" > "$T/noport"
got22=$(cd "$T" && mkdir -p np/.gitx && cp noport np/.gitx/gitea-release-target && cd np && . "$GGR" && ggr_read_marker 2>&1) || true
if [ "$got" = "$HOSTX 2222 my-releases/$NAME" ] && [ "$got22" = "$HOSTX 22 my-releases/$NAME" ]; then
    ok "5: ggr_read_marker → HOST PORT OWNER/REPO; no port (CRLF line) → 22"
else fail "5: ggr_read_marker got '$got' / '$got22'"; fi

# --- 6: tampered release dir → exit 1, nothing pushed ---
mk_project tamperapp "$VER"
TRD="$T/tamperapp/Release/tamperapp-$VER"
printf 'x' >> "$TRD/install.sh"
: > "$T/git.log"
run_ggr "$T/tamperapp" "$B" --skip-api
if [ "$RC" = 1 ] && has_line "$OUT" "❌ checksums.txt verification failed in $TRD" && [ "$(refs_n "$B")" = 0 ] && no_net_git; then
    ok "6: tampered dir → exit 1 with ❌ checksums line, no git network call, bare repo untouched"
else fail "6: tampered dir (rc=$RC, refs=$(refs_n "$B"))"; show; fi

# --- 6b: a file not listed in checksums.txt (.DS_Store) → exit 1, nothing pushed ---
mk_project strayapp "$VER"
SRD="$T/strayapp/Release/strayapp-$VER"
printf 'junk' > "$SRD/.DS_Store"
: > "$T/git.log"
run_ggr "$T/strayapp" "$B" --skip-api
if [ "$RC" = 1 ] && has_line "$OUT" "❌ unlisted file(s) in $SRD: .DS_Store" && [ "$(refs_n "$B")" = 0 ] && no_net_git; then
    ok "6b: unlisted .DS_Store → exit 1 naming it, no git network call"
else fail "6b: unlisted file (rc=$RC)"; show; fi

# --- 6c: .gitattributes in the dir (even when listed) → exit 1, nothing pushed ---
mk_project attrapp "$VER"
GRD="$T/attrapp/Release/attrapp-$VER"
mkdir -p "$GRD/sub"; printf '* text eol=crlf\n' > "$GRD/sub/.gitattributes"
( cd "$GRD" && sha_files sub/.gitattributes >> checksums.txt )
: > "$T/git.log"
run_ggr "$T/attrapp" "$B" --skip-api
if [ "$RC" = 1 ] && has "$OUT" "❌ .gitattributes in $GRD: sub/.gitattributes" && [ "$(refs_n "$B")" = 0 ] && no_net_git; then
    ok "6c: .gitattributes (listed in checksums.txt) → exit 1, no git network call"
else fail "6c: .gitattributes (rc=$RC)"; show; fi

# --- 7: --dry-run derives both URLs from the marker, pushes nothing ---
: > "$T/git.log"
run_ggr "$P" "$B" --dry-run --skip-api
if [ "$RC" = 0 ] && [ "$(refs_n "$B")" = 0 ] && no_net_git \
   && has_line "$OUT" "🧪 dry-run: remote ssh://git${AT}$HOSTX:2222/my-releases/$NAME.git" \
   && has_line "$OUT" "🧪 dry-run: api https://$HOSTX/api/v1" \
   && has "$OUT" '🧪 dry-run: would push'; then
    ok "7: --dry-run → exit 0, derived ssh + api URLs, bare repo untouched"
else fail "7: --dry-run (rc=$RC)"; show; fi
cp "$T/noport" "$P/.gitx/gitea-release-target"
run_ggr "$P" "$B" --dry-run --skip-api
if [ "$RC" = 0 ] && has_line "$OUT" "🧪 dry-run: remote ssh://git${AT}$HOSTX:22/my-releases/$NAME.git"; then
    ok "7b: --dry-run with a port-less marker derives port 22"
else fail "7b: port-less dry-run (rc=$RC)"; show; fi
printf '%s:2222/my-releases/%s\n' "$HOSTX" "$NAME" > "$P/.gitx/gitea-release-target"

# check_published BARE NAME LABEL — the first-publish contract on BARE.
check_published() {
    local b="$1" n="$2" why=""
    [ "$RC" = 0 ] || why="$why rc=$RC"
    has_line "$OUT" "✅ pushed $n $VER → $b" || why="$why no-✅-line"
    git -C "$b" rev-parse -q --verify refs/heads/main >/dev/null || why="$why no-main"
    git -C "$b" rev-parse -q --verify "refs/tags/$VER" >/dev/null || why="$why no-tag"
    [ "$(git -C "$b" cat-file -t "refs/tags/$VER" 2>/dev/null)" = tag ] || why="$why tag-not-annotated"
    local tree; tree=$(git -C "$b" ls-tree -r --name-only main 2>/dev/null)
    for f in install.sh checksums.txt "$n-$VER.skill"; do
        grep -qxF -- "$f" <<<"$tree" || why="$why missing:$f"
    done
    [ "$(git -C "$b" log -1 --format='%an|%ae|%cn|%ce|%ad|%cd' --date=short main 2>/dev/null)" \
      = "gitx|gitx${AT}localhost|gitx|gitx${AT}localhost|2026-01-02|2026-01-02" ] || why="$why commit-identity/date"
    [ "$(git -C "$b" for-each-ref --format='%(taggername)|%(taggeremail)|%(taggerdate:short)' "refs/tags/$VER" 2>/dev/null)" \
      = "gitx|<gitx${AT}localhost>|2026-01-02" ] || why="$why tagger-identity/date"
    if [ -z "$why" ]; then ok "$3"; else fail "$3 —$why"; show; fi
}

# --- 8: first publish ---
run_ggr "$P" "$B" --skip-api
check_published "$B" "$NAME" "8: first publish → main + annotated tag, files, author gitx, CHANGELOG date"
main1=$(git -C "$B" rev-parse main 2>/dev/null || true)
tag1=$(git -C "$B" rev-parse "refs/tags/$VER" 2>/dev/null || true)

# --- 9: second run is idempotent ---
run_ggr "$P" "$B" --skip-api
if [ "$RC" = 0 ] && has_line "$OUT" "ℹ️ already published: tag $VER exists on $B (use --force to replace)" \
   && [ "$(git -C "$B" rev-parse main)" = "$main1" ] && [ "$(git -C "$B" rev-parse "refs/tags/$VER")" = "$tag1" ]; then
    ok "9: second run → ℹ️ already published, main and tag unchanged"
else fail "9: idempotent rerun (rc=$RC)"; show; fi

# --- 9b: tag exists but the dir was rebuilt (new checksums), no --force → refuse ---
printf '#!/bin/sh\necho REPLACED-INSTALL\n' > "$RD/install.sh"
rm -f "$RD/RELEASE_NOTES.md"
regen_sums "$RD"
run_ggr "$P" "$B" --skip-api
if [ "$RC" = 1 ] \
   && has_line "$OUT" "❌ tag $VER exists on $B but its checksums.txt differs from $RD — use --force to replace" \
   && [ "$(git -C "$B" rev-parse main)" = "$main1" ] && [ "$(git -C "$B" rev-parse "refs/tags/$VER")" = "$tag1" ]; then
    ok "9b: tag exists + changed dir, no --force → exit 1 with ❌ differs line, remote unchanged"
else fail "9b: changed dir without --force (rc=$RC)"; show; fi

# --- 10 + 12: --force --skip-api rebuilds main from the current dir, moves the tag ---
# Only the tag is forced: the push carries +refs/tags/… and a plain main refspec.
: > "$T/git.log"
run_ggr "$P" "$B" --force --skip-api
main2=$(git -C "$B" rev-parse main 2>/dev/null || true)
push10=$(grep -E '(^| )push( |$)' "$T/git.log" || true)
if [ "$RC" = 0 ] && [ -n "$main2" ] && [ "$main2" != "$main1" ] \
   && has "$push10" " refs/heads/main:refs/heads/main +refs/tags/$VER:refs/tags/$VER" \
   && ! has "$push10" '--force' && ! has "$push10" '+refs/heads' \
   && has "$(git -C "$B" show main:install.sh 2>/dev/null)" REPLACED-INSTALL \
   && [ "$(git -C "$B" rev-parse "refs/tags/$VER^{commit}")" = "$main2" ] \
   && ! has_line "$(git -C "$B" ls-tree -r --name-only main 2>/dev/null)" RELEASE_NOTES.md; then
    ok "10: --force → new main commit with new content, tag moved, removed file gone; only the tag is forced"
else fail "10: --force (rc=$RC)"; show; fi
if [ "$RC" = 0 ] && has "$OUT" '⚠️ --force without the API phase'; then
    ok "12: --force --skip-api allowed with ⚠️ stale-release warning"
else fail "12: --force --skip-api warning missing (rc=$RC)"; show; fi

# --- 13: --force on an identical dir adds no commit; tag still on main ---
run_ggr "$P" "$B" --force --skip-api
if [ "$RC" = 0 ] && [ "$(git -C "$B" rev-parse main)" = "$main2" ] \
   && [ "$(git -C "$B" rev-parse "refs/tags/$VER^{commit}")" = "$main2" ]; then
    ok "13: --force twice on an identical dir → main unchanged, tag still points at main"
else fail "13: identical --force (rc=$RC)"; show; fi

# --- 14: main pushed but tag missing → plain rerun restores the tag, no new commit ---
git -C "$B" tag -d "$VER" >/dev/null 2>&1
run_ggr "$P" "$B" --skip-api
if [ "$RC" = 0 ] && has_line "$OUT" "✅ pushed $NAME $VER → $B" && [ "$(git -C "$B" rev-parse main)" = "$main2" ] \
   && [ "$(git -C "$B" rev-parse "refs/tags/$VER^{commit}" 2>/dev/null)" = "$main2" ]; then
    ok "14: tag missing on remote → rerun re-tags HEAD without a new commit"
else fail "14: tag recovery (rc=$RC)"; show; fi

# --- 15: version defaults to the skills/<SKILL_NAME>/VERSION sidecar (wrapper's resolver) ---
printf 'v9.9.9\n' > "$P/VERSION"
run_ggr "$P" "$B" --dry-run --skip-api
v_side=$OUT; rc_side=$RC
run_ggr "$P" "$B" --dry-run --skip-api --version v9.9.9
if [ "$rc_side" = 0 ] && has "$v_side" "would push $NAME $VER " && [ "$RC" = 1 ] && has "$OUT" "Release/$NAME-v9.9.9"; then
    ok "15: no --version → sidecar version ($VER, root VERSION ignored); --version overrides"
else fail "15: version resolution (rc=$rc_side/$RC)"; sed 's/^/    | /' <<<"$v_side"; show; fi
printf '%s\n' "$VER" > "$P/VERSION"

# --- 11: explicit PROJECT_NAME/SKILL_NAME env win (pipeline override contract) ---
# Dir basename "dirx" ≠ project "overr": ignoring the override would look for
# Release/dirx-… and fail.
mk_project overr "$VER" dirx
B2="$T/bare2.git"; mk_bare "$B2"
OUT=$(cd "$T/dirx" && PROJECT_ROOT="$T/dirx" PROJECT_NAME=overr SKILL_NAME=overr \
      GITX_GITEA_REMOTE_URL="$B2" bash "$GGR" --skip-api 2>&1) && RC=0 || RC=$?
check_published "$B2" overr "11: explicit PROJECT_NAME/SKILL_NAME (dir basename differs) → publishes Release/overr-$VER"

# --- 11b: global core.autocrlf=input + a CRLF file → pushed bytes equal the dir ---
mk_project crlfapp "$VER"
CRD="$T/crlfapp/Release/crlfapp-$VER"
printf 'line one\r\nline two\r\n' > "$CRD/NOTES-crlf.md"
regen_sums "$CRD"
printf '[core]\n\tautocrlf = input\n\tsafecrlf = true\n' > "$T/home/.gitconfig"
BC="$T/bare-crlf.git"; mk_bare "$BC"
run_ggr "$T/crlfapp" "$BC" --skip-api
rm -f "$T/home/.gitconfig"
if [ "$RC" = 0 ] && git -C "$BC" show main:NOTES-crlf.md | cmp -s - "$CRD/NOTES-crlf.md" \
   && git -C "$BC" show main:checksums.txt | cmp -s - "$CRD/checksums.txt"; then
    ok "11b: global autocrlf=input + CRLF file → published blob byte-identical to the release dir"
else fail "11b: CRLF bytes (rc=$RC)"; show; fi

# --- 16: ggr_ssh_publish refuses an empty / non-release dir (never copies `/`) ---
# B3 is built here with tag $VER already on it, independent of earlier cases:
# should the guard ever regress, the tag-exists path still exits before the
# `cp -R "$dir"/.` that would otherwise copy `/` (load-bearing, keep it).
B3="$T/bare3.git"; mk_bare "$B3"
S3="$T/seed3"; mkdir -p "$S3"
( cd "$S3" && git init -q && git symbolic-ref HEAD refs/heads/main \
  && git -c user.name=t -c user.email=t@localhost commit -q --allow-empty -m seed \
  && git -c user.name=t -c user.email=t@localhost tag -a "$VER" -m seed \
  && git push -q "$B3" refs/heads/main "refs/tags/$VER" ) >/dev/null 2>&1
# Sourcing turns on the script's set -e, so capture the rc via `&& … || …`.
r16=$( (. "$GGR"; PROJECT_NAME=x; ggr_ssh_publish "" "$VER" "$B3" 0 >/dev/null 2>&1 && echo 0 || echo "$?") )
r16b=$( (. "$GGR"; PROJECT_NAME=x; ggr_ssh_publish "$T/bin" "$VER" "$B3" 0 >/dev/null 2>&1 && echo 0 || echo "$?") )
r16c=$( (. "$GGR"; PROJECT_NAME=x; ggr_ssh_publish "$RD" "$VER" "" 0 >/dev/null 2>&1 && echo 0 || echo "$?") )
if git -C "$B3" rev-parse -q --verify "refs/tags/$VER" >/dev/null \
   && [ "$r16" = 1 ] && [ "$r16b" = 1 ] && [ "$r16c" = 1 ]; then
    ok "16: ggr_ssh_publish refuses an empty dir, a dir without checksums.txt, and an empty remote"
else fail "16: ggr_ssh_publish guard (rc=$r16/$r16b/$r16c)"; fi

# --- 17: extraction contract — ggr_read_marker alone via awk+eval under set -euo pipefail ---
got17=$(cd "$T/np" && bash -c 'set -euo pipefail; eval "$(awk "/^ggr_read_marker\\(\\)/,/^\\}/" "$1")"; ggr_read_marker' _ "$GGR" 2>&1) || true
if [ "$got17" = "$HOSTX 22 my-releases/$NAME" ]; then
    ok "17: ggr_read_marker extracted alone (awk+eval, set -euo pipefail) parses the marker"
else fail "17: extracted ggr_read_marker got '$got17'"; fi

# --- 19: inherited GIT_DIR / GIT_WORK_TREE never redirect the publish ---
# The sentinel repo's HEAD is refs/heads/trunk, so a stray `symbolic-ref HEAD
# refs/heads/main` (or `init`) on it would show.
SEN="$T/sentinel.git"; SWT="$T/sentinel-wt"
git init -q --bare "$SEN" && git -C "$SEN" symbolic-ref HEAD refs/heads/trunk
( cd "$T" && rm -rf seed-sen && git init -q seed-sen && cd seed-sen \
  && git -c user.name=t -c user.email=t@localhost commit -q --allow-empty -m seed \
  && git push -q "$SEN" HEAD:refs/heads/trunk ) >/dev/null 2>&1
mkdir -p "$SWT"; printf 'keep\n' > "$SWT/keep.txt"
sen_state() { printf '%s\n' "$(cat "$SEN/HEAD")"; git -C "$SEN" for-each-ref; ls -A "$SWT"; cat "$SWT/keep.txt"
              ls -d "$T/sentinel-index" "$T/sentinel-common" "$T/sentinel-objects" "$T/sentinel-alt" 2>/dev/null || true; }
sen_before=$(sen_state)
mk_project envapp "$VER"
BE="$T/bare-env.git"; mk_bare "$BE"
# All seven variables the script clears; the four path ones point at sentinel
# paths that must stay absent, GIT_NAMESPACE must not prefix the pushed refs.
export GIT_DIR="$SEN" GIT_WORK_TREE="$SWT" GIT_INDEX_FILE="$T/sentinel-index" \
       GIT_COMMON_DIR="$T/sentinel-common" GIT_OBJECT_DIRECTORY="$T/sentinel-objects" \
       GIT_ALTERNATE_OBJECT_DIRECTORIES="$T/sentinel-alt" GIT_NAMESPACE=sentinelns
run_ggr "$T/envapp" "$BE" --skip-api
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
sen_after=$(sen_state)
if [ "$sen_after" = "$sen_before" ] && [ -z "$(git -C "$BE" for-each-ref refs/namespaces)" ]; then sen_same=1; else sen_same=0; fi
check_published "$BE" envapp "19a: all seven GIT_* vars exported at sentinels → publish still lands on the remote"
if [ "$sen_same" = 1 ]; then
    ok "19b: sentinel repo/work tree untouched, sentinel index/common/objects/alt paths absent, no namespaced refs"
else fail "19b: sentinel changed"; diff <(printf '%s\n' "$sen_before") <(printf '%s\n' "$sen_after") | sed 's/^/    | /'; fi

# --- 20: non-regular entries (symlinks, even dangling) are refused before any network git ---
mk_project linkapp "$VER"
LRD="$T/linkapp/Release/linkapp-$VER"
ln -s install.sh "$LRD/extra"
: > "$T/git.log"
run_ggr "$T/linkapp" "$B" --skip-api
if [ "$RC" = 1 ] && has_line "$OUT" "❌ non-regular entries in $LRD: extra" && no_net_git; then
    ok "20: unlisted symlink extra -> install.sh → exit 1 ❌ non-regular, no git network call"
else fail "20: unlisted symlink (rc=$RC)"; show; fi
rm -f "$LRD/extra"; ln -s nowhere "$LRD/dang"
: > "$T/git.log"
run_ggr "$T/linkapp" "$B" --skip-api
if [ "$RC" = 1 ] && has_line "$OUT" "❌ non-regular entries in $LRD: dang" && no_net_git; then
    ok "20b: dangling symlink → exit 1 ❌ non-regular, no git network call"
else fail "20b: dangling symlink (rc=$RC)"; show; fi
rm -f "$LRD/dang"

# --- 21: checksums.txt lists a file missing from the dir → refused before hashing ---
mk_project missapp "$VER"
MRD="$T/missapp/Release/missapp-$VER"
rm -f "$MRD/RELEASE_NOTES.md"
: > "$T/git.log"; : > "$T/shasum.log"
run_ggr "$T/missapp" "$B" --skip-api
if [ "$RC" = 1 ] && has "$OUT" "❌ checksums.txt line " && has "$OUT" "'./RELEASE_NOTES.md' is not a regular file in $MRD" \
   && no_net_git && [ ! -s "$T/shasum.log" ]; then
    ok "21: manifest lists a file absent from the dir → exit 1 ❌ naming it, no hashing, no git network call"
else fail "21: listed-but-missing file (rc=$RC)"; show; fi

# --- 25: tampered manifest paths are refused BEFORE any checksum tool runs
# (shasum would block on /dev/zero, a FIFO or stdin) ---
mk_project manapp "$VER"
NRD="$T/manapp/Release/manapp-$VER"
cp "$NRD/checksums.txt" "$T/manifest.keep"
Z64=0000000000000000000000000000000000000000000000000000000000000000
mkfifo "$T/manapp/Release/outside.txt"
# man_case LABEL LINE EXPECTED_FRAGMENT [extra setup already done]
man_case() {
    cp "$T/manifest.keep" "$NRD/checksums.txt"
    [ -z "$2" ] || printf '%s\n' "$2" >> "$NRD/checksums.txt"
    : > "$T/git.log"; : > "$T/shasum.log"
    run_ggr "$T/manapp" "$B" --skip-api
    if [ "$RC" = 1 ] && has "$OUT" "$3" && no_net_git && [ ! -s "$T/shasum.log" ]; then
        ok "$1 → exit 1 ❌ naming the entry, shasum never ran, no git network call"
    else fail "$1 (rc=$RC, shasum calls=$(wc -l < "$T/shasum.log" | tr -d ' '))"; show; fi
}
man_case "25a: manifest lists /dev/zero" "$Z64  /dev/zero" "unsafe path '/dev/zero' in $NRD"
man_case "25b: manifest lists ../outside.txt (a FIFO outside the dir)" "$Z64  ../outside.txt" "unsafe path '../outside.txt' in $NRD"
man_case "25c: manifest lists - (stdin)" "$Z64  -" "unsafe path '-' in $NRD"
man_case "25d: manifest lists an existing path twice" "$(grep -m1 'install.sh' "$T/manifest.keep")" "duplicate entry 'install.sh' in $NRD"
# 25e: a listed path that is a symlink to a regular file (dir gate names it first)
ln -s install.sh "$NRD/alias.sh"
man_case "25e: listed symlink alias.sh -> install.sh" "$Z64  alias.sh" "❌ non-regular entries in $NRD: alias.sh"
rm -f "$NRD/alias.sh" "$T/manapp/Release/outside.txt"
cp "$T/manifest.keep" "$NRD/checksums.txt"
# 25f: ggr_manifest_check on its own also refuses a listed symlink (defence in depth)
ln -s install.sh "$NRD/alias.sh"; printf '%s  alias.sh\n' "$Z64" >> "$NRD/checksums.txt"
o25=$(cd "$T" && bash -c 'set -euo pipefail; eval "$(awk "/^ggr_manifest_check\\(\\)/,/^\\}/" "$1")"; ggr_manifest_check "$2"' _ "$GGR" "$NRD" 2>&1) && r25=0 || r25=$?
if [ "$r25" = 1 ] && has "$o25" "'alias.sh' is not a regular file in $NRD"; then
    ok "25f: ggr_manifest_check extracted alone refuses a listed symlink"
else fail "25f: manifest check on a symlink (rc=$r25): $o25"; fi
rm -f "$NRD/alias.sh"; cp "$T/manifest.keep" "$NRD/checksums.txt"

# --- 26: NUL bytes in checksums.txt are refused before any checksum tool runs
# (read -r drops a NUL, a C hashing tool stops at it: `-<NUL>foo` → stdin) ---
nul_case() {
    : > "$T/git.log"; : > "$T/shasum.log"
    run_ggr "$T/manapp" "$B" --skip-api
    if [ "$RC" = 1 ] && has_line "$OUT" "❌ checksums.txt contains NUL bytes in $NRD" && no_net_git && [ ! -s "$T/shasum.log" ]; then
        ok "$1 → exit 1 ❌ NUL bytes, shasum never ran, no git network call"
    else fail "$1 (rc=$RC, shasum calls=$(wc -l < "$T/shasum.log" | tr -d ' '))"; show; fi
}
cp "$T/manifest.keep" "$NRD/checksums.txt"; printf '%s  -\000foo\n' "$Z64" >> "$NRD/checksums.txt"
nul_case "26a: manifest line '<hash>  -<NUL>foo'"
cp "$T/manifest.keep" "$NRD/checksums.txt"; printf '\000' >> "$NRD/checksums.txt"
nul_case "26b: a lone NUL at the end of the manifest"
cp "$T/manifest.keep" "$NRD/checksums.txt"
BN="$T/bare-nul.git"; mk_bare "$BN"
run_ggr "$T/manapp" "$BN" --skip-api
if [ "$RC" = 0 ] && git -C "$BN" rev-parse -q --verify "refs/tags/$VER" >/dev/null; then
    ok "26c: restored manifest → publishes (rc 0, tag $VER on a fresh remote) — the NUL gate passes a clean manifest"
else fail "26c: clean manifest after NUL cases (rc=$RC)"; show; fi

# --- 27: any .git entry (file or dir, any case, any depth) is refused before
# hashing — cp -R would merge it into the publish repo's own .git/ ---
mk_project gitapp "$VER"
GRD="$T/gitapp/Release/gitapp-$VER"
cp "$GRD/checksums.txt" "$T/manifest-git.keep"
git_case() {
    : > "$T/git.log"; : > "$T/shasum.log"
    run_ggr "$T/gitapp" "$B" --skip-api
    if [ "$RC" = 1 ] && has "$OUT" "❌ .git entry in $GRD: $2 — refusing" && no_net_git && [ ! -s "$T/shasum.log" ] \
       && [ ! -e "$T/evil.ran" ]; then
        ok "$1 → exit 1 ❌ naming $2, shasum never ran, no filter ran, no git network call"
    else fail "$1 (rc=$RC, evil.ran=$([ -e "$T/evil.ran" ] && echo yes || echo no))"; show; fi
}
mkdir -p "$GRD/.git/info"
printf '[filter "evil"]\n\tclean = touch \\"%s/evil.ran\\"\n' "$T" > "$GRD/.git/config"
printf '* filter=evil\n' > "$GRD/.git/info/attributes"
( cd "$GRD" && sha_files .git/config .git/info/attributes >> checksums.txt )
git_case "27a: payload .git/config clean filter + .git/info/attributes, both listed" ".git"
rm -rf "$GRD/.git"; cp "$T/manifest-git.keep" "$GRD/checksums.txt"
mkdir "$GRD/.GIT"
git_case "27b: empty upper-case .GIT dir, not listed" ".GIT"
rmdir "$GRD/.GIT"
mkdir "$GRD/sub"; printf 'gitdir: nowhere\n' > "$GRD/sub/.git"
( cd "$GRD" && sha_files sub/.git >> checksums.txt )
git_case "27c: regular file sub/.git (a gitdir pointer), listed" "sub/.git"
rm -rf "$GRD/sub"; cp "$T/manifest-git.keep" "$GRD/checksums.txt"

# --- 22: committed path set ≠ checksums.txt → no push (ggr_ssh_publish called
# directly, past the dir gate, with a regular file listed nowhere) ---
mk_project pathapp "$VER"
PRD="$T/pathapp/Release/pathapp-$VER"
printf 'unaudited\n' > "$PRD/sneaky.txt"
BP="$T/bare-path.git"; mk_bare "$BP"
r22=$( (. "$GGR"; PROJECT_NAME=pathapp; ggr_ssh_publish "$PRD" "$VER" "$BP" 0 > "$T/out22" 2>&1 && echo 0 || echo "$?") )
if [ "$r22" = 1 ] && grep -qxF "❌ archive path set differs from checksums.txt" "$T/out22" && [ "$(refs_n "$BP")" = 0 ]; then
    ok "22: extra committed path not in checksums.txt → ❌ archive path set differs, remote untouched"
else fail "22: path-set check (rc=$r22, refs=$(refs_n "$BP"))"; sed 's/^/    | /' < "$T/out22"; fi

# --- 23: a stalled git network call is killed at GITX_GITEA_GIT_DEADLINE ---
# Deadline 2 / stall 6: whole-second granularity must not kill a fast
# ls-remote/fetch that merely straddles a second boundary on a loaded runner.
# The shim stalls the git subcommand named by GGR_SLOW_OP.
mkdir -p "$T/slowbin"
printf '#!/bin/sh\ncase " $* " in *" $GGR_SLOW_OP "*) sleep 6 ;; esac\nexec "%s" "$@"\n' "$T/bin/git" > "$T/slowbin/git"
chmod +x "$T/slowbin/git"
# slow_case OP PROJECT BARE — sets RC / OUT / el.
slow_case() {
    local sp=$PATH t0=$SECONDS
    PATH="$T/slowbin:$PATH"
    export GITX_GITEA_GIT_DEADLINE=2 GGR_SLOW_OP="$1"
    run_ggr "$2" "$3" --skip-api
    unset GITX_GITEA_GIT_DEADLINE GGR_SLOW_OP
    PATH=$sp
    el=$((SECONDS - t0))
}
mk_project slowapp "$VER"
BW="$T/bare-slow.git"; mk_bare "$BW"
slow_case push "$T/slowapp" "$BW"
if [ "$RC" = 1 ] && has_line "$OUT" "❌ git push timed out after 2s" && [ "$el" -lt 20 ] \
   && ! git -C "$BW" rev-parse -q --verify "refs/tags/$VER" >/dev/null; then
    ok "23: push stalls past GITX_GITEA_GIT_DEADLINE=2 → exit 1 ❌ timed out in ${el}s, remote tag absent"
else fail "23: deadline (rc=$RC, ${el}s)"; show; fi
slow_case ls-remote "$T/slowapp" "$BW"
if [ "$RC" = 1 ] && has_line "$OUT" "❌ git ls-remote timed out after 2s" && has "$OUT" "❌ cannot reach $BW" \
   && [ "$el" -lt 20 ] && [ "$(refs_n "$BW")" = 0 ]; then
    ok "23b: ls-remote stalls past the deadline → exit 1 ❌ timed out in ${el}s, remote untouched"
else fail "23b: ls-remote deadline (rc=$RC, ${el}s)"; show; fi

# --- 24: INT / TERM reaching the shell that runs ggr_run_deadline takes the
# running command AND its grandchild down (a background job would otherwise be
# orphaned). The helper runs under `set -m`: an async job of a non-interactive
# shell starts with SIGINT ignored and could not trap it, whereas the real
# publish subshell runs in the foreground.
cat > "$T/sig24.sh" <<'SIG'
set -m
( . "$1"; ggr_run_deadline 60 sh -c 'sleep 30 & echo $! > "$1"; echo $$ >> "$1"; exec sleep 30' _ "$2" ) &
w=$!
n=0
while [ "$(wc -l < "$2" 2>/dev/null | tr -d ' ')" != 2 ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n+1)); done
kill -"$3" "$w"
wait "$w"
SIG
for sig in INT TERM; do
    pf="$T/pids24-$sig"; rm -f "$pf"
    bash "$T/sig24.sh" "$GGR" "$pf" "$sig" >/dev/null 2>&1
    pids=$(tr '\n' ' ' < "$pf" 2>/dev/null || true)
    alive=""
    n=0
    while :; do
        alive=""
        for p in $pids; do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
        [ -n "$alive" ] && [ "$n" -lt 50 ] || break
        sleep 0.1; n=$((n+1))
    done
    if [ "$(wc -w <<<"$pids" | tr -d ' ')" = 2 ] && [ -z "$alive" ]; then
        ok "24: $sig to the waiting shell → child and grandchild both killed, nothing orphaned"
    else
        fail "24: $sig — survivors:${alive:- none} (pids: ${pids:-unrecorded})"
        for p in $alive; do kill -KILL "$p" 2>/dev/null; done
    fi
done
# fast command: real status still returned
r24=$( (. "$GGR"; ggr_run_deadline 5 sh -c 'exit 7' && echo 0 || echo "$?") )
if [ "$r24" = 7 ]; then ok "24b: ggr_run_deadline returns the command's own status (7)"
else fail "24b: fast command status '$r24'"; fi

# ══ Task 2: Gitea Release API phase — recording mock curl + ~/.netrc ══
# The mock records each call's argv joined by \x1f (one line per call), writes
# EVERY response body to the -o file and prints only the HTTP status. Unknown
# requests print 599 and exit 1, so an unexpected call fails loudly. Control
# files under $T: release-exists, release-assets (asset names the existing
# Release already has, one per line), asset-checksums (body of the Release's
# checksums.txt download; absent → 404), fail-release, release-noid, fail-asset
# (holds the asset name to fail). The last --data-binary @file is kept as body.json.
cat > "$T/bin/curl" <<'MOCK'
#!/bin/sh
T=$(cd "$(dirname "$0")/.." && pwd)
US=$(printf '\037')
out=""; m=GET; url=""; prev=""; line=""; first=1
for a in "$@"; do
    if [ "$first" = 1 ]; then line="$a"; first=0; else line="$line$US$a"; fi
    case "$prev" in
        -o) out="$a" ;;
        -X) m="$a" ;;
        --data-binary) case "$a" in @*) cp "${a#@}" "$T/body.json" ;; esac ;;
    esac
    case "$a" in https://*) url="$a" ;; esac
    prev="$a"
done
printf '%s\n' "$line" >> "$T/curl.log"
code=599; body='{}'
case "$m $url" in
    "GET "*/releases/tags/*)
        code=404
        if [ -e "$T/release-exists" ]; then
            code=200; body='{"id":90,"tag_name":"x","name":"x v1","assets":['; sep=''
            if [ -f "$T/release-assets" ]; then
                while IFS= read -r an; do
                    body="$body$sep{\"id\":5,\"name\":\"$an\"}"; sep=','
                done < "$T/release-assets"
            fi
            body="$body]}"
        fi ;;
    "DELETE "*/releases/90) code=204; body='' ;;
    "GET "*/releases/download/*/checksums.txt)
        code=404; body='Not Found'
        if [ -f "$T/asset-checksums" ]; then code=200; body=$(cat "$T/asset-checksums"; printf x); body="${body%x}"; fi ;;
    "POST "*/releases/90/assets\?name=*)
        code=201
        if [ -f "$T/fail-asset" ] && [ "${url##*name=}" = "$(cat "$T/fail-asset")" ]; then code=500; fi ;;
    "POST "*/releases)
        code=201; body='{"id":90,"author":{"id":7}}'
        if [ -e "$T/fail-release" ]; then code=500; body='{"message":"boom"}'; fi
        if [ -e "$T/release-noid" ]; then body='{"message":"ok"}'; fi ;;
esac
if [ -n "$out" ]; then printf '%s' "$body" > "$out"; fi
printf '%s' "$code"
[ "$code" != 599 ]
MOCK
chmod +x "$T/bin/curl"
export GITX_GITEA_CURL="$T/bin/curl"
NETRC="$T/home/.netrc"
US=$(printf '\037')
ALL_OUT=""; : > "$T/curl.all"

# calls — "METHOD URL" for each recorded curl call, in order.
calls() {
    awk -v FS="$US" '{ m = "GET"; u = ""
        for (i = 1; i <= NF; i++) { if ($i == "-X") m = $(i + 1); if ($i ~ /^https:\/\//) u = $i }
        print m " " u }' "$T/curl.log"
}
# run_api PROJECT BARE ARGS… — run_ggr on a fresh curl.log; every output and
# every recorded call is also kept for the cross-case asserts (e) and (f).
run_api() {
    : > "$T/curl.log"; rm -f "$T/body.json"
    run_ggr "$@"
    ALL_OUT="$ALL_OUT$OUT"$'\n'
    cat "$T/curl.log" >> "$T/curl.all"
}
show_calls() { sed 's/^/    > /' < "$T/curl.log" | tr '\037' ' '; }

AN=apiapp
PA="$T/$AN"
mk_project "$AN" "$VER"
BA="$T/bare-api.git"; mk_bare "$BA"
API="https://$HOSTX/api/v1/repos/my-releases/$AN"
REL_URL="🔗 release: https://$HOSTX/my-releases/$AN/releases/tag/$VER"
SKIP_LINE="⚠️ no ~/.netrc entry for $HOSTX — skipping Gitea Release (tag + archive are published)"
ASSET_CALLS="POST $API/releases/90/assets?name=$AN-$VER.skill
POST $API/releases/90/assets?name=$AN-$VER-full.tar.gz
POST $API/releases/90/assets?name=checksums.txt
POST $API/releases/90/assets?name=install.sh"

# --- a: no ~/.netrc → ⚠️ skip, no curl call, exit 0 (SSH publish still done) ---
rm -f "$NETRC"
run_api "$PA" "$BA"
if [ "$RC" = 0 ] && has_line "$OUT" "$SKIP_LINE" && [ ! -s "$T/curl.log" ] \
   && has_line "$OUT" "✅ pushed $AN $VER → $BA" \
   && has_line "$OUT" "🔗 repo: https://$HOSTX/my-releases/$AN" \
   && has_line "$OUT" "📦 install: git clone --depth 1 --branch $VER ssh://git${AT}$HOSTX:2222/my-releases/$AN.git $AN-$VER && cd $AN-$VER && shasum -a 256 -c checksums.txt && ./install.sh" \
   && ! has "$OUT" "$REL_URL"; then
    ok "a: no ~/.netrc → ⚠️ skip line, zero curl calls, exit 0, repo URL + install one-liner"
else fail "a: no netrc (rc=$RC)"; show; show_calls; fi

# --- a3: only look-alike netrc entries (dots unescaped would match) → still skip ---
printf 'machine gitXexampleXinternal login x password y\nmachine %s.evil login x password y\n#machine %s\n' \
    "$HOSTX" "$HOSTX" > "$NETRC"
run_api "$PA" "$BA"
if [ "$RC" = 0 ] && has_line "$OUT" "$SKIP_LINE" && [ ! -s "$T/curl.log" ]; then
    ok "a3: look-alike netrc hosts (unescaped dots, suffix, comment) do not count as an entry"
else fail "a3: look-alike netrc (rc=$RC)"; show; show_calls; fi

# --- a2: no netrc entry + --force → ❌ refusing, exit 1, nothing pushed ---
BA2="$T/bare-api2.git"; mk_bare "$BA2"
: > "$T/git.log"
run_api "$PA" "$BA2" --force
if [ "$RC" = 1 ] \
   && has_line "$OUT" "❌ refusing --force: no ~/.netrc entry for $HOSTX — the existing Gitea Release would go stale" \
   && [ "$(refs_n "$BA2")" = 0 ] && no_net_git && [ ! -s "$T/curl.log" ]; then
    ok "a2: --force without a netrc entry → exit 1 ❌ refusing, no git network call, bare repo untouched"
else fail "a2: --force without netrc (rc=$RC, refs=$(refs_n "$BA2"))"; show; fi

printf '  machine %s\n  login x\n  password y\n' "$HOSTX" > "$NETRC"

# --- b: netrc present, release absent → GET, POST release, 4× POST assets ---
run_api "$PA" "$BA"
exp_b="GET $API/releases/tags/$VER
POST $API/releases
$ASSET_CALLS"
if [ "$RC" = 0 ] && [ "$(calls)" = "$exp_b" ] && has_line "$OUT" "✅ release $VER created (4 assets)" \
   && has_line "$OUT" "$REL_URL" && [ "$(grep -c "${US}-F${US}attachment=@" "$T/curl.log")" = 4 ] \
   && grep -q "${US}Content-Type: application/json${US}--data-binary${US}@" "$T/curl.log"; then
    ok "b: release absent → GET, POST release (JSON file body), 4 asset POSTs in order with ?name=, ✅ + release URL"
else fail "b: happy path (rc=$RC)"; show; show_calls; fi
cp "$T/curl.log" "$T/curl.happy"

# --- c: release exists with all 4 assets, no --force → GET + checksums download, ℹ️, exit 0 ---
DL_CALL="GET https://$HOSTX/my-releases/$AN/releases/download/$VER/checksums.txt"
: > "$T/release-exists"
cp "$PA/Release/$AN-$VER/checksums.txt" "$T/asset-checksums"
printf '%s\n' "$AN-$VER.skill" "$AN-$VER-full.tar.gz" checksums.txt install.sh > "$T/release-assets"
run_api "$PA" "$BA"
if [ "$RC" = 0 ] && [ "$(calls)" = "GET $API/releases/tags/$VER
$DL_CALL" ] \
   && has_line "$OUT" "ℹ️ release $VER already exists" && has_line "$OUT" "$REL_URL"; then
    ok "c: release exists with all 4 assets + identical checksums.txt asset → GET + download only, ℹ️ already exists, exit 0"
else fail "c: release exists (rc=$RC)"; show; show_calls; fi

# --- c7: release exists, its checksums.txt asset differs → stale, exit 1, no upload ---
printf 'stale\n' > "$T/asset-checksums"
run_api "$PA" "$BA"
if [ "$RC" = 1 ] && [ "$(calls)" = "GET $API/releases/tags/$VER
$DL_CALL" ] \
   && has_line "$OUT" "❌ Gitea Release $VER assets are stale relative to tag $VER (checksums.txt differs) — re-run with --force to recreate"; then
    ok "c7: existing Release whose checksums.txt asset differs → exit 1 ❌ stale, no uploads"
else fail "c7: stale assets (rc=$RC)"; show; show_calls; fi

# --- c8: release exists with NO assets, checksums.txt download 404 → all four uploaded ---
rm -f "$T/asset-checksums" "$T/release-assets"
run_api "$PA" "$BA"
if [ "$RC" = 0 ] && [ "$(calls)" = "GET $API/releases/tags/$VER
$DL_CALL
$ASSET_CALLS" ] \
   && has_line "$OUT" "✅ release $VER completed (4 missing asset(s) uploaded)"; then
    ok "c8: empty Release + checksums.txt download 404 → all 4 assets uploaded, ✅ completed"
else fail "c8: 404 on an empty release (rc=$RC)"; show; show_calls; fi

# --- c8b: checksums.txt download 404 but other assets present → stale, exit 1, no upload ---
printf '%s\n' "$AN-$VER.skill" install.sh > "$T/release-assets"
run_api "$PA" "$BA"
if [ "$RC" = 1 ] && [ "$(calls)" = "GET $API/releases/tags/$VER
$DL_CALL" ] \
   && has_line "$OUT" "❌ Gitea Release $VER assets are stale relative to tag $VER (checksums.txt asset missing) — re-run with --force to recreate"; then
    ok "c8b: 404 on checksums.txt + other assets present → exit 1 ❌ stale, no uploads"
else fail "c8b: 404 with other assets (rc=$RC)"; show; show_calls; fi
cp "$PA/Release/$AN-$VER/checksums.txt" "$T/asset-checksums"

# --- c5: release exists with 2 of 4 assets → GET + download + exactly the 2 missing uploads ---
printf '%s\n' "$AN-$VER.skill" checksums.txt > "$T/release-assets"
run_api "$PA" "$BA"
if [ "$RC" = 0 ] && [ "$(calls)" = "GET $API/releases/tags/$VER
$DL_CALL
POST $API/releases/90/assets?name=$AN-$VER-full.tar.gz
POST $API/releases/90/assets?name=install.sh" ] \
   && has_line "$OUT" "✅ release $VER completed (2 missing asset(s) uploaded)" && has_line "$OUT" "$REL_URL"; then
    ok "c5: partial Release (2/4 assets) → GET + download + 2 asset POSTs for the missing names, ✅ completed"
else fail "c5: partial release (rc=$RC)"; show; show_calls; fi
rm -f "$T/release-assets"

# --- d: release exists + --force → GET, DELETE …/90, POST, 4 assets ---
run_api "$PA" "$BA" --force
exp_d="GET $API/releases/tags/$VER
DELETE $API/releases/90
POST $API/releases
$ASSET_CALLS"
if [ "$RC" = 0 ] && [ "$(calls)" = "$exp_d" ] && has_line "$OUT" "✅ release $VER created (4 assets)"; then
    ok "d: --force + existing release → DELETE …/releases/90 before POST, then 4 assets"
else fail "d: --force recreate (rc=$RC)"; show; show_calls; fi
rm -f "$T/release-exists" "$T/asset-checksums"

# --- c2: POST release → 500 → exit 1 ❌, no asset call ---
: > "$T/fail-release"
run_api "$PA" "$BA"
if [ "$RC" = 1 ] && [ "$(calls)" = "GET $API/releases/tags/$VER
POST $API/releases" ] && has_line "$OUT" "❌ creating Gitea Release $VER failed (HTTP 500)"; then
    ok "c2: POST release 500 → exit 1 with ❌ line, no asset uploads"
else fail "c2: release POST failure (rc=$RC)"; show; show_calls; fi
rm -f "$T/fail-release"

# --- c4: POST release 201 without an id → exit 1 ❌, no asset call ---
: > "$T/release-noid"
run_api "$PA" "$BA"
if [ "$RC" = 1 ] && [ "$(wc -l < "$T/curl.log" | tr -d ' ')" = 2 ] \
   && has_line "$OUT" "❌ Gitea Release $VER: no release id in the API response — re-run to upload the missing asset(s), or --force to recreate"; then
    ok "c4: release created without an id → exit 1 with ❌ line, no asset uploads"
else fail "c4: missing id (rc=$RC)"; show; show_calls; fi
rm -f "$T/release-noid"

# --- c3: one asset POST → 500 → exit 1 naming that asset ---
printf 'checksums.txt' > "$T/fail-asset"
run_api "$PA" "$BA"
if [ "$RC" = 1 ] && [ "$(wc -l < "$T/curl.log" | tr -d ' ')" = 5 ] \
   && has_line "$OUT" "❌ uploading asset checksums.txt to Gitea Release $VER failed (HTTP 500) — re-run to upload the missing asset(s), or --force to recreate"; then
    ok "c3: asset upload 500 → exit 1 with ❌ line naming checksums.txt, later assets not sent"
else fail "c3: asset failure (rc=$RC)"; show; show_calls; fi
rm -f "$T/fail-asset"

# --- c6: tag exists with different checksums (SSH rc 5), API phase active → exit 1, no curl ---
printf '#!/bin/sh\necho REBUILT\n' > "$PA/Release/$AN-$VER/install.sh"
regen_sums "$PA/Release/$AN-$VER"
run_api "$PA" "$BA"
if [ "$RC" = 1 ] && has "$OUT" "❌ tag $VER exists on $BA but its checksums.txt differs" && [ ! -s "$T/curl.log" ]; then
    ok "c6: SSH says tag differs (5) with netrc + mock curl → exit 1, zero curl calls"
else fail "c6: rc 5 with API active (rc=$RC)"; show; show_calls; fi

# --- c9: the review sequence — publish A, --force moves the tag to B but the
# Release step fails (modelled by --skip-api), so the Release keeps A's assets;
# a plain rerun must not report success ---
SN=seqapp
mk_project "$SN" "$VER"
SQD="$T/$SN/Release/$SN-$VER"
BS="$T/bare-seq.git"; mk_bare "$BS"
run_api "$T/$SN" "$BS"
rc9a=$RC
cp "$SQD/checksums.txt" "$T/asset-checksums"
printf '#!/bin/sh\necho VERSION-B\n' > "$SQD/install.sh"
regen_sums "$SQD"
run_api "$T/$SN" "$BS" --force --skip-api
rc9b=$RC
: > "$T/release-exists"
printf '%s\n' "$SN-$VER.skill" "$SN-$VER-full.tar.gz" checksums.txt install.sh > "$T/release-assets"
run_api "$T/$SN" "$BS"
if [ "$rc9a" = 0 ] && [ "$rc9b" = 0 ] && [ "$RC" = 1 ] \
   && has_line "$OUT" "ℹ️ already published: tag $VER exists on $BS (use --force to replace)" \
   && has "$OUT" "❌ Gitea Release $VER assets are stale relative to tag $VER" \
   && ! grep -q "${US}POST${US}" "$T/curl.log"; then
    ok "c9: publish A, --force to B without the Release step, plain rerun → exit 1 ❌ stale (not success), no uploads"
else fail "c9: stale-after-failed-force sequence (rc=$rc9a/$rc9b/$RC)"; show; show_calls; fi
rm -f "$T/release-exists" "$T/release-assets" "$T/asset-checksums"

# --- j1/j2: JSON request body — RELEASE_NOTES.md with ", \, a tab, newlines ---
JN=notesapp
mk_project "$JN" "$VER"
JRD="$T/$JN/Release/$JN-$VER"
printf '# %s "quoted" \\ back\\slash\ttab\n\nline 2 \\n literal\n' "$JN" > "$JRD/RELEASE_NOTES.md"
regen_sums "$JRD"
BJ="$T/bare-notes.git"; mk_bare "$BJ"
# json_check FILE EXPECTED_BODY_FILE — 0 when FILE parses and matches the contract.
json_check() {
    python3 -I -c 'import json,sys
d = json.load(open(sys.argv[1]))
want = open(sys.argv[2]).read()
ok = (d["body"] == want and d["name"] == sys.argv[3] + " " + sys.argv[4]
      and d["tag_name"] == sys.argv[4] and d["draft"] is False and d["prerelease"] is False)
sys.exit(0 if ok else 1)' "$1" "$2" "$JN" "$VER"
}
PY_OK=0; python3 -I -c 'pass' >/dev/null 2>&1 && PY_OK=1
run_api "$T/$JN" "$BJ"
if [ "$RC" = 0 ] && [ -f "$T/body.json" ]; then
    if [ "$PY_OK" = 1 ]; then
        if json_check "$T/body.json" "$JRD/RELEASE_NOTES.md"; then
            ok "j1: python3 present → request body is valid JSON carrying RELEASE_NOTES.md verbatim"
        else fail "j1: body JSON mismatch"; sed 's/^/    | /' < "$T/body.json"; fi
    else echo "  ➖ j1: python3 unusable in this test env — JSON parse assertion skipped"; fi
else fail "j1: notes publish (rc=$RC)"; show; show_calls; fi
# A python3 shim that exits 127 hides python3 from the script (the release dir
# check uses shasum/sha256sum, which never needs python3).
mkdir -p "$T/nopy"; printf '#!/bin/sh\nexit 127\n' > "$T/nopy/python3"; chmod +x "$T/nopy/python3"
printf 'Release artifacts for %s %s. Verify with checksums.txt, then run install.sh.' "$JN" "$VER" > "$T/fixed.txt"
SAVED_PATH=$PATH; PATH="$T/nopy:$PATH"
run_api "$T/$JN" "$BJ"
PATH=$SAVED_PATH
if [ "$RC" = 0 ] && [ -f "$T/body.json" ] && has_line "$OUT" "✅ release $VER created (4 assets)"; then
    if [ "$PY_OK" = 1 ]; then
        if json_check "$T/body.json" "$T/fixed.txt"; then
            ok "j2: python3 hidden → valid JSON with the fixed one-line body (no hand escaping)"
        else fail "j2: fallback body mismatch"; sed 's/^/    | /' < "$T/body.json"; fi
    else echo "  ➖ j2: python3 unusable in this test env — JSON parse assertion skipped"; fi
else fail "j2: python3-hidden publish (rc=$RC)"; show; show_calls; fi

# --- e: the netrc fixture secret never reaches stdout/stderr ---
if [ -n "$ALL_OUT" ] && ! has "$ALL_OUT" 'password y' && ! has "$ALL_OUT" 'login x'; then
    ok "e: no run printed the netrc login/password"
else fail "e: netrc content leaked into output"; fi

# --- f: every curl call starts with -q (no ~/.curlrc), carries -n,
# --connect-timeout, -m; none -k/--insecure ---
f_bad=""; f_n=0
while IFS= read -r l; do
    f_n=$((f_n+1))
    fields=$(tr '\037' '\n' <<<"$l")
    [ "${l%%"$US"*}" = -q ] || f_bad="$f_bad call$f_n:argv1-not-q"
    for need in -n --connect-timeout -m; do
        grep -qxF -- "$need" <<<"$fields" || f_bad="$f_bad call$f_n:no$need"
    done
    if grep -qxE -- '-k|--insecure' <<<"$fields"; then f_bad="$f_bad call$f_n:insecure"; fi
done < "$T/curl.all"
if [ -z "$f_bad" ] && [ "$f_n" -ge 20 ]; then
    ok "f: all $f_n recorded curl calls start with -q, carry -n --connect-timeout -m, never -k/--insecure"
else fail "f: argv contract (calls=$f_n) — $(cut -c1-200 <<<"$f_bad")"; fi

# --- 18: extraction contract — ggr_netrc_has_host + ggr_api_publish alone ---
r18=$(cd "$T" && PROJECT_NAME="$AN" bash -c 'set -euo pipefail
for fn in ggr_netrc_has_host ggr_api_publish; do eval "$(awk "/^${fn}\\(\\)/,/^\\}/" "$1")"; done
ggr_api_publish "$2" "$3" "$4" "$5" 0 >/dev/null 2>&1 && echo 0 || echo "$?"' \
    _ "$GGR" "$PA/Release/$AN-$VER" "$VER" "$HOSTX" "my-releases/$AN" 2>&1) || true
if [ "$r18" = 0 ]; then
    ok "18: ggr_netrc_has_host + ggr_api_publish extracted alone (awk+eval) create the release"
else fail "18: extracted ggr_api_publish rc='$r18'"; fi

echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ]
