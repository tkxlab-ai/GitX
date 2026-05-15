#!/bin/bash
# gitx-release.sh — one-command GitX release wrapper
# usage: gitx-release.sh [--dry-run] [--version vX.Y.Z]
# exit:  0 release completed, 1 release failed, 2 usage / unsupported version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

DRY_RUN=0
REQUESTED_VERSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --version)
            shift
            REQUESTED_VERSION="${1:-}"
            [ -n "$REQUESTED_VERSION" ] || { echo "❌ --version requires vX.Y.Z" >&2; exit 2; }
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--version vX.Y.Z]"
            echo "Default: bump the detected skill VERSION sidecar patch number."
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

update_skill_versions() {
    local version="$1"
    write_version_file "$VERSION_FILE" "$version"
    write_version_file "$PROJECT_ROOT/VERSION" "$version"
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
backup_release_state() {
    BACKUP_DIR="$(mktemp -d)"
    [ -f "$VERSION_FILE" ] && cp "$VERSION_FILE" "$BACKUP_DIR/skill.VERSION"
    [ -f "$PROJECT_ROOT/VERSION" ] && cp "$PROJECT_ROOT/VERSION" "$BACKUP_DIR/root.VERSION"
    [ -f "$PROJECT_ROOT/Release/CHANGELOG.md" ] && cp "$PROJECT_ROOT/Release/CHANGELOG.md" "$BACKUP_DIR/CHANGELOG.md"
    return 0
}

restore_release_state() {
    [ -n "${BACKUP_DIR:-}" ] && [ -d "$BACKUP_DIR" ] || return 0
    [ -f "$BACKUP_DIR/skill.VERSION" ] && cp "$BACKUP_DIR/skill.VERSION" "$VERSION_FILE"
    if [ -f "$BACKUP_DIR/root.VERSION" ]; then
        cp "$BACKUP_DIR/root.VERSION" "$PROJECT_ROOT/VERSION"
    else
        rm -f "$PROJECT_ROOT/VERSION"
    fi
    if [ -f "$BACKUP_DIR/CHANGELOG.md" ]; then
        mkdir -p "$PROJECT_ROOT/Release"
        cp "$BACKUP_DIR/CHANGELOG.md" "$PROJECT_ROOT/Release/CHANGELOG.md"
    else
        rm -f "$PROJECT_ROOT/Release/CHANGELOG.md"
    fi
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
    local status release_dir release_log
    set +e
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
    release_dir="$PROJECT_ROOT/Release/${PROJECT_NAME}-${VERSION}"
    if [ -d "$release_dir" ]; then
        release_log="$release_dir/$(basename "$LOG_FILE")"
        cp "$LOG_FILE" "$release_log"
        if command -v shasum >/dev/null 2>&1; then
            (cd "$release_dir" && shasum -a 256 "$(basename "$release_log")" > "$(basename "$release_log").sha256")
        elif command -v sha256sum >/dev/null 2>&1; then
            (cd "$release_dir" && sha256sum "$(basename "$release_log")" > "$(basename "$release_log").sha256")
        else
            echo "❌ neither shasum nor sha256sum available for release log digest" >&2
            exit 1
        fi
        echo "release_log=$release_log" >> "$LOG_FILE"
    fi
    echo ""
    echo "🧾 GitX release diagnostic log: $LOG_FILE"
    if [ -n "${release_log:-}" ]; then
        echo "🧾 Release-scoped log: $release_log"
    fi

    # v1.0.8 hardening (Arch #2): if CHANGELOG still bears the auto-entry
    # sentinel, the published artifact ships with placeholder release notes.
    # Warn the operator to replace before any upstream publication. Both root
    # and Release-scoped CHANGELOGs are checked because flatten_docs copies.
    local changelog_root="$PROJECT_ROOT/Release/CHANGELOG.md"
    local changelog_scoped="$release_dir/CHANGELOG.md"
    if [ -f "$changelog_root" ] && grep -qF '<!-- gitx-auto-entry' "$changelog_root"; then
        echo ""
        echo "⚠️  CHANGELOG still has auto-generated placeholder for $VERSION."
        echo "    Edit Release/CHANGELOG.md (and the flattened copy in $release_dir)"
        echo "    to replace the auto-line with real release notes BEFORE publishing."
        echo "    Sentinel: <!-- gitx-auto-entry ... -->"
    elif [ -f "$changelog_scoped" ] && grep -qF '<!-- gitx-auto-entry' "$changelog_scoped"; then
        echo ""
        echo "⚠️  Release-scoped CHANGELOG ($changelog_scoped) still has auto-line sentinel."
        echo "    Replace before publishing."
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

backup_release_state
update_skill_versions "$VERSION"
ensure_changelog_entry "$VERSION"
init_release_log

run_release_with_log
