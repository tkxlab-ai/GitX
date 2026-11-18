#!/bin/bash
# gitx-release.sh — one-command GitX release wrapper
# usage: gitx-release.sh [--dry-run] [--version vX.Y.Z]
# exit:  0 release completed, 1 release failed, 2 usage / unsupported version /
#        unusable version manifest (bad JSON, no jq),
#        5 refusing to write through a symlinked version / CHANGELOG path

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

DRY_RUN=0
REQUESTED_VERSION=""
SKIP_GITEA_RELEASE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        # Kept so existing invocations do not break: the internal release no
        # longer touches the central marketplace (design D5 — every
        # outward-facing step runs together in gitx-publish.sh after the
        # GitHub draft is approved), so there is nothing left to skip.
        --skip-marketplace)
            echo "ℹ️  --skip-marketplace is a no-op: the central-marketplace bump moved to scripts/gitx-publish.sh (run after approving the GitHub draft)." >&2
            ;;
        --skip-gitea-release) SKIP_GITEA_RELEASE=1 ;;
        --version)
            shift
            REQUESTED_VERSION="${1:-}"
            [ -n "$REQUESTED_VERSION" ] || { echo "❌ --version requires vX.Y.Z" >&2; exit 2; }
            ;;
        -h|--help)
            cat <<'EOF'
Usage: gitx-release [--dry-run] [--version vX.Y.Z] [--skip-marketplace] [--skip-gitea-release] [--help]

  --dry-run            Preview release without writing artifacts.
  --version vX.Y.Z     Override auto-bump (default: patch bump).
  --skip-marketplace   No-op, accepted for compatibility. This internal release never
                       bumps the central marketplace; that happens in
                       scripts/gitx-publish.sh, after the GitHub draft is approved.
  --skip-gitea-release Skip the post-release Gitea release-repo publish this run only.
                       Marker is NOT removed; next 'gitx-release' publishes again.
                       To persistently opt out: rm .gitx/gitea-release-target.

Examples:
  gitx-release                          # Standard release + Gitea publish (if opted in)
  gitx-release --skip-gitea-release     # Release without the Gitea publish this run
  gitx-release --dry-run                # Preview the release
EOF
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1" >&2
            echo "   Usage: $0 [--dry-run] [--version vX.Y.Z]" >&2
            exit 2
            ;;
    esac
    shift
done

# ---- logging helper (stderr + RELEASE_LOG) ---------------------------------

log_warn() {
    local msg="$1"
    printf '⚠️  %s\n' "$msg" >&2
    if [ -n "${RELEASE_LOG:-}" ]; then
        mkdir -p "$(dirname "$RELEASE_LOG")" 2>/dev/null || true
        printf '[%s] WARN %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$msg" >> "$RELEASE_LOG" 2>/dev/null || true
    fi
}

# Env override is a test seam (the one-command suite points it at a recorder).
GITEA_RELEASE_BIN="${GITEA_RELEASE_BIN:-$SCRIPT_DIR/gitx-gitea-release.sh}"

# ---- v1.13.0: Gitea release-repo publish hook (post-release, opt-in) -------

invoke_gitea_release() {
    # Opt-in via a marker, runs in the project root, best-effort — the local
    # release already succeeded, so a publish failure only warns. gitx-gitea-release.sh itself is strict
    # (exit 1/2); `|| rc=$?` keeps that status from aborting a `set -e` caller.
    (
    cd "${PROJECT_ROOT:-.}" || exit 0
    [ "${SKIP_GITEA_RELEASE:-0}" -eq 1 ] && return 0

    [ -f .gitx/gitea-release-target ] || return 0
    [ -f "$GITEA_RELEASE_BIN" ] || {
        log_warn "gitea release step: $GITEA_RELEASE_BIN not found — skipping."
        return 0
    }

    local V="${VERSION:-}" rc
    if [ -z "$V" ] && [ -f VERSION ]; then
        V=$(tr -d '[:space:]' < VERSION)
    fi
    [ -n "$V" ] || {
        log_warn "gitea release step: no version (VERSION unset, no VERSION file) — skipping."
        return 0
    }
    case "$V" in v*) ;; *) V="v$V" ;; esac

    printf '→ publishing %s to the Gitea release repo (post-release best-effort)…\n' "$V" >&2
    # Explicit PROJECT_* like the wrapper's other children: the publish must
    # resolve the same Release/<project>-<version>/ the wrapper just built
    # (an empty value falls back to the script's own derivation).
    rc=0
    PROJECT_ROOT="${PROJECT_ROOT:-}" PROJECT_NAME="${PROJECT_NAME:-}" SKILL_NAME="${SKILL_NAME:-}" \
        bash "$GITEA_RELEASE_BIN" --version "$V" || rc=$?
    if [ "$rc" -ne 0 ]; then
        # The script's stderr above carries the cause; --force is only right
        # for the two stale cases it names.
        log_warn "gitea release step failed (exit $rc) — the local release is unaffected.
                 Re-run after diagnosing: bash $GITEA_RELEASE_BIN --version $V
                 (add --force only if it reported (1) the remote tag exists with different
                 checksums, or (2) the tag matches but the Gitea Release assets are stale
                 or its checksums.txt asset is missing)."
    fi
    return 0
    )
}

LOG_FILE=""
init_wrapper_log() {
    local log_dir stamp initial_version
    PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]')}"
    log_dir="$PROJECT_ROOT/Release/logs"
    mkdir -p "$log_dir"
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    initial_version="${REQUESTED_VERSION:-auto}"
    LOG_FILE="$log_dir/gitx-release-${stamp}-${initial_version}.log"
    {
        echo "event=gitx_release_start"
        echo "timestamp_utc=$stamp"
        echo "project_root=$PROJECT_ROOT"
        echo "project_name=$PROJECT_NAME"
        echo "skill_name=${SKILL_NAME:-unknown}"
        echo "previous_version=unknown"
        echo "version=$initial_version"
        echo "wrapper=$0"
        echo "--- output ---"
    } > "$LOG_FILE"
}

fail_with_log() {
    local status="$1"
    {
        echo "--- result ---"
        echo "exit_code=$status"
    } >> "$LOG_FILE"
    echo ""
    echo "❌ GitX release failed. Diagnostic log: $LOG_FILE"
    exit "$status"
}

# Refuses to write through a symlinked path or any symlinked parent (relative
# to cwd). Used before the first wrapper write — the diagnostic log.
_refuse_symlink_path() { local d="$1"; while [ -n "$d" ] && [ "$d" != "." ] && [ "$d" != "/" ]; do if [ -L "$d" ]; then echo "❌ $d is a symlink — refusing to write through it" >&2; return 1; fi; d="$(dirname "$d")"; done; return 0; }

# init_wrapper_log mkdirs + writes Release/logs/ in every mode (dry-run too);
# a committed Release symlink would receive the log in its target. No log
# exists yet, so report on stderr only.
if ! (cd "$PROJECT_ROOT" && _refuse_symlink_path Release/logs); then
    exit 5
fi

init_wrapper_log

detect_err="$(mktemp)"
set +e
source "$SCRIPT_DIR/lib/detect-project.sh" 2>"$detect_err"
detect_status=$?
set -e
if [ -s "$detect_err" ]; then
    cat "$detect_err" | tee -a "$LOG_FILE" >&2
fi
rm -f "$detect_err"
if [ "$detect_status" -ne 0 ]; then
    fail_with_log "$detect_status"
fi

SKILL_MD="$PROJECT_ROOT/skills/$SKILL_NAME/SKILL.md"
if [ ! -f "$SKILL_MD" ]; then
    echo "❌ Missing skill file: $SKILL_MD" | tee -a "$LOG_FILE" >&2
    fail_with_log 2
fi
VERSION_FILE="$PROJECT_ROOT/skills/$SKILL_NAME/VERSION"

current_skill_version() {
    [ -f "$VERSION_FILE" ] || return 0
    tr -d '[:space:]' < "$VERSION_FILE"
}

next_patch_version() {
    local current="$1"
    if ! echo "$current" | grep -qE '^v[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
        echo "❌ Cannot auto-bump non-stable version: $current" >&2
        echo "   Re-run with --version vX.Y.Z" >&2
        exit 2
    fi

    local body major minor patch
    body="${current#v}"
    major="$(printf '%s' "$body" | awk -F. '{print $1}')"
    minor="$(printf '%s' "$body" | awk -F. '{print $2}')"
    patch="$(printf '%s' "$body" | awk -F. '{print $3}')"
    patch="${patch:-0}"
    patch=$((patch + 1))
    printf 'v%s.%s.%s\n' "$major" "$minor" "$patch"
}

write_version_file() {
    local file="$1"
    local version="$2"
    printf '%s\n' "$version" > "$file"
}

_managed_json_error() { printf '❌ %s\n' "$1" | tee -a "${LOG_FILE:-/dev/null}" >&2; }

# Every file that carries the release version, project-relative, fixed order.
# Codex reads plugin.json, the marketplace reads marketplace.json and npm reads
# package.json — bumping only VERSION would ship them stale. package.json is
# managed only when it IS the npm-target package; any other package.json stays
# untouched (and stays dirty-tree-guarded). Each managed JSON is parsed here,
# before any write, so a broken one fails the release instead of being skipped.
version_managed_files() {
    local f target name jq_needed=0
    echo VERSION
    echo "skills/$SKILL_NAME/VERSION"
    for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
        if [ -f "$PROJECT_ROOT/$f" ]; then jq_needed=1; fi
    done
    if [ -f "$PROJECT_ROOT/.gitx/npm-target" ] && [ -f "$PROJECT_ROOT/package.json" ]; then jq_needed=1; fi
    if [ "$jq_needed" = "1" ] && ! command -v jq >/dev/null 2>&1; then
        _managed_json_error "jq is required to bump the version in .claude-plugin/*.json / package.json — install jq"
        return 1
    fi
    if [ -f "$PROJECT_ROOT/.claude-plugin/plugin.json" ]; then
        jq -e 'type == "object" and (.name | type == "string")' "$PROJECT_ROOT/.claude-plugin/plugin.json" >/dev/null 2>&1 || {
            _managed_json_error ".claude-plugin/plugin.json is not a JSON object with a string .name"
            return 1
        }
        echo .claude-plugin/plugin.json
    fi
    if [ -f "$PROJECT_ROOT/.claude-plugin/marketplace.json" ]; then
        jq -e 'type == "object" and ((.plugins // []) | type == "array")' "$PROJECT_ROOT/.claude-plugin/marketplace.json" >/dev/null 2>&1 || {
            _managed_json_error ".claude-plugin/marketplace.json is not a JSON object with a .plugins array"
            return 1
        }
        echo .claude-plugin/marketplace.json
    fi
    if [ -f "$PROJECT_ROOT/.gitx/npm-target" ] && [ -f "$PROJECT_ROOT/package.json" ]; then
        target="$(tr -d '[:space:]' < "$PROJECT_ROOT/.gitx/npm-target")"
        if [ -z "$target" ]; then
            _managed_json_error ".gitx/npm-target is empty — expected the npm package name"
            return 1
        fi
        if ! name="$(jq -er 'if type == "object" then (.name // "") else error("not an object") end' "$PROJECT_ROOT/package.json" 2>/dev/null)"; then
            _managed_json_error "package.json is not a JSON object — cannot tell whether it is the npm-target package"
            return 1
        fi
        if [ "$name" = "$target" ]; then echo package.json; fi
    fi
    return 0
}

# What the wrapper writes before release.sh: the version files plus the
# CHANGELOG entry from ensure_changelog_entry. Backup/rollback, the symlink
# guard and release.sh's dirty-tree allowance all use exactly this list.
wrapper_mutated_files() {
    version_managed_files || return 1
    echo Release/CHANGELOG.md
}

# jq into a same-dir temp that started as a `cp -p` of the target, so the
# rename keeps the file's mode (a bare mktemp is 0600 and would ship that way).
_write_json_version() {
    local f="$1" filter="$2" tmp
    shift 2
    tmp="$(mktemp "$(dirname "$f")/.gitx-version.XXXXXX")" || return 1
    if cp -p "$f" "$tmp" && jq "$@" "$filter" "$f" > "$tmp" && mv "$tmp" "$f"; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}

update_skill_versions() {
    local version="$1" bare="${1#v}" p plugin_name=""
    while IFS= read -r p; do
        case "$p" in
            VERSION|skills/*/VERSION)
                write_version_file "$PROJECT_ROOT/$p" "$version" ;;
            .claude-plugin/plugin.json|package.json)
                _write_json_version "$PROJECT_ROOT/$p" '.version = $v' --arg v "$bare" || return 1 ;;
            .claude-plugin/marketplace.json)
                if [ -f "$PROJECT_ROOT/.claude-plugin/plugin.json" ]; then
                    plugin_name="$(jq -r '.name' "$PROJECT_ROOT/.claude-plugin/plugin.json")" || return 1
                fi
                _write_json_version "$PROJECT_ROOT/$p" \
                    '.version = $v | (.plugins[]? | select(.name == $n) | .version) = $v' \
                    --arg v "$bare" --arg n "$plugin_name" || return 1 ;;
        esac
    done <<EOF_VMF
$VERSION_MANAGED_FILES
EOF_VMF
    return 0
}

ensure_changelog_entry() {
    local version="$1"
    local changelog="$PROJECT_ROOT/Release/CHANGELOG.md"
    local date title tmp
    date="$(date +%Y-%m-%d)"
    title="$(printf '%s' "$PROJECT_NAME" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"

    mkdir -p "$PROJECT_ROOT/Release"
    if [ ! -f "$changelog" ]; then
        cat > "$changelog" <<EOF
# $title — Release History

记录各版本的关键变化。最新版本在最上面。

EOF
    fi

    if grep -qF "## $version " "$changelog"; then
        return 0
    fi

    tmp="$(mktemp)"
    # v1.2 A1 fix: anchor to first `^## ` line instead of head -4 hardcode.
    # mac-release v0.1.0 self-bake had a 2-line header — the old head-4 logic
    # inserted the new entry below the first existing entry instead of above,
    # so audit §4 saw the wrong "top version" and FAILed. Anchor-based logic
    # auto-detects header length, so any header layout works.
    # awk (not grep|head|cut): grep returns 1 on no match, which under
    # `set -euo pipefail` aborts the wrapper before we can check anchor_line.
    # awk with `/pat/{print NR;exit}` always exits 0 — empty output means "none".
    local anchor_line
    anchor_line=$(awk '/^## / { print NR; exit }' "$changelog")
    if [ -n "$anchor_line" ]; then
        head -n $((anchor_line - 1)) "$changelog" > "$tmp"
    else
        cp "$changelog" "$tmp"
    fi
    # v1.0.8 hardening (Arch #2): the auto-generated entry passes release.sh's
    # TODO gate but isn't a meaningful CHANGELOG body. Embed a sentinel HTML
    # comment so the wrapper can detect "still on auto-line" at end of run
    # and warn the operator to edit before publishing.
    cat >> "$tmp" <<EOF
## $version — $date

<!-- gitx-auto-entry: replace this section with real release notes before publishing -->
- Automated GitX release: run full gate suite, package artifacts, generate attestations, and complete deep audit.

Artifacts: \`Release/${PROJECT_NAME}-$version/\`

---

EOF
    if [ -n "$anchor_line" ]; then
        tail -n +"$anchor_line" "$changelog" >> "$tmp"
    fi
    mv "$tmp" "$changelog"
}

CURRENT_VERSION="$(current_skill_version)"
if [ -z "$CURRENT_VERSION" ]; then
    echo "❌ Missing VERSION sidecar: $VERSION_FILE" | tee -a "$LOG_FILE" >&2
    fail_with_log 2
fi

VERSION="${REQUESTED_VERSION:-$(next_patch_version "$CURRENT_VERSION")}"
if ! echo "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "❌ GitX release version must be stable vX.Y.Z: $VERSION" | tee -a "$LOG_FILE" >&2
    fail_with_log 2
fi

guard_duplicate_release() {
    local release_name release_dir latest_target
    release_name="${PROJECT_NAME}-${VERSION}"
    release_dir="$PROJECT_ROOT/Release/$release_name"

    if [ -d "$release_dir" ]; then
        echo "❌ Release already exists: $release_dir" >&2
        echo "   Refusing duplicate release for $VERSION before invoking release.sh." >&2
        echo "   Move the existing release aside manually if you intentionally need to rebuild it." >&2
        exit 1
    fi

    if [ -L "$PROJECT_ROOT/Release/latest" ]; then
        latest_target="$(readlink "$PROJECT_ROOT/Release/latest" 2>/dev/null || true)"
        if [ "$latest_target" = "$release_name" ]; then
            echo "❌ Release/latest already points to $release_name, but $release_dir is missing." >&2
            echo "   Refusing duplicate release from an inconsistent Release/latest state." >&2
            echo "   Restore the release directory or move Release/latest aside manually before rerunning." >&2
            exit 1
        fi
    fi
}

BACKUP_DIR=""
RELEASE_OK=0
VERSION_MANAGED_FILES=""
WRAPPER_MUTATED_FILES=""
# A file absent at backup time has no copy, so rollback deletes it — a
# wrapper-created root VERSION / CHANGELOG must not survive a failed release.
backup_release_state() {
    local p
    BACKUP_DIR="$(mktemp -d)"
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        if [ -f "$PROJECT_ROOT/$p" ]; then
            mkdir -p "$BACKUP_DIR/files/$(dirname "$p")"
            cp -p "$PROJECT_ROOT/$p" "$BACKUP_DIR/files/$p"
        fi
    done <<EOF_BK
$WRAPPER_MUTATED_FILES
EOF_BK
    return 0
}

restore_release_state() {
    local p
    [ -n "${BACKUP_DIR:-}" ] && [ -d "$BACKUP_DIR" ] || return 0
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        if [ -f "$BACKUP_DIR/files/$p" ]; then
            mkdir -p "$PROJECT_ROOT/$(dirname "$p")" || true
            cp -p "$BACKUP_DIR/files/$p" "$PROJECT_ROOT/$p" || true
        else
            rm -f "$PROJECT_ROOT/$p" || true
        fi
    done <<EOF_RS
$WRAPPER_MUTATED_FILES
EOF_RS
    return 0
}

cleanup_wrapper() {
    local status=$?
    if [ "$DRY_RUN" != "1" ] && [ "$RELEASE_OK" != "1" ] && [ "$status" -ne 0 ]; then
        restore_release_state
    fi
    if [ -n "${BACKUP_DIR:-}" ]; then rm -rf "$BACKUP_DIR"; fi
}
trap cleanup_wrapper EXIT

init_release_log() {
    {
        echo "--- detected ---"
        echo "skill_name=$SKILL_NAME"
        echo "previous_version=$CURRENT_VERSION"
        echo "version=$VERSION"
    } >> "$LOG_FILE"
}

run_release_with_log() {
    local status release_dir dirty_ok
    # release.sh's clean-tree preflight must excuse exactly the files bumped
    # by update_skill_versions + ensure_changelog_entry (uncommitted by design
    # until release). Inline, not exported: only release.sh may see it.
    dirty_ok="$WRAPPER_MUTATED_FILES"
    set +e
    _GITX_WRAPPER_DIRTY_OK="$dirty_ok" \
    PROJECT_ROOT="$PROJECT_ROOT" PROJECT_NAME="$PROJECT_NAME" SKILL_NAME="$SKILL_NAME" \
        bash "$SCRIPT_DIR/release.sh" "$VERSION" 2>&1 | tee -a "$LOG_FILE"
    status=${PIPESTATUS[0]}
    set -e
    {
        echo "--- result ---"
        echo "exit_code=$status"
    } >> "$LOG_FILE"
    if [ "$status" -ne 0 ]; then
        echo ""
        echo "❌ GitX release failed. Diagnostic log: $LOG_FILE"
        exit "$status"
    fi
    RELEASE_OK=1
    # The diagnostic log stays in Release/logs/ (with a .sha256 sidecar) and is
    # NOT copied into Release/<project>-<version>/: that directory is the
    # distributable artifact (audited, every file hashed into checksums.txt),
    # and the log carries absolute PROJECT_ROOT paths plus test-fixture bait
    # that the v1.13.0 all-files sanitizer rightly rejects on a standalone
    # re-audit (Gotcha #105).
    release_dir="$PROJECT_ROOT/Release/${PROJECT_NAME}-${VERSION}"
    if command -v shasum >/dev/null 2>&1; then
        (cd "$(dirname "$LOG_FILE")" && shasum -a 256 "$(basename "$LOG_FILE")" > "$(basename "$LOG_FILE").sha256")
    elif command -v sha256sum >/dev/null 2>&1; then
        (cd "$(dirname "$LOG_FILE")" && sha256sum "$(basename "$LOG_FILE")" > "$(basename "$LOG_FILE").sha256")
    else
        echo "❌ neither shasum nor sha256sum available for release log digest" >&2
        exit 1
    fi
    echo ""
    echo "🧾 GitX release diagnostic log: $LOG_FILE"
    echo "🧾 Log digest: ${LOG_FILE}.sha256"

    # v1.0.8 hardening (Arch #2): if CHANGELOG still bears the auto-entry
    # sentinel, the published artifact ships with placeholder release notes.
    # Warn the operator to replace before any upstream publication. Both root
    # and Release-scoped CHANGELOGs are checked because flatten_docs copies.
    local changelog_root="$PROJECT_ROOT/Release/CHANGELOG.md"
    local changelog_scoped="$release_dir/CHANGELOG.md"
    if [ -f "$changelog_root" ] && grep -qF '<!-- gitx-auto-entry' "$changelog_root"; then
        echo ""
        echo "⚠️  CHANGELOG still has auto-generated placeholder for $VERSION."
        # checksums.txt hashes the release-dir CHANGELOG copies, so editing
        # them in place breaks `shasum -c` and install.sh integrity; the only
        # safe path is source edit + full rebuild (re-scan, re-hash, re-ship).
        echo "    Edit ONLY Release/CHANGELOG.md (source of truth) to replace the"
        echo "    auto-line with real release notes, then delete $release_dir"
        echo "    (plus its *.skill / tarballs and the Release/latest symlink) and re-run"
        echo "    the release BEFORE publishing."
        echo "    Never edit files inside the release dir — they are hashed in checksums.txt."
        echo "    Sentinel: <!-- gitx-auto-entry ... -->"
    elif [ -f "$changelog_scoped" ] && grep -qF '<!-- gitx-auto-entry' "$changelog_scoped"; then
        echo ""
        echo "⚠️  Release-scoped CHANGELOG ($changelog_scoped) still has auto-line sentinel."
        echo "    Fix Release/CHANGELOG.md, delete $release_dir and the Release/latest"
        echo "    symlink, then re-run the release before publishing (never edit the"
        echo "    hashed release-dir copy)."
    fi
}

echo "🚀 GitX release"
echo "   Project: $PROJECT_ROOT"
echo "   Skill:   $SKILL_NAME"
echo "   Version: $CURRENT_VERSION → $VERSION"

guard_duplicate_release

if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] Would update VERSION sidecars and CHANGELOG"
    PROJECT_ROOT="$PROJECT_ROOT" PROJECT_NAME="$PROJECT_NAME" SKILL_NAME="$SKILL_NAME" \
        bash "$SCRIPT_DIR/release.sh" "$VERSION" --dry-run
    exit 0
fi

# A committed symlink at (or above) a file the wrapper bumps would make both
# the bump AND the failure rollback write through it into the link target.
# Refuse before backup/update so not a single byte (or mtime) escapes.
# The lists are resolved first: they parse every managed JSON, so a broken
# one stops the release here, before anything is written.
VERSION_MANAGED_FILES="$(version_managed_files)" || fail_with_log 2
WRAPPER_MUTATED_FILES="$(wrapper_mutated_files)" || fail_with_log 2
while IFS= read -r _wp; do
    if ! _sym_err=$(cd "$PROJECT_ROOT" && _refuse_symlink_path "$_wp" 2>&1); then
        echo "$_sym_err" | tee -a "$LOG_FILE" >&2
        fail_with_log 5
    fi
done <<EOF_SYM
$WRAPPER_MUTATED_FILES
EOF_SYM

backup_release_state
update_skill_versions "$VERSION"
ensure_changelog_entry "$VERSION"
init_release_log

run_release_with_log
release_status=$?

if [ "$release_status" -eq 0 ]; then
    invoke_gitea_release || true        # opt-in, best-effort; never propagates
fi
exit "$release_status"
