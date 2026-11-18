#!/bin/bash
# skill-creator-version.sh — v1.3.0 helper for system-vs-vendored version detection.
#
# Reads vendored skill-creator/VERSION pinning file + probes system skill-creator
# install (plugin cache, ~/.claude/skills/, ~/.agents/skills/) + PyYAML available?
# Computes a verdict per date proxy comparison (YYYY-MM-DD string compare works
# because all dates are zero-padded ISO 8601).
#
# Exported vars after calling `skill_creator_status <skill-root>`:
#   SKC_VENDORED_PATH     abs path to vendored skill-creator/ (empty if missing)
#   SKC_VENDORED_DATE     YYYY-MM-DD pinning date from vendored VERSION
#   SKC_VENDORED_COMMIT   upstream commit hash (full sha)
#   SKC_SYSTEM_PATH       abs path to system skill-creator (empty if absent)
#   SKC_SYSTEM_DATE       YYYY-MM-DD from plugin cache dir mtime (date proxy)
#   SKC_PYYAML_OK         "1" if `python3 -c "import yaml"` succeeds, else "0"
#   SKC_VERDICT           one of:
#     same             — system == vendored date (use system)
#     system_newer     — system date > vendored date (use system)
#     vendored_newer   — system date < vendored date (prompt or use vendored)
#     system_absent    — system not found (use vendored)
#     vendored_absent  — vendored not found (defensive; shouldn't happen post-v1.3.0)
#     both_absent      — neither found (caller falls back to zip)
#
# Usage:
#   source scripts/lib/skill-creator-version.sh
#   skill_creator_status "$SKILL_ROOT"
#   case "$SKC_VERDICT" in ... esac

# shellcheck disable=SC2034  # SKC_* vars are read by callers via `source`
_skc_read_vendored() {
    local skc_root="$1"
    local vendored_dir="$skc_root/vendored/skill-creator"
    local vendored_ver="$vendored_dir/VERSION"
    SKC_VENDORED_PATH=""
    SKC_VENDORED_DATE=""
    SKC_VENDORED_COMMIT=""
    if [ -f "$vendored_ver" ] && [ -f "$vendored_dir/scripts/package_skill.py" ]; then
        SKC_VENDORED_PATH="$vendored_dir"
        SKC_VENDORED_DATE=$(awk -F= '/^upstream_date=/ {print $2}' "$vendored_ver" | tr -d ' "')
        SKC_VENDORED_COMMIT=$(awk -F= '/^upstream_commit=/ {print $2}' "$vendored_ver" | tr -d ' "')
    fi
}

_skc_probe_system() {
    SKC_SYSTEM_PATH=""
    SKC_SYSTEM_DATE=""
    local cand
    for cand in "$HOME/.claude/plugins/cache/claude-plugins-official/skill-creator"/*/skills/skill-creator \
                "$HOME/.claude/skills/skill-creator" \
                "$HOME/.agents/skills/skill-creator"; do
        if [ -d "$cand" ] && [ -f "$cand/scripts/package_skill.py" ]; then
            SKC_SYSTEM_PATH="$cand"
            # Cross-platform mtime → YYYY-MM-DD (macOS BSD stat vs GNU stat)
            SKC_SYSTEM_DATE=$(stat -f "%Sm" -t "%Y-%m-%d" "$cand" 2>/dev/null || \
                              stat -c "%y" "$cand" 2>/dev/null | awk '{print $1}')
            break
        fi
    done
}

_skc_check_pyyaml() {
    if python3 -c "import yaml" >/dev/null 2>&1; then
        SKC_PYYAML_OK="1"
    else
        SKC_PYYAML_OK="0"
    fi
}

_skc_compute_verdict() {
    if [ -z "$SKC_SYSTEM_DATE" ] && [ -z "$SKC_VENDORED_DATE" ]; then
        SKC_VERDICT="both_absent"
    elif [ -z "$SKC_VENDORED_DATE" ]; then
        SKC_VERDICT="vendored_absent"
    elif [ -z "$SKC_SYSTEM_DATE" ]; then
        SKC_VERDICT="system_absent"
    elif [ "$SKC_SYSTEM_DATE" = "$SKC_VENDORED_DATE" ]; then
        SKC_VERDICT="same"
    else
        # ISO 8601 string compare via [ x \> y ] works for YYYY-MM-DD
        if [ "$SKC_SYSTEM_DATE" \> "$SKC_VENDORED_DATE" ]; then
            SKC_VERDICT="system_newer"
        else
            SKC_VERDICT="vendored_newer"
        fi
    fi
}

skill_creator_status() {
    local skc_root="${1:-${SKILL_ROOT:-$(pwd)}}"
    _skc_read_vendored "$skc_root"
    _skc_probe_system
    _skc_check_pyyaml
    _skc_compute_verdict
}

# v1.4.0: best-effort PyYAML enablement. If system Python lacks PyYAML, try
# creating a temporary venv with PyYAML installed. Sets:
#   SKC_PYYAML_OK=1
#   SKC_VENV_PYTHON  — path to venv's python3 (or "python3" if system already has PyYAML)
#   SKC_VENV_DIR     — venv dir path if created (caller should reap via cleanup trap)
# Returns 0 on success (PyYAML available), 1 if no Python or venv/pip fails.
# Idempotent: if SKC_PYYAML_OK was already 1, returns 0 immediately with
# SKC_VENV_PYTHON=python3 (no venv needed).
ensure_pyyaml_via_venv() {
    SKC_VENV_DIR=""
    if [ "$SKC_PYYAML_OK" = "1" ]; then
        SKC_VENV_PYTHON="python3"
        return 0
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        return 1
    fi
    SKC_VENV_DIR=$(mktemp -d 2>/dev/null) || return 1
    if python3 -m venv "$SKC_VENV_DIR" >/dev/null 2>&1 && \
       "$SKC_VENV_DIR/bin/pip" install pyyaml --quiet >/dev/null 2>&1; then
        SKC_PYYAML_OK="1"
        SKC_VENV_PYTHON="$SKC_VENV_DIR/bin/python3"
        return 0
    fi
    rm -rf "$SKC_VENV_DIR"
    SKC_VENV_DIR=""
    return 1
}
