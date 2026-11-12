#!/usr/bin/env bash
# tests/test_gitx_marketplace.sh — v1.13.0 marketplace helper BDD.
#
# Mocks gh as a shell function (Q5: zero network in CI). Each test sets up its
# own fixture dir under a mktemp scratch, exports a mock gh function, invokes
# the helper, and asserts on exit code + side-effects.
#
# Generic-safe: SKIP all tests if scripts/gitx-marketplace.sh missing (public
# release artifact layout — v1.12.4 CI fix pattern).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GMK="$ROOT/scripts/gitx-marketplace.sh"

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }
skip() { SKIP=$((SKIP+1)); echo "  ➖ $1"; }

# Mock-gh harness: tests can preset MOCK_GH_* env vars to canned responses.
# Override gh as a shell function in the test process before invoking gitx-marketplace.
install_mock_gh() {
    gh() {
        case "$1 ${2:-}" in
            "auth status"|"auth ")          return "${MOCK_GH_AUTH_RC:-0}" ;;
            "api"*)
                if [ -n "${MOCK_GH_API_RESPONSE:-}" ]; then
                    printf '%s' "$MOCK_GH_API_RESPONSE"
                fi
                return "${MOCK_GH_API_RC:-0}" ;;
            "pr create"|"pr "*"create"*)    return "${MOCK_GH_PR_CREATE_RC:-0}" ;;
            "pr merge"|"pr "*"merge"*)      return "${MOCK_GH_PR_MERGE_RC:-0}" ;;
            "pr list")                      printf '%s' "${MOCK_GH_PR_LIST:-[]}"; return 0 ;;
            *)                              return 1 ;;
        esac
    }
    export -f gh
}

# Helper: create a scratch skill project with marker + manifest
_scratch_skill() {
    tmp=$(mktemp -d)
    mkdir -p "$tmp/.gitx" "$tmp/.claude-plugin" "$tmp/scripts"
    cp "$ROOT/tests/fixtures/marketplace.json" "$tmp/.claude-plugin/marketplace.json"
    # Restrict marketplace.json to a single plugin (plugins[0] contract)
    jq '{name, owner, plugins: [.plugins[0]]}' "$tmp/.claude-plugin/marketplace.json" \
       > "$tmp/.claude-plugin/marketplace.json.new" \
       && mv "$tmp/.claude-plugin/marketplace.json.new" "$tmp/.claude-plugin/marketplace.json"
    echo "1.2.0" > "$tmp/VERSION"
    echo "$tmp"
}

if [ ! -f "$GMK" ]; then
    skip "gitx-marketplace.sh not present — generic-safe skip"
    echo "SUMMARY: $PASS passed, $FAIL failed, $SKIP skipped"; exit 0
fi

# --- T0: script is executable and --help exits 0 with usage banner ---
out=$(bash "$GMK" --help 2>&1) && rc=0 || rc=$?
if [ "$rc" = 0 ] && grep -q '^Usage: gitx-marketplace' <<<"$out"; then
    ok "T0: --help exits 0 with usage banner"
else
    fail "T0: --help did not produce expected banner (rc=$rc)"
fi

# --- T14: validate_marker_content rejects CRLF / metachar / dotdot / absolute / oversize ---
# Source the script to access the helper directly.
( # shellcheck disable=SC1090
  . "$GMK"
  for bad in $'foo/bar\r' "  /bar" "../escape" "/abs/path" "foo bar/x" "a/b"$'\n'"c" "" "$(printf 'x%.0s' {1..150})"; do
      if validate_marker_content "$bad" 2>/dev/null; then
          echo "  ❌ T14: validate_marker_content WRONGLY accepted: $(printf '%q' "$bad")"
          exit 1
      fi
  done
  # Valid cases must accept
  for good in "tkxlab-ai/marketplace" "owner/repo-with.dot_under"; do
      validate_marker_content "$good" || { echo "  ❌ T14: WRONGLY rejected: $good"; exit 1; }
  done
  echo "  ✅ T14: validate_marker_content accept/reject contract holds"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T6: validate_entry rejects malformed plugin entry ---
( # shellcheck disable=SC1090
  . "$GMK"
  bad=$(cat "$ROOT/tests/fixtures/plugin-entry-bad.json")
  if validate_entry "$bad" 2>/dev/null; then
      echo "  ❌ T6: validate_entry accepted malformed entry"; exit 1
  fi
  good=$(cat "$ROOT/tests/fixtures/plugin-entry-good.json")
  validate_entry "$good" 2>/dev/null || { echo "  ❌ T6: validate_entry rejected good entry"; exit 1; }
  echo "  ✅ T6: validate_entry accept/reject contract"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T11: bump with gh auth missing → exit 4 ---
(
    set -e
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    cd "$tmp"
    mkdir -p .gitx .claude-plugin
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    cp "$ROOT/tests/fixtures/marketplace.json" .claude-plugin/marketplace.json
    echo "v1.2.0" > VERSION
    install_mock_gh
    MOCK_GH_AUTH_RC=1 bash "$GMK" bump >/dev/null 2>&1; rc=$?
    [ "$rc" = 4 ] || { echo "  ❌ T11: expected exit 4 got $rc"; exit 1; }
    echo "  ✅ T11: bump exits 4 on gh auth failure"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T3: marker present R1, --repo R2, no --force → exit 2 ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    install_mock_gh
    bash "$GMK" register --repo someone-else/different-repo >/dev/null 2>&1; rc=$?
    [ "$rc" = 2 ] || { echo "  ❌ T3: expected exit 2 got $rc"; exit 1; }
    echo "  ✅ T3: marker mismatch without --force → exit 2"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T4: marker present R1, --repo R2 --force → marker overwritten + warning ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    install_mock_gh
    MOCK_GH_API_RESPONSE='{"content":""}' bash "$GMK" register --repo someone-else/other --force --dry-run >"$tmp/t4.out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T4: --force expected exit 0 got $rc"; cat "$tmp/t4.out"; exit 1; }
    # dry-run must leave the existing marker untouched (nothing written under --dry-run)
    grep -q '^tkxlab-ai/marketplace$' .gitx/marketplace-target || { echo "  ❌ T4: dry-run modified the marker"; exit 1; }
    grep -qi 'orphan' "$tmp/t4.out" || { echo "  ❌ T4: missing orphan warning"; exit 1; }
    echo "  ✅ T4: --force --dry-run warns about orphan, marker untouched"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T5: marketplace.json with 2 plugins → exit 1 multi-plugin ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    cp "$ROOT/tests/fixtures/marketplace.json" .claude-plugin/marketplace.json  # 3 plugins
    install_mock_gh
    bash "$GMK" register --repo tkxlab-ai/marketplace --dry-run >/dev/null 2>&1; rc=$?
    [ "$rc" = 1 ] || { echo "  ❌ T5: expected exit 1 got $rc"; exit 1; }
    echo "  ✅ T5: multi-plugin marketplace.json → exit 1"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T7: register --dry-run produces intended diff + no marker change when present ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    install_mock_gh
    MOCK_GH_API_RESPONSE='{"content":""}' bash "$GMK" register --repo tkxlab-ai/marketplace --dry-run >"$tmp/t7.out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T7: dry-run rc=$rc"; cat "$tmp/t7.out"; exit 1; }
    grep -q 'Intended marketplace.json diff' "$tmp/t7.out" \
        || { echo "  ❌ T7: dry-run missing intent banner"; exit 1; }
    [ ! -e .gitx/marketplace-target ] \
        || { echo "  ❌ T7: dry-run wrote the marker"; exit 1; }
    echo "  ✅ T7: --dry-run prints intent, writes no marker, no PR"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T7b: fresh fixture (no .gitx at all) + --dry-run → exit 0, .gitx NOT created ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    rmdir .gitx
    install_mock_gh
    MOCK_GH_API_RESPONSE='{"content":""}' bash "$GMK" register --repo o/r --dry-run >"$tmp/out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T7b: dry-run rc=$rc"; cat "$tmp/out"; exit 1; }
    [ ! -e .gitx ] || { echo "  ❌ T7b: dry-run created .gitx"; exit 1; }
    grep -q 'dry-run.*would write' "$tmp/out" || { echo "  ❌ T7b: missing would-write notice"; exit 1; }
    echo "  ✅ T7b: --dry-run creates nothing (not even .gitx/)"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T15: marker is a symlink to a victim file → refuse, victim untouched ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp" "$victim"' EXIT; cd "$tmp"
    victim=$(mktemp); printf 'line1\nline2\n' > "$victim"
    ln -s "$victim" .gitx/marketplace-target
    install_mock_gh
    bash "$GMK" register --repo evil/repo >"$tmp/out" 2>"$tmp/err"; rc=$?
    [ "$rc" != 0 ] || { echo "  ❌ T15: expected non-zero exit"; exit 1; }
    grep -qi 'symlink' "$tmp/err" || { echo "  ❌ T15: stderr missing 'symlink'"; cat "$tmp/err"; exit 1; }
    [ "$(cat "$victim")" = "$(printf 'line1\nline2')" ] || { echo "  ❌ T15: victim modified"; exit 1; }
    echo "  ✅ T15: symlinked marker refused, victim unchanged"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T16: .gitx itself symlinked outside → refuse, outside dir untouched ---
(
    set -e; tmp=$(_scratch_skill); outside=$(mktemp -d); trap 'rm -rf "$tmp" "$outside"' EXIT; cd "$tmp"
    rmdir .gitx; ln -s "$outside" .gitx
    install_mock_gh
    bash "$GMK" register --repo evil/repo >"$tmp/out" 2>"$tmp/err"; rc=$?
    [ "$rc" != 0 ] || { echo "  ❌ T16: expected non-zero exit"; exit 1; }
    grep -qi 'symlink' "$tmp/err" || { echo "  ❌ T16: stderr missing 'symlink'"; cat "$tmp/err"; exit 1; }
    [ -z "$(ls -A "$outside")" ] || { echo "  ❌ T16: outside dir was written"; exit 1; }
    echo "  ✅ T16: symlinked .gitx refused, outside dir unchanged"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T1: register happy path — marker written, jq append staged, mock-gh PR+merge ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    # Mock git to stay local-only (no real network, no real branches/PR).
    # No-op most commands to simulate successful workflow.
    git() {
        case "$1" in
            clone)
                shift
                local _last="${!#}"
                mkdir -p "$_last/.claude-plugin"
                printf '{"plugins":[]}' > "$_last/.claude-plugin/marketplace.json"
                command git -C "$_last" init >/dev/null 2>&1 || true
                command git -C "$_last" config user.name "test" >/dev/null 2>&1 || true
                command git -C "$_last" config user.email "test@test" >/dev/null 2>&1 || true
                ;;
            config|checkout|add|commit|push|ls-remote)
                return 0
                ;;
            *)
                command git "$@"
                ;;
        esac
    }
    export -f git
    install_mock_gh
    # Probe → entry absent → register proceeds. PR create + merge → 0.
    MOCK_GH_API_RC=1 \
    MOCK_GH_API_RESPONSE='' \
    bash "$GMK" register --repo tkxlab-ai/marketplace >"$tmp/t1.out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T1: expected exit 0 got $rc"; cat "$tmp/t1.out"; exit 1; }
    grep -q '^tkxlab-ai/marketplace$' .gitx/marketplace-target \
        || { echo "  ❌ T1: marker not written"; exit 1; }
    echo "  ✅ T1: register happy path — marker + PR flow exit 0"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T2: register when entry already present → exit 3 (call bump instead) ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    install_mock_gh
    # Probe returns entry-present (base64 decode of marketplace.json includes plugins[0].name)
    entry_name=$(jq -r '.plugins[0].name' .claude-plugin/marketplace.json)
    payload=$(jq -nc --arg n "$entry_name" '{plugins:[{name:$n}]}' | base64)
    MOCK_GH_API_RC=0 \
    MOCK_GH_API_RESPONSE="$payload" \
    bash "$GMK" register --repo tkxlab-ai/marketplace --dry-run >/dev/null 2>&1; rc=$?
    [ "$rc" = 3 ] || { echo "  ❌ T2: expected exit 3 got $rc"; exit 1; }
    echo "  ✅ T2: register when already-present → exit 3"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T8: bump with no marker → exit 2 ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    rm -f .gitx/marketplace-target
    install_mock_gh
    bash "$GMK" bump >/dev/null 2>&1; rc=$?
    [ "$rc" = 2 ] || { echo "  ❌ T8: expected 2 got $rc"; exit 1; }
    echo "  ✅ T8: bump without marker → exit 2"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T9: bump --version v1.2.0 when marketplace at v1.2.0 → no-op exit 0 ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    install_mock_gh
    entry_name=$(jq -r '.plugins[0].name' .claude-plugin/marketplace.json)
    payload=$(jq -nc --arg n "$entry_name" '{plugins:[{name:$n,version:"1.2.0"}]}' | base64)
    MOCK_GH_API_RESPONSE="$payload" bash "$GMK" bump --version v1.2.0 >"$tmp/t9.out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T9: rc=$rc"; cat "$tmp/t9.out"; exit 1; }
    grep -qi 'no-op' "$tmp/t9.out" || { echo "  ❌ T9: no-op msg missing"; cat "$tmp/t9.out"; exit 1; }
    echo "  ✅ T9: bump no-op when version equal"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T10: bump --version v1.3.0 when marketplace at v1.2.0 → PR/merge happen ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    git() {
        case "$1" in
            clone)
                shift
                local _last="${!#}"
                mkdir -p "$_last/.claude-plugin"
                printf '{"plugins":[{"name":"gitx","version":"1.2.0"}]}' > "$_last/.claude-plugin/marketplace.json"
                ;;
            *) command git "$@" ;;
        esac
    }
    export -f git
    install_mock_gh
    entry_name=$(jq -r '.plugins[0].name' .claude-plugin/marketplace.json)
    payload=$(jq -nc --arg n "$entry_name" '{plugins:[{name:$n,version:"1.2.0"}]}' | base64)
    MOCK_GH_API_RESPONSE="$payload" bash "$GMK" bump --version v1.3.0 --dry-run >"$tmp/t10.out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T10: rc=$rc"; cat "$tmp/t10.out"; exit 1; }
    grep -q 'Intended.*1.3.0' "$tmp/t10.out" || { echo "  ❌ T10: missing intended diff"; cat "$tmp/t10.out"; exit 1; }
    echo "  ✅ T10: bump dry-run emits intended version change"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T12: list with no marker and no --repo → exit 2 ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    rm -f .gitx/marketplace-target
    install_mock_gh
    bash "$GMK" list >/dev/null 2>&1; rc=$?
    [ "$rc" = 2 ] || { echo "  ❌ T12: expected 2 got $rc"; exit 1; }
    echo "  ✅ T12: list without marker or --repo → exit 2"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T13: list --repo R prints header + entries from mock gh api ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    install_mock_gh
    payload=$(base64 < "$ROOT/tests/fixtures/marketplace.json")
    MOCK_GH_API_RESPONSE="$payload" bash "$GMK" list --repo tkxlab-ai/marketplace >"$tmp/t13.out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T13: rc=$rc"; cat "$tmp/t13.out"; exit 1; }
    head -1 "$tmp/t13.out" | grep -qE '^NAME[[:space:]]+VERSION[[:space:]]+SOURCE' \
        || { echo "  ❌ T13: missing header"; cat "$tmp/t13.out"; exit 1; }
    grep -q 'demo-skill-one' "$tmp/t13.out" || { echo "  ❌ T13: missing plugin entry"; exit 1; }
    echo "  ✅ T13: list prints tab-separated table from gh api"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T15: register dry-run leaves no mktemp dirs behind ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    install_mock_gh
    before=$(ls "${TMPDIR:-/tmp}"/tmp.* 2>/dev/null | wc -l | tr -d ' ')
    MOCK_GH_API_RC=1 bash "$GMK" register --repo tkxlab-ai/marketplace --dry-run >/dev/null 2>&1 || true
    after=$(ls "${TMPDIR:-/tmp}"/tmp.* 2>/dev/null | wc -l | tr -d ' ')
    [ "$before" = "$after" ] \
        || { echo "  ❌ T15: mktemp residue (before=$before after=$after)"; exit 1; }
    echo "  ✅ T15: trap cleanup leaves no /tmp residue"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T16: register --dry-run with source:"./" transforms via .homepage to github form ---
(
    set -e; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    mkdir -p .gitx .claude-plugin
    # Create marketplace.json with source:"./" and valid .homepage URL
    cat > .claude-plugin/marketplace.json <<'JSON'
{
  "name": "tkx-skills",
  "plugins": [{
    "name": "demo-self-ref",
    "source": "./",
    "version": "1.0.0",
    "description": "demo skill using self-reference source form",
    "homepage": "https://github.com/tkxlab-ai/demo-self-ref"
  }]
}
JSON
    install_mock_gh
    MOCK_GH_API_RC=1 bash "$GMK" register --repo tkxlab-ai/marketplace --dry-run >"$tmp/t16.out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T16: expected exit 0 got $rc"; cat "$tmp/t16.out"; exit 1; }
    grep -q 'Intended marketplace.json diff' "$tmp/t16.out" || { echo "  ❌ T16: missing intent"; exit 1; }
    # Codex round-5 [low]: assert the transformed entry contains expected source object
    grep -q '"source":[[:space:]]*"github"' "$tmp/t16.out" \
        || { echo "  ❌ T16: transformed entry missing github source type"; cat "$tmp/t16.out"; exit 1; }
    grep -q '"repo":[[:space:]]*"tkxlab-ai/demo-self-ref"' "$tmp/t16.out" \
        || { echo "  ❌ T16: transformed entry missing inferred repo 'tkxlab-ai/demo-self-ref'"; cat "$tmp/t16.out"; exit 1; }
    echo "  ✅ T16: register --dry-run transforms source:'./' → github form"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T17: bump probe gh-failure → graceful exit 3, no set -e abort (HIGH regression) ---
# gh auth OK but the api read fails (network/404). The probe pipeline must NOT abort
# cmd_bump under `set -euo pipefail`; the intended exit-3 path must be reached.
# Pre-fix this returned a bare exit 1 (set -e abort) — exactly what 5 Codex rounds missed.
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    install_mock_gh
    MOCK_GH_API_RC=1 MOCK_GH_API_RESPONSE='' bash "$GMK" bump --version v1.3.0 >"$tmp/t17.out" 2>&1; rc=$?
    [ "$rc" = 3 ] || { echo "  ❌ T17: expected exit 3 on failing probe, got $rc (set -e abort bug?)"; cat "$tmp/t17.out"; exit 1; }
    echo "  ✅ T17: bump probe gh-failure → graceful exit 3 (no set -e abort)"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T18: bump corrupt remote marketplace.json → exit 1 with diagnostic ---
# Remote JSON not a plugins[] array → must report corrupt (exit 1), not silently
# degrade to "not registered" (exit 3) nor leak jq's exit 5. Mirrors register's guard.
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    echo "tkxlab-ai/marketplace" > .gitx/marketplace-target
    install_mock_gh
    payload=$(printf '%s' '{"garbage":true}' | base64)
    MOCK_GH_API_RESPONSE="$payload" bash "$GMK" bump --version v1.3.0 >"$tmp/t18.out" 2>&1; rc=$?
    [ "$rc" = 1 ] || { echo "  ❌ T18: expected exit 1 on corrupt remote, got $rc"; cat "$tmp/t18.out"; exit 1; }
    grep -qi 'corrupt' "$tmp/t18.out" || { echo "  ❌ T18: missing corrupt diagnostic"; cat "$tmp/t18.out"; exit 1; }
    echo "  ✅ T18: bump corrupt remote JSON → exit 1 with diagnostic"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo "SUMMARY: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
