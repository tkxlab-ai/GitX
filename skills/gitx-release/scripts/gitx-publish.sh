#!/bin/bash
# gitx-publish.sh — make an approved release public in one human-gated command:
#   step 0 preflight (read-only) → 1 GitHub Release draft → public (+ re-assert
#   Latest) → 2 central marketplace bump → 3 npm publish.
# usage: gitx-publish.sh --version vX.Y.Z [--repo OWNER/REPO] [--dry-run] [--help]
# exit:  0 done / every step already done / dry-run, 1 failure (rerun the same
#        command after fixing — finished steps report ℹ️), 2 usage error
#
# Why one command, and why every check comes first: an npm version can never be
# re-used and a version is often re-cut locally, so nothing may go out until
# every check — GitHub draft assets, GitHub main VERSION, GitHub tag snapshot,
# npm identity / state / pack contents / sanitize — has passed. Any answer that
# cannot be classified counts as a failure, never as "absent" or "done".
#
# Inputs: Release/<PROJECT_NAME>-vX.Y.Z/ (checksums.txt, <proj>-vX.Y.Z.skill,
#   <proj>-vX.Y.Z-source.tar.gz); GitHub repo from --repo, else
#   .claude-plugin/plugin.json .repository, else a github.com `origin` remote
#   (downstream projects often have neither of the first two); switches .gitx/marketplace-target and .gitx/npm-target (one
#   line: the npm package name). The npm package is packed from the EXTRACTED
#   source tarball (git-tracked content only), never from the working tree.
# Test seams (environment): GH_BIN (default gh), NPM_BIN (default npm),
#   MARKETPLACE_BIN (default gitx-marketplace.sh next to this script).
# No npm token is read or printed; npm asks for a one-time password itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH="${GH_BIN:-gh}"
NPM="${NPM_BIN:-npm}"
MKT="${MARKETPLACE_BIN:-$SCRIPT_DIR/gitx-marketplace.sh}"
REG="https://registry.npmjs.org/"
DONE_STEP=-1

usage() {
    cat <<'EOF'
Usage: gitx-publish.sh --version vX.Y.Z [--repo OWNER/REPO] [--dry-run] [--help]

Run after approving the GitHub draft. Checks everything first, then:
  1. GitHub Release vX.Y.Z draft → public, Latest re-asserted on the highest semver
  2. central marketplace bump (skipped ➖ without .gitx/marketplace-target)
  3. npm publish of the package packed from the source tarball
     (skipped ➖ without .gitx/npm-target)

  --repo      GitHub OWNER/REPO (default: .claude-plugin/plugin.json
              .repository, else a github.com `origin` remote).
  --dry-run   Run every check and print the plan; write nothing.
Exit: 0 done / already done / dry-run   1 failure (fix, then rerun)   2 usage
EOF
}

# die MSG — report where the run stopped; finished steps are skipped on rerun.
die() {
    echo "❌ $1" >&2
    if [ "$DONE_STEP" -lt 0 ]; then
        echo "   尚未执行任何远端写操作；修复后重跑同一命令。" >&2
    else
        echo "   已完成到第 $DONE_STEP 步，修复后重跑同一命令。" >&2
    fi
    exit 1
}

# repo_slug URL — OWNER/REPO from a github.com URL (https, ssh or scp form) or
# a bare OWNER/REPO; empty if not one. Matched with [[ =~ ]], not a line-based
# grep, so a value with an embedded newline or control char is rejected whole.
repo_slug() {
    # `at` keeps scp/ssh remote literals out of the source: user@host is
    # email-shaped and trips release-sanitize's EMAIL scan (Gotcha #83).
    local u="${1#git+}" re='^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$' at='@'
    u="${u%/}"; u="${u%.git}"
    u="${u#https://github.com/}"; u="${u#ssh://git${at}github.com/}"; u="${u#git${at}github.com:}"
    case "$u" in *..*|*[![:print:]]*) return 0 ;; esac
    if [[ $u =~ $re ]]; then printf '%s\n' "$u"; fi
}

# single_dir DIR — the only entry of DIR, if it is a directory.
single_dir() {
    local n
    n=$(find "$1" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
    [ "$n" = 1 ] || return 1
    find "$1" -mindepth 1 -maxdepth 1 -type d
}

# in_whitelist PATH — npm package members allowed to ship (path inside package/).
in_whitelist() {
    case "$1" in
        package.json|README.md|LICENSE|opencode/*|"skills/$SKILL_NAME/"*) return 0 ;;
    esac
    return 1
}

VERSION_ARG=""; DRY=0; REPO_ARG=""; HAVE_REPO_ARG=0
while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION_ARG="${2:-}"; [ $# -ge 2 ] && shift; shift ;;
        --version=*) VERSION_ARG="${1#--version=}"; shift ;;
        --repo) REPO_ARG="${2:-}"; HAVE_REPO_ARG=1; [ $# -ge 2 ] && shift; shift ;;
        --repo=*) REPO_ARG="${1#--repo=}"; HAVE_REPO_ARG=1; shift ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "❌ unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done
[ -n "$VERSION_ARG" ] || { echo "❌ --version vX.Y.Z is required" >&2; usage >&2; exit 2; }
VER="v${VERSION_ARG#v}"
printf '%s\n' "$VER" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    || { echo "❌ version must be vX.Y.Z (got '$VERSION_ARG')" >&2; exit 2; }
NUM="${VER#v}"
REPO=""
if [ "$HAVE_REPO_ARG" = 1 ]; then
    REPO=$(repo_slug "$REPO_ARG")
    [ -n "$REPO" ] && [ "$REPO" = "$REPO_ARG" ] \
        || { echo "❌ --repo must be OWNER/REPO (got '$REPO_ARG')" >&2; exit 2; }
fi

# shellcheck disable=SC2034  # read by the sourced detect-project.sh
PROJECT_ROOT="$(pwd)"
# shellcheck source=lib/detect-project.sh
source "$SCRIPT_DIR/lib/detect-project.sh" || die "cannot resolve PROJECT_NAME / SKILL_NAME"
W=$(mktemp -d)
# bash 3.2 reports rc 0 for a `set -u` abort when an EXIT trap runs, so any
# exit that did not pass through a deliberate success path is forced to 1.
FINISHED=0; _rc=0
trap '_rc=$?; rm -rf "$W"; [ "$_rc" != 0 ] || [ "$FINISHED" = 1 ] || _rc=1; exit "$_rc"' EXIT

echo "▶ 第 0 步：预检（不做任何远端写操作）"
RD="Release/$PROJECT_NAME-$VER"
SRC_TGZ="$RD/$PROJECT_NAME-$VER-source.tar.gz"
# Exactly what the GitHub SOP (7.1) uploads to the draft. The source tarball is
# deliberately not an asset (it carries un-redacted dev narrative); it is held
# to checksums.txt here and to the GitHub tag snapshot below instead.
ASSETS="checksums.txt $PROJECT_NAME-$VER.skill sbom.cyclonedx.json"
for f in $ASSETS "$PROJECT_NAME-$VER-source.tar.gz"; do
    [ -f "$RD/$f" ] || die "missing local artifact $RD/$f — build the release first"
done
if command -v shasum >/dev/null 2>&1; then SUMCHK="shasum -a 256 -c"; else SUMCHK="sha256sum -c"; fi
# shellcheck disable=SC2086  # SUMCHK is a command plus flags
( cd "$RD" && $SUMCHK checksums.txt ) > "$W/sum.log" 2>&1 \
    || die "local $RD fails its checksums.txt: $(grep -v ': OK$' "$W/sum.log" | head -c 300)"
# `-c` verifies only what is listed, so an unlisted artifact (e.g. the SBOM)
# would go out unchecked; every shipped file must be listed.
for f in "$PROJECT_NAME-$VER.skill" sbom.cyclonedx.json "$PROJECT_NAME-$VER-source.tar.gz"; do
    awk -v f="$f" '$2 == f || $2 == "*" f {found=1} END {exit !found}' "$RD/checksums.txt" \
        || die "$f is not listed in $RD/checksums.txt — rebuild the release"
done
if [ -z "$REPO" ]; then
    REPO_URL=""
    [ ! -f .claude-plugin/plugin.json ] \
        || REPO_URL=$(jq -r '.repository | if type == "object" then .url else . end // empty' .claude-plugin/plugin.json 2>/dev/null || true)
    if [ -n "$REPO_URL" ]; then
        REPO=$(repo_slug "$REPO_URL")
        [ -n "$REPO" ] || die "plugin.json .repository is not a github.com repo: '$REPO_URL' — pass --repo OWNER/REPO"
    else
        ORIGIN=$(git remote get-url origin 2>/dev/null || true)
        REPO=$(repo_slug "$ORIGIN")
        [ -n "$REPO" ] || die "no GitHub repo: plugin.json has no .repository and origin is not github.com — pass --repo OWNER/REPO"
    fi
fi
echo "  GitHub 仓库：$REPO"

# GitHub Release exists (draft, or already public on a rerun) with our bytes.
VIEW=$("$GH" release view "$VER" --repo "$REPO" --json isDraft,assets 2>"$W/gh.err") \
    || die "GitHub Release $VER not found on $REPO (or gh failed): $(head -c 300 "$W/gh.err")"
IS_DRAFT=$(printf '%s' "$VIEW" | jq -r '.isDraft' 2>/dev/null || true)
case "$IS_DRAFT" in true|false) ;; *) die "cannot read isDraft of GitHub Release $VER" ;; esac
# The remote asset set must be exactly $ASSETS: a missing asset would publish an
# incomplete Release, an extra one something nobody audited.
HAVE=$(printf '%s' "$VIEW" | jq -r '.assets[].name' 2>/dev/null | LC_ALL=C sort || true)
WANT=$(printf '%s\n' $ASSETS | LC_ALL=C sort)
[ "$HAVE" = "$WANT" ] || die "GitHub Release $VER assets [$(echo $HAVE)] ≠ expected [$(echo $WANT)]"
mkdir -p "$W/assets"
"$GH" release download "$VER" --repo "$REPO" --dir "$W/assets" >/dev/null 2>"$W/gh.err" \
    || die "cannot download assets of GitHub Release $VER: $(head -c 300 "$W/gh.err")"
for n in $ASSETS; do
    [ -f "$W/assets/$n" ] || die "GitHub asset $n did not download"
    cmp -s "$W/assets/$n" "$RD/$n" || die "GitHub asset $n differs from local $RD/$n — re-upload the draft assets"
done
echo "  ✅ GitHub Release $VER 存在（draft=${IS_DRAFT}），附件与本地逐字节一致"

# Plugin marketplaces install from main, so main must already carry VER.
MAIN_V=$("$GH" api "repos/$REPO/contents/VERSION?ref=main" -H 'Accept: application/vnd.github.raw' 2>"$W/gh.err" \
    | tr -d '[:space:]') || die "cannot read VERSION on GitHub main: $(head -c 300 "$W/gh.err")"
[ "${MAIN_V#v}" = "$NUM" ] || die "GitHub main VERSION is '$MAIN_V', expected $VER — push main first"
echo "  ✅ GitHub main VERSION = $VER"

# The local source tarball (what npm packs) must equal the GitHub tag snapshot
# in every npm-relevant path — a same-version re-cut must not drift silently.
mkdir -p "$W/src" "$W/tag"
tar -xzf "$SRC_TGZ" -C "$W/src" 2>/dev/null || die "cannot extract $SRC_TGZ"
SRC="$W/src/$PROJECT_NAME-$VER"
[ -d "$SRC" ] && [ "$(single_dir "$W/src" || true)" = "$SRC" ] \
    || die "$SRC_TGZ must hold exactly one top dir $PROJECT_NAME-$VER/"
"$GH" api "repos/$REPO/tarball/$VER" > "$W/tag.tgz" 2>"$W/gh.err" \
    || die "cannot download GitHub tag $VER snapshot: $(head -c 300 "$W/gh.err")"
tar -xzf "$W/tag.tgz" -C "$W/tag" 2>/dev/null || die "cannot extract GitHub tag $VER snapshot"
TAG=$(single_dir "$W/tag" || true)
[ -n "$TAG" ] || die "GitHub tag $VER snapshot has no single top dir"
for p in package.json opencode "skills/$SKILL_NAME"; do
    [ -e "$SRC/$p" ] || [ -e "$TAG/$p" ] || continue
    diff -r "$SRC/$p" "$TAG/$p" > "$W/diff.txt" 2>&1 \
        || die "local source tarball and GitHub tag $VER differ in $p: $(head -c 300 "$W/diff.txt")"
done
echo "  ✅ GitHub tag $VER 快照与本地源码包（package.json / opencode / skills/${SKILL_NAME}）逐字节一致"

[ ! -L .gitx ] && [ ! -L .gitx/npm-target ] && [ ! -L .gitx/marketplace-target ] \
    || die ".gitx or a switch file in it is a symlink — refusing to read through it"
NPM_PKG=""; NPM_DONE=0; TGZ=""
if [ -f .gitx/npm-target ]; then
    NPM_PKG=$(tr -d '\r' < .gitx/npm-target | grep '[^[:space:]]' || true)
    NAME_OK=$(printf '%s\n' "$NPM_PKG" | grep -cE '^(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$' || true)
    [ "$NAME_OK" = 1 ] && [ "$(printf '%s\n' "$NPM_PKG" | wc -l | tr -d ' ')" = 1 ] \
        || die ".gitx/npm-target must be one line holding an npm package name"
    [ -f "$SRC/package.json" ] || die "source tarball has no package.json"
    PJ_NAME=$(jq -r '.name // empty' "$SRC/package.json" 2>/dev/null || true)
    PJ_VER=$(jq -r '.version // empty' "$SRC/package.json" 2>/dev/null || true)
    [ "$PJ_NAME" = "$NPM_PKG" ] || die "package.json name '$PJ_NAME' ≠ .gitx/npm-target '$NPM_PKG'"
    [ "$PJ_VER" = "$NUM" ] || die "package.json version '$PJ_VER' ≠ $NUM"
    "$NPM" whoami --registry "$REG" >/dev/null 2>"$W/npm.err" \
        || die "npm whoami failed — run: npm login --registry $REG"
    rc=0
    VIEW_OUT=$("$NPM" view "$NPM_PKG@$NUM" version --registry "$REG" 2>"$W/npm.err") || rc=$?
    VIEW_OUT=$(printf '%s' "$VIEW_OUT" | tr -d '[:space:]')
    if [ "$rc" = 0 ] && [ "$VIEW_OUT" = "$NUM" ]; then
        NPM_DONE=1
    elif { [ "$rc" = 0 ] && [ -z "$VIEW_OUT" ]; } || { [ "$rc" != 0 ] && grep -q 'E404' "$W/npm.err"; }; then
        # rc 0 + empty = package exists without this version; E404 = no package yet.
        NPM_DONE=0
    else
        die "cannot tell whether $NPM_PKG@$NUM is on npm: $(head -c 300 "$W/npm.err")"
    fi
fi
if [ -n "$NPM_PKG" ] && [ "$NPM_DONE" = 0 ]; then
    mkdir -p "$W/pack" "$W/pkg"
    ( cd "$SRC" && "$NPM" pack --ignore-scripts --registry "$REG" --pack-destination "$W/pack" ) \
        > "$W/pack.log" 2>&1 || die "npm pack failed: $(tail -c 400 "$W/pack.log")"
    n=$(find "$W/pack" -name '*.tgz' | wc -l | tr -d ' ')
    [ "$n" = 1 ] || die "npm pack produced $n .tgz files, expected 1"
    TGZ=$(find "$W/pack" -name '*.tgz')
    tar -tzf "$TGZ" > "$W/members.txt" 2>/dev/null || die "cannot list $TGZ"
    while IFS= read -r m; do
        rel="${m#package/}"
        [ "$rel" != "$m" ] && in_whitelist "$rel" || die "npm package member outside the whitelist: $m"
    done < "$W/members.txt"
    tar -xzf "$TGZ" -C "$W/pkg" 2>/dev/null || die "cannot extract $TGZ"
    # npm adds root README.md / LICENSE on its own, from the local source
    # tarball, which never went through the public SOP redaction (4.5). So every
    # shipped byte must already be public: each member equals the GitHub tag.
    while IFS= read -r m; do
        rel="${m#package/}"
        [ -f "$TAG/$rel" ] && [ ! -L "$TAG/$rel" ] && cmp -s "$W/pkg/$m" "$TAG/$rel" \
            || die "npm package member $rel differs from (or is missing in) GitHub tag $VER"
    done < "$W/members.txt"
    bash "$SCRIPT_DIR/release-sanitize.sh" --label npm "$W/pkg/package" > "$W/san.log" 2>&1 \
        || { cat "$W/san.log" >&2; die "npm package failed release-sanitize"; }
    echo "  ✅ npm $NPM_PKG@$NUM 待发布：打包 $(wc -l < "$W/members.txt" | tr -d ' ') 个成员，白名单 + 与 tag 逐字节一致 + sanitize 通过"
elif [ -n "$NPM_PKG" ]; then
    echo "  ✅ npm $NPM_PKG@$NUM 已在 registry 上"
fi
# Step 2 runs after the Release is already public, so its preconditions (the
# central entry exists and is valid) are proven here by bump's own read-only
# --dry-run — a missing entry must stop the run before anything goes public.
if [ -f .gitx/marketplace-target ]; then
    [ -x "$MKT" ] || die "marketplace tool $MKT is not executable"
    MOUT=$("$MKT" bump --version "$VER" --dry-run 2>&1) \
        || { printf '%s\n' "$MOUT" >&2; die "central marketplace bump --dry-run failed (missing entry → run gitx-marketplace register)"; }
    echo "  ✅ 中央市场 bump 预演通过"
fi
DONE_STEP=0

if [ "$DRY" = 1 ]; then
    echo "🧪 dry-run 计划（未做任何写操作）："
    [ "$IS_DRAFT" = true ] && echo "  1. gh release edit $VER --repo $REPO --draft=false --latest" \
        || echo "  1. ℹ️ GitHub Release $VER 已公开"
    [ -f .gitx/marketplace-target ] && echo "  2. $(basename "$MKT") bump --version $VER" || echo "  2. ➖ 无中央市场开关"
    if [ -z "$NPM_PKG" ]; then echo "  3. ➖ 无 npm 开关"
    elif [ "$NPM_DONE" = 1 ]; then echo "  3. ℹ️ npm $NPM_PKG@$NUM 已发布"
    else echo "  3. npm publish $(basename "$TGZ") --ignore-scripts --access public --registry $REG"; fi
    FINISHED=1
    exit 0
fi

echo "▶ 第 1 步：公开 GitHub Release"
if [ "$IS_DRAFT" = true ]; then
    "$GH" release edit "$VER" --repo "$REPO" --draft=false --latest >/dev/null || die "gh release edit $VER failed"
    # Public from here on, whatever happens to the Latest re-assert below.
    DONE_STEP=1
    echo "✅ GitHub Release $VER 已公开"
else
    echo "ℹ️ GitHub Release $VER 已是公开状态"
fi
# Backfilling an older version can steal "Latest"; keep it on the highest semver.
LIST=$("$GH" release list --repo "$REPO" --limit 200 --json tagName,isDraft,isPrerelease,isLatest 2>"$W/gh.err") \
    || die "gh release list failed: $(head -c 300 "$W/gh.err")"
NEWEST=$(printf '%s' "$LIST" | jq -r '.[] | select(.isDraft | not) | select(.isPrerelease | not) | .tagName' 2>/dev/null \
    | sort -V | tail -1 || true)
[ -n "$NEWEST" ] || die "cannot determine the highest published release"
IS_LATEST=$(printf '%s' "$LIST" | jq -r --arg t "$NEWEST" '.[] | select(.tagName == $t) | .isLatest' 2>/dev/null || true)
if [ "$IS_LATEST" != true ]; then
    "$GH" release edit "$NEWEST" --repo "$REPO" --latest >/dev/null || die "cannot re-assert Latest on $NEWEST"
fi
echo "  Latest = $NEWEST"
DONE_STEP=1

echo "▶ 第 2 步：中央市场"
if [ ! -f .gitx/marketplace-target ]; then
    echo "➖ 无 .gitx/marketplace-target，跳过中央市场"
else
    MOUT=$("$MKT" bump --version "$VER" 2>&1) || { printf '%s\n' "$MOUT" >&2; die "central marketplace bump failed"; }
    if grep -q 'no-op' <<<"$MOUT"; then echo "ℹ️ 中央市场已是 $VER"; else echo "✅ 中央市场已更新到 $VER"; fi
fi
DONE_STEP=2

echo "▶ 第 3 步：npm"
if [ -z "$NPM_PKG" ]; then
    echo "➖ 无 .gitx/npm-target，跳过 npm"
elif [ "$NPM_DONE" = 1 ]; then
    echo "ℹ️ npm $NPM_PKG@$NUM 已发布"
else
    # Interactive on purpose: npm itself asks for the one-time password.
    "$NPM" publish "$TGZ" --ignore-scripts --access public --registry "$REG" || die "npm publish $NPM_PKG@$NUM failed"
    echo "✅ npm $NPM_PKG@$NUM 已发布"
fi
DONE_STEP=3
echo "✅ $VER 已全部公开"
FINISHED=1
