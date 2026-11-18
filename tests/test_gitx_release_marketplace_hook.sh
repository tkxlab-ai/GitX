#!/usr/bin/env bash
# tests/test_gitx_release_marketplace_hook.sh — post-release hook contract of
# the internal release wrapper (gitx-release.sh).
#
# Marketplace: the central-marketplace bump is an outward-facing step and
# moved to gitx-publish.sh (design D5: public GitHub Release, marketplace bump
# and npm publish all happen together, after the owner approves the GitHub
# draft). The internal release must therefore NEVER touch gitx-marketplace.sh
# — not even when .gitx/marketplace-target is present. These cases guard that.
# Gitea: invoke_gitea_release (internal SH Gitea publish) stays; G1-G6 below.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$ROOT/scripts/gitx-release.sh"

# Hermetic env (Gotcha #74): under the real pipeline, release.sh exports
# PROJECT_ROOT = the real repo, and invoke_gitea_release cd's there — the
# extracted-hook cases would then run against the real repo instead of their
# scratch dirs. Every case starts from "cwd is the project".
unset PROJECT_ROOT SKILL_NAME PROJECT_NAME SKIP_MARKETPLACE DRY_RUN RELEASE_LOG MARKETPLACE_BIN
unset SKIP_GITEA_RELEASE GITEA_RELEASE_BIN

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }
skip() { SKIP=$((SKIP+1)); echo "  ➖ $1"; }

if [ ! -f "$WRAPPER" ]; then
    skip "gitx-release.sh missing — generic-safe"
    echo "SUMMARY: $PASS passed, $FAIL failed, $SKIP skipped"; exit 0
fi

# ---- Marketplace: the internal release never invokes it ---------------------

# --- M0: no marketplace hook code left in the wrapper ---
if grep -q 'invoke_marketplace_sync\|interpret_marketplace_exit\|gitx-marketplace' "$WRAPPER"; then
    fail "M0: wrapper still references the marketplace hook: $(grep -n 'invoke_marketplace_sync\|interpret_marketplace_exit\|gitx-marketplace' "$WRAPPER" | head -3)"
else
    ok "M0: wrapper has no invoke_marketplace_sync / interpret_marketplace_exit / gitx-marketplace reference"
fi

# Full-wrapper fixture: an opted-in project (.gitx/marketplace-target +
# .claude-plugin/marketplace.json) and a recorder at the wrapper's sibling
# gitx-marketplace.sh, which is where the old hook both sourced and ran it.
# A fake `gh` on PATH records too, so no case can ever reach real GitHub.
MP_FIXTURES=""
trap 'rm -rf $MP_FIXTURES' EXIT
_mp_fixture() {
    local g="$1"
    MP_FIXTURES="$MP_FIXTURES $g"
    mkdir -p "$g/project/skills/demo-skill" "$g/project/Release" "$g/project/.gitx" \
        "$g/project/.claude-plugin" "$g/scripts/lib" "$g/bin"
    cp "$WRAPPER" "$g/scripts/gitx-release.sh"
    cp "$ROOT/scripts/lib/detect-project.sh" "$g/scripts/lib/detect-project.sh"
    chmod +x "$g/scripts/gitx-release.sh"
    printf '#!/bin/bash\nmkdir -p "$PROJECT_ROOT/Release/project-$1"\nexit 0\n' > "$g/scripts/release.sh"
    chmod +x "$g/scripts/release.sh"
    # `return` first: the old wrapper sourced this file, and a bare `exit`
    # would end the wrapper itself instead of just recording.
    printf '#!/bin/bash\nprintf "market %%s\\n" "$*" >> "%s/rec.log"\nreturn 0 2>/dev/null || exit 0\n' "$g" \
        > "$g/scripts/gitx-marketplace.sh"
    chmod +x "$g/scripts/gitx-marketplace.sh"
    printf '#!/bin/bash\nprintf "gh %%s\\n" "$*" >> "%s/rec.log"\nexit 1\n' "$g" > "$g/bin/gh"
    chmod +x "$g/bin/gh"
    printf -- '---\nname: demo-skill\ndescription: Demo skill for the GitX marketplace guard test.\n---\n' \
        > "$g/project/skills/demo-skill/SKILL.md"
    printf 'v0.0.1\n' > "$g/project/skills/demo-skill/VERSION"
    printf 'v0.0.1\n' > "$g/project/VERSION"
    echo "tkxlab-ai/marketplace" > "$g/project/.gitx/marketplace-target"
    printf '{"name":"tkxlab","plugins":[{"name":"demo-skill","version":"0.0.1"}]}\n' \
        > "$g/project/.claude-plugin/marketplace.json"
}
_run_mp_fixture() {
    local g="$1"; shift
    env -u PROJECT_NAME -u SKILL_NAME -u SKIP_GITEA_RELEASE PATH="$g/bin:$PATH" \
        PROJECT_ROOT="$g/project" bash "$g/scripts/gitx-release.sh" "$@" > "$g/stdout.txt" 2>&1
    mp_status=$?
}

# --- M1: marker present, full release → marketplace recorder never called ---
MP_RUN=$(mktemp -d)
_mp_fixture "$MP_RUN"
_run_mp_fixture "$MP_RUN" --version v0.0.2
if [ "$mp_status" -eq 0 ] && [ ! -s "$MP_RUN/rec.log" ]; then
    ok "M1: .gitx/marketplace-target present → full release exit 0, marketplace script + gh never invoked"
else
    fail "M1: status=$mp_status rec=$(cat "$MP_RUN/rec.log" 2>/dev/null) out=$(cat "$MP_RUN/stdout.txt")"
fi

# --- M2: --skip-marketplace is an accepted no-op that points at gitx-publish.sh ---
MP_SKIP=$(mktemp -d)
_mp_fixture "$MP_SKIP"
_run_mp_fixture "$MP_SKIP" --version v0.0.2 --skip-marketplace
if [ "$mp_status" -eq 0 ] && [ ! -s "$MP_SKIP/rec.log" ] \
    && grep -q 'gitx-publish.sh' "$MP_SKIP/stdout.txt"; then
    ok "M2: --skip-marketplace → rc 0, notice names gitx-publish.sh, nothing invoked"
else
    fail "M2: status=$mp_status rec=$(cat "$MP_SKIP/rec.log" 2>/dev/null) out=$(cat "$MP_SKIP/stdout.txt")"
fi

# --- M3: --help keeps --skip-marketplace and says the bump lives in gitx-publish.sh ---
out=$(bash "$WRAPPER" --help 2>&1) || true
if grep -q -- '--skip-marketplace' <<<"$out" && grep -q 'gitx-publish.sh' <<<"$out"; then
    ok "M3: --help lists --skip-marketplace (no-op) and points at gitx-publish.sh"
else
    fail "M3: --help missing --skip-marketplace or gitx-publish.sh"
fi

# ---- Gitea release hook (invoke_gitea_release) ------------------------------
# Extract the hook and its log helpers from the wrapper into a sourceable file.
set -e
FUNCS_FILE=$(mktemp)
trap 'rm -rf $MP_FIXTURES; rm -f "$FUNCS_FILE"' EXIT
{
    sed -n '/^log_warn()/,/^}/p' "$WRAPPER"
    sed -n '/^invoke_gitea_release()/,/^}/p' "$WRAPPER"
    echo "true"
} > "$FUNCS_FILE"

# The recorder stands in for gitx-gitea-release.sh: it appends its argv to
# $GITEA_REC_LOG and exits $STUB_GITEA_RC, so the cases assert on whether and
# how the hook called it — never on any network behaviour.
_install_gitea_recorder() {
    cat > "$1/gitea-rec.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GITEA_REC_LOG"
printf 'PROJECT_ROOT=%s PROJECT_NAME=%s SKILL_NAME=%s\n' "${PROJECT_ROOT-<unset>}" \
    "${PROJECT_NAME-<unset>}" "${SKILL_NAME-<unset>}" >> "$GITEA_REC_LOG.env"
echo "STUB-GITEA argv=$*" >&2
exit "${STUB_GITEA_RC:-0}"
STUB
    chmod +x "$1/gitea-rec.sh"
}

# --- G1: marker absent → recorder not called, rc 0 ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    _install_gitea_recorder "$tmp"
    export GITEA_RELEASE_BIN="$tmp/gitea-rec.sh" GITEA_REC_LOG="$tmp/rec.log" VERSION=v1.13.0
    invoke_gitea_release; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ G1: rc=$rc"; exit 1; }
    [ ! -e "$tmp/rec.log" ] || { echo "  ❌ G1: recorder called without a marker"; exit 1; }
    echo "  ✅ G1: gitea marker absent → recorder not called, rc 0"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- G2: marker present → recorder called once with --version v<V> and the
# wrapper's PROJECT_ROOT/PROJECT_NAME/SKILL_NAME passed explicitly ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx
    echo "git.example.internal:2222/rel/demo" > .gitx/gitea-release-target
    _install_gitea_recorder "$tmp"
    export GITEA_RELEASE_BIN="$tmp/gitea-rec.sh" GITEA_REC_LOG="$tmp/rec.log" VERSION=v1.13.0
    # Not exported: only the hook's explicit prefix can hand them to the child.
    # shellcheck disable=SC2034  # read by the eval'd invoke_gitea_release, not by this file
    PROJECT_ROOT="$tmp" PROJECT_NAME=demo SKILL_NAME=demo-skill
    invoke_gitea_release 2>/dev/null; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ G2: rc=$rc"; exit 1; }
    [ -f "$tmp/rec.log" ] && [ "$(wc -l < "$tmp/rec.log" | tr -d ' ')" = 1 ] \
        || { echo "  ❌ G2: recorder not called exactly once"; exit 1; }
    [ "$(cat "$tmp/rec.log")" = "--version v1.13.0" ] \
        || { echo "  ❌ G2: argv=$(cat "$tmp/rec.log")"; exit 1; }
    [ "$(cat "$tmp/rec.log.env")" = "PROJECT_ROOT=$tmp PROJECT_NAME=demo SKILL_NAME=demo-skill" ] \
        || { echo "  ❌ G2: child env=$(cat "$tmp/rec.log.env")"; exit 1; }
    echo "  ✅ G2: gitea marker present → called once with --version v1.13.0 + explicit PROJECT_ROOT/NAME/SKILL_NAME"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- G3: SKIP_GITEA_RELEASE=1 → recorder not called even with the marker ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx
    echo "git.example.internal/rel/demo" > .gitx/gitea-release-target
    _install_gitea_recorder "$tmp"
    export GITEA_RELEASE_BIN="$tmp/gitea-rec.sh" GITEA_REC_LOG="$tmp/rec.log" VERSION=v1.13.0
    SKIP_GITEA_RELEASE=1 invoke_gitea_release; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ G3: rc=$rc"; exit 1; }
    [ ! -e "$tmp/rec.log" ] || { echo "  ❌ G3: recorder called despite SKIP_GITEA_RELEASE=1"; exit 1; }
    echo "  ✅ G3: SKIP_GITEA_RELEASE=1 → recorder not called"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- G4: recorder exits 1 → warning names the standalone re-run, rc 0 ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx
    echo "git.example.internal/rel/demo" > .gitx/gitea-release-target
    _install_gitea_recorder "$tmp"
    export GITEA_RELEASE_BIN="$tmp/gitea-rec.sh" GITEA_REC_LOG="$tmp/rec.log" VERSION=v1.13.0
    out=$(STUB_GITEA_RC=1 invoke_gitea_release 2>&1); rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ G4: rc=$rc"; exit 1; }
    grep -q 'gitea release step failed' <<<"$out" || { echo "  ❌ G4: missing warn"; echo "$out"; exit 1; }
    grep -qF "bash $tmp/gitea-rec.sh --version v1.13.0" <<<"$out" \
        || { echo "  ❌ G4: warn does not name the standalone re-run"; echo "$out"; exit 1; }
    echo "  ✅ G4: recorder exit 1 → warn with standalone re-run, rc 0"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- G5: VERSION unset → version read from the sidecar, v-prefixed ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx
    echo "git.example.internal/rel/demo" > .gitx/gitea-release-target
    echo "1.13.0" > VERSION
    _install_gitea_recorder "$tmp"
    unset VERSION
    export GITEA_RELEASE_BIN="$tmp/gitea-rec.sh" GITEA_REC_LOG="$tmp/rec.log"
    invoke_gitea_release 2>/dev/null; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ G5: rc=$rc"; exit 1; }
    [ "$(cat "$tmp/rec.log" 2>/dev/null)" = "--version v1.13.0" ] \
        || { echo "  ❌ G5: argv=$(cat "$tmp/rec.log" 2>/dev/null)"; exit 1; }
    echo "  ✅ G5: VERSION unset → sidecar 1.13.0 passed as --version v1.13.0"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- G6: --help advertises --skip-gitea-release ---
out=$(bash "$WRAPPER" --help 2>&1) || true
if grep -q -- '--skip-gitea-release' <<<"$out"; then
    PASS=$((PASS+1)); echo "  ✅ G6: --help advertises --skip-gitea-release"
else
    FAIL=$((FAIL+1)); echo "  ❌ G6: --help missing --skip-gitea-release"
fi

echo "SUMMARY: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
