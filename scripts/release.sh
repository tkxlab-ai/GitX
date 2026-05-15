#!/bin/bash
# release.sh — TKX generic release pipeline (skill-packaged)
# usage:
#   cd <project-root>
#   PROJECT_ROOT=$(pwd) bash <skill-path>/scripts/release.sh <version> [--dry-run]
#
# Or via thin wrapper in project root (see skill docs).
#
# Env vars:
#   PROJECT_ROOT   default: $(pwd)                — 项目仓根
#   PROJECT_NAME   default: basename($PROJECT_ROOT), lowercased — artifact 命名用
#   SKILL_NAME     default: auto-detect from $PROJECT_ROOT/skills/*/SKILL.md  — 打包目标
#   .sanitize-ignore  — 白名单文件（项目根），代替已删除的 FORCE=1 绕过（S3-1）
#
# Flags:
#   --dry-run       Validate everything but skip filesystem-mutating steps
#
# Produces (under $PROJECT_ROOT/Release/<version>/):
#   <project>-<version>.skill            — 单文件分发
#   <project>-<version>-source.tar.gz    — 完整源码
#   README.md / INSTALL.md / CHANGELOG.md / ...  — 平摊文档
#   RELEASE_NOTES.md                      — 本版本说明（自动生成）
#   install.sh                            — 平摊安装脚本

set -euo pipefail

# P1-6: Propagate trap across subshells and function calls for robust cleanup
set -o errtrace

# --- Resolve self location ---
SKILL_ROOT="$(cd "$(dirname "$0")" && pwd)"   # scripts/ 目录 — audit/sanitize 就在这里

# --- Version arg + flags ---
DRY_RUN=0
VERSION=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$arg"
            fi
            ;;
    esac
done
VERSION="${VERSION:?Usage: PROJECT_ROOT=<dir> bash $0 <version> [--dry-run]}"
if ! echo "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+(\.[0-9]+)?(-(alpha|beta|rc)\.?[0-9]*)?$'; then
    echo "❌ Invalid version: $VERSION (expected vX.Y[.Z][-alpha|beta|rc[.N]])"
    exit 1
fi

# --- Project context ---
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
[ -d "$PROJECT_ROOT" ] || { echo "❌ PROJECT_ROOT 不存在: $PROJECT_ROOT"; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"   # normalize

# Auto-detect PROJECT_NAME + SKILL_NAME via shared lib
source "$SKILL_ROOT/lib/detect-project.sh"

# v0.9.10: versioned dir includes PROJECT_NAME prefix so monorepos and
# multi-project review surfaces can tell what's in Release/ at a glance.
RELEASE_DIR="$PROJECT_ROOT/Release/${PROJECT_NAME}-${VERSION}"

# --- Helper: safe_version (escape regex meta-chars for awk/grep contexts) ---
# v1.0.8 hardening (Sec Minor #1): VERSION is already pre-validated to a
# safe charset by the regex at line 47, so today only `.` matters. Escape
# the broader set defensively in case the validation regex is ever loosened
# (e.g., to allow build-metadata `+` or pre-release `~` characters).
safe_version() {
    printf '%s' "$1" | sed 's/[.[*+?(){}\\^$|]/\\&/g'
}

# --- Dry-run wrapper ---
run() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] $*"
    else
        "$@"
    fi
}

# --- Consolidated cleanup trap ---
CLEANUP_EXTRAS=()
RELEASE_DIR_CREATED=0
cleanup_on_fail() {
    if [ "$RELEASE_DIR_CREATED" = "1" ] && [ -d "$RELEASE_DIR" ] && [ "${RELEASE_SUCCESS:-0}" != "1" ]; then
        echo "🧹 Cleaning up failed release: $RELEASE_DIR"
        rm -rf "$RELEASE_DIR"
    fi
    if [ -n "${SKILL_CREATOR_ERR:-}" ]; then rm -f "$SKILL_CREATOR_ERR"; fi
    if [ -n "${STAGE:-}" ]; then rm -rf "$STAGE"; fi
    if [ -n "${SKILL_STAGE:-}" ]; then rm -rf "$SKILL_STAGE"; fi
    if [ "${#CLEANUP_EXTRAS[@]}" -gt 0 ]; then rm -rf "${CLEANUP_EXTRAS[@]}"; fi
}
trap 'cleanup_on_fail' EXIT

# ============================================================
# Function definitions
# ============================================================

preflight_external_tools() {
    # v1.0.8 hardening (Arch #3): README claims "pure Bash, no external deps"
    # but the pipeline relies on these system tools. Probe each up front so
    # missing ones produce a clear actionable message instead of a cryptic
    # mid-flight failure. SHA tools probed separately at checksums step.
    local missing=()
    for t in rsync tar gzip unzip awk sed grep find diff; do
        if ! command -v "$t" >/dev/null 2>&1; then
            missing+=("$t")
        fi
    done
    if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
        missing+=("shasum or sha256sum")
    fi
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "❌ Missing required external tools: ${missing[*]}" >&2
        echo "   This pipeline depends on POSIX-ish coreutils plus tar/gzip/zip/rsync." >&2
        echo "   Install the missing tools and rerun." >&2
        exit 1
    fi
}

preflight_checks() {
    # --- Pre-flight: VERSION sidecar consistency (S3-3) ---
    SKILL_MD_PATH="$PROJECT_ROOT/skills/$SKILL_NAME/SKILL.md"
    VERSION_FILE="$PROJECT_ROOT/skills/$SKILL_NAME/VERSION"
    if [ -f "$SKILL_MD_PATH" ]; then
        if awk '/^---$/{c++; next} c==1 && /^metadata:[[:space:]]*$/{found=1} END{exit found ? 0 : 1}' "$SKILL_MD_PATH"; then
            echo "❌ $SKILL_MD_PATH 含 Codex 不兼容的 frontmatter metadata: 块"
            echo "   修正：删除 SKILL.md metadata，版本号写入 $VERSION_FILE"
            exit 1
        fi
    fi
    if [ -f "$VERSION_FILE" ]; then
        SKILL_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
        if [ -z "$SKILL_VERSION" ]; then
            echo "❌ $VERSION_FILE 为空（S3-3 契约）"
            echo "   请写入版本号，例如：$VERSION"
            exit 1
        fi
        if [ "$SKILL_VERSION" != "$VERSION" ]; then
            echo "❌ VERSION 不一致：VERSION=$SKILL_VERSION, 传入=$VERSION"
            echo "   修正：将 $VERSION_FILE 改为 $VERSION 再重试"
            exit 1
        fi
        echo "✅ VERSION 一致：$SKILL_VERSION"
    else
        echo "❌ 缺少 VERSION sidecar：$VERSION_FILE"
        echo "   Codex 不接受 SKILL.md metadata.version；版本号必须放在 VERSION 文件"
        exit 1
    fi

    echo "🎯 Project: $PROJECT_ROOT"
    echo "   Name:    $PROJECT_NAME"
    echo "   Skill:   $SKILL_NAME"
    echo "   Version: $VERSION"
    echo "   Pipeline: $SKILL_ROOT"
    echo ""

    # --- Pre-flight 0: CHANGELOG gate (§4 #5 — fail-fast before any artifact is created) ---
    # Derive release date from root CHANGELOG header for reproducible builds.
    # Priority: root CHANGELOG.md grep → SOURCE_DATE_EPOCH → wall-clock.
    # v1.0.8 hardening (Arch #4): wall-clock is now LAST RESORT and emits a
    # stderr warning. When SOURCE_DATE_EPOCH is also unset and no CHANGELOG
    # date can be parsed, we still proceed (preserving v1.0.7 behaviour for
    # bootstrap / first-release cases) but the warning makes the operator
    # aware that the resulting RELEASE_NOTES.md is not byte-reproducible.
    RELEASE_DATE=$(grep -m1 "^## ${VERSION} " "$PROJECT_ROOT/CHANGELOG.md" 2>/dev/null \
                   | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
    if [ -z "$RELEASE_DATE" ] && [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
        RELEASE_DATE=$(date -u -r "$SOURCE_DATE_EPOCH" "+%Y-%m-%d" 2>/dev/null \
                       || date -u -d "@$SOURCE_DATE_EPOCH" "+%Y-%m-%d" 2>/dev/null \
                       || echo "")
    fi
    if [ -z "$RELEASE_DATE" ]; then
        echo "⚠️  RELEASE_DATE: no parseable YYYY-MM-DD in CHANGELOG and no SOURCE_DATE_EPOCH set." >&2
        echo "    Falling back to wall-clock — RELEASE_NOTES.md will NOT be byte-reproducible." >&2
        echo "    To fix: ensure '## ${VERSION} — YYYY-MM-DD' header in CHANGELOG, or export SOURCE_DATE_EPOCH." >&2
        RELEASE_DATE=$(date +%Y-%m-%d)
    fi
    PROJECT_TITLE="$(echo "$PROJECT_NAME" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
    ACCUM_CHANGELOG="$PROJECT_ROOT/Release/CHANGELOG.md"
    if [ "$DRY_RUN" = "1" ]; then
        if [ ! -f "$ACCUM_CHANGELOG" ]; then
            echo "  [dry-run] Would create Release/CHANGELOG.md (not yet exists)"
            echo ""
            echo "⛔ [dry-run] CHANGELOG gate: Release/CHANGELOG.md 不存在"
            echo "   请先运行一次非 dry-run 模式创建 CHANGELOG 结构"
            exit 1
        fi
    else
        mkdir -p "$PROJECT_ROOT/Release"
        if [ ! -f "$ACCUM_CHANGELOG" ]; then
            cat > "$ACCUM_CHANGELOG" <<EOF
# $PROJECT_TITLE — Release History

记录各版本的关键变化。最新版本在最上面。

EOF
        fi
    fi
    if ! grep -qF "## $VERSION " "$ACCUM_CHANGELOG"; then
        # No entry — create scaffold and abort before any packaging
        if [ "$DRY_RUN" = "1" ]; then
            echo ""
            echo "⛔ [dry-run] CHANGELOG gate（§4 #5）：$VERSION 无条目"
            echo "   [dry-run] 会创建占位条目，但跳过文件写入"
            echo "   填完后重新运行 release.sh $VERSION"
            exit 1
        fi
        TMP_CHANGELOG=$(mktemp)
        CLEANUP_EXTRAS+=("$TMP_CHANGELOG")
        head -4 "$ACCUM_CHANGELOG" > "$TMP_CHANGELOG"
        cat >> "$TMP_CHANGELOG" <<EOF
## $VERSION — $RELEASE_DATE

<!-- TODO: 在此填写本版本要点，建议包括：新增 / 修复 / 破坏性变更 -->

Artifacts: \`Release/${PROJECT_NAME}-$VERSION/\`

---

EOF
        tail -n +5 "$ACCUM_CHANGELOG" >> "$TMP_CHANGELOG" 2>/dev/null || true
        mv "$TMP_CHANGELOG" "$ACCUM_CHANGELOG"
        echo ""
        echo "⛔ CHANGELOG gate（§4 #5）：已为 $VERSION 创建占位条目"
        echo "   请在 Release/CHANGELOG.md 的 $VERSION 节填写真实说明（删掉 TODO 注释）"
        echo "   填完后重新运行 release.sh $VERSION"
        exit 1
    else
        SAFE_VERSION=$(safe_version "$VERSION")
        entry_section=$(awk "/^## $SAFE_VERSION /,/^---$/" "$ACCUM_CHANGELOG")
        if echo "$entry_section" | grep -q "<!-- TODO"; then
            if [ "$DRY_RUN" = "1" ]; then
                echo ""
                echo "⛔ [dry-run] CHANGELOG gate（§4 #5）：$VERSION 条目仍含 TODO 占位"
                echo "   [dry-run] 拒绝 TODO 占位（与正常模式一致）"
                exit 1
            fi
            echo ""
            echo "⛔ CHANGELOG gate（§4 #5）：$VERSION 条目仍含 TODO 占位"
            echo "   请在 Release/CHANGELOG.md 的 $VERSION 节填写真实说明（删掉 TODO 注释）"
            echo "   填完后重新运行 release.sh $VERSION"
            exit 1
        fi
        echo "✅ CHANGELOG gate：$VERSION 条目真实"
    fi

    # --- §2.1 triad: scan for FIXME/HACK markers in source scripts (warn) ---
    FIXME_HITS=$({ grep -rE 'FIXME|HACK' "$PROJECT_ROOT" \
                   --include="*.sh" \
                   --exclude-dir=Release --exclude-dir=.git \
                   --exclude-dir=".1by1" --exclude-dir=scripts \
                   --exclude-dir=tests \
                   2>/dev/null || true; } | wc -l | tr -d ' ')
    if [ "$FIXME_HITS" -gt 0 ]; then
        echo "⚠️  §2.1 triad: $FIXME_HITS FIXME/HACK marker(s) in source scripts"
        grep -rE 'FIXME|HACK' "$PROJECT_ROOT" --include="*.sh" \
             --exclude-dir=Release --exclude-dir=.git \
             --exclude-dir=".1by1" --exclude-dir=scripts \
             --exclude-dir=tests \
             2>/dev/null | head -5 || true
        echo "   Review and resolve (or defer to a tracked issue) before shipping."
    else
        echo "✅ §2.1 triad: no FIXME/HACK markers in source scripts"
    fi
}

run_tests() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] Skipping regression tests (dry-run mode)"
        return 0
    fi
    echo "🧪 Running regression..."
    if [ ! -f "$PROJECT_ROOT/tests/run_all.sh" ]; then
        echo "❌ 找不到 $PROJECT_ROOT/tests/run_all.sh —— 项目必须有测试入口"
        exit 1
    fi
    TEST_LOG=$(mktemp "/tmp/tkx-release-test-XXXXXXXX")
    if ! bash "$PROJECT_ROOT/tests/run_all.sh" 2>&1 | tee "$TEST_LOG"; then
        echo ""
        echo "❌ Tests failed — release aborted"
        echo "   Full log: $TEST_LOG"
        exit 1
    fi
    rm -f "$TEST_LOG"
    echo "✅ Tests passed"
}

check_dual_source() {
    if [ ! -d "$PROJECT_ROOT/scripts" ]; then
        echo "❌ Missing root scripts directory: $PROJECT_ROOT/scripts"
        exit 1
    fi
    if [ ! -d "$PROJECT_ROOT/skills/$SKILL_NAME/scripts" ]; then
        echo "❌ Missing bundled scripts directory: $PROJECT_ROOT/skills/$SKILL_NAME/scripts"
        exit 1
    fi

    _SCRIPTS_ROOT="$PROJECT_ROOT/scripts"
    drift=$(diff -rq "$PROJECT_ROOT/scripts/" "$PROJECT_ROOT/skills/$SKILL_NAME/scripts/" 2>&1 \
            | { while IFS= read -r _ln; do
                    case "$_ln" in
                        # release-* are protected pipeline scripts (Gotcha #22)
                        "Only in ${_SCRIPTS_ROOT}: release-"*) ;;
                        # scrub-tarball.sh is OPTIONAL project tooling (Gotcha #33,
                        # v1.1.7): a project may ship it in scripts/ to opt into
                        # git-archive-based source tarball; it is NOT part of the
                        # skill bundle, so root-only is the correct shape.
                        "Only in ${_SCRIPTS_ROOT}: scrub-tarball.sh") ;;
                        *) printf '%s\n' "$_ln" ;;
                    esac
                done; } || true)
    if [ -n "$drift" ]; then
        echo "❌ 双源脚本漂移（v2.2 §4 #11）："
        echo "$drift"
        echo ""
        echo "   修复后再 release。禁止 FORCE 绕过（silent ghost release 护城河）"
        exit 1
    fi
    echo "✅ 双源脚本 byte-identical"
}

_discover_skill_creator() {
    # v1.2.1 fix: prior SKILL_CREATOR path put a placeholder literal as the
    # plugin hash dir segment but never implemented glob expansion. Claude
    # Code plugin marketplace assigns a real hash dir name (e.g. a 12-char
    # hex), so the old hardcoded path never matched even when skill-creator
    # was installed — every self-bake printed the misleading "不在" warning.
    #
    # Discovery order: (1) plugin marketplace cache glob, (2) legacy ~/.claude/
    # skills/ slot, (3) ~/.agents/skills/ canonical slot. Each candidate must
    # contain scripts/package_skill.py to be accepted (rejects stale empty dirs).
    SKILL_CREATOR=""
    for cand in "$HOME/.claude/plugins/cache/claude-plugins-official/skill-creator"/*/skills/skill-creator \
                "$HOME/.claude/skills/skill-creator" \
                "$HOME/.agents/skills/skill-creator"; do
        if [ -d "$cand" ] && [ -f "$cand/scripts/package_skill.py" ]; then
            SKILL_CREATOR="$cand"
            return 0
        fi
    done
    return 1
}

build_skill_package() {
    # v1.3.0: full system-vs-vendored skill-creator detection + interactive
    # version selection via lib helper. Replaces v1.2.1's _discover_skill_creator
    # call (kept below as backwards-compat thin wrapper for test coverage).
    # shellcheck source=lib/skill-creator-version.sh
    source "$SKILL_ROOT/lib/skill-creator-version.sh"
    skill_creator_status "$SKILL_ROOT"

    SKILL_CREATOR=""
    case "$SKC_VERDICT" in
        same|system_newer)
            # System is at least as fresh → silent use of system (no prompt)
            SKILL_CREATOR="$SKC_SYSTEM_PATH"
            ;;
        vendored_newer)
            # System exists but is older than vendored pinning. Prompt if TTY,
            # otherwise default to vendored (fresh + reproducible in CI).
            if [ -t 0 ] && [ -z "${CI:-}" ] && [ "$DRY_RUN" != "1" ]; then
                echo ""
                echo "🔍 skill-creator version comparison:"
                echo "   System ($SKC_SYSTEM_PATH): $SKC_SYSTEM_DATE"
                echo "   Vendored ($SKC_VENDORED_PATH): $SKC_VENDORED_DATE (newer, commit ${SKC_VENDORED_COMMIT:0:8})"
                echo ""
                printf "Use [v]endored (recommended) or [s]ystem? [v]: "
                read -r _skc_answer
                case "${_skc_answer:-v}" in
                    s|S|system) SKILL_CREATOR="$SKC_SYSTEM_PATH" ;;
                    *) SKILL_CREATOR="$SKC_VENDORED_PATH" ;;
                esac
            else
                SKILL_CREATOR="$SKC_VENDORED_PATH"
            fi
            ;;
        system_absent)
            # System missing → silent use of vendored
            SKILL_CREATOR="$SKC_VENDORED_PATH"
            ;;
        vendored_absent|both_absent)
            # Neither (defensive; vendored_absent shouldn't happen post-v1.3.0)
            SKILL_CREATOR=""
            ;;
    esac

    # v1.4.0: best-effort PyYAML enablement. skill-creator quick_validate.py
    # imports PyYAML; macOS Python 3 ships without it and PEP 668 blocks
    # system pip. Try creating a temporary venv with PyYAML — if that works,
    # the official packager path is enabled. Falls back to zip if no Python
    # or venv/pip fails (less surprising than aborting release).
    if [ -n "$SKILL_CREATOR" ] && [ "$SKC_PYYAML_OK" != "1" ]; then
        if ensure_pyyaml_via_venv; then
            echo "🐍 PyYAML enabled via temporary venv ($SKC_VENV_DIR)"
            CLEANUP_EXTRAS+=("$SKC_VENV_DIR")
        else
            echo "⚠️  skill-creator 探测到（${SKILL_CREATOR}）但 PyYAML venv 创建失败，回退 zip fallback"
            echo "    手工启用: pip3 install pyyaml --break-system-packages（或先确保 python3 + venv 可用）"
            SKILL_CREATOR=""
        fi
    fi
    # Choose Python binary: venv's if we just created one, else system python
    PYTHON_BIN="${SKC_VENV_PYTHON:-python}"

    SKILL_OUT="$RELEASE_DIR/${PROJECT_NAME}-${VERSION}.skill"
    SKILL_SRC_DIR="$PROJECT_ROOT/skills/$SKILL_NAME"

    if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] Would build .skill from $SKILL_SRC_DIR → $SKILL_OUT"
        return 0
    fi

    if [ -n "$SKILL_CREATOR" ] && [ -d "$SKILL_CREATOR" ]; then
        echo "📦 Building .skill via skill-creator (discovered at $SKILL_CREATOR)..."
        run rm -f "$SKILL_CREATOR/${SKILL_NAME}.skill" "$PROJECT_ROOT/${SKILL_NAME}.skill"
        SKILL_CREATOR_ERR=$(mktemp)
        # v1.4.0: PYTHONDONTWRITEBYTECODE=1 prevents __pycache__/ side-effect
        # in scripts/vendored/skill-creator/scripts/ (would break dual-source
        # diff with skills/gitx-release/scripts/vendored/...)
        if (cd "$SKILL_CREATOR" && PYTHONDONTWRITEBYTECODE=1 "$PYTHON_BIN" -m scripts.package_skill "$SKILL_SRC_DIR" > /dev/null 2>"$SKILL_CREATOR_ERR"); then
            run mv "$SKILL_CREATOR/${SKILL_NAME}.skill" "$SKILL_OUT"
            echo "   → $SKILL_OUT ($(du -h "$SKILL_OUT" 2>/dev/null | cut -f1 || echo "dry-run"))"
        else
            echo "❌ skill-creator failed. Output:"
            cat "$SKILL_CREATOR_ERR" >&2
            exit 1
        fi
        rm -f "$SKILL_CREATOR_ERR"
    else
        echo "⚠️  skill-creator 不在，改用 zip 直接打包"
        if [ "$DRY_RUN" = "1" ]; then
            echo "  [dry-run] zip -qX (sorted, mtime-normalized staging) → $SKILL_OUT"
        else
            # Stage + mtime-normalize to produce byte-identical zips across builds.
            # Reading live source directly embeds developer mtimes → non-deterministic.
            _ZIP_STAGE=$(mktemp -d)
            CLEANUP_EXTRAS+=("$_ZIP_STAGE")
            rsync -a --exclude='evals/' \
                  "$PROJECT_ROOT/skills/$SKILL_NAME/" "$_ZIP_STAGE/$SKILL_NAME/"
            _SDE_ZIP="200001010000.00"
            if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
                _SDE_ZIP=$(date -u -r "$SOURCE_DATE_EPOCH" "+%Y%m%d%H%M.%S" 2>/dev/null \
                           || date -u -d "@$SOURCE_DATE_EPOCH" "+%Y%m%d%H%M.%S" 2>/dev/null \
                           || echo "200001010000.00")
            fi
            find "$_ZIP_STAGE" -exec touch -t "$_SDE_ZIP" {} + || true
            (cd "$_ZIP_STAGE" && find "$SKILL_NAME" | LC_ALL=C sort | zip -qX "$SKILL_OUT" -@)
        fi
        echo "   → $SKILL_OUT ($(du -h "$SKILL_OUT" 2>/dev/null | cut -f1 || echo "dry-run"))"
    fi
}

build_source_tarball() {
    TAR_OUT="$RELEASE_DIR/${PROJECT_NAME}-${VERSION}-source.tar.gz"

    # v1.1.7+ Gotcha #20 long-term fix: prefer git-archive via the project's
    # own scripts/scrub-tarball.sh when present. That path uses
    # `git archive --worktree-attributes HEAD | gzip -n` — clean by
    # construction (only git-tracked content, .gitattributes export-ignore
    # honoured, no exclude list to maintain). For projects without
    # scrub-tarball.sh, falls back to the legacy rsync staging path
    # below (unchanged), which relies on the explicit --exclude list.
    #
    # History: this exact leak (.planning/, .archive/, project-internal
    # docs leaking into source tarball because rsync ignores .gitignore
    # and .gitattributes) bit the 1by1 skill on three consecutive releases
    # (v0.5.3, v0.6.0, v0.6.1). The scrub-tarball.sh path eliminates the
    # class of bug rather than playing exclude-list whack-a-mole.
    PROJECT_SCRUB="$PROJECT_ROOT/scripts/scrub-tarball.sh"
    if [ -x "$PROJECT_SCRUB" ] && git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        echo "📦 Building source tarball via $PROJECT_SCRUB (git-tracked-only, deterministic)..."
        if [ "$DRY_RUN" = "1" ]; then
            echo "  [dry-run] bash $PROJECT_SCRUB $TAR_OUT ${PROJECT_NAME}-${VERSION} HEAD"
        else
            bash "$PROJECT_SCRUB" "$TAR_OUT" "${PROJECT_NAME}-${VERSION}" HEAD
        fi
        echo "   → $TAR_OUT ($(du -h "$TAR_OUT" 2>/dev/null | cut -f1 || echo "dry-run"))"
        # v1.1.8 hot-patch: run_sanity_scans (line 490) reads $STAGE_SUB and
        # would abort under `set -u` if we return without setting it. The
        # legacy rsync path below sets STAGE/STAGE_SUB/SKILL_STAGE; the modern
        # scrub-tarball path must satisfy the same downstream contract.
        # Solution: extract the just-built tarball into STAGE so sanity scan
        # sees the actual ship content. CLEANUP_EXTRAS reaps STAGE on exit.
        # Self-bake of git_release_skill never hit this because the project
        # ships no scrub-tarball.sh — but 1by1 v0.6.2 abort on this exact path.
        STAGE=$(mktemp -d)
        CLEANUP_EXTRAS+=("$STAGE")
        SKILL_STAGE=""
        STAGE_SUB="$STAGE/${PROJECT_NAME}-${VERSION}"
        if [ "$DRY_RUN" = "1" ]; then
            run mkdir -p "$STAGE_SUB"
        else
            tar -xzf "$TAR_OUT" -C "$STAGE"
        fi
        return 0
    fi

    # --- Legacy fallback: rsync staging mode ---
    # Used when project does NOT provide scripts/scrub-tarball.sh.
    # Caveat: does NOT honor .gitignore or .gitattributes export-ignore;
    # the explicit --exclude list below must be kept current. Projects
    # vulnerable to dev-artifact leakage (e.g. .planning/, .archive/,
    # internal audit docs) should vendor scripts/scrub-tarball.sh to
    # opt into the safer path above.
    echo "📦 Staging source (rsync mode — project has no scripts/scrub-tarball.sh)..."
    STAGE=$(mktemp -d)
    SKILL_STAGE=""
    STAGE_SUB="$STAGE/${PROJECT_NAME}-${VERSION}"
    run mkdir -p "$STAGE_SUB"

    # v2.3 §10.3: 通配 *.bak 而非具名
    # Bug #7 fix: also exclude any stray extracted tarball dirs
    # Bug #9 fix: exclude memory/ dir
    # v1.7.1: '/commands' is NO LONGER excluded — the v1.1.0-era exclude was
    # for a redundant /gitx-release shim, but v1.6.0+ ships real subcommand
    # shims (/gitx-init, /gitx-sop) that MUST reach the source tarball + the
    # public mirror + install.sh's repo-root copy path.
    SKILL_EXCLUDE=()
    if [ -f "$PROJECT_ROOT/SKILL.md" ]; then
        SKILL_EXCLUDE=(--exclude='/skills')
    fi

    run rsync -a \
        --exclude='.git' \
        --exclude='Release' \
        --exclude='*.skill' \
        --exclude='tests/.tmp' \
        --exclude='.claude' \
        --exclude='.omc' \
        --exclude='.1by1' \
        --exclude='.i18n-cache' \
        --exclude='.cache' \
        --exclude='.gitx' \
        --exclude='.env*' \
        --exclude='.ssh' \
        --exclude='.aws' \
        --exclude='memory' \
        --exclude='HANDOFF.md' \
        --exclude='HANDOFF.archive.md' \
        --exclude='HANDOFF.md.bak' \
        --exclude='REVIEW.md' \
        --exclude='GitHub_STANDARD_ANALYSIS.md' \
        --exclude='.DS_Store' \
        --exclude='*.bak' \
        --exclude='*.pyc' \
        --exclude='__pycache__' \
        --exclude="${PROJECT_NAME}-v*" \
        --exclude="skills/${SKILL_NAME}-workspace" \
        "${SKILL_EXCLUDE[@]+"${SKILL_EXCLUDE[@]}"}" \
        "$PROJECT_ROOT/" "$STAGE_SUB/" 2>/dev/null

    echo "📦 Building source tarball..."
    # v0.9.8 (Gotcha #14): reproducible-build transforms so two consecutive
    # releases of the same source produce byte-identical tarballs.
    # v0.9.9 (feature A): honor SOURCE_DATE_EPOCH (Debian/Nix/SLSA standard).
    if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
        SDE_TOUCH=$(date -u -r "$SOURCE_DATE_EPOCH" "+%Y%m%d%H%M.%S" 2>/dev/null \
                    || date -u -d "@$SOURCE_DATE_EPOCH" "+%Y%m%d%H%M.%S" 2>/dev/null \
                    || echo "200001010000.00")
    else
        SDE_TOUCH="200001010000.00"
    fi
    run find "$STAGE_SUB" -exec touch -t "$SDE_TOUCH" {} + || true
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] tar + gzip → $TAR_OUT"
    else
        (
            cd "$STAGE" && \
            find "${PROJECT_NAME}-${VERSION}" -print | LC_ALL=C sort | \
            tar --no-recursion --owner=0 --group=0 --numeric-owner -T - -cf -
        ) 2>/dev/null | gzip -n > "$TAR_OUT"
    fi
    echo "   → $TAR_OUT ($(du -h "$TAR_OUT" 2>/dev/null | cut -f1 || echo "dry-run"))"
}

run_sanity_scans() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] Skipping sanity scans (no staged artifacts in dry-run)"
        return 0
    fi
    SKILL_SRC_DIR="$PROJECT_ROOT/skills/$SKILL_NAME"
    SKILL_OUT="$RELEASE_DIR/${PROJECT_NAME}-${VERSION}.skill"

    echo "🔍 Running pre-release sanity scan..."
    SANITIZE="$SKILL_ROOT/release-sanitize.sh"
    if [ -x "$SANITIZE" ]; then
        echo "   → 使用 $SANITIZE"
        # Bug C fix (v1.1.5): label each pass so the operator can tell which
        # pass succeeded/failed. release-sanitize.sh emits e.g.
        # "✅ Release sanity clean (staging) — ..." vs "(.skill bundle)".
        if ! bash "$SANITIZE" --label staging "$STAGE_SUB" 2>&1; then
            echo ""
            echo "❌ Release aborted: 发现敏感信息 (staging)"
            echo "   修复上述文件后再跑 release；明确豁免请加到项目根的 .sanitize-ignore"
            exit 1
        fi
        # 同时扫 .skill 解压内容
        if [ -f "$SKILL_OUT" ]; then
            SKILL_STAGE=$(mktemp -d)
            unzip -q "$SKILL_OUT" -d "$SKILL_STAGE"
            # v1.2 A4 fix (Gotcha #11 surface 3): the bundle scan inherits no
            # .sanitize-ignore because .sanitize-ignore must NEVER persist into
            # the .skill bundle (Gotcha #11 original contract — would leak the
            # whitelist downstream). Without inheritance, fixture content like
            # MAC-literal patterns in assets/TEST-SCENARIOS.md trips sanitize
            # as false-positive (mac-release v0.1.0 self-bake hit this — Dev
            # Log 2026-05-07; Gotcha #31 forbids literal bait strings here).
            # Solution: scan SKILL_STAGE/$SKILL_NAME (the actual unzipped
            # bundle root) instead of SKILL_STAGE — that way every file's
            # path-relative-to-scan-root matches what the project root scan
            # saw, so project-root .sanitize-ignore patterns work unchanged.
            # Temporarily copy project-root .sanitize-ignore into the scan
            # root for scan duration, rm immediately on success AND failure
            # paths. SKILL_STAGE is a mktemp dir that gets discarded, so the
            # temp .sanitize-ignore never reaches any persistent path.
            # Mirrors release-audit.sh §7 (line 504-508) pattern.
            if [ -f "$PROJECT_ROOT/.sanitize-ignore" ] && [ -d "$SKILL_STAGE/$SKILL_NAME" ]; then
                cp "$PROJECT_ROOT/.sanitize-ignore" "$SKILL_STAGE/$SKILL_NAME/.sanitize-ignore"
            fi
            if ! bash "$SANITIZE" --label .skill "$SKILL_STAGE/$SKILL_NAME" 2>&1; then
                if [ -f "$SKILL_STAGE/$SKILL_NAME/.sanitize-ignore" ]; then
                    rm -f "$SKILL_STAGE/$SKILL_NAME/.sanitize-ignore"
                fi
                echo ""
                echo "❌ .skill 文件内容有敏感信息"
                exit 1
            fi
            if [ -f "$SKILL_STAGE/$SKILL_NAME/.sanitize-ignore" ]; then
                rm -f "$SKILL_STAGE/$SKILL_NAME/.sanitize-ignore"
            fi
        fi
    else
        echo "❌ $SANITIZE 不存在（skill 不完整）"
        exit 1
    fi
}

flatten_docs() {
    SKILL_SRC_DIR="$PROJECT_ROOT/skills/$SKILL_NAME"

    # --- 2.6 Flatten docs + install.sh ---
    echo "📄 Flattening top-level docs to release dir..."
    for doc in README.md INSTALL.md TEST-SCENARIOS.md LICENSE CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md ROADMAP.md; do
        [ -f "$PROJECT_ROOT/$doc" ] && run cp "$PROJECT_ROOT/$doc" "$RELEASE_DIR/$doc"
    done

    # v1.1.2: optional .release-flatten manifest for project-specific files
    # not in the standard 8-doc list. One path per line; comments (`#`) and
    # blank lines tolerated. Paths relative to PROJECT_ROOT. Resolves the
    # claudemex case where install.sh references project-specific docs.
    _RF_MANIFEST="$PROJECT_ROOT/.release-flatten"
    if [ -f "$_RF_MANIFEST" ]; then
        echo "📝 Reading .release-flatten manifest..."
        while IFS= read -r _rf_line || [ -n "$_rf_line" ]; do
            _rf_line="${_rf_line%%#*}"                         # strip whole-line + trailing comments
            _rf_line="${_rf_line#"${_rf_line%%[![:space:]]*}"}" # ltrim
            _rf_line="${_rf_line%"${_rf_line##*[![:space:]]}"}" # rtrim
            [ -z "$_rf_line" ] && continue
            if [ -f "$PROJECT_ROOT/$_rf_line" ]; then
                run cp "$PROJECT_ROOT/$_rf_line" "$RELEASE_DIR/$(basename "$_rf_line")"
            elif [ -d "$PROJECT_ROOT/$_rf_line" ]; then
                run cp -R "$PROJECT_ROOT/$_rf_line" "$RELEASE_DIR/$(basename "$_rf_line")"
            else
                echo "⚠️  .release-flatten: '$_rf_line' not found in PROJECT_ROOT — skipping" >&2
            fi
        done < "$_RF_MANIFEST"
    fi
    if [ -f "$PROJECT_ROOT/install.sh" ]; then
        run cp "$PROJECT_ROOT/install.sh" "$RELEASE_DIR/install.sh"
        run chmod +x "$RELEASE_DIR/install.sh"
    fi
    if [ -f "$SKILL_SRC_DIR/SKILL.md" ]; then
        run cp "$SKILL_SRC_DIR/SKILL.md" "$RELEASE_DIR/SKILL.md"
    fi
    if [ -f "$SKILL_SRC_DIR/VERSION" ]; then
        run cp "$SKILL_SRC_DIR/VERSION" "$RELEASE_DIR/VERSION"
    fi
    if [ -d "$SKILL_SRC_DIR/scripts" ]; then
        run cp -R "$SKILL_SRC_DIR/scripts" "$RELEASE_DIR/scripts"
        run chmod +x "$RELEASE_DIR/scripts/"*.sh 2>/dev/null || true
    fi
    # NOTE: commands/ flattening is part of the GENERIC release pipeline
    # contract for any downstream skill that ships slash commands. As of
    # v1.6.0 gitx-release itself ships real subcommand shims (gitx-init,
    # gitx-sop); v1.7.1 stopped excluding them from the source tarball so
    # they reach the public mirror + every install path.
    if [ -d "$SKILL_SRC_DIR/commands" ]; then
        run cp -R "$SKILL_SRC_DIR/commands" "$RELEASE_DIR/commands"
    fi
    if [ -d "$SKILL_SRC_DIR/agents" ]; then
        run cp -R "$SKILL_SRC_DIR/agents" "$RELEASE_DIR/agents"
    fi
    if [ -d "$SKILL_SRC_DIR/references" ]; then
        run cp -R "$SKILL_SRC_DIR/references" "$RELEASE_DIR/references"
    fi
    if [ -d "$SKILL_SRC_DIR/assets" ]; then
        run cp -R "$SKILL_SRC_DIR/assets" "$RELEASE_DIR/assets"
    fi
    echo "   → 已拷到 $RELEASE_DIR/（顶层）"
}

generate_attestations() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] Skipping attestations (SBOM, TOKEN_USAGE, checksums)"
        return 0
    fi
    SKILL_SRC_DIR="$PROJECT_ROOT/skills/$SKILL_NAME"

    # --- 2.7 SBOM — via emit-sbom.sh ---
    echo "🧾 Generating sbom.cyclonedx.json..."
    run "$PROJECT_ROOT/scripts/emit-sbom.sh" "$RELEASE_DIR" "$PROJECT_NAME" "$VERSION" "$SKILL_NAME"

    # --- 2.7b TOKEN_USAGE.md ---
    if [ -f "$SKILL_SRC_DIR/SKILL.md" ]; then
        echo "🧮 Generating TOKEN_USAGE.md..."
        if ! "$PROJECT_ROOT/scripts/emit-token-usage.sh" \
                "$SKILL_SRC_DIR" \
                "$RELEASE_DIR/TOKEN_USAGE.md" \
                "$VERSION"; then
            echo "❌ emit-token-usage.sh failed" >&2
            exit 1
        fi
    fi

    # --- 2.8 checksums.txt (sha256 of distributable artifacts + SBOM + TOKEN_USAGE) ---
    echo "🔐 Generating checksums.txt..."
    if command -v shasum >/dev/null 2>&1; then
        SHA_CMD="shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then
        SHA_CMD="sha256sum"
    else
        echo "❌ neither shasum nor sha256sum available" >&2
        exit 1
    fi
    (
        cd "$RELEASE_DIR"
        CHK_FILES=()
        [ -f "${PROJECT_NAME}-${VERSION}.skill" ]          && CHK_FILES+=("${PROJECT_NAME}-${VERSION}.skill")
        [ -f "${PROJECT_NAME}-${VERSION}-source.tar.gz" ]  && CHK_FILES+=("${PROJECT_NAME}-${VERSION}-source.tar.gz")
        [ -f "install.sh" ]                                && CHK_FILES+=("install.sh")
        [ -f "sbom.cyclonedx.json" ]                       && CHK_FILES+=("sbom.cyclonedx.json")
        [ -f "TOKEN_USAGE.md" ]                            && CHK_FILES+=("TOKEN_USAGE.md")
        if [ "${#CHK_FILES[@]}" -eq 0 ]; then
            echo "❌ no artifacts found to hash" >&2
            exit 1
        fi
        $SHA_CMD "${CHK_FILES[@]}" | LC_ALL=C sort > checksums.txt
    )
    echo "   → $RELEASE_DIR/checksums.txt"
}

generate_release_notes() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] Skipping RELEASE_NOTES.md generation"
        return 0
    fi
    SKILL_SRC_DIR="$PROJECT_ROOT/skills/$SKILL_NAME"
    PROJECT_TITLE="$(echo "$PROJECT_NAME" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"

    HAS_COMMANDS=0
    if [ -d "$SKILL_SRC_DIR/commands" ] && [ "$(find "$SKILL_SRC_DIR/commands" -maxdepth 1 -name '*.md' -print -quit)" ]; then
        HAS_COMMANDS=1
    fi

    if [ "$HAS_COMMANDS" = "1" ]; then
        COMMANDS_SETUP="mkdir -p ~/.claude/skills ~/.claude/commands"
        COMMANDS_INSTALL_LINE=$'\n# 安装 slash command shims\ncp ~/.claude/skills/'"${SKILL_NAME}"'/commands/*.md ~/.claude/commands/'
    else
        COMMANDS_SETUP="mkdir -p ~/.claude/skills"
        COMMANDS_INSTALL_LINE=""
    fi

    cat > "$RELEASE_DIR/RELEASE_NOTES.md" <<EOF
# $PROJECT_TITLE $VERSION — Release Notes

Release date: $RELEASE_DATE

## 本目录包含

### 分发包
- \`${PROJECT_NAME}-${VERSION}.skill\` — 单文件 zip 分发
- \`${PROJECT_NAME}-${VERSION}-source.tar.gz\` — 完整源码包

### 平摊文档与安装脚本
- \`README.md\` / \`INSTALL.md\` / \`CHANGELOG.md\` / \`TEST-SCENARIOS.md\` / \`SKILL.md\` / \`LICENSE\` / \`CONTRIBUTING.md\` / \`CODE_OF_CONDUCT.md\` / \`SECURITY.md\`
- \`install.sh\` — 平摊安装脚本（支持自举从同目录 .skill / tarball 解压）

## 快速安装

### 方式 A（推荐）：直接跑本目录 install.sh
\`\`\`bash
./install.sh
\`\`\`

### 方式 B：只装 skill
\`\`\`bash
${COMMANDS_SETUP}
unzip -o ./${PROJECT_NAME}-${VERSION}.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/${SKILL_NAME}/scripts/*.sh${COMMANDS_INSTALL_LINE}
\`\`\`

### 方式 C：完整解压 source tarball
\`\`\`bash
tar xzf ./${PROJECT_NAME}-${VERSION}-source.tar.gz
cd ${PROJECT_NAME}-${VERSION}
./install.sh
\`\`\`

完整命令见 \`INSTALL.md\`；本版本变更见 \`CHANGELOG.md\` 的 **$VERSION** 条目。
EOF

    # Inject CHANGELOG entry into RELEASE_NOTES
    SAFE_VERSION=$(safe_version "$VERSION")
    CHLG_ENTRY=$(awk "/^## $SAFE_VERSION /,/^---$/" "$ACCUM_CHANGELOG" | sed '$d')
    if [ -n "$CHLG_ENTRY" ]; then
        {
            echo ""
            echo "## What's new in $VERSION"
            echo ""
            echo "$CHLG_ENTRY" | sed '1{/^## /d;}'
        } >> "$RELEASE_DIR/RELEASE_NOTES.md"
    fi
    echo "   → $RELEASE_DIR/RELEASE_NOTES.md"
}

update_changelog() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] Skipping CHANGELOG flatten"
        return 0
    fi
    # --- 5. Flatten Release/CHANGELOG.md into release dir ---
    run cp "$PROJECT_ROOT/Release/CHANGELOG.md" "$RELEASE_DIR/CHANGELOG.md"
    echo "✅ Release/CHANGELOG.md 已平摊到 $RELEASE_DIR/（含 $VERSION 条目）"
}

run_deep_audit() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] Skipping deep audit (no artifacts to audit)"
        return 0
    fi
    echo ""
    echo "📦 Release $VERSION 产物已就绪："
    ls -lh "$RELEASE_DIR"
    echo ""

    AUDIT="$SKILL_ROOT/release-audit.sh"
    if [ -x "$AUDIT" ]; then
        echo "🔍 Running post-release deep audit..."
        echo "   → 使用 $AUDIT"
        echo ""
        # v1.0.8 hardening: _GITX_INTERNAL_INLINE=1 proves to release-audit.sh
        # that --inline came from this trusted in-pipeline call (not a CLI
        # bypass attempt). Audit refuses to honor --inline without this env.
        if ! (cd "$PROJECT_ROOT" && \
              PROJECT_NAME="$PROJECT_NAME" SKILL_NAME="$SKILL_NAME" \
              _GITX_INTERNAL_INLINE=1 \
              bash "$AUDIT" --inline "$VERSION"); then
            echo ""
            echo "❌ Deep audit 未通过。修复后执行："
            echo "   rm -rf $RELEASE_DIR"
            echo "   PROJECT_ROOT=$PROJECT_ROOT SKILL_NAME=$SKILL_NAME bash $0 $VERSION"
            exit 1
        fi
    else
        echo "❌ $AUDIT 不存在（skill 不完整）"
        exit 1
    fi
}

build_full_tarball() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] Would build full release tarball → ${PROJECT_NAME}-${VERSION}-full.tar.gz"
        return 0
    fi
    _FULL_TAR_NAME="${PROJECT_NAME}-${VERSION}-full.tar.gz"
    _FULL_TAR_PATH="$RELEASE_DIR/$_FULL_TAR_NAME"
    echo "📦 Building full release tarball..."
    _FULL_STAGE=$(mktemp -d)
    # Single source of cleanup: EXIT trap reaps CLEANUP_EXTRAS on any exit path.
    CLEANUP_EXTRAS+=("$_FULL_STAGE")
    rsync -a "$RELEASE_DIR/" "$_FULL_STAGE/${PROJECT_NAME}-${VERSION}/"
    if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
        _SDE=$(date -u -r "$SOURCE_DATE_EPOCH" "+%Y%m%d%H%M.%S" 2>/dev/null \
               || date -u -d "@$SOURCE_DATE_EPOCH" "+%Y%m%d%H%M.%S" 2>/dev/null \
               || echo "200001010000.00")
    else
        _SDE="200001010000.00"
    fi
    find "$_FULL_STAGE" -exec touch -t "$_SDE" {} + || true
    (
        cd "$_FULL_STAGE" && \
        find "${PROJECT_NAME}-${VERSION}" -print | LC_ALL=C sort | \
        tar --no-recursion --owner=0 --group=0 --numeric-owner -T - -cf -
    ) | gzip -n > "$_FULL_TAR_PATH"
    echo "   → $_FULL_TAR_PATH ($(du -h "$_FULL_TAR_PATH" 2>/dev/null | cut -f1 || echo "unknown"))"
    # Append full tarball hash and re-sort to preserve LC_ALL=C invariant from §2.8.
    # Note: the checksums.txt embedded inside full.tar.gz cannot list full.tar.gz
    # itself (a tarball cannot contain its own hash). The OUTER checksums.txt
    # written here is authoritative — audit §11h shasum -c validates everything.
    if [ -f "$RELEASE_DIR/checksums.txt" ]; then
        if command -v shasum >/dev/null 2>&1; then
            _SHA_APPEND="shasum -a 256"
        else
            _SHA_APPEND="sha256sum"
        fi
        (
            cd "$RELEASE_DIR"
            { cat checksums.txt; $_SHA_APPEND "$_FULL_TAR_NAME"; } \
                | LC_ALL=C sort > checksums.txt.tmp
            mv checksums.txt.tmp checksums.txt
        )
        echo "   → checksums.txt 追加 full tarball sha256（已重新排序，保持 LC_ALL=C 不变量）"
    fi
}

update_latest_symlink() {
    # --- Atomic latest symlink update (only after audit passes) ---
    # v0.9.8 (Gotcha #15): previous recipe `mv -f .latest.tmp latest` breaks on
    # BSD mv (macOS): when `latest` already points to a directory, BSD mv
    # FOLLOWS the symlink and moves `.latest.tmp` INTO that directory instead
    # of replacing the symlink. Result: latest stays stale + orphan .latest.tmp
    # accumulates inside the previous release dir.
    # `ln -sfn` is portable across BSD/GNU and atomically replaces the symlink:
    #   -s: symbolic
    #   -f: force (remove existing)
    #   -n: treat existing symlink-to-directory as a regular file (don't follow)
    run ln -sfn "${PROJECT_NAME}-${VERSION}" "$PROJECT_ROOT/Release/latest"
    echo "✅ Release/latest → ${PROJECT_NAME}-${VERSION}（audit 通过后原子更新）"
}

# ============================================================
# Main flow
# ============================================================

preflight_external_tools
preflight_checks

if [ -d "$RELEASE_DIR" ]; then
    echo "❌ Release dir already exists: $RELEASE_DIR"
    echo "   Refusing to overwrite an existing release. Move it aside or remove it manually, then rerun."
    exit 1
fi

if [ ! -d "$RELEASE_DIR" ]; then
    RELEASE_DIR_CREATED=1
fi
run mkdir -p "$RELEASE_DIR"

run_tests
check_dual_source
build_skill_package
build_source_tarball
run_sanity_scans
flatten_docs
generate_attestations
generate_release_notes
update_changelog
build_full_tarball
run_deep_audit
update_latest_symlink

RELEASE_SUCCESS=1

echo ""
echo "下一步："
echo "  1. 确认 CHANGELOG $VERSION 条目真实完整（非 TODO）"
echo "  2. 如需上游发布，请人工复核产物、CHANGELOG 和仓库状态后再操作"
echo "  3. 若要分发：把 $RELEASE_DIR/ 下文件发给同事"
