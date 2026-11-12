#!/usr/bin/env bash
# gitx-gitea-release.sh — publish a built Release/<project>-<version>/ directory
# to a private Gitea "release-only" repo over SSH (one commit on main + an
# annotated tag), then create the matching Gitea Release (API, ~/.netrc auth)
# with the .skill, -full.tar.gz, checksums.txt and install.sh assets.
# usage: gitx-gitea-release.sh [--dry-run] [--force] [--version vX.Y.Z] [--skip-api] [--help]
# exit:  0 published / already published / dry-run / API skipped (no netrc entry),
#        1 any failure (incl. --force with no ~/.netrc entry, refused before any push),
#        2 usage error or missing / invalid marker
#        (ggr_ssh_publish returns 0 published, 3 already published with an
#        identical checksums.txt, 5 tag exists but checksums.txt differs, 1 error;
#        standalone maps 3 → exit 0 and 5 → exit 1. ggr_api_publish returns
#        0 created / missing assets uploaded to an existing Release,
#        3 already exists with every asset, 4 skipped-no-netrc, 1 error.)
#
# Marker .gitx/gitea-release-target (gitignored, per-machine, symlink refused):
#   exactly one non-empty line (CR stripped), grammar HOST[:PORT]/OWNER/REPO,
#   charset [A-Za-z0-9._:/-], at most one ':' (host part only), exactly two '/'.
#   Anything containing '://', 'password', 'token' or whitespace is refused, so
#   the marker can never carry a credential or a full URL. PORT defaults to 22.
#   Derived: SSH remote ssh://git@HOST:PORT/OWNER/REPO.git, API https://HOST/api/v1.
#
# Test-only seams (environment):
#   GITX_GITEA_REMOTE_URL  replaces the derived SSH URL for every git network call
#                          (tests point it at a local bare repo).
#   GITX_GITEA_CURL        replaces the curl binary name for the API phase.
# Operator knob (environment):
#   GITX_GITEA_GIT_DEADLINE  seconds each git network call (ls-remote, fetch,
#                          push) may run before it is killed (default 300). SSH
#                          keepalives only catch a dead link, not a remote git
#                          that stalls on a live session.
#
# Inherited GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE / … are cleared before any
# git call, so a caller's environment can never redirect them at its own repo.
#
# No credential is read or printed: SSH auth is the operator's agent/key. When
# the seam is unset, GIT_SSH_COMMAND becomes the operator's own command
# ($GIT_SSH_COMMAND, else core.sshCommand, else ssh) plus BatchMode=yes,
# ConnectTimeout=15, ServerAliveInterval=15, ServerAliveCountMax=4 — so a hook
# never blocks on a prompt or a dead link. The host key must already be in
# known_hosts (BatchMode will not ask to accept it).
# The API uses `curl -q -n` (-q first: ~/.curlrc is ignored, so it cannot turn
# TLS checks off; never -k/--insecure, always --connect-timeout/-m);
# ~/.netrc is only probed for a `machine HOST` line, curl reads the secret itself.
# Use a host-specific `machine HOST login … password …` entry only: curl < 8.11.1
# (CVE-2024-11053) can send netrc credentials to a redirect host when ~/.netrc
# has a passwordless or `default` entry, and the asset download follows redirects.
#
# Pushed bytes = audited bytes: the release dir is refused if it holds a
# non-regular entry (symlink, fifo, …), a file not listed in checksums.txt or
# any .gitattributes; checksums.txt itself is validated (safe relative paths to
# regular files inside the dir, no duplicates, exact set) before any checksum
# tool reads it; git runs with autocrlf off and no attributes file; and the
# committed tree is re-extracted with `git archive`, re-verified against
# checksums.txt and its path set compared with checksums.txt before anything is
# pushed.
#
# Extraction contract (hooks/tests may `eval "$(awk '/^fn\(\)/,/^\}/' …)"`):
#   self-contained on their own: _refuse_symlink_path, ggr_read_marker,
#   ggr_release_date, ggr_netrc_has_host, ggr_run_deadline, ggr_manifest_check.
#   ggr_release_dir needs ggr_manifest_check + PROJECT_ROOT + PROJECT_NAME.
#   ggr_ssh_publish needs ggr_release_date +
#   ggr_run_deadline + PROJECT_NAME (refuses if unset). ggr_api_publish needs
#   ggr_netrc_has_host + PROJECT_NAME (refuses if unset), honours
#   GITX_GITEA_CURL, uses python3 only if it works.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GGR_MARKER=".gitx/gitea-release-target"

# _refuse_symlink_path PATH
# Fails if PATH or any parent component (relative to cwd) is a symlink, so a
# planted link cannot point the marker read at an arbitrary file.
_refuse_symlink_path() {
    local d="$1"
    while [ -n "$d" ] && [ "$d" != "." ] && [ "$d" != "/" ]; do
        if [ -L "$d" ]; then
            echo "❌ $d is a symlink — refusing to read through it" >&2
            return 1
        fi
        d="$(dirname "$d")"
    done
    return 0
}

usage() {
    cat <<'EOF'
Usage: gitx-gitea-release [--dry-run] [--force] [--version vX.Y.Z] [--skip-api] [--help]

Publish Release/<project>-<version>/ to a private Gitea release-only repo:
one commit on main (the flattened release dir) + annotated tag vX.Y.Z over SSH.

  --dry-run          Verify checksums and print the derived remote/API + intent; push nothing.
  --force            Replace an already-published tag (rebuilds main from the current dir).
  --version vX.Y.Z   Version to publish (default: the VERSION sidecar).
  --skip-api         Skip the Gitea Release API phase this run.

Marker: .gitx/gitea-release-target — one line HOST[:PORT]/OWNER/REPO
        (gitignored, per-machine; PORT defaults to 22; no URLs, no secrets).

Exit codes: 0 published / already published / dry-run  1 failure  2 usage / marker
EOF
}

# ggr_read_marker
# Prints "HOST PORT OWNER/REPO" for a valid marker in cwd; returns 1 otherwise.
ggr_read_marker() {
    local content line n lower slashes colons host_part host port owner_repo owner repo
    local m="${GGR_MARKER:-.gitx/gitea-release-target}"
    # Inline symlink check (not _refuse_symlink_path) keeps this function
    # extraction-safe on its own; ggr_main reports the symlink loudly first.
    [ ! -L "$m" ] && [ ! -L "$(dirname "$m")" ] || return 1
    [ -f "$m" ] || return 1
    content=$(tr -d '\r' < "$m")
    n=$(printf '%s\n' "$content" | grep -c '[^[:space:]]' || true)
    [ "$n" = 1 ] || return 1
    line=$(printf '%s\n' "$content" | grep '[^[:space:]]' || true)
    lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *://*|*password*|*token*|*[[:space:]]*|*[!a-z0-9._:/-]*) return 1 ;;
    esac
    slashes="${line//[!\/]/}"
    colons="${line//[!:]/}"
    [ "${#slashes}" = 2 ] || return 1
    [ "${#colons}" -le 1 ] || return 1
    host_part="${line%%/*}"
    owner_repo="${line#*/}"
    owner="${owner_repo%%/*}"
    repo="${owner_repo#*/}"
    case "$owner_repo" in *:*) return 1 ;; esac
    host="${host_part%%:*}"
    port=22
    case "$host_part" in *:*) port="${host_part#*:}" ;; esac
    case "$port" in ''|*[!0-9]*) return 1 ;; esac
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
    local part
    for part in "$host" "$owner" "$repo"; do
        case "$part" in ''|-*|.|..) return 1 ;; esac
    done
    printf '%s %s %s\n' "$host" "$port" "$owner_repo"
}

# ggr_manifest_check DIR
# Validates DIR/checksums.txt BEFORE any checksum tool reads it: a listed
# /dev/zero, a FIFO via ../, or `-` (stdin) would make `shasum -c` block
# forever. Every line must be `<64 hex> [ *]PATH`; PATH (one leading ./ allowed)
# must be relative, free of control chars and of empty / . / .. components, not
# `-`, listed once, a regular non-symlink file whose parent resolves inside DIR;
# and the listed set must equal DIR's regular files minus checksums.txt.
# Returns 1 with a ❌ line naming the offending entry.
ggr_manifest_check() {
    local dir="$1" line p q shown n=0 paths="" nl=$'\n' rd pd extra missing
    local re='^[0-9a-fA-F]{64} [ *]?(.+)$'
    rd=$(cd "$dir" && pwd -P) || { echo "❌ cannot resolve $dir" >&2; return 1; }
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n+1))
        if ! [[ $line =~ $re ]]; then
            echo "❌ checksums.txt line $n is malformed in $dir" >&2
            return 1
        fi
        p="${BASH_REMATCH[1]}"
        q="${p#./}"
        shown="${p//[[:cntrl:]]/?}"
        case "$p" in *[[:cntrl:]]*|-)
            echo "❌ checksums.txt line $n: unsafe path '$shown' in $dir" >&2
            return 1 ;;
        esac
        case "/$q/" in *//*|*/./*|*/../*)
            echo "❌ checksums.txt line $n: unsafe path '$shown' in $dir" >&2
            return 1 ;;
        esac
        if [ ! -f "$dir/$q" ] || [ -L "$dir/$q" ]; then
            echo "❌ checksums.txt line $n: '$shown' is not a regular file in $dir" >&2
            return 1
        fi
        pd=$(cd "$dir/$(dirname "$q")" && pwd -P) || pd=""
        case "$pd/" in "$rd"/*) ;; *)
            echo "❌ checksums.txt line $n: '$shown' resolves outside $dir" >&2
            return 1 ;;
        esac
        case "$nl$paths" in *"$nl$q$nl"*)
            echo "❌ checksums.txt line $n: duplicate entry '$shown' in $dir" >&2
            return 1 ;;
        esac
        paths="$paths$q$nl"
    done < "$dir/checksums.txt" || return 1
    # The whole dir is pushed, so every file must be one the audit hashed.
    extra=$(cd "$dir" && LC_ALL=C comm -23 \
        <(find . -type f | sed 's|^\./||' | { grep -vxF checksums.txt || true; } | LC_ALL=C sort) \
        <(printf '%s' "$paths" | LC_ALL=C sort) | tr '\n' ' ') || return 1
    if [ -n "$extra" ]; then
        echo "❌ unlisted file(s) in $dir: ${extra% }" >&2
        return 1
    fi
    missing=$(cd "$dir" && LC_ALL=C comm -13 \
        <(find . -type f | sed 's|^\./||' | { grep -vxF checksums.txt || true; } | LC_ALL=C sort) \
        <(printf '%s' "$paths" | LC_ALL=C sort) | tr '\n' ' ') || return 1
    if [ -n "$missing" ]; then
        echo "❌ checksums.txt lists entries that are not audited files in $dir: ${missing% }" >&2
        return 1
    fi
    return 0
}

# ggr_release_dir VERSION
# Prints $PROJECT_ROOT/Release/<PROJECT_NAME>-VERSION after its checksums.txt
# validates (ggr_manifest_check) and verifies; returns 1 (with a ❌ line) on a
# missing dir or any mismatch, so a tampered release never reaches a git
# network call.
ggr_release_dir() {
    local dir="$PROJECT_ROOT/Release/${PROJECT_NAME}-$1"
    if [ ! -d "$dir" ]; then
        echo "❌ release dir not found: $dir (build it with gitx-release first)" >&2
        return 1
    fi
    # `find -type f` below never sees a symlink, yet cp -R would copy it and
    # git would commit it — so anything but plain files and dirs is refused.
    local nonreg
    nonreg=$(cd "$dir" && find . -mindepth 1 ! -type f ! -type d | sed 's|^\./||' | tr '\n' ' ') || {
        echo "❌ cannot scan $dir for non-regular entries (find failed)" >&2
        return 1
    }
    if [ -n "$nonreg" ]; then
        echo "❌ non-regular entries in $dir: ${nonreg% }" >&2
        return 1
    fi
    # cp -R merges a payload .git/ into the scratch repo's .git/ — its config
    # and info/attributes would run arbitrary filters under `git add`.
    local dotgit
    dotgit=$(cd "$dir" && find . -iname .git | sed 's|^\./||' | tr '\n' ' ') || {
        echo "❌ cannot scan $dir for .git entries (find failed)" >&2
        return 1
    }
    if [ -n "$dotgit" ]; then
        echo "❌ .git entry in $dir: ${dotgit% } — refusing (it would merge into the publish repo)" >&2
        return 1
    fi
    if [ ! -f "$dir/checksums.txt" ]; then
        echo "❌ checksums.txt verification failed in $dir" >&2
        return 1
    fi
    # read -r drops NUL bytes, so a path with one would validate as a different
    # string than the bytes a C hashing tool stops at (`-` → stdin → hang).
    # LC_ALL=C: under a UTF-8 locale BSD tr aborts on a non-ASCII byte, which
    # would make a legitimate Latin-1 file name look like a NUL.
    local bytes stripped
    bytes=$(wc -c < "$dir/checksums.txt") \
        && stripped=$(LC_ALL=C tr -d '\000' < "$dir/checksums.txt" | wc -c) || {
        echo "❌ cannot read checksums.txt in $dir" >&2
        return 1
    }
    if [ "$stripped" -ne "$bytes" ]; then
        echo "❌ checksums.txt contains NUL bytes in $dir" >&2
        return 1
    fi
    ggr_manifest_check "$dir" || return 1
    local verified=1
    if command -v shasum >/dev/null 2>&1; then
        (cd "$dir" && shasum -a 256 -c checksums.txt < /dev/null >/dev/null 2>&1) || verified=0
    elif command -v sha256sum >/dev/null 2>&1; then
        (cd "$dir" && sha256sum -c checksums.txt < /dev/null >/dev/null 2>&1) || verified=0
    else
        verified=0
    fi
    if [ "$verified" != 1 ]; then
        echo "❌ checksums.txt verification failed in $dir" >&2
        return 1
    fi
    # A .gitattributes could rewrite bytes (eol / filters) on the way into git.
    local ga
    ga=$(cd "$dir" && find . -iname .gitattributes | sed 's|^\./||' | tr '\n' ' ') || return 1
    if [ -n "$ga" ]; then
        echo "❌ .gitattributes in $dir: ${ga% } — refusing (it could change the pushed bytes)" >&2
        return 1
    fi
    printf '%s\n' "$dir"
}

# ggr_release_date DIR VERSION
# Prints YYYY-MM-DD: the "## VERSION " CHANGELOG header (release.sh's anchor),
# else SOURCE_DATE_EPOCH, else today — so the published commit date matches the
# release instead of the wall clock of whoever re-runs the publish.
ggr_release_date() {
    local v d
    v=$(printf '%s' "$2" | sed 's/[.[*+?(){}\\^$|]/\\&/g')
    d=$(grep -m1 "^## ${v} " "$1/CHANGELOG.md" 2>/dev/null \
        | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)
    if [ -z "$d" ] && [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
        d=$(date -u -r "$SOURCE_DATE_EPOCH" "+%Y-%m-%d" 2>/dev/null \
            || date -u -d "@$SOURCE_DATE_EPOCH" "+%Y-%m-%d" 2>/dev/null \
            || true)
    fi
    [ -n "$d" ] || d=$(date -u +%Y-%m-%d)
    printf '%s\n' "$d"
}

# ggr_run_deadline SECS CMD… — run CMD (a command or shell function); return its
# status, or 124 after killing it once SECS seconds have passed (GNU `timeout`
# is not on macOS). The whole process tree is signalled — TERM, then KILL 2 s
# later — because a surviving ssh child would keep a `$(…)` capture open.
# Polls every 0.2 s (BSD and GNU sleep both take fractions) so a fast call is
# not padded by a whole second. Without job control a background job ignores
# SIGINT, so an INT/TERM reaching this shell would orphan a running `git push`;
# the trap below takes the tree down first (and is reset before returning).
ggr_run_deadline() {
    local secs="$1" pid rc=0 start
    shift
    # _ggr_kill_tree PID GRACE — TERM the tree, wait GRACE s, KILL. The tree is
    # collected before signalling: once a parent dies its children are
    # re-parented and could no longer be found.
    _ggr_kill_tree() {
        local tree="$1" kids="$1" p n
        while [ -n "$kids" ]; do
            n=""
            for p in $kids; do
                n="$n $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v pp="$p" '$2 == pp { print $1 }')"
            done
            # shellcheck disable=SC2086
            kids=$(printf '%s ' $n)
            kids="${kids% }"
            [ -z "$kids" ] || tree="$tree $kids"
        done
        # shellcheck disable=SC2086
        kill -TERM $tree 2>/dev/null || true
        sleep "$2"
        # shellcheck disable=SC2086
        kill -KILL $tree 2>/dev/null || true
    }
    start=$SECONDS
    "$@" &
    pid=$!
    trap '_ggr_kill_tree "$pid" 1' INT TERM
    while kill -0 "$pid" 2>/dev/null; do
        if [ $((SECONDS - start)) -ge "$secs" ]; then
            _ggr_kill_tree "$pid" 2
            wait "$pid" 2>/dev/null || true
            trap - INT TERM
            return 124
        fi
        sleep 0.2
    done
    wait "$pid" || rc=$?
    trap - INT TERM
    return "$rc"
}

# ggr_ssh_publish DIR VERSION REMOTE_URL FORCE(0|1)
# Returns 0 published, 3 already published (tag exists with identical
# checksums.txt, FORCE=0), 5 tag exists but checksums.txt differs (FORCE=0), 1 error.
# Starts from the remote main (history is kept), replaces every tracked file
# with DIR's contents, commits as gitx at the release date and tags VERSION.
# The body runs in a subshell so its temp-dir trap cannot clobber a caller's.
ggr_ssh_publish() {
    local dir="$1" ver="$2" url="$3" force="$4" date dl="${GITX_GITEA_GIT_DEADLINE:-300}"
    # An empty DIR would turn `cp -R "$dir"/.` into a copy of `/`; only ever
    # publish a real release dir (one that carries its checksums.txt).
    if [ -z "$dir" ] || [ ! -d "$dir" ] || [ ! -f "$dir/checksums.txt" ] || [ -z "$url" ] \
       || [ -z "${PROJECT_NAME:-}" ]; then
        echo "❌ ggr_ssh_publish: invalid release dir '$dir', empty remote or unset PROJECT_NAME" >&2
        return 1
    fi
    case "$dl" in ''|0|*[!0-9]*)
        echo "❌ GITX_GITEA_GIT_DEADLINE must be a positive number of seconds (got '$dl')" >&2
        return 1 ;;
    esac
    date=$(ggr_release_date "$dir" "$ver")
    (
        # An inherited GIT_DIR would make `init` / `symbolic-ref` below act on
        # the caller's repo instead of the scratch dir.
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
              GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
        W=$(mktemp -d "${TMPDIR:-/tmp}/gitx-gitea.XXXXXX") || exit 1
        W2=$(mktemp -d "${TMPDIR:-/tmp}/gitx-gitea-check.XXXXXX") || { rm -rf "$W"; exit 1; }
        trap 'rm -rf "$W" "$W2"' EXIT
        # Global hooks / signing / excludes / eol conversion / attributes must
        # not alter or block the publish.
        g() { git -C "$W" -c core.hooksPath=/dev/null -c commit.gpgSign=false \
                  -c tag.gpgSign=false -c user.name=gitx -c user.email=gitx@localhost \
                  -c core.autocrlf=false -c core.attributesFile=/dev/null -c core.safecrlf=false "$@"; }
        # net OP CMD… — a git network call under the deadline; names a timeout.
        net() {
            local op="$1" rc=0
            shift
            ggr_run_deadline "$dl" "$@" || rc=$?
            if [ "$rc" = 124 ]; then echo "❌ git $op timed out after ${dl}s" >&2; fi
            return "$rc"
        }
        g init -q || exit 1
        g symbolic-ref HEAD refs/heads/main || exit 1
        # Full ref: a bare `main` pattern also matches e.g. refs/heads/x/main.
        heads=$(net ls-remote git ls-remote --heads "$url" refs/heads/main) \
            || { echo "❌ cannot reach $url (git ls-remote failed)" >&2; exit 1; }
        if [ -n "$heads" ]; then
            net fetch g fetch -q --depth 1 "$url" refs/heads/main || { echo "❌ fetch of main from $url failed" >&2; exit 1; }
            g checkout -q -B main FETCH_HEAD || exit 1
        fi
        tags=$(net ls-remote git ls-remote --tags "$url" "refs/tags/$ver") \
            || { echo "❌ cannot list tags on $url" >&2; exit 1; }
        if [ -n "$tags" ] && [ "$force" != 1 ]; then
            # "Already published" only when the tag ships the same bytes;
            # a rebuilt dir under an existing tag needs an explicit --force.
            net fetch g fetch -q --depth 1 "$url" "refs/tags/$ver:refs/tags/$ver" \
                || { echo "❌ fetch of tag $ver from $url failed" >&2; exit 1; }
            if ! g show "refs/tags/$ver:checksums.txt" > "$W/.git/gitx-remote-checksums" 2>/dev/null; then
                echo "❌ tag $ver exists on $url but could not read checksums.txt from the remote tag — use --force to replace" >&2
                exit 5
            fi
            if cmp -s "$W/.git/gitx-remote-checksums" "$dir/checksums.txt"; then
                exit 3
            fi
            echo "❌ tag $ver exists on $url but its checksums.txt differs from $dir — use --force to replace" >&2
            exit 5
        fi
        g rm -rq --cached . >/dev/null 2>&1 || true
        find "$W" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} + || exit 1
        cp -R "$dir"/. "$W"/ || exit 1
        # -f + empty excludesFile: a shipped file must never be dropped by an
        # ignore rule (global excludes or a .gitignore inside the release dir).
        g -c core.excludesFile=/dev/null add -A -f || exit 1
        # Unchanged tree → reuse HEAD as the release commit, so --force on an
        # identical dir and "main pushed, tag missing" recovery add no commit.
        if g rev-parse -q --verify HEAD >/dev/null && g diff --cached --quiet; then
            :
        else
            GIT_AUTHOR_DATE="$date 00:00:00 +0000" GIT_COMMITTER_DATE="$date 00:00:00 +0000" \
                g commit -q --allow-empty -m "$PROJECT_NAME $ver — release artifacts" || exit 1
        fi
        GIT_COMMITTER_DATE="$date 00:00:00 +0000" \
            g tag -a -f "$ver" -m "$PROJECT_NAME $ver" || exit 1
        # What git would hand a cloner must reproduce the audited checksums;
        # any conversion slipping past the -c overrides is caught before a push.
        if ! { g archive --format=tar HEAD | tar -xf - -C "$W2"; } \
           || ! (cd "$W2" && if command -v shasum >/dev/null 2>&1; then
                     shasum -a 256 -c checksums.txt; else sha256sum -c checksums.txt; fi < /dev/null >/dev/null 2>&1); then
            echo "❌ archive self-check failed: committed tree differs from $dir" >&2
            exit 1
        fi
        # shasum -c only proves the listed paths; the tree must also hold
        # nothing else (an extra path would ship unaudited).
        if ! g -c core.quotePath=false ls-files | LC_ALL=C sort > "$W/.git/gitx-tree-paths" \
           || ! { awk '{ sub(/^[0-9a-fA-F]+ [ *]/, ""); sub(/^\.\//, ""); print }' "$dir/checksums.txt"
                  echo checksums.txt; } | LC_ALL=C sort -u > "$W/.git/gitx-sum-paths" \
           || ! cmp -s "$W/.git/gitx-tree-paths" "$W/.git/gitx-sum-paths"; then
            echo "❌ archive path set differs from checksums.txt" >&2
            exit 1
        fi
        # main is always built on the fetched tip, so it never needs force;
        # --force only moves the tag. --atomic: a rejected tag must not leave
        # main updated (or vice versa).
        tagref="refs/tags/$ver:refs/tags/$ver"
        if [ "$force" = 1 ]; then tagref="+$tagref"; fi
        net push g push -q --atomic "$url" refs/heads/main:refs/heads/main "$tagref" \
            || { echo "❌ push to $url failed" >&2; exit 1; }
        exit 0
    )
}

# ggr_netrc_has_host HOST
# 0 when ~/.netrc has a `machine HOST` entry. Only that one line shape is probed
# (dots escaped so a look-alike host never matches); nothing else in the file
# is read or printed — curl -n reads the credential itself.
ggr_netrc_has_host() {
    local host_re="${1//./\\.}"
    [ -n "$1" ] && [ -r "$HOME/.netrc" ] \
        && grep -qE "^[[:space:]]*machine[[:space:]]+${host_re}([[:space:]]|$)" "$HOME/.netrc"
}

# ggr_api_publish DIR VERSION HOST OWNER_REPO FORCE(0|1)
# Creates the Gitea Release for tag VERSION and attaches the assets.
# Returns 0 created (or an existing Release completed with its missing assets),
# 3 already exists with every asset (FORCE=0), 4 skipped (no ~/.netrc entry),
# 1 error (a ❌ line names the failed step). With FORCE=1 an existing Release
# is deleted first so its assets match the re-pushed tag; with FORCE=0 an
# existing Release whose checksums.txt asset differs from DIR's is refused (1).
ggr_api_publish() {
    local dir="$1" ver="$2" host="$3" or="$4" force="$5"
    if [ -z "$dir" ] || [ ! -d "$dir" ] || [ -z "$host" ] || [ -z "$or" ] || [ -z "${PROJECT_NAME:-}" ]; then
        echo "❌ ggr_api_publish: invalid release dir '$dir', empty host/repo or unset PROJECT_NAME" >&2
        return 1
    fi
    # Both values land in JSON and URLs unescaped, so only plain names pass.
    case "$PROJECT_NAME$ver" in *[!A-Za-z0-9._-]*)
        echo "❌ ggr_api_publish: PROJECT_NAME/version must match [A-Za-z0-9._-]" >&2
        return 1 ;;
    esac
    if ! ggr_netrc_has_host "$host"; then
        echo "⚠️ no ~/.netrc entry for $host — skipping Gitea Release (tag + archive are published)" >&2
        return 4
    fi
    (
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
              GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
        W=$(mktemp -d "${TMPDIR:-/tmp}/gitx-gitea-api.XXXXXX") || exit 1
        trap 'rm -rf "$W"' EXIT
        api="https://$host/api/v1/repos/$or"
        # -q (must be first): ignore ~/.curlrc, which could disable TLS checks.
        # -n: the credential comes from ~/.netrc, never from argv; the timeouts
        # keep a hook from hanging the wrapper. Bodies go to a file, stdout is
        # only the status (000 when curl itself failed).
        c() { "${GITX_GITEA_CURL:-curl}" -q -n -sS --connect-timeout 15 -m 300 \
                  -o "$W/resp" -w '%{http_code}' "$@"; }
        resp_id() { grep -oE '"id":[0-9]+' "$W/resp" 2>/dev/null | head -1 | cut -d: -f2 || true; }
        # upload_assets ID [have] — POST each of the four assets not named in
        # the file "have" (one name per line); prints how many were sent.
        # Runs from inside DIR so the form field is a bare file name.
        upload_assets() {
            local f k=0
            for f in "$PROJECT_NAME-$ver.skill" "$PROJECT_NAME-$ver-full.tar.gz" checksums.txt install.sh; do
                [ -f "$f" ] || continue
                if [ -n "${2:-}" ] && grep -qxF -- "$f" "$2"; then continue; fi
                code=$(c -X POST -F "attachment=@$f" "$api/releases/$1/assets?name=$f") || true
                [ "$code" = 201 ] || {
                    echo "❌ uploading asset $f to Gitea Release $ver failed (HTTP ${code:-000}) — re-run to upload the missing asset(s), or --force to recreate" >&2
                    return 1
                }
                k=$((k+1))
            done
            echo "$k"
        }
        cd "$dir" || exit 1

        code=$(c -X GET "$api/releases/tags/$ver") || true
        case "$code" in
            200)
                id=$(resp_id)
                if [ "$force" != 1 ]; then
                    # A Release left half-uploaded by an earlier run is
                    # completed here instead of being reported as done.
                    # Gitea serialises compact JSON; optional whitespace is
                    # still tolerated. Only names inside "assets":[…] count
                    # (the Release's own "name" precedes it), and upload_assets
                    # compares exact asset filenames (grep -x).
                    tr -d '\n' < "$W/resp" 2>/dev/null \
                        | sed -n 's/.*"assets"[[:space:]]*:[[:space:]]*\[//p' \
                        | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*"' \
                        | sed 's/.*"\([^"]*\)"$/\1/' > "$W/have" || true
                    [ -n "$id" ] || { echo "❌ Gitea Release $ver: no release id in the API response" >&2; exit 1; }
                    # A --force that moved the tag but then failed to recreate
                    # the Release leaves the old assets behind; their
                    # checksums.txt is what tells them apart from the tag.
                    code=$(c -X GET -L --proto-redir =https \
                           "https://$host/$or/releases/download/$ver/checksums.txt") || true
                    case "$code" in
                        200)
                            cmp -s "$W/resp" "$dir/checksums.txt" || {
                                echo "❌ Gitea Release $ver assets are stale relative to tag $ver (checksums.txt differs) — re-run with --force to recreate" >&2
                                exit 1
                            } ;;
                        # No checksums.txt asset: only an empty Release can be
                        # completed safely; any asset already there is of
                        # unknown provenance.
                        404) if [ -s "$W/have" ]; then
                                 echo "❌ Gitea Release $ver assets are stale relative to tag $ver (checksums.txt asset missing) — re-run with --force to recreate" >&2
                                 exit 1
                             fi ;;
                        *) echo "❌ downloading checksums.txt of Gitea Release $ver failed (HTTP ${code:-000})" >&2; exit 1 ;;
                    esac
                    k=$(upload_assets "$id" "$W/have") || exit 1
                    if [ "$k" -gt 0 ]; then
                        echo "✅ release $ver completed ($k missing asset(s) uploaded)"
                        exit 0
                    fi
                    echo "ℹ️ release $ver already exists"
                    exit 3
                fi
                [ -n "$id" ] || { echo "❌ Gitea Release $ver: no release id in the API response" >&2; exit 1; }
                code=$(c -X DELETE "$api/releases/$id") || true
                case "$code" in
                    200|204) ;;
                    *) echo "❌ deleting Gitea Release $ver failed (HTTP ${code:-000})" >&2; exit 1 ;;
                esac
                ;;
            404) ;;
            *) echo "❌ looking up Gitea Release $ver failed (HTTP ${code:-000})" >&2; exit 1 ;;
        esac

        # json.dumps does the escaping; without a working python3 the body is a
        # fixed line (plain names only, validated above) — never hand-escaped.
        body=""
        if [ -f "$dir/RELEASE_NOTES.md" ]; then
            body=$(python3 -I -c 'import json,sys; print(json.dumps(sys.stdin.buffer.read().decode("utf-8", "replace")))' \
                   < "$dir/RELEASE_NOTES.md" 2>/dev/null) || body=""
        fi
        [ -n "$body" ] || body="\"Release artifacts for $PROJECT_NAME $ver. Verify with checksums.txt, then run install.sh.\""
        printf '{"tag_name":"%s","name":"%s %s","body":%s,"draft":false,"prerelease":false}' \
            "$ver" "$PROJECT_NAME" "$ver" "$body" > "$W/body.json" || exit 1

        code=$(c -X POST -H 'Content-Type: application/json' --data-binary "@$W/body.json" "$api/releases") || true
        [ "$code" = 201 ] || { echo "❌ creating Gitea Release $ver failed (HTTP ${code:-000})" >&2; exit 1; }
        id=$(resp_id)
        [ -n "$id" ] || { echo "❌ Gitea Release $ver: no release id in the API response — re-run to upload the missing asset(s), or --force to recreate" >&2; exit 1; }

        n=$(upload_assets "$id") || exit 1
        echo "✅ release $ver created ($n assets)"
        exit 0
    )
}

ggr_main() {
    local dry_run=0 force=0 skip_api=0 req_version=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)  dry_run=1 ;;
            --force)    force=1 ;;
            --skip-api) skip_api=1 ;;
            --version)
                shift
                req_version="${1:-}"
                [ -n "$req_version" ] || { echo "❌ --version requires vX.Y.Z" >&2; return 2; }
                ;;
            -h|--help)  usage; return 0 ;;
            *) echo "❌ Unknown option: $1 (see --help)" >&2; return 2 ;;
        esac
        shift
    done

    PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
    PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)" || { echo "❌ PROJECT_ROOT not found" >&2; return 1; }
    cd "$PROJECT_ROOT" || return 1

    _refuse_symlink_path "$GGR_MARKER" || return 2
    if [ ! -f "$GGR_MARKER" ]; then
        echo "❌ no $GGR_MARKER marker in $PROJECT_ROOT — create it with one line HOST[:PORT]/OWNER/REPO" >&2
        return 2
    fi
    local parsed host port owner_repo
    parsed=$(ggr_read_marker) || {
        echo "❌ invalid $GGR_MARKER — expected one line HOST[:PORT]/OWNER/REPO (no URL, no secrets)" >&2
        return 2
    }
    read -r host port owner_repo <<<"$parsed"
    local derived_ssh="ssh://git@${host}:${port}/${owner_repo}.git"
    local api_base="https://${host}/api/v1"

    # shellcheck source=lib/detect-project.sh
    source "$SCRIPT_DIR/lib/detect-project.sh" || { echo "❌ cannot resolve PROJECT_NAME / SKILL_NAME" >&2; return 1; }

    # Default version = the wrapper's sidecar (skills/<SKILL_NAME>/VERSION), so
    # the hook and a standalone run resolve the same release.
    local version="$req_version"
    if [ -z "$version" ]; then
        local sidecar="$PROJECT_ROOT/skills/$SKILL_NAME/VERSION"
        if [ ! -f "$sidecar" ]; then
            echo "❌ Missing VERSION sidecar: $sidecar (or pass --version vX.Y.Z)" >&2
            return 2
        fi
        version=$(tr -d '[:space:]' < "$sidecar")
    fi
    case "$version" in v*) ;; *) version="v$version" ;; esac
    if ! printf '%s' "$version" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "❌ version must be stable vX.Y.Z (got '${req_version:-${version#v}}')" >&2
        return 2
    fi

    if [ "$force" = 1 ] && [ "$skip_api" = 1 ]; then
        echo "⚠️ --force without the API phase: an existing Gitea Release (if any) will go stale" >&2
    fi
    # Checked before any push: a forced tag with an old Release left behind
    # would ship assets that no longer match the tag.
    if [ "$force" = 1 ] && [ "$skip_api" = 0 ] && ! ggr_netrc_has_host "$host"; then
        echo "❌ refusing --force: no ~/.netrc entry for $host — the existing Gitea Release would go stale" >&2
        return 1
    fi

    local release_dir
    release_dir=$(ggr_release_dir "$version") || return 1

    local remote="${GITX_GITEA_REMOTE_URL:-$derived_ssh}"
    if [ "$dry_run" = 1 ]; then
        echo "🧪 dry-run: remote $derived_ssh"
        echo "🧪 dry-run: api $api_base"
        echo "🧪 dry-run: would push $PROJECT_NAME $version ($release_dir) → $remote (main + tag $version)"
        if [ "$skip_api" = 1 ]; then
            echo "🧪 dry-run: would skip the API phase (--skip-api)"
        else
            echo "🧪 dry-run: would create release $PROJECT_NAME $version at $api_base/repos/$owner_repo/releases"
        fi
        return 0
    fi

    export GIT_TERMINAL_PROMPT=0
    if [ -z "${GITX_GITEA_REMOTE_URL:-}" ]; then
        # Keep the operator's own ssh command (jump host, key, port) and only
        # add non-interactive + bounded-time options on top.
        GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-$(git config --get core.sshCommand 2>/dev/null || echo ssh)} -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=4"
        export GIT_SSH_COMMAND
    fi

    local rc=0
    ggr_ssh_publish "$release_dir" "$version" "$remote" "$force" || rc=$?
    case "$rc" in
        0) echo "✅ pushed $PROJECT_NAME $version → $remote" ;;
        3) echo "ℹ️ already published: tag $version exists on $remote (use --force to replace)" ;;
        5) return 1 ;;
        *) echo "❌ SSH publish of $PROJECT_NAME $version to $remote failed" >&2; return 1 ;;
    esac

    # API phase also runs after "already published", so a Release that failed
    # (or was skipped) last time is created later without --force.
    local web="https://${host}/${owner_repo}" api_rc=0 rel_ok=0
    if [ "$skip_api" = 1 ]; then
        echo "ℹ️ API phase skipped (--skip-api)"
    else
        ggr_api_publish "$release_dir" "$version" "$host" "$owner_repo" "$force" || api_rc=$?
        case "$api_rc" in
            0|3) rel_ok=1 ;;
            4) ;;
            *) return 1 ;;
        esac
    fi
    echo "🔗 repo: $web"
    if [ "$rel_ok" = 1 ]; then
        echo "🔗 release: $web/releases/tag/$version"
    fi
    echo "📦 install: git clone --depth 1 --branch $version $derived_ssh $PROJECT_NAME-$version && cd $PROJECT_NAME-$version && shasum -a 256 -c checksums.txt && ./install.sh"
    return 0
}

# Allow sourcing (tests / the gitx-release hook reuse the helpers) without running.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    ggr_main "$@"
fi
