#!/usr/bin/env bash
# tests/test_gitx_release_marketplace_hook.sh — v1.13.0 wrapper hook BDD.
# Mocks release.sh + gitx-marketplace.sh; asserts on hook orchestration only.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$ROOT/scripts/gitx-release.sh"

# Hermetic env (Gotcha #74): under the real pipeline, release.sh exports
# PROJECT_ROOT = the real repo, and invoke_marketplace_sync cd's there — the
# extracted-hook cases would then run against the real repo instead of their
# scratch dirs. Every case starts from "cwd is the project"; T13 sets
# PROJECT_ROOT explicitly.
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

# --- T0: log_warn / log_info / interpret_marketplace_exit are defined ---
# Extract the function definitions from the wrapper and test them
set +e

# Use grep to find and verify the function signatures exist in the wrapper
if grep -q "^log_warn()" "$WRAPPER" && \
   grep -q "^log_info()" "$WRAPPER" && \
   grep -q "^interpret_marketplace_exit()" "$WRAPPER"; then
    echo "  ✅ T0: logging + interpret helpers exported"
    PASS=$((PASS+1))
else
    echo "  ❌ T0: helper functions missing from wrapper"
    FAIL=$((FAIL+1))
fi

set -e

# Extract function definitions from wrapper and gitx-marketplace helper
setup_functions() {
    local SCRIPT_DIR="$ROOT/scripts"
    # Create a minimal functions file with just what we need
    {
        # log_warn, log_info, interpret_marketplace_exit from wrapper
        sed -n '/^log_warn()/,/^}/p' "$SCRIPT_DIR/gitx-release.sh"
        sed -n '/^log_info()/,/^}/p' "$SCRIPT_DIR/gitx-release.sh"
        sed -n '/^interpret_marketplace_exit()/,/^}/p' "$SCRIPT_DIR/gitx-release.sh"
        sed -n '/^invoke_marketplace_sync()/,/^}/p' "$SCRIPT_DIR/gitx-release.sh"
        sed -n '/^invoke_gitea_release()/,/^}/p' "$SCRIPT_DIR/gitx-release.sh"
        # Helpers from gitx-marketplace.sh
        sed -n '/^validate_marker_content()/,/^}/p' "$SCRIPT_DIR/gitx-marketplace.sh"
        sed -n '/^read_marker()/,/^}/p' "$SCRIPT_DIR/gitx-marketplace.sh"
        sed -n '/^fetch_marketplace_json()/,/^}/p' "$SCRIPT_DIR/gitx-marketplace.sh"
        echo "true" # Ensure success exit
    } > "$1"
}

FUNCS_FILE=$(mktemp)
trap 'rm -f "$FUNCS_FILE"' EXIT
setup_functions "$FUNCS_FILE"

# Helper to install a stub gitx-marketplace.sh that just echoes its argv
_install_stub_market() {
    cat > "$1/scripts/gitx-marketplace.sh" <<'STUB'
#!/usr/bin/env bash
printf 'STUB-MARKET argv=%s\n' "$*" >&2
exit "${STUB_MARKET_RC:-0}"
STUB
    chmod +x "$1/scripts/gitx-marketplace.sh"
}

# --- T1: marker absent → invoke_marketplace_sync returns 0 silently ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    invoke_marketplace_sync; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T1: rc=$rc"; exit 1; }
    echo "  ✅ T1: marker absent → silent skip rc 0"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T10: marker present but tampered → log_warn + skip, rc 0 ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx .claude-plugin
    printf 'invalid\x00marker' > .gitx/marketplace-target
    cp "$ROOT/tests/fixtures/marketplace.json" .claude-plugin/marketplace.json 2>/dev/null || echo '{"plugins":[{"name":"test"}]}' > .claude-plugin/marketplace.json
    echo "1.0.0" > VERSION
    out=$(invoke_marketplace_sync 2>&1); rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T10: rc=$rc"; exit 1; }
    grep -qi 'marker.*invalid' <<<"$out" || { echo "  ❌ T10: missing warn"; exit 1; }
    echo "  ✅ T10: tampered marker → warn + skip rc 0"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T11: .claude-plugin/marketplace.json missing → log_warn + skip, rc 0 ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    out=$(invoke_marketplace_sync 2>&1); rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T11: rc=$rc"; exit 1; }
    grep -qi 'marketplace.json' <<<"$out" || { echo "  ❌ T11: missing warn"; exit 1; }
    echo "  ✅ T11: marketplace.json missing → warn + skip rc 0"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T2/T3: --skip-marketplace bypasses hook (marker absent or present) ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    SKIP_MARKETPLACE=1 invoke_marketplace_sync; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T2/T3: rc=$rc"; exit 1; }
    echo "  ✅ T2/T3: SKIP_MARKETPLACE=1 bypasses hook silently"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T7: arg-parse exposes --skip-marketplace flag ---
out=$(bash "$WRAPPER" --help 2>&1) || true
if grep -q -- '--skip-marketplace' <<<"$out"; then
    PASS=$((PASS+1)); echo "  ✅ T7: --help advertises --skip-marketplace"
else
    FAIL=$((FAIL+1)); echo "  ❌ T7: --help missing --skip-marketplace"
fi

# --- T4: marker present, probe=present → bump invoked once ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx .claude-plugin scripts
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    cp "$ROOT/tests/fixtures/marketplace.json" .claude-plugin/marketplace.json
    echo "1.13.0" > VERSION
    _install_stub_market "$tmp"
    export MARKETPLACE_BIN="$tmp/scripts/gitx-marketplace.sh"
    gh() { printf '%s' "$(jq -nc '{plugins:[{name:"demo-skill-one"}]}' | base64)"; return 0; }
    export -f gh
    out=$(invoke_marketplace_sync 2>&1); rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T4: rc=$rc"; exit 1; }
    grep -q 'STUB-MARKET argv=bump' <<<"$out" \
        || { echo "  ❌ T4: stub not called with bump"; echo "$out"; exit 1; }
    echo "  ✅ T4: probe=present → bump invoked"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T5: marker present, probe=absent (gh api 200 but entry missing) → register fallback ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx .claude-plugin scripts
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    cp "$ROOT/tests/fixtures/marketplace.json" .claude-plugin/marketplace.json
    echo "1.13.0" > VERSION
    _install_stub_market "$tmp"
    export MARKETPLACE_BIN="$tmp/scripts/gitx-marketplace.sh"
    gh() { printf '%s' "$(jq -nc '{plugins:[]}' | base64)"; return 0; }
    export -f gh
    out=$(invoke_marketplace_sync 2>&1); rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T5: rc=$rc"; exit 1; }
    grep -q 'STUB-MARKET argv=register' <<<"$out" \
        || { echo "  ❌ T5: stub not called with register"; echo "$out"; exit 1; }
    grep -qi 'falling back to register' <<<"$out" \
        || { echo "  ❌ T5: missing cold-restart warn"; exit 1; }
    echo "  ✅ T5: probe=absent → register fallback + warn"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T6: gh probe fails entirely → still register fallback with different warn text ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx .claude-plugin scripts
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    cp "$ROOT/tests/fixtures/marketplace.json" .claude-plugin/marketplace.json
    echo "1.13.0" > VERSION
    _install_stub_market "$tmp"
    export MARKETPLACE_BIN="$tmp/scripts/gitx-marketplace.sh"
    gh() { return 1; }   # all gh calls fail
    export -f gh
    out=$(invoke_marketplace_sync 2>&1); rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T6: rc=$rc"; exit 1; }
    grep -qi 'probe failed' <<<"$out" \
        || { echo "  ❌ T6: missing probe-failed warn"; exit 1; }
    echo "  ✅ T6: probe failure → register fallback with diagnostic"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T8: stub returns rc=4 → wrapper still exit 0, warn message shown ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx .claude-plugin scripts
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    cp "$ROOT/tests/fixtures/marketplace.json" .claude-plugin/marketplace.json
    echo "1.13.0" > VERSION
    _install_stub_market "$tmp"
    export MARKETPLACE_BIN="$tmp/scripts/gitx-marketplace.sh"
    gh() { printf '%s' "$(jq -nc '{plugins:[{name:"demo-skill-one"}]}' | base64)"; return 0; }
    export -f gh
    out=$(STUB_MARKET_RC=4 invoke_marketplace_sync 2>&1); rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T8: rc=$rc"; exit 1; }
    grep -qi 'gh auth missing' <<<"$out" \
        || { echo "  ❌ T8: missing exit-4 interpretation"; exit 1; }
    echo "  ✅ T8: sub-exit 4 → wrapper exit 0 + actionable warn"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T9: DRY_RUN=1 propagates --dry-run to stub ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx .claude-plugin scripts
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    cp "$ROOT/tests/fixtures/marketplace.json" .claude-plugin/marketplace.json
    echo "1.13.0" > VERSION
    _install_stub_market "$tmp"
    export MARKETPLACE_BIN="$tmp/scripts/gitx-marketplace.sh"
    gh() { printf '%s' "$(jq -nc '{plugins:[{name:"demo-skill-one"}]}' | base64)"; return 0; }
    export -f gh
    out=$(DRY_RUN=1 invoke_marketplace_sync 2>&1); rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T9: rc=$rc"; exit 1; }
    grep -q -- '--dry-run' <<<"$out" \
        || { echo "  ❌ T9: --dry-run not propagated"; exit 1; }
    echo "  ✅ T9: --dry-run propagated to gitx-marketplace stub"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T12: warning lands in BOTH stderr AND RELEASE_LOG file ---
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx .claude-plugin scripts Release/logs
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    cp "$ROOT/tests/fixtures/marketplace.json" .claude-plugin/marketplace.json
    echo "1.13.0" > VERSION
    _install_stub_market "$tmp"
    export MARKETPLACE_BIN="$tmp/scripts/gitx-marketplace.sh"
    gh() { printf '%s' "$(jq -nc '{plugins:[{name:"demo-skill-one"}]}' | base64)"; return 0; }
    export -f gh
    RELEASE_LOG="$tmp/Release/logs/test.log"
    STUB_MARKET_RC=1 invoke_marketplace_sync 2>&1 | grep -qi 'marketplace step failed' || { echo "  ❌ T12 stderr"; exit 1; }
    grep -qi 'WARN.*marketplace' "$RELEASE_LOG" || { echo "  ❌ T12: no warn in RELEASE_LOG"; exit 1; }
    echo "  ✅ T12: warning in BOTH stderr AND RELEASE_LOG"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T13: hook resolves marker/VERSION from $PROJECT_ROOT, not the caller's cwd ---
# The wrapper honours PROJECT_ROOT=… from any directory; the hook used bare
# relative paths, so an out-of-tree invocation silently skipped marketplace sync.
(
    set -e
    # shellcheck disable=SC1090
    . "$FUNCS_FILE"
    fix=$(mktemp -d); other=$(mktemp -d); trap 'rm -rf "$fix" "$other"' EXIT
    mkdir -p "$fix/.gitx" "$fix/.claude-plugin" "$fix/scripts"
    echo "tkxlab-ai/marketplace" > "$fix/.gitx/marketplace-target"
    cp "$ROOT/tests/fixtures/marketplace.json" "$fix/.claude-plugin/marketplace.json"
    echo "1.13.0" > "$fix/VERSION"
    _install_stub_market "$fix"
    export MARKETPLACE_BIN="$fix/scripts/gitx-marketplace.sh"
    gh() { printf '%s' "$(jq -nc '{plugins:[{name:"demo-skill-one"}]}' | base64)"; return 0; }
    export -f gh
    cd "$other"
    out=$(PROJECT_ROOT="$fix" invoke_marketplace_sync 2>&1); rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T13: rc=$rc"; exit 1; }
    grep -q 'STUB-MARKET argv=bump' <<<"$out" \
        || { echo "  ❌ T13: hook did not find \$PROJECT_ROOT/.gitx/marketplace-target from another cwd"; echo "$out"; exit 1; }
    [ "$(pwd)" = "$other" ] || { echo "  ❌ T13: hook changed the caller's cwd"; exit 1; }
    echo "  ✅ T13: PROJECT_ROOT out of cwd → hook runs in project root (caller cwd unchanged)"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# ---- Gitea release hook (invoke_gitea_release) ------------------------------
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
