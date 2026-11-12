#!/bin/bash
# install.sh — Git Release Pipeline installer (§6.10 interface contract)
# Installs the skill bundle to $HOME/.agents/skills/gitx-release/ (canonical)
# and creates symlinks for Claude Code and OpenCode.
# Gemini CLI and Codex CLI auto-discover from ~/.agents/skills/ natively.
# usage: ./install.sh [--dry-run] [--force] [--help]
# exit:
#   0 success / dry-run preview / help
#   1 generic failure
#   2 usage / bad flag

set -euo pipefail

SKILL_NAME="gitx-release"
# v1.1.0 rebrand: the canonical skill name was renamed from
# `git-release-pipeline` to `gitx-release` to collapse the
# slash-command-vs-skill duplicate in Claude Code's `/`-menu. The
# install routine cleans up any prior install of the legacy name.
SKILL_NAME_LEGACY="git-release-pipeline"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Integrity verification (v1.0.8 supply-chain hardening) ---
# Runs BEFORE sourcing anything: the output helper below is itself bundle
# code, so a tampered helper must be rejected before it can execute. Plain
# echo here because the styled helpers are not loaded yet; the success text
# is replayed at checkpoint 1 once they are.
if [ -f "$SELF_DIR/checksums.txt" ]; then
    if command -v shasum >/dev/null 2>&1; then
        _SHA_VERIFY="shasum -a 256 -c"
    elif command -v sha256sum >/dev/null 2>&1; then
        _SHA_VERIFY="sha256sum -c"
    else
        echo "❌ checksums.txt present but neither shasum nor sha256sum is available" >&2
        echo "❌ Cannot verify integrity -- refusing to install." >&2
        exit 1
    fi
    if ! (cd "$SELF_DIR" && $_SHA_VERIFY checksums.txt >/dev/null 2>&1); then
        echo "❌ Integrity check FAILED -- bundle appears tampered or incomplete" >&2
        (cd "$SELF_DIR" && $_SHA_VERIFY checksums.txt 2>&1 || true) | grep -E 'FAILED|missing' | sed 's/^/     /' >&2
        exit 1
    fi
    _CHK_COUNT=$(awk 'END{print NR}' "$SELF_DIR/checksums.txt")
    _INTEGRITY_MSG="checksums.txt verified (${_CHK_COUNT}/${_CHK_COUNT})"
else
    _INTEGRITY_MSG="dev-tree install (no checksums.txt) -- integrity check skipped"
fi

# --- Unified install output helper (TKX standard) ---
# Master copy lives in Git_Release_Skill/scripts/lib/; vendored byte-identical
# into each TKX skill bundle. Enforces same banner / checkpoint / summary
# visual across gitx-release / mac-release / handoff / 1by1 / ClaudeMeX.
if [ -f "$SELF_DIR/scripts/lib/install-output-style.sh" ]; then
    # shellcheck source=scripts/lib/install-output-style.sh
    source "$SELF_DIR/scripts/lib/install-output-style.sh"
else
    echo "❌ Missing required helper: scripts/lib/install-output-style.sh" >&2
    echo "   Re-extract the release bundle or re-clone the source repo." >&2
    exit 1
fi

DRY_RUN=0
FORCE=0

print_help() {
    cat <<EOF
Git Release Pipeline -- installer

Usage:
  ./install.sh [--dry-run] [--force] [--help]

Options:
  --dry-run     Preview actions without touching the filesystem.
  --force       Overwrite an existing installation without prompt.
  --help, -h    Show this help and exit.

What it does:
  1. Verifies bash version + required files (SKILL.md, scripts/*.sh).
  2. Installs to \$HOME/.agents/skills/$SKILL_NAME/ (cross-CLI canonical path).
  3. Creates symlinks at:
     - \$HOME/.claude/skills/$SKILL_NAME (Claude Code)
     - \$HOME/.config/opencode/skills/$SKILL_NAME (OpenCode)
  Gemini CLI and Codex CLI auto-discover from ~/.agents/skills/ natively.
  Codex command selectors such as \$gitx-release are declared in agents/codex-commands.txt.
  One install covers Claude Code + Codex + OpenCode + Gemini CLI.

Uninstall:
  rm -rf \$HOME/.agents/skills/$SKILL_NAME \\
         \$HOME/.agents/skills/$SKILL_NAME_LEGACY \\
         \$HOME/.agents/skills/GitX-release \\
         \$HOME/.claude/skills/$SKILL_NAME \\
         \$HOME/.claude/skills/$SKILL_NAME_LEGACY \\
         \$HOME/.claude/commands/GitX-release.md \\
         \$HOME/.codex/skills/$SKILL_NAME \\
         \$HOME/.codex/skills/$SKILL_NAME_LEGACY \\
         \$HOME/.codex/skills/GitX-release \\
         \$HOME/.config/opencode/skills/$SKILL_NAME \\
         \$HOME/.config/opencode/skills/$SKILL_NAME_LEGACY
EOF
}

# --- Parse flags ---
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
        --help|-h) print_help; exit 0 ;;
        *)
            install_step_fail "Unknown option: $1"
            print_help >&2
            exit 2
            ;;
    esac
    shift
done

# Read version sidecar for banner display.
_INSTALL_VERSION="$(tr -d '[:space:]' < "$SELF_DIR/VERSION" 2>/dev/null || echo unknown)"

# Determine mode label for banner. Both --dry-run and --force may be
# combined; --dry-run wins (no filesystem writes) but the label shows both
# so the operator sees exactly which flags are active.
if [ "$DRY_RUN" -eq 1 ] && [ "$FORCE" -eq 1 ]; then
    _INSTALL_MODE="--dry-run --force"
elif [ "$DRY_RUN" -eq 1 ]; then
    _INSTALL_MODE="--dry-run"
elif [ "$FORCE" -eq 1 ]; then
    _INSTALL_MODE="install --force"
else
    _INSTALL_MODE="install"
fi

# 7 checkpoints: Integrity / Preflight / Install canonical / Symlinks /
# Legacy cleanup / Validation / PATH shim.
install_style_init 7
install_banner_top "$SKILL_NAME" "$_INSTALL_VERSION" "$_INSTALL_MODE" "$SELF_DIR"

# --- Checkpoint 1/6: Integrity verification (verified above, before sourcing) ---
install_checkpoint "$_TKX_E_LOCK" "Integrity verification"
install_step_ok "$_INTEGRITY_MSG"

# --- Checkpoint 2/6: Preflight ---
install_checkpoint "$_TKX_E_SEARCH" "Preflight"
_BASH_VER="$(bash --version | head -1 | sed -E 's/.*version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
if bash --version | head -1 | grep -qE 'version [4-9]\.|version [0-9]{2,}\.'; then
    install_step_ok "Bash $_BASH_VER (>= 4.0)"
else
    install_step_warn "Bash $_BASH_VER -- 4.0+ recommended"
fi

REQUIRED_FILES=(
    "SKILL.md"
    "VERSION"
    "scripts/gitx-release.sh"
    "scripts/release.sh"
    "scripts/release-audit.sh"
    "scripts/release-sanitize.sh"
    "scripts/scan-credentials.sh"
)
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SELF_DIR/$f" ]; then
        install_step_fail "Missing required file: $SELF_DIR/$f"
        exit 1
    fi
done
install_step_ok "Required files present (${#REQUIRED_FILES[@]}/${#REQUIRED_FILES[@]})"

# Cross-CLI canonical path (Agent Skills open standard):
#   ~/.agents/skills/          → Gemini CLI + Codex (auto-discovered natively)
#   ~/.claude/skills/          → Claude Code (symlink to canonical)
#   ~/.config/opencode/skills/ → OpenCode (symlink to canonical)
#   ~/.codex/skills/           → legacy duplicate cleanup only; no visible alias skill
CANONICAL="$HOME/.agents/skills/$SKILL_NAME"
CLAUDE_LINK="$HOME/.claude/skills/$SKILL_NAME"
CLAUDE_COMMANDS="$HOME/.claude/commands"
OPENCODE_LINK="$HOME/.config/opencode/skills/$SKILL_NAME"
CODEX_SKILLS_DIR="$HOME/.codex/skills"

# --- Dry run: preview, don't write ---
if [ "$DRY_RUN" -eq 1 ]; then
    install_checkpoint "$_TKX_E_SEARCH" "Dry-run preview"
    install_step_ok "canonical: $CANONICAL  (Codex + Gemini auto-discovery)"
    install_step_ok "symlink : $CLAUDE_LINK  (Claude Code)"
    install_step_ok "symlink : $OPENCODE_LINK  (OpenCode)"
    install_step_ok "codex   : $CODEX_SKILLS_DIR  (legacy duplicate cleanup target)"
    if [ -f "$SELF_DIR/agents/codex-commands.txt" ]; then
        install_step_ok "codex commands: $(tr '\n' ' ' < "$SELF_DIR/agents/codex-commands.txt" | sed 's/[[:space:]]*$//')"
    fi
    install_step_ok "PATH shim: $HOME/.agents/bin/gitx-marketplace → $CANONICAL/scripts/gitx-marketplace.sh"
    if [ -d "$CANONICAL" ] || [ -L "$CLAUDE_LINK" ]; then
        if [ "$FORCE" -eq 1 ]; then
            install_step_warn "WOULD overwrite existing installation (--force)"
        else
            install_step_warn "WOULD refuse -- already installed (use --force to overwrite)"
        fi
    else
        install_step_ok "WOULD install + create symlinks"
    fi
    install_banner_bottom "$SKILL_NAME" "$_INSTALL_VERSION (dry-run)"
    exit 0
fi

ensure_managed_link_or_force() {
    local path="$1"
    local label="$2"
    if [ -L "$path" ] && [ "$(readlink "$path")" = "$CANONICAL" ]; then
        return 0
    fi
    if [ -e "$path" ] || [ -L "$path" ]; then
        if [ "$FORCE" -eq 1 ]; then
            return 0
        fi
        install_step_fail "Existing $label path not managed by installer: $path"
        install_step_fail "Re-run with --force to replace, or move it aside manually."
        exit 1
    fi
}

if [ -e "$CANONICAL" ] || [ -L "$CANONICAL" ]; then
    if [ "$FORCE" -ne 1 ]; then
        install_step_fail "Already installed or occupied at $CANONICAL"
        install_step_fail "Re-run with --force to overwrite, or move it aside manually."
        exit 1
    fi
fi
ensure_managed_link_or_force "$CLAUDE_LINK" "Claude Code"
ensure_managed_link_or_force "$OPENCODE_LINK" "OpenCode"

# --- Checkpoint 3/6: Install canonical path (~/.agents/skills/) ---
install_checkpoint "$_TKX_E_DIR" "Install canonical"
mkdir -p "$(dirname "$CANONICAL")"
rm -rf "$CANONICAL"
mkdir -p "$CANONICAL"

cp "$SELF_DIR/SKILL.md" "$CANONICAL/SKILL.md"
cp "$SELF_DIR/VERSION" "$CANONICAL/VERSION"
mkdir -p "$CANONICAL/scripts"
cp "$SELF_DIR/scripts/"*.sh "$CANONICAL/scripts/"
if [ -d "$SELF_DIR/scripts/lib" ]; then
    mkdir -p "$CANONICAL/scripts/lib"
    cp "$SELF_DIR/scripts/lib/"* "$CANONICAL/scripts/lib/"
fi
# v1.3.1 hot-patch: also copy scripts/vendored/ so installed canonical has
# the self-contained skill-creator copy. v1.3.0 install.sh shipped without
# this line, leaving installed canonical without vendored/ — self-contained
# feature silently broken for users who only had the v1.3.0 install.sh.
if [ -d "$SELF_DIR/scripts/vendored" ]; then
    cp -R "$SELF_DIR/scripts/vendored" "$CANONICAL/scripts/vendored"
fi
chmod +x "$CANONICAL/scripts/"*.sh
[ -d "$SELF_DIR/references" ] && cp -R "$SELF_DIR/references" "$CANONICAL/references"
[ -d "$SELF_DIR/assets" ] && cp -R "$SELF_DIR/assets" "$CANONICAL/assets"
[ -d "$SELF_DIR/agents" ] && cp -R "$SELF_DIR/agents" "$CANONICAL/agents"
# v1.6.0: commands/ propagation restored — needed for /gitx-init slash shim.
# v1.1.0 rationale (commands/gitx-release.md was a duplicate of Claude Code's
# auto-promoted /gitx-release) no longer applies because the new shim is
# /gitx-init, which is a *subcommand* with no auto-promotion path.
[ -d "$SELF_DIR/commands" ] && cp -R "$SELF_DIR/commands" "$CANONICAL/commands"

# v1.7.5: the skill-bundle commands/ dir is NOT where Claude Code discovers
# slash commands — it only scans ~/.claude/commands/*.md (this is why
# /handoff-recall works but /gitx-sop reported "Unknown command" for three
# releases). Subcommand shims (/gitx-init, /gitx-sop) have no skill-name
# auto-promotion, so they MUST be flat files in $CLAUDE_COMMANDS. The main
# /gitx-release is intentionally excluded — it auto-promotes from SKILL.md
# name: and a duplicate shim would double-list it (v1.1.0 rationale).
if [ -d "$SELF_DIR/commands" ]; then
    mkdir -p "$CLAUDE_COMMANDS"
    for _shim in "$SELF_DIR/commands/"*.md; do
        [ -f "$_shim" ] || continue
        case "$(basename "$_shim")" in
            gitx-release.md|GitX-release.md) continue ;;
        esac
        cp "$_shim" "$CLAUDE_COMMANDS/$(basename "$_shim")"
    done
fi

install_step_ok "$CANONICAL  [$_INSTALL_VERSION]"

# --- Checkpoint 4/6: Symlinks (Claude Code + OpenCode) ---
install_checkpoint "$_TKX_E_LINK" "Symlinks"

mkdir -p "$(dirname "$CLAUDE_LINK")"
rm -f "$CLAUDE_LINK" 2>/dev/null || rm -rf "$CLAUDE_LINK"
ln -s "$CANONICAL" "$CLAUDE_LINK"
install_step_ok "Claude Code  -> $CLAUDE_LINK"

if mkdir -p "$(dirname "$OPENCODE_LINK")" 2>/dev/null; then
    rm -f "$OPENCODE_LINK" 2>/dev/null || rm -rf "$OPENCODE_LINK"
    ln -s "$CANONICAL" "$OPENCODE_LINK"
    install_step_ok "OpenCode     -> $OPENCODE_LINK"
else
    install_step_warn "OpenCode     -> skipped (cannot create $(dirname "$OPENCODE_LINK"))"
fi

# --- Checkpoint 5/6: Legacy cleanup ---
install_checkpoint "$_TKX_E_BROOM" "Legacy cleanup"
_LEGACY_REMOVED=0
# v1.1.0 rebrand: legacy slash-command shim cleanup so reinstall doesn't
# leave the old /gitx-release entry around alongside the new /gitx-release.
if [ -f "$CLAUDE_COMMANDS/GitX-release.md" ]; then
    rm -f "$CLAUDE_COMMANDS/GitX-release.md" && _LEGACY_REMOVED=$((_LEGACY_REMOVED + 1))
fi
# Legacy skill folder (pre-rebrand) cleanup across all CLIs.
for _legacy in \
    "$HOME/.agents/skills/$SKILL_NAME_LEGACY" \
    "$HOME/.claude/skills/$SKILL_NAME_LEGACY" \
    "$HOME/.config/opencode/skills/$SKILL_NAME_LEGACY"; do
    if [ -e "$_legacy" ] || [ -L "$_legacy" ]; then
        rm -rf "$_legacy" && _LEGACY_REMOVED=$((_LEGACY_REMOVED + 1))
    fi
done
# Legacy duplicate cleanup. NOTE: we deliberately do NOT rm
# `$HOME/.agents/skills/GitX-release/` here — on macOS HFS+ that path is
# case-insensitively equivalent to `$HOME/.agents/skills/gitx-release/`
# (the canonical install we just created above), so removing it would
# nuke the canonical install. (Gotcha #16 + Decision 2026-04-30).
for _codex in \
    "${CODEX_SKILLS_DIR:?}/$SKILL_NAME" \
    "${CODEX_SKILLS_DIR:?}/$SKILL_NAME_LEGACY" \
    "${CODEX_SKILLS_DIR:?}/GitX-release"; do
    if [ -e "$_codex" ] || [ -L "$_codex" ]; then
        rm -rf "$_codex" && _LEGACY_REMOVED=$((_LEGACY_REMOVED + 1))
    fi
done
install_step_ok "Removed $_LEGACY_REMOVED stale legacy entries"

# --- Checkpoint 6/6: Validation ---
install_checkpoint "$_TKX_E_CHECK" "Validation"
if [ -f "$CANONICAL/SKILL.md" ]; then
    install_step_ok "SKILL.md present at canonical"
else
    install_step_fail "SKILL.md missing at $CANONICAL/SKILL.md"
    exit 1
fi
if [ -L "$CLAUDE_LINK" ] && [ "$(readlink "$CLAUDE_LINK")" = "$CANONICAL" ]; then
    install_step_ok "Claude Code symlink resolves to canonical"
else
    install_step_fail "Claude Code symlink not pointing to canonical"
    exit 1
fi
if [ -x "$CANONICAL/scripts/gitx-release.sh" ]; then
    install_step_ok "scripts/*.sh executable"
else
    install_step_fail "scripts/gitx-release.sh not executable"
    exit 1
fi

# --- Checkpoint 7/7: Install PATH shim (v1.13.0) ---
install_checkpoint "$_TKX_E_LINK" "PATH shim (gitx-marketplace)"
install_marketplace_path_shim() {
    local bindir="$HOME/.agents/bin"
    local target="$CANONICAL/scripts/gitx-marketplace.sh"
    if [ ! -x "$target" ]; then
        install_step_fail "gitx-marketplace.sh not executable at $target"
        return 1
    fi
    mkdir -p "$bindir"
    local shim="$bindir/gitx-marketplace"
    # Reject if exists as a directory (safety catch-all before FORCE branch).
    # Prevents user confusion if someone manually mkdir'd $shim by mistake.
    if [ -d "$shim" ] && [ ! -L "$shim" ]; then
        install_step_fail "$shim exists as a directory. Refusing to recursively remove. Inspect and 'rm -rf $shim' manually if intended."
        return 1
    fi
    # Reject if exists as regular file (not symlink) — prevent overwriting user files silently.
    # --force overrides the refusal (rm + ln); without --force, surface as failure with rm hint.
    if [ -e "$shim" ] && [ ! -L "$shim" ]; then
        if [ "$FORCE" = "1" ]; then
            rm -f "$shim"
        else
            install_step_fail "$shim exists as a regular file (not a symlink). Refusing to overwrite without --force. Either rerun with --force or rm '$shim' manually."
            return 1
        fi
    fi
    # Warn if replacing an existing symlink to a different target
    if [ -L "$shim" ] && [ "$(readlink "$shim" 2>/dev/null)" != "$target" ]; then
        printf '    %s (warn) replacing existing symlink: %s → %s\n' "$_TKX_BULLET" "$shim" "$(readlink "$shim")" >&2
    fi
    ln -sfn "$target" "$shim"
    install_step_ok "PATH shim: ~/.agents/bin/gitx-marketplace → $target"
    case ":$PATH:" in
        *":$bindir:"*) ;;
        *) printf '    %s Add to PATH: export PATH="$HOME/.agents/bin:$PATH"\n' "$_TKX_BULLET" ;;
    esac
    return 0
}
install_marketplace_path_shim || exit 1

# --- Success banner + CLI table + next hints ---
install_banner_bottom "$SKILL_NAME" "$_INSTALL_VERSION"
install_cli_table_begin
install_cli_row "Claude Code" "/gitx-release"          "$CLAUDE_LINK"
install_cli_row "Codex CLI"   "\$gitx-release"          "$CANONICAL"
install_cli_row "Codex CLI"   "\$git-release-pipeline"  "(deprecated alias, /skills lists both)"
install_cli_row "OpenCode"    "say \"gitx release\""     "$OPENCODE_LINK"
install_cli_row "Gemini CLI"  "say \"gitx release\""     "$CANONICAL"
install_cli_row "PATH"        "gitx-marketplace"        "$HOME/.agents/bin/gitx-marketplace"
install_cli_table_end
install_next_block \
    "Run /gitx-release in any skill project to ship a new version" \
    "See INSTALL.md section 5 for self-check commands" \
    "Read references/TKX_Git_Release_policy_and_process.md for the full policy"
