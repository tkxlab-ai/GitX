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

# validate_entry ENTRY_JSON
# Returns 0 if all required fields pass per Section 3 entry-validation table.
validate_entry() {
    local entry_json="$1"
    local name source_type source_repo version desc
    name=$(printf '%s' "$entry_json"        | jq -r '.name // ""')
    source_type=$(printf '%s' "$entry_json" | jq -r '.source.source // ""')
    source_repo=$(printf '%s' "$entry_json" | jq -r '.source.repo // ""')
    version=$(printf '%s' "$entry_json"     | jq -r '.version // ""')
    desc=$(printf '%s' "$entry_json"        | jq -r '.description // ""')

    printf '%s' "$name"        | grep -qE '^[a-z0-9][a-z0-9-]{0,63}$' \
        || { echo "error: entry.name invalid: $name" >&2; return 1; }
    [ "$source_type" = "github" ] \
        || { echo "error: entry.source.source must be 'github': $source_type" >&2; return 1; }
    # Codex round-5 [low]: reject .. in source.repo (defense-in-depth against path traversal)
    case "$source_repo" in
        *..*) echo "error: entry.source.repo contains '..': $source_repo" >&2; return 1 ;;
    esac
    printf '%s' "$source_repo" | grep -qE '^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$' \
        || { echo "error: entry.source.repo invalid: $source_repo" >&2; return 1; }
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

    # Transform self-source "./" to {"source":"github","repo":...} via .homepage.
    # Claude Code marketplace.json allows source:"./" for plugins co-located with
    # their listing (plugin-self-reference). But the CENTRAL marketplace needs
    # an explicit github source. Infer from .homepage (https://github.com/OWNER/REPO).
    # Codex round-4 [high] — cross-skill register dogfood gap.
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
                entry=$(printf '%s' "$entry" | jq --arg r "$inferred_repo" '.source = {source:"github", repo:$r}')
            else
                echo "error: .plugins[0].source is './' but cannot infer github repo from .homepage ($hp)." >&2
                echo "       Set explicit '.source = {source: \"github\", repo: \"OWNER/REPO\"}' or fix .homepage to 'https://github.com/OWNER/REPO'." >&2
                return 1
            fi
        else
            echo "error: .plugins[0].source is a string ($raw_source) but only './' is supported. Use object form: {source:'github', repo:'OWNER/REPO'}." >&2
            return 1
        fi
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

    # Stale branch / orphan PR check
    if (cd "$tmp_clone" && gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null | grep -q '^[0-9]'); then
        echo "error: orphan open PR for branch $branch in $repo; close it manually or wait" >&2
        return 1
    fi
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
        gh pr merge --squash --delete-branch >/dev/null 2>&1 || exit 1
    ) || { echo "error: marketplace PR flow failed; check 'gh pr list -R $repo'" >&2; return 1; }

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
    current_v=$(printf '%s' "$_decoded" | jq -r --arg n "$entry_name" '.plugins[] | select(.name == $n) | .version' 2>/dev/null | sed 's/^v//' | head -1 || true)

    [ -n "$current_v" ] \
        || { echo "error: entry '$entry_name' NOT in $repo; run 'gitx-marketplace register --repo $repo' first" >&2; return 3; }

    if [ "$current_v" = "$target_v" ]; then
        echo "no-op: marketplace already at v$target_v"
        return 0
    fi

    if [ "$dry_run" = 1 ]; then
        cat <<EOF
Intended marketplace.json diff:
  ~ plugins[name=$entry_name].version: $current_v → $target_v
Intended branch: bump-$entry_name-v$target_v
Intended PR title: bump($entry_name): v$current_v → v$target_v
EOF
        return 0
    fi

    # Live path
    local tmp_clone; tmp_clone=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf \"$tmp_clone\"" RETURN
    git clone --depth=1 "https://github.com/$repo" "$tmp_clone" >/dev/null 2>&1 \
        || { echo "error: clone of $repo failed" >&2; return 1; }

    local branch="bump-$entry_name-v$target_v"
    if (cd "$tmp_clone" && gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null | grep -q '^[0-9]'); then
        echo "error: orphan open PR for $branch" >&2; return 1
    fi
    # Parity with cmd_register: check for orphan remote branch
    if (cd "$tmp_clone" && git ls-remote --heads origin "$branch" 2>/dev/null | grep -q "refs/heads/$branch$"); then
        echo "error: orphan remote branch $branch in $repo; delete it or 'gh pr' close" >&2
        return 1
    fi

    local mfile="$tmp_clone/.claude-plugin/marketplace.json"
    jq --arg n "$entry_name" --arg v "$target_v" \
        '(.plugins[] | select(.name == $n) | .version) = $v' "$mfile" > "$mfile.new" \
        && mv "$mfile.new" "$mfile"

    (
        cd "$tmp_clone"
        git config user.name  "gitx-marketplace"
        git config user.email "noreply@github.com"
        git checkout -b "$branch" >/dev/null 2>&1
        git add .claude-plugin/marketplace.json
        git commit -m "bump($entry_name): v$current_v → v$target_v" >/dev/null 2>&1
        git push -u origin "$branch" >/dev/null 2>&1 || exit 1
        gh pr create --title "bump($entry_name): v$current_v → v$target_v" --body "automated bump" --head "$branch" --base main >/dev/null 2>&1 || exit 1
        gh pr merge --squash --delete-branch >/dev/null 2>&1 || exit 1
    ) || { echo "error: marketplace bump PR flow failed" >&2; return 1; }

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
    printf '%s' "$raw" | jq -r '.plugins[] | "\(.name)\t\(.version)\t\(.source.repo // .homepage // "—")"'
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
