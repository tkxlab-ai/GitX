#!/usr/bin/env bash
# gitx-marketplace.sh — TKX skills marketplace registration helper (v1.13.0).
# usage: gitx-marketplace.sh {register --repo OWNER/REPO|bump [--version vX.Y.Z]|list [--repo OWNER/REPO]} [--dry-run] [--force]
#
# Subcommands: register / bump / list. Marker-driven, single-try (Q4),
# best-effort when invoked from gitx-release wrapper hook.
# Why this design: see docs/superpowers/specs/2026-05-20-v1.13.0-marketplace-helper-design.md

set -euo pipefail

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# _refuse_symlink_path PATH
# Fails if PATH or any parent component (relative to cwd) is a symlink, so a
# planted link cannot redirect a working-tree write outside the project.
_refuse_symlink_path() {
    local d="$1"
    while [ -n "$d" ] && [ "$d" != "." ] && [ "$d" != "/" ]; do
        if [ -L "$d" ]; then
            echo "❌ $d is a symlink — refusing to write through it" >&2
            return 1
        fi
        d="$(dirname "$d")"
    done
    return 0
}

# ---- marker helpers (Section 3) -------------------------------------------

# validate_marker_content INPUT
# Returns 0 if INPUT is a valid OWNER/REPO marker; 1 otherwise.
# Rejects: empty, whitespace inside, tab/newline, CRLF, dotdot, absolute path,
#          length > 140, anything not matching the owner/repo regex.
validate_marker_content() {
    local raw
    raw="${1:-}"
    # Reject if contains CRLF, LF, TAB, or space
    case "$raw" in
        ''|*$'\r'*|*$'\n'*|*$'\t'*|*' '*|*'..'*|/*) return 1 ;;
    esac
    [ "${#raw}" -le 140 ] || return 1
    printf '%s' "$raw" \
      | grep -qE '^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$' || return 1
    return 0
}

# read_marker
# Echoes the marker contents (single-line, CR-stripped). Returns 1 if absent or unreadable.
# Rejects markers with multiple non-empty lines (tampering detection).
read_marker() {
    [ -f .gitx/marketplace-target ] || return 1
    local content
    content=$(tr -d '\r' < .gitx/marketplace-target)
    # Reject if more than one non-empty line (defense-in-depth — caller still runs
    # validate_marker_content on the first line, but a multi-line marker is a
    # tampering signal worth surfacing rather than silently truncating).
    local nonempty_count
    nonempty_count=$(printf '%s\n' "$content" | grep -c '[^[:space:]]')
    if [ "$nonempty_count" -gt 1 ]; then
        echo "error: marker has $nonempty_count non-empty lines; expected exactly 1 (OWNER/REPO)" >&2
        return 1
    fi
    printf '%s' "$content" | head -1
}

# fetch_marketplace_json REPO
# Echoes the decoded .claude-plugin/marketplace.json from the central marketplace
# (empty string if unreadable: network / auth / 404). Single source for the probe
# fetch shared by register / bump / the gitx-release hook — the trailing `|| true`
# keeps it from aborting the caller under `set -euo pipefail` (a pipefail-failing
# gh used to abort cmd_bump before its exit-3 path). Callers classify
# corrupt-vs-present-vs-absent on the returned text. NB: cmd_list deliberately does
# NOT use this — it wants a loud failure, not a silent empty.
fetch_marketplace_json() {
    gh api "/repos/$1/contents/.claude-plugin/marketplace.json" --jq '.content' 2>/dev/null \
        | base64 -d 2>/dev/null || true
}

# valid_github_git_url URL
# Returns 0 if URL is https://github.com/OWNER/REPO.git with no '..'.
# Whole-string match: a line-based grep would accept "<valid url>\n<anything>".
valid_github_git_url() {
    local re='^https://github\.com/[A-Za-z0-9-]+/[A-Za-z0-9._-]+\.git$'
    case "$1" in *..*|*[![:print:]]*) return 1 ;; esac
    [[ $1 =~ $re ]]
}

# _pick_pr CLONE_DIR BRANCH SHA
# Echoes the number of the one open PR we may merge: same repo, base main, head at
# SHA. Echoes nothing when no open PR uses BRANCH as head name. Returns 1 when the
# listing fails or any open PR with that head name is cross-repository, targets
# another base, or sits at another commit — `gh pr list --head` matches by branch
# NAME only, so on a public marketplace a fork PR could otherwise be merged. The
# list is deliberately not filtered by --base so other-base PRs are seen and refused.
_pick_pr() {
    local prs
    prs=$(cd "$1" && gh pr list --head "$2" --state open \
            --json number,headRefOid,isCrossRepository,headRepositoryOwner,baseRefName 2>/dev/null) || return 1
    printf '%s' "$prs" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    printf '%s' "$prs" | jq -er --arg s "$3" '
        if length == 0 then ""
        elif length == 1 and .[0].isCrossRepository == false and .[0].baseRefName == "main"
             and $s != "" and .[0].headRefOid == $s and (.[0].number | type) == "number"
        then .[0].number | tostring
        else error("unverified PR") end' 2>/dev/null || return 1
}

# validate_entry ENTRY_JSON
# Returns 0 if all required fields pass per Section 3 entry-validation table.
# Central entries use {"source":"url","url":"https://github.com/O/R.git"}: it is
# the only entry type both Claude Code and Codex install from — Codex reports
# "plugin not found" for {"source":"github"}.
validate_entry() {
    local entry_json="$1"
    local name source_type source_url version desc
    name=$(printf '%s' "$entry_json"        | jq -r '.name // ""')
    source_type=$(printf '%s' "$entry_json" | jq -r '.source.source? // ""')
    source_url=$(printf '%s' "$entry_json"  | jq -r '.source.url? // ""')
    version=$(printf '%s' "$entry_json"     | jq -r '.version // ""')
    desc=$(printf '%s' "$entry_json"        | jq -r '.description // ""')

    printf '%s' "$name"        | grep -qE '^[a-z0-9][a-z0-9-]{0,63}$' \
        || { echo "error: entry.name invalid: $name" >&2; return 1; }
    [ "$source_type" = "url" ] \
        || { echo "error: entry.source.source must be 'url': $source_type" >&2; return 1; }
    valid_github_git_url "$source_url" \
        || { echo "error: entry.source.url must be https://github.com/OWNER/REPO.git (no '..'): $source_url" >&2; return 1; }
    printf '%s' "$version"     | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$' \
        || { echo "error: entry.version invalid: $version" >&2; return 1; }
    [ -n "$desc" ] && [ "${#desc}" -le 500 ] \
        || { echo "error: entry.description missing or > 500 chars" >&2; return 1; }
    return 0
}

# preflight SUBCMD
# Checks shared prereqs per Section 5 table. SUBCMD ∈ {register,bump,list}.
# On miss: prints actionable stderr + returns the documented exit code.
preflight() {
    local sub="$1"
    command -v jq  >/dev/null 2>&1 || { echo "error: jq not in PATH; install jq" >&2; return 1; }
    command -v git >/dev/null 2>&1 || { echo "error: git not in PATH" >&2; return 1; }
    command -v gh  >/dev/null 2>&1 || { echo "error: gh not in PATH; install github cli" >&2; return 1; }
    # gh auth: required for register/bump (mutation); optional for list (public read).
    case "$sub" in
        register|bump)
            gh auth status >/dev/null 2>&1 \
                || { echo "error: gh auth missing; next step: 'gh auth login --hostname github.com'" >&2; return 4; }
            ;;
    esac
    return 0
}

usage() {
    cat <<'EOF'
Usage: gitx-marketplace register [--repo OWNER/REPO] [--force] [--dry-run]
       gitx-marketplace bump     [--version vX.Y.Z] [--dry-run]
       gitx-marketplace list     [--repo OWNER/REPO]
       gitx-marketplace --help

Subcommands:
  register   First-time add THIS skill's entry to the central marketplace.
             --repo OWNER/REPO  Marketplace repo (required first time).
             --force            Override existing marker if --repo differs.
             --dry-run          Preview diff/branch/PR without push/PR/merge.
  bump       Update version field. Auto-invoked by 'gitx-release' (best-effort)
             after each successful release when marker present.
             --version vX.Y.Z   Override (default: read ./VERSION).
             --dry-run          Preview without push/PR/merge.
  list       Read-only: list current marketplace plugins[] (no auth required).

Marker:
  .gitx/marketplace-target — single-line plaintext, gitignored, per-machine.
  Created by first 'register'; consumed by 'bump' and 'list'.

Prereqs: gh (authenticated), jq, git. Write access to marketplace repo.

Exit codes:
  0 success / idempotent  1 generic failure  2 usage  3 state  4 permission
EOF
}

cmd_register() {
    local repo="" force=0 dry_run=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo)     repo="${2:?--repo requires value}"; shift 2 ;;
            --force)    force=1; shift ;;
            --dry-run)  dry_run=1; shift ;;
            *) echo "error: unknown arg '$1'; run 'gitx-marketplace register --help'" >&2; return 2 ;;
        esac
    done

    # Preflight + file presence
    [ -f .claude-plugin/marketplace.json ] \
        || { echo "error: .claude-plugin/marketplace.json missing; run 'gitx-init --type=skill --force'" >&2; return 1; }

    # plugins[0] contract: exactly one plugin (Q8 + spec line 134)
    local n_plugins; n_plugins=$(jq '.plugins | length' .claude-plugin/marketplace.json 2>/dev/null || echo 0)
    [ "$n_plugins" = 1 ] \
        || { echo "error: multi-plugin marketplace.json (n=$n_plugins) not supported in v1.13.0" >&2; return 1; }

    preflight register || return $?

    # Marker check (Section 2 register table)
    local existing="" had_marker=0
    if existing=$(read_marker 2>/dev/null); then
        had_marker=1
        validate_marker_content "$existing" \
            || { echo "error: existing marker invalid ($existing); fix .gitx/marketplace-target" >&2; return 1; }
    fi
    if [ -z "$repo" ]; then
        [ "$had_marker" = 1 ] \
            || { echo "error: --repo required for first register" >&2; return 2; }
        repo="$existing"
    fi
    validate_marker_content "$repo" \
        || { echo "error: --repo invalid ($repo); expected OWNER/REPO" >&2; return 2; }
    if [ "$had_marker" = 1 ] && [ "$existing" != "$repo" ]; then
        [ "$force" = 1 ] \
            || { echo "error: marker exists for $existing, --repo $repo conflicts; use --force" >&2; return 2; }
        echo "⚠️  --force: stale entry in $existing may remain orphan — manually 'gh pr' remove if needed" >&2
    fi

    # Extract + validate entry
    local entry; entry=$(jq '.plugins[0]' .claude-plugin/marketplace.json)

    # Transform self-source "./" to {"source":"url","url":"https://github.com/O/R.git"}
    # via .homepage. Claude Code marketplace.json allows source:"./" for plugins
    # co-located with their listing (plugin-self-reference). But the CENTRAL
    # marketplace needs an explicit remote source. Infer from .homepage
    # (https://github.com/OWNER/REPO). Codex round-4 [high] — cross-skill register dogfood gap.
    local entry_source_type; entry_source_type=$(printf '%s' "$entry" | jq -r '.source | type')
    if [ "$entry_source_type" = "string" ]; then
        local raw_source hp inferred_repo
        raw_source=$(printf '%s' "$entry" | jq -r '.source')
        if [ "$raw_source" = "./" ]; then
            hp=$(printf '%s' "$entry" | jq -r '.homepage // ""')
            inferred_repo=$(printf '%s' "$hp" | sed -nE 's#^https://github\.com/([A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+)/?$#\1#p')
            if [ -n "$inferred_repo" ]; then
                # Codex round-5 [low]: reject .. in inferred repo (defense-in-depth)
                case "$inferred_repo" in
                    *..*)
                        echo "error: inferred github repo contains '..' ($inferred_repo); fix .homepage" >&2
                        return 1 ;;
                esac
                entry=$(printf '%s' "$entry" | jq --arg u "https://github.com/${inferred_repo%.git}.git" '.source = {source:"url", url:$u}')
            else
                echo "error: .plugins[0].source is './' but cannot infer github repo from .homepage ($hp)." >&2
                echo "       Set explicit '.source = {source: \"url\", url: \"https://github.com/OWNER/REPO.git\"}' or fix .homepage to 'https://github.com/OWNER/REPO'." >&2
                return 1
            fi
        else
            echo "error: .plugins[0].source is a string ($raw_source) but only './' is supported. Use object form: {source:'url', url:'https://github.com/OWNER/REPO.git'}." >&2
            return 1
        fi
    elif [ "$(printf '%s' "$entry" | jq -r '.source.source? // ""')" = "github" ]; then
        # Legacy {"source":"github","repo":R} → url form (Codex cannot install github entries).
        local legacy_repo
        legacy_repo=$(printf '%s' "$entry" | jq -r '.source.repo // ""')
        entry=$(printf '%s' "$entry" | jq --arg u "https://github.com/${legacy_repo%.git}.git" \
            '.source = ({source:"url", url:$u} + (.source | del(.source, .repo, .url)))')
    fi

    validate_entry "$entry" || return 1

    # Write marker (after all validation passes) — deliberately BEFORE the presence
    # probe below. If the entry turns out already-present (probe → "use bump",
    # exit 3) the marker must still persist: bump/list read it to locate the target
    # repo, so writing it only on the success path would strand the
    # already-registered → bump handoff. A failed PR flow likewise leaves the marker
    # as recorded intent (re-running register is idempotent).
    # A symlinked marker/.gitx would redirect this write onto an arbitrary file
    # (e.g. ~/.zshrc), so refuse before touching anything — also under --dry-run.
    _refuse_symlink_path .gitx/marketplace-target || return 1
    if [ "$dry_run" = 1 ]; then
        echo "[dry-run] would write .gitx/marketplace-target=$repo"
    else
        mkdir -p .gitx
        printf '%s\n' "$repo" > .gitx/marketplace-target
    fi

    # Probe: is entry already present in target marketplace?
    # 2-step: first decode + validate JSON shape, then check entry presence.
    # Codex round-5 [medium] — malformed JSON used to silently degrade to "absent".
    local entry_name probe_rc=0 _decoded
    entry_name=$(printf '%s' "$entry" | jq -r '.name')
    _decoded=$(fetch_marketplace_json "$repo")
    if [ -n "$_decoded" ]; then
        if ! printf '%s' "$_decoded" | jq -e '.plugins | type == "array"' >/dev/null 2>&1; then
            echo "error: $repo/.claude-plugin/marketplace.json appears corrupt (not valid JSON with plugins[] array); aborting register" >&2
            return 1
        fi
        if printf '%s' "$_decoded" | jq -e --arg n "$entry_name" '.plugins[] | select(.name == $n)' >/dev/null 2>&1; then
            probe_rc=0   # found
        else
            probe_rc=1   # absent
        fi
    else
        probe_rc=2  # gh failed entirely (network/auth/404) — treat as absent + warn
    fi
    if [ "$probe_rc" = 0 ]; then
        echo "error: entry '$entry_name' already in $repo; use 'gitx-marketplace bump' instead" >&2
        return 3
    fi

    # Dry-run: emit intent, exit 0
    if [ "$dry_run" = 1 ]; then
        local version desc
        version=$(printf '%s' "$entry" | jq -r '.version')
        desc=$(printf '%s' "$entry" | jq -r '.description')
        cat <<EOF
Intended marketplace.json diff:
  + plugins += $entry
Intended branch: add-$entry_name-v$version
Intended PR title: add($entry_name): v$version initial entry
Intended PR body:  $desc
EOF
        return 0
    fi

    # ---- Live path ----------------------------------------------------------
    local tmp_clone branch pr_title pr_body version
    version=$(printf '%s' "$entry" | jq -r '.version' | sed 's/^v//')
    branch="add-$entry_name-v$version"
    pr_title="add($entry_name): v$version initial entry"
    pr_body=$(printf '%s' "$entry" | jq -r '.description')

    tmp_clone=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf \"$tmp_clone\"" RETURN

    # Shallow clone marketplace
    gh repo clone "$repo" "$tmp_clone" -- --depth=1 >/dev/null 2>&1 \
        || git clone --depth=1 "https://github.com/$repo" "$tmp_clone" >/dev/null 2>&1 \
        || { echo "error: clone of $repo failed (network/auth/branch protection)" >&2; return 1; }

    # Stale branch / orphan PR check (an unreadable PR list counts as orphan)
    local pr_num sha
    pr_num=$(_pick_pr "$tmp_clone" "$branch" "") && [ -z "$pr_num" ] || {
        echo "error: open PR(s) for branch $branch in $repo, or PR list unreadable; inspect 'gh pr list -R $repo --head $branch', close it manually or wait" >&2
        return 1
    }
    if (cd "$tmp_clone" && git ls-remote --heads origin "$branch" 2>/dev/null | grep -q "refs/heads/$branch$"); then
        echo "error: orphan remote branch $branch in $repo; delete it or 'gh pr' close" >&2
        return 1
    fi

    # Append entry via jq
    local mfile="$tmp_clone/.claude-plugin/marketplace.json"
    [ -f "$mfile" ] || { echo "error: $repo missing .claude-plugin/marketplace.json" >&2; return 1; }
    jq --argjson e "$entry" '.plugins += [$e]' "$mfile" > "$mfile.new" && mv "$mfile.new" "$mfile"

    # Branch + commit + push + PR + merge
    (
        cd "$tmp_clone"
        git config user.name  "gitx-marketplace"
        git config user.email "noreply@github.com"
        git checkout -b "$branch" >/dev/null 2>&1
        git add .claude-plugin/marketplace.json
        git commit -m "$pr_title" -m "$pr_body" >/dev/null 2>&1
        git push -u origin "$branch" >/dev/null 2>&1 || exit 1
        gh pr create --title "$pr_title" --body "$pr_body" --head "$branch" --base main >/dev/null 2>&1 || exit 1
    ) || { echo "error: marketplace PR flow failed; check 'gh pr list -R $repo'" >&2; return 1; }
    # Merge only the PR whose head is the commit we just pushed, pinned to it.
    sha=$(cd "$tmp_clone" && git rev-parse HEAD) \
        && pr_num=$(_pick_pr "$tmp_clone" "$branch" "$sha") && [ -n "$pr_num" ] \
        && (cd "$tmp_clone" && gh pr merge "$pr_num" --squash --delete-branch --match-head-commit "$sha" >/dev/null 2>&1) \
        || { echo "error: marketplace PR for $branch could not be verified/merged; check 'gh pr list -R $repo --head $branch'" >&2; return 1; }

    echo "✅ marketplace registered: $repo → $entry_name v$version"
    return 0
}
cmd_bump() {
    local override_version="" dry_run=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --version)  override_version="${2:?--version requires value}"; shift 2 ;;
            --dry-run)  dry_run=1; shift ;;
            *) echo "error: unknown arg '$1'" >&2; return 2 ;;
        esac
    done

    # Early CLI-arg semver validation (usage error must return 2 regardless of
    # downstream preflight / gh auth / network state; Codex round-3 [low]).
    if [ -n "$override_version" ]; then
        local _early_v
        _early_v=$(printf '%s' "$override_version" | sed 's/^v//')
        printf '%s' "$_early_v" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$' \
            || { echo "error: --version '$override_version' not semver (expected vX.Y.Z or X.Y.Z)" >&2; return 2; }
    fi

    [ -f .claude-plugin/marketplace.json ] \
        || { echo "error: .claude-plugin/marketplace.json missing" >&2; return 1; }

    local repo
    repo=$(read_marker) \
        || { echo "error: no marker; run 'gitx-marketplace register --repo R' first" >&2; return 2; }
    validate_marker_content "$repo" \
        || { echo "error: marker invalid ($repo); expected OWNER/REPO" >&2; return 1; }

    preflight bump || return $?

    local target_v
    if [ -n "$override_version" ]; then
        target_v="$override_version"
    else
        [ -f VERSION ] || { echo "error: ./VERSION missing and no --version override" >&2; return 1; }
        target_v=$(tr -d '[:space:]' < VERSION)
    fi
    target_v=$(printf '%s' "$target_v" | sed 's/^v//')
    printf '%s' "$target_v" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$' \
        || { echo "error: version '$target_v' not semver (expected vX.Y.Z or X.Y.Z)" >&2; return 2; }

    local entry_name
    entry_name=$(jq -r '.plugins[0].name // ""' .claude-plugin/marketplace.json)
    [ -n "$entry_name" ] || { echo "error: no plugins[0].name in marketplace.json" >&2; return 1; }

    # Probe current marketplace version for entry.
    # 2-step decode → validate shape → extract, mirroring cmd_register's probe so a
    # failing/corrupt remote yields an actionable exit, NOT a set -e abort: under
    # `set -euo pipefail` an unguarded `current_v=$(gh … | … | head -1)` aborts the
    # whole function on any stage failure (gh non-zero on 404/network), bypassing
    # the exit-3 path below and leaking jq's exit 5 on corrupt JSON.
    local _decoded current_v=""
    _decoded=$(fetch_marketplace_json "$repo")
    if [ -z "$_decoded" ]; then
        echo "error: cannot read $repo/.claude-plugin/marketplace.json (network/auth/404); cannot bump" >&2
        return 3
    fi
    if ! printf '%s' "$_decoded" | jq -e '.plugins | type == "array"' >/dev/null 2>&1; then
        echo "error: $repo/.claude-plugin/marketplace.json appears corrupt (not valid JSON with plugins[] array); aborting bump" >&2
        return 1
    fi
    local cur_entry cur_src_type cur_src canon_url=""
    cur_entry=$(printf '%s' "$_decoded" | jq -c --arg n "$entry_name" 'first(.plugins[] | select(.name == $n)) // empty' 2>/dev/null || true)
    current_v=$(printf '%s' "$cur_entry" | jq -r '.version // ""' 2>/dev/null | sed 's/^v//' || true)

    [ -n "$current_v" ] \
        || { echo "error: entry '$entry_name' NOT in $repo; run 'gitx-marketplace register --repo $repo' first" >&2; return 3; }

    # Canonical source is {"source":"url","url":"https://github.com/O/R.git"} (Codex
    # cannot install {"source":"github"}). A legacy github entry is migrated by every
    # bump — even at an unchanged version — so the live central entry converges
    # without anyone knowing whether it was already migrated by hand.
    cur_src=$(printf '%s' "$cur_entry" | jq -c '.source // null')
    cur_src_type=$(printf '%s' "$cur_entry" | jq -r '.source.source? // ""')
    if [ "$cur_src_type" = "url" ]; then
        canon_url=$(printf '%s' "$cur_entry" | jq -r '.source.url // ""')
    elif [ "$cur_src_type" = "github" ]; then
        canon_url=$(printf '%s' "$cur_entry" | jq -r '.source.repo // ""')
        canon_url="https://github.com/${canon_url%.git}.git"
    fi
    valid_github_git_url "$canon_url" || {
        echo "error: entry '$entry_name' in $repo has an unrecognised source $cur_src;" >&2
        echo "       fix it by hand to {\"source\":\"url\",\"url\":\"https://github.com/OWNER/REPO.git\"}" >&2
        return 1
    }

    if [ "$current_v" = "$target_v" ] && [ "$cur_src_type" = "url" ]; then
        echo "no-op: marketplace already at v$target_v (url source)"
        return 0
    fi

    # The one intended change, applied to the central marketplace.json. Fields other
    # than .version and .source (and extra source keys such as ref/sha) stay as-is.
    local xform='(.plugins[] | select(.name == $n)) |= (.version = $v | .source = ({source:"url", url:$u} + (.source | del(.source, .repo, .url))))'
    local branch="bump-$entry_name-v$target_v" title
    if [ "$current_v" = "$target_v" ]; then
        title="bump($entry_name): v$target_v source → url"
    else
        title="bump($entry_name): v$current_v → v$target_v"
    fi

    if [ "$dry_run" = 1 ]; then
        cat <<EOF
Intended marketplace.json diff:
  ~ plugins[name=$entry_name].version: $current_v → $target_v
  ~ plugins[name=$entry_name].source:  $cur_src → {"source":"url","url":"$canon_url"}
Intended branch: $branch
Intended PR title: $title
EOF
        return 0
    fi

    # Live path
    local tmp_clone; tmp_clone=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf \"$tmp_clone\"" RETURN
    git clone --depth=1 "https://github.com/$repo" "$tmp_clone" >/dev/null 2>&1 \
        || { echo "error: clone of $repo failed" >&2; return 1; }

    local mfile="$tmp_clone/.claude-plugin/marketplace.json" expected
    [ -f "$mfile" ] || { echo "error: $repo missing .claude-plugin/marketplace.json" >&2; return 1; }
    expected=$(jq -S -c --arg n "$entry_name" --arg v "$target_v" --arg u "$canon_url" "$xform" "$mfile") \
        || { echo "error: cannot apply bump to $repo marketplace.json" >&2; return 1; }

    # Resume state. Anything we cannot determine is a failure, never "absent":
    # guessing "no branch / no PR" here would push or merge on top of unknown state.
    local ls_out sha="" pr_num
    ls_out=$(cd "$tmp_clone" && git ls-remote --heads origin "refs/heads/$branch" 2>/dev/null) \
        || { echo "error: cannot list branches of $repo; refusing to guess (re-run later)" >&2; return 1; }

    local recover="       recovery: inspect it ('gh pr list -R $repo --head $branch --state all'; compare the branch with main);
                 if it is stale, close its PR and delete the branch by hand, then re-run
                 'gitx-marketplace bump --version v$target_v'. Nothing was deleted or overwritten."

    if [ -n "$ls_out" ]; then
        # A previous run (or someone else) left $branch. Reuse it only if its whole
        # diff against main is exactly this bump: marketplace.json alone, and that
        # file semantically equal to the intended result. The SHA verified here is
        # the only head we will later merge.
        case "$ls_out" in
            *$'\n'*) echo "error: several remote refs match $branch in $repo" >&2; echo "$recover" >&2; return 1 ;;
        esac
        sha="${ls_out%%[[:space:]]*}"
        local changed got fetched
        (cd "$tmp_clone" && git fetch --depth=1 origin "refs/heads/$branch:refs/remotes/origin/$branch" >/dev/null 2>&1) \
            || { echo "error: cannot fetch existing branch $branch from $repo" >&2; return 1; }
        fetched=$(cd "$tmp_clone" && git rev-parse "refs/remotes/origin/$branch") \
            || { echo "error: cannot resolve fetched branch $branch" >&2; return 1; }
        [ "$fetched" = "$sha" ] \
            || { echo "error: branch $branch moved while being verified ($sha → $fetched)" >&2; echo "$recover" >&2; return 1; }
        changed=$(cd "$tmp_clone" && git diff --name-only HEAD "$sha") \
            || { echo "error: cannot diff existing branch $branch against main" >&2; return 1; }
        got=$(cd "$tmp_clone" && git show "$sha:.claude-plugin/marketplace.json" 2>/dev/null | jq -S -c . 2>/dev/null || true)
        if [ "$changed" != ".claude-plugin/marketplace.json" ] || [ "$got" != "$expected" ]; then
            echo "error: remote branch $branch in $repo already exists but differs from this bump (relative to main); refusing to reuse it." >&2
            echo "$recover" >&2
            return 1
        fi
        echo "resuming: reusing existing branch $branch at $sha" >&2
    else
        pr_num=$(_pick_pr "$tmp_clone" "$branch" "") && [ -z "$pr_num" ] || {
            echo "error: open PR(s) use head name $branch but no such branch exists in $repo (or the PR list is unreadable)." >&2
            echo "$recover" >&2
            return 1
        }
        jq --arg n "$entry_name" --arg v "$target_v" --arg u "$canon_url" "$xform" "$mfile" > "$mfile.new" \
            && mv "$mfile.new" "$mfile"
        (
            cd "$tmp_clone"
            git config user.name  "gitx-marketplace"
            git config user.email "noreply@github.com"
            git checkout -b "$branch" >/dev/null 2>&1
            git add .claude-plugin/marketplace.json
            git commit -m "$title" >/dev/null 2>&1
            git push -u origin "$branch" >/dev/null 2>&1
        ) || { echo "error: push of $branch to $repo failed; re-run 'gitx-marketplace bump --version v$target_v'" >&2; return 1; }
        sha=$(cd "$tmp_clone" && git rev-parse HEAD) \
            || { echo "error: cannot resolve pushed commit" >&2; return 1; }
    fi

    # Only a same-repo PR into main whose head is the verified/pushed commit may be
    # merged, and the merge is pinned to that commit (no TOCTOU on the head).
    pr_num=$(_pick_pr "$tmp_clone" "$branch" "$sha") || {
        echo "error: an open PR with head name $branch is cross-repository, targets another base, or is not at the verified commit $sha (or the PR list is unreadable); refusing to merge." >&2
        echo "$recover" >&2
        return 1
    }
    if [ -z "$pr_num" ]; then
        (cd "$tmp_clone" && gh pr create --title "$title" --body "automated bump" --head "$branch" --base main >/dev/null 2>&1) \
            || { echo "error: marketplace bump PR create failed; branch $branch kept — re-run 'gitx-marketplace bump --version v$target_v' to resume" >&2; return 1; }
        pr_num=$(_pick_pr "$tmp_clone" "$branch" "$sha") && [ -n "$pr_num" ] || {
            echo "error: created PR for $branch cannot be verified (same repo, base main, head $sha); refusing to merge." >&2
            echo "$recover" >&2
            return 1
        }
    fi
    (cd "$tmp_clone" && gh pr merge "$pr_num" --squash --delete-branch --match-head-commit "$sha" >/dev/null 2>&1) \
        || { echo "error: marketplace bump PR #$pr_num merge failed; branch $branch kept — re-run 'gitx-marketplace bump --version v$target_v' to resume" >&2; return 1; }

    echo "✅ marketplace bumped: $repo → $entry_name v$target_v"
    return 0
}
cmd_list() {
    local repo="" dry_run=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo) repo="${2:?--repo requires value}"; shift 2 ;;
            --dry-run) dry_run=1; shift ;;
            *) echo "error: unknown arg '$1'" >&2; return 2 ;;
        esac
    done
    if [ -z "$repo" ]; then
        repo=$(read_marker) \
            || { echo "error: no marker and no --repo; pass --repo OWNER/REPO" >&2; return 2; }
    fi
    validate_marker_content "$repo" \
        || { echo "error: --repo invalid ($repo); expected OWNER/REPO" >&2; return 2; }
    command -v gh >/dev/null 2>&1 || { echo "error: gh missing" >&2; return 1; }
    command -v jq >/dev/null 2>&1 || { echo "error: jq missing" >&2; return 1; }

    local raw
    raw=$(gh api "/repos/$repo/contents/.claude-plugin/marketplace.json" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null) \
        || { echo "error: gh api failed for $repo (network/auth/404)" >&2; return 1; }
    [ -n "$raw" ] || { echo "error: empty marketplace.json from $repo" >&2; return 1; }

    printf 'NAME\tVERSION\tSOURCE\n'
    printf '%s' "$raw" | jq -r '.plugins[] | "\(.name)\t\(.version)\t\(.source.repo? // .source.url? // .homepage // "—")"'
    return 0
}

main() {
    case "${1:-}" in
        register) shift; cmd_register "$@" ;;
        bump)     shift; cmd_bump     "$@" ;;
        list)     shift; cmd_list     "$@" ;;
        -h|--help|"") usage ;;
        *) echo "error: unknown subcommand '${1}'; run 'gitx-marketplace --help'" >&2; exit 2 ;;
    esac
}

# Allow sourcing (for test reuse of helper functions) without auto-running.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
