#!/bin/bash
# test_release_stage_gitignored.sh — rsync staging must not ship gitignored files.
# Why: the legacy rsync path ignores .gitignore, so a gitignored secret not on
# release.sh's hand-kept --exclude list (e.g. .npmrc with a token) was staged
# into the public source tarball. prune_gitignored_from_stage closes that.
# exit: 0 all pass, 1 any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== test_release_stage_gitignored.sh ==="

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

eval "$(awk '/^prune_gitignored_from_stage\(\) *\{/,/^\}/' "$REAL/scripts/release.sh")"
if ! type prune_gitignored_from_stage >/dev/null 2>&1; then
    fail "prune_gitignored_from_stage not defined in scripts/release.sh"
    echo ""
    echo "Results: ✅$PASS / ❌$FAIL"
    exit 1
fi

# ── git fixture: tracked README, gitignored .npmrc + node_modules/ ──────────
G="$T/gitproj"
mkdir -p "$G/node_modules"
printf '# readme\n' > "$G/README.md"
printf '.npmrc\nnode_modules/\n' > "$G/.gitignore"
( cd "$G" && git init -q && git add README.md .gitignore \
  && git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false \
         -c core.hooksPath=/dev/null commit -qm init )
printf 'registry-auth=%s\n' "placeholder-not-a-secret" > "$G/.npmrc"
printf 'module.exports = 1;\n' > "$G/node_modules/x.js"

S="$T/stage-git"
mkdir -p "$S"
rsync -a --exclude=.git "$G/" "$S/"
rc=0; prune_gitignored_from_stage "$G" "$S" || rc=$?
[ "$rc" -eq 0 ] && ok "prune returns 0 on a git repo" || fail "prune returned $rc"
[ ! -e "$S/.npmrc" ] && ok "gitignored .npmrc pruned from stage" || fail ".npmrc still staged"
[ ! -e "$S/node_modules/x.js" ] && ok "gitignored node_modules/x.js pruned" || fail "node_modules/x.js still staged"
[ -f "$S/README.md" ] && ok "tracked README.md kept" || fail "tracked README.md removed"
[ -f "$S/.gitignore" ] && ok "tracked .gitignore kept" || fail "tracked .gitignore removed"
[ -f "$G/.npmrc" ] && [ -f "$G/node_modules/x.js" ] \
    && ok "working tree untouched (only the stage is pruned)" \
    || fail "prune deleted files from the project root"

# ── gitignored dangling symlink: -e alone follows the link and skips it ────
D="$T/gitlink"
mkdir -p "$D"
printf '# readme\n' > "$D/README.md"
printf 'cache-link\n' > "$D/.gitignore"
( cd "$D" && git init -q && git add README.md .gitignore \
  && git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false \
         -c core.hooksPath=/dev/null commit -qm init )
ln -s "$T/does-not-exist/target" "$D/cache-link"
S3="$T/stage-link"
mkdir -p "$S3"
rsync -a --exclude=.git "$D/" "$S3/"
[ -L "$S3/cache-link" ] || fail "fixture: dangling symlink not staged by rsync"
rc=0; prune_gitignored_from_stage "$D" "$S3" || rc=$?
if [ "$rc" -eq 0 ] && [ ! -L "$S3/cache-link" ] && [ ! -e "$S3/cache-link" ]; then
    ok "gitignored dangling symlink pruned from stage"
else
    fail "gitignored dangling symlink still staged (rc=$rc)"
fi
[ -f "$S3/README.md" ] && ok "tracked README.md kept beside pruned link" || fail "README.md removed"

# ── non-git fixture: stage left unchanged ────────────────────────────────────
N="$T/plain"
mkdir -p "$N"
printf '# readme\n' > "$N/README.md"
printf '.npmrc\n' > "$N/.gitignore"
printf 'x\n' > "$N/.npmrc"
S2="$T/stage-plain"
mkdir -p "$S2"
rsync -a "$N/" "$S2/"
rc=0; prune_gitignored_from_stage "$N" "$S2" || rc=$?
if [ "$rc" -eq 0 ] && diff -rq "$N" "$S2" >/dev/null; then
    ok "non-git project: stage unchanged, returns 0"
else
    fail "non-git project: stage modified or rc=$rc"
fi

echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
