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
  # h: url must be https://github.com/OWNER/REPO.git, no '..'; legacy github form is
  # no longer a valid central entry (register converts it before validating).
  for u in "http://github.com/o/r.git" "https://gitlab.com/o/r.git" "https://github.com/o/../r.git" \
           "https://github.com/o/r" "https://github.com/o/r.git/x" "https://github.com/o/r..git" "" \
           "https://github.com/o/r.git"$'\n'"https://evil.example/x" "https://github.com/o/r.git"$'\t' \
           "https://github.com/o/r.git"$'\r' $'\n'"https://github.com/o/r.git"; do
      e=$(jq -c --arg u "$u" '.source = {source:"url", url:$u}' <<<"$good")
      if validate_entry "$e" 2>/dev/null; then echo "  ❌ T6: accepted bad url '$u'"; exit 1; fi
  done
  e=$(jq -c '.source = {source:"github", repo:"tkxlab-ai/demo-skill-new"}' <<<"$good")
  if validate_entry "$e" 2>/dev/null; then echo "  ❌ T6: accepted legacy github source"; exit 1; fi
  echo "  ✅ T6: validate_entry accept/reject contract (url source only)"
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
    payload=$(jq -nc --arg n "$entry_name" '{plugins:[{name:$n,version:"1.2.0",source:{source:"url",url:"https://github.com/tkxlab-ai/demo-skill-one.git"}}]}' | base64)
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
    payload=$(jq -nc --arg n "$entry_name" '{plugins:[{name:$n,version:"1.2.0",source:{source:"github",repo:"tkxlab-ai/demo-skill-one"}}]}' | base64)
    MOCK_GH_API_RESPONSE="$payload" bash "$GMK" bump --version v1.3.0 --dry-run >"$tmp/t10.out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T10: rc=$rc"; cat "$tmp/t10.out"; exit 1; }
    grep -q 'Intended.*1.3.0' "$tmp/t10.out" || { echo "  ❌ T10: missing intended diff"; cat "$tmp/t10.out"; exit 1; }
    grep -q 'https://github.com/tkxlab-ai/demo-skill-one.git' "$tmp/t10.out" || { echo "  ❌ T10: missing url migration in intent"; cat "$tmp/t10.out"; exit 1; }
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
  "name": "tkxlab",
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
    grep -q '"source":[[:space:]]*"url"' "$tmp/t16.out" \
        || { echo "  ❌ T16: transformed entry missing url source type"; cat "$tmp/t16.out"; exit 1; }
    grep -q '"url":[[:space:]]*"https://github.com/tkxlab-ai/demo-self-ref.git"' "$tmp/t16.out" \
        || { echo "  ❌ T16: transformed entry missing inferred url"; cat "$tmp/t16.out"; exit 1; }
    if grep -q '"github"' "$tmp/t16.out"; then echo "  ❌ T16: github source type leaked"; cat "$tmp/t16.out"; exit 1; fi
    echo "  ✅ T16: register --dry-run transforms source:'./' → url form (a)"
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

# ---- Task 5: url source / legacy migration / resumable bump ----------------
# A local bare repo stands in for the central marketplace. git's insteadOf
# rewrites the https clone URL onto it and GIT_ALLOW_PROTOCOL=file makes any
# un-rewritten URL fail instead of reaching GitHub. The gh mock reads/merges
# against the same bare repo, so a re-run sees exactly what the previous run left.
LEGACY_SRC='{"source":"github","repo":"tkxlab-ai/GitX"}'
URL_SRC='{"source":"url","url":"https://github.com/tkxlab-ai/GitX.git"}'
CANON_URL='https://github.com/tkxlab-ai/GitX.git'

install_bare_gh() {
    gh() {
        local b="" a
        printf '%s\n' "$*" >> "$MOCK_STATE/calls.log"
        for a in "$@"; do
            [ "$b" = "--head" ] && { b="$a"; break; }
            [ "$a" = "--head" ] && b="--head"
        done
        case "$1 ${2:-}" in
            "auth status") return 0 ;;
            "api "*)
                command git --git-dir="$MOCK_BARE" show main:.claude-plugin/marketplace.json | base64
                return 0 ;;
            "pr list")
                # Our PR (head SHA read live from the bare repo) + any planted
                # foreign PRs from extra-prs.json with the same head name.
                local own="[]" oid
                [ ! -f "$MOCK_STATE/fail-list" ] || return 1
                if [ -f "$MOCK_STATE/pr-$b" ]; then
                    oid=$(command git --git-dir="$MOCK_BARE" rev-parse "refs/heads/$b" 2>/dev/null || echo gone)
                    own=$(jq -nc --argjson n "$(cat "$MOCK_STATE/pr-$b")" --arg o "$oid" \
                        '[{number:$n, headRefOid:$o, isCrossRepository:false, headRepositoryOwner:{login:"tkxlab-ai"}, baseRefName:"main"}]')
                fi
                jq -c --argjson own "$own" --arg b "$b" '$own + [.[] | select(.headRefName == $b) | del(.headRefName)]' \
                    "$MOCK_STATE/extra-prs.json"
                return 0 ;;
            "pr create")
                if [ -f "$MOCK_STATE/fail-create" ]; then rm -f "$MOCK_STATE/fail-create"; return 1; fi
                command git --git-dir="$MOCK_BARE" show-ref -q --verify "refs/heads/$b" || return 1
                echo 7 > "$MOCK_STATE/pr-$b"; return 0 ;;
            "pr merge")
                # Merge by PR number, only when pinned to the branch's current head.
                local n="$3" m="" f
                for a in "$@"; do
                    [ "$m" = "-" ] && { m="$a"; break; }
                    [ "$a" = "--match-head-commit" ] && m="-"
                done
                if [ -f "$MOCK_STATE/fail-merge" ]; then rm -f "$MOCK_STATE/fail-merge"; return 1; fi
                b=""
                for f in "$MOCK_STATE"/pr-*; do
                    [ -f "$f" ] && [ "$(cat "$f")" = "$n" ] && b="${f##*/pr-}"
                done
                [ -n "$b" ] && [ -n "$m" ] && [ "$m" != "-" ] || return 1
                [ "$(command git --git-dir="$MOCK_BARE" rev-parse "refs/heads/$b")" = "$m" ] || return 1
                command git --git-dir="$MOCK_BARE" update-ref refs/heads/main "refs/heads/$b" || return 1
                command git --git-dir="$MOCK_BARE" update-ref -d "refs/heads/$b"
                rm -f "$MOCK_STATE/pr-$b"; return 0 ;;
            *) return 1 ;;
        esac
    }
    export -f gh
}

# _bump_env SOURCE_JSON CENTRAL_VERSION — sets tmp / MOCK_BARE / MOCK_STATE,
# a gitx skill project with a marker, and a central repo whose gitx entry has
# SOURCE_JSON at CENTRAL_VERSION next to an unrelated entry.
_bump_env() {
    tmp=$(_scratch_skill)
    jq '.plugins = [{name:"gitx",source:"./",version:"1.2.0",description:"d",homepage:"https://github.com/tkxlab-ai/GitX"}]' \
        "$tmp/.claude-plugin/marketplace.json" > "$tmp/m.new" && mv "$tmp/m.new" "$tmp/.claude-plugin/marketplace.json"
    echo "tkxlab-ai/marketplace" > "$tmp/.gitx/marketplace-target"
    local seed="$tmp/seed"
    command git init -q -b main "$seed"
    mkdir -p "$seed/.claude-plugin"
    jq -n --argjson s "$1" --arg v "$2" '{name:"tkxlab",owner:{name:"tkxlab"},plugins:[
        {name:"demo-skill-one",source:{source:"github",repo:"tkxlab-ai/demo-skill-one"},version:"0.2.0",description:"other"},
        {name:"gitx",source:$s,description:"d",version:$v,homepage:"https://github.com/tkxlab-ai/GitX",keywords:["release"]}]}' \
        > "$seed/.claude-plugin/marketplace.json"
    command git -C "$seed" add -A
    command git -C "$seed" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm init
    command git clone -q --bare "$seed" "$tmp/remote.git"
    MOCK_BARE="$tmp/remote.git"; MOCK_STATE="$tmp/state"; mkdir -p "$MOCK_STATE"
    echo '[]' > "$MOCK_STATE/extra-prs.json"
    export MOCK_BARE MOCK_STATE GIT_ALLOW_PROTOCOL=file GIT_CONFIG_COUNT=2 \
        GIT_CONFIG_KEY_0="url.file://$MOCK_BARE.insteadOf" GIT_CONFIG_VALUE_0="https://github.com/tkxlab-ai/marketplace" \
        GIT_CONFIG_KEY_1=commit.gpgsign GIT_CONFIG_VALUE_1=false
    install_bare_gh
}
_central()  { command git --git-dir="$MOCK_BARE" show main:.claude-plugin/marketplace.json; }
_refs()     { command git --git-dir="$MOCK_BARE" for-each-ref --format='%(refname) %(objectname)'; }
# _expect_main VERSION — central main == seed with gitx at VERSION + canonical url, rest untouched
_expect_main() {
    local want got
    want=$(command git --git-dir="$MOCK_BARE" show "$(command git --git-dir="$MOCK_BARE" rev-list --max-parents=0 main):.claude-plugin/marketplace.json" \
        | jq -S -c --arg v "$1" --arg u "$CANON_URL" '.plugins[1].version = $v | .plugins[1].source = {source:"url", url:$u}')
    got=$(_central | jq -S -c .)
    [ "$want" = "$got" ] || { echo "    want: $want"; echo "    got:  $got"; return 1; }
}

# --- T19 (a'): register converts an explicit legacy github source → url ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    jq '.plugins[0].source = {source:"github", repo:"tkxlab-ai/demo-skill-one"}' .claude-plugin/marketplace.json > m.new && mv m.new .claude-plugin/marketplace.json
    install_mock_gh
    MOCK_GH_API_RC=1 bash "$GMK" register --repo tkxlab-ai/marketplace --dry-run >"$tmp/out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T19: rc=$rc"; cat "$tmp/out"; exit 1; }
    grep -q '"url":[[:space:]]*"https://github.com/tkxlab-ai/demo-skill-one.git"' "$tmp/out" \
        || { echo "  ❌ T19: legacy github source not converted to url"; cat "$tmp/out"; exit 1; }
    echo "  ✅ T19: register converts legacy github source → url"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T20 (b): version differs + legacy github entry → migrate + bump, rest untouched ---
(
    set -e; _bump_env "$LEGACY_SRC" 1.2.0; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    bash "$GMK" bump --version v1.3.0 >"$tmp/out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T20: rc=$rc"; cat "$tmp/out"; exit 1; }
    _expect_main 1.3.0 || { echo "  ❌ T20: central main not as expected"; exit 1; }
    grep -qx "pr merge 7 --squash --delete-branch --match-head-commit $(command git --git-dir="$MOCK_BARE" rev-parse main)" "$MOCK_STATE/calls.log" \
        || { echo "  ❌ T20: merge not by PR number pinned to the pushed SHA"; cat "$MOCK_STATE/calls.log"; exit 1; }
    [ "$(_refs | wc -l | tr -d ' ')" = 1 ] || { echo "  ❌ T20: leftover branch"; _refs; exit 1; }
    echo "  ✅ T20: bump migrates github → url and bumps version, other fields untouched"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T21 (c): version equal + legacy github entry → still migrates (not a no-op) ---
(
    set -e; _bump_env "$LEGACY_SRC" 1.2.0; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    bash "$GMK" bump --version v1.2.0 >"$tmp/out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T21: rc=$rc"; cat "$tmp/out"; exit 1; }
    if grep -qi 'no-op' "$tmp/out"; then echo "  ❌ T21: treated as no-op"; cat "$tmp/out"; exit 1; fi
    _expect_main 1.2.0 || { echo "  ❌ T21: central not migrated"; exit 1; }
    echo "  ✅ T21: equal version + legacy source → migrated, not no-op"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T22 (d): version equal + already url → no-op, nothing pushed, no PR calls ---
(
    set -e; _bump_env "$URL_SRC" 1.2.0; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    before=$(_refs)
    bash "$GMK" bump --version v1.2.0 >"$tmp/out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T22: rc=$rc"; cat "$tmp/out"; exit 1; }
    grep -qi 'no-op' "$tmp/out" || { echo "  ❌ T22: no-op msg missing"; cat "$tmp/out"; exit 1; }
    [ "$before" = "$(_refs)" ] || { echo "  ❌ T22: remote refs changed"; exit 1; }
    if grep -q '^pr ' "$MOCK_STATE/calls.log"; then echo "  ❌ T22: PR calls made"; exit 1; fi
    echo "  ✅ T22: equal version + url source → no-op, no push"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T23 (e): branch pushed, PR create fails → re-run creates PR and merges ---
(
    set -e; _bump_env "$LEGACY_SRC" 1.2.0; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    touch "$MOCK_STATE/fail-create"
    bash "$GMK" bump --version v1.3.0 >"$tmp/out1" 2>&1; rc=$?
    [ "$rc" != 0 ] || { echo "  ❌ T23: first run should fail"; exit 1; }
    command git --git-dir="$MOCK_BARE" show-ref -q --verify refs/heads/bump-gitx-v1.3.0 \
        || { echo "  ❌ T23: branch not left behind by first run"; cat "$tmp/out1"; exit 1; }
    : > "$MOCK_STATE/calls.log"
    bash "$GMK" bump --version v1.3.0 >"$tmp/out2" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T23: resume rc=$rc"; cat "$tmp/out2"; exit 1; }
    grep -q '^pr create' "$MOCK_STATE/calls.log" || { echo "  ❌ T23: resume did not create PR"; exit 1; }
    _expect_main 1.3.0 || { echo "  ❌ T23: central not updated after resume"; exit 1; }
    echo "  ✅ T23: PR-create failure → re-run reuses branch, creates PR, merges"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T24 (f): PR open, merge fails → re-run only merges ---
(
    set -e; _bump_env "$LEGACY_SRC" 1.2.0; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    touch "$MOCK_STATE/fail-merge"
    bash "$GMK" bump --version v1.3.0 >"$tmp/out1" 2>&1; rc=$?
    [ "$rc" != 0 ] || { echo "  ❌ T24: first run should fail"; exit 1; }
    [ -f "$MOCK_STATE/pr-bump-gitx-v1.3.0" ] || { echo "  ❌ T24: PR not left open"; cat "$tmp/out1"; exit 1; }
    : > "$MOCK_STATE/calls.log"
    bash "$GMK" bump --version v1.3.0 >"$tmp/out2" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T24: resume rc=$rc"; cat "$tmp/out2"; exit 1; }
    if grep -q '^pr create' "$MOCK_STATE/calls.log"; then echo "  ❌ T24: resume re-created PR"; exit 1; fi
    grep -q '^pr merge' "$MOCK_STATE/calls.log" || { echo "  ❌ T24: resume did not merge"; exit 1; }
    _expect_main 1.3.0 || { echo "  ❌ T24: central not updated after resume"; exit 1; }
    echo "  ✅ T24: merge failure → re-run merges the open PR only"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# _plant_branch JQ_FILTER [EXTRA_FILE] — push bump-gitx-v1.3.0 off main with a
# hand-made change, as a stale or foreign run would have left it.
_plant_branch() {
    local w="$tmp/plant"
    command git clone -q "$MOCK_BARE" "$w"
    jq "$1" "$w/.claude-plugin/marketplace.json" > "$w/m.new" && mv "$w/m.new" "$w/.claude-plugin/marketplace.json"
    [ -z "${2:-}" ] || echo x > "$w/$2"
    command git -C "$w" add -A
    command git -C "$w" -c user.name=t -c user.email=t@t commit -qm planted
    command git -C "$w" push -q origin HEAD:refs/heads/bump-gitx-v1.3.0
}

# --- T25 (g): remote branch content differs from intended → refuse, keep branch ---
(
    set -e; _bump_env "$LEGACY_SRC" 1.2.0; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    _plant_branch '.plugins[1].version = "9.9.9"'
    before=$(_refs)
    bash "$GMK" bump --version v1.3.0 >"$tmp/out" 2>"$tmp/err"; rc=$?
    [ "$rc" != 0 ] || { echo "  ❌ T25: expected non-zero"; exit 1; }
    grep -qi 'recover' "$tmp/err" || { echo "  ❌ T25: no recovery steps"; cat "$tmp/err"; exit 1; }
    [ "$before" = "$(_refs)" ] || { echo "  ❌ T25: remote refs changed (branch deleted/overwritten?)"; exit 1; }
    if grep -qE '^pr (create|merge)' "$MOCK_STATE/calls.log"; then echo "  ❌ T25: PR create/merge attempted"; exit 1; fi
    echo "  ✅ T25: mismatched leftover branch → refuse with recovery steps, branch kept"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T25b (g): right JSON but an extra file on the branch → still refused ---
(
    set -e; _bump_env "$LEGACY_SRC" 1.2.0; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    _plant_branch '.plugins[1].version = "1.3.0" | .plugins[1].source = {source:"url", url:"https://github.com/tkxlab-ai/GitX.git"}' EXTRA.txt
    before=$(_refs)
    bash "$GMK" bump --version v1.3.0 >"$tmp/out" 2>"$tmp/err"; rc=$?
    [ "$rc" != 0 ] || { echo "  ❌ T25b: expected non-zero"; exit 1; }
    [ "$before" = "$(_refs)" ] || { echo "  ❌ T25b: remote refs changed"; exit 1; }
    echo "  ✅ T25b: leftover branch touching other files → refused"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T26: PR listing unavailable → fail closed before any push ---
(
    set -e; _bump_env "$LEGACY_SRC" 1.2.0; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    touch "$MOCK_STATE/fail-list"
    before=$(_refs)
    bash "$GMK" bump --version v1.3.0 >"$tmp/out" 2>&1; rc=$?
    [ "$rc" != 0 ] || { echo "  ❌ T26: expected non-zero"; exit 1; }
    [ "$before" = "$(_refs)" ] || { echo "  ❌ T26: pushed despite unknown PR state"; exit 1; }
    echo "  ✅ T26: unknown PR state → fail closed, nothing pushed"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T1: register happy path — marker, url entry appended, merge pinned to pushed SHA ---
(
    set -e; _bump_env "$URL_SRC" 1.2.0; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    jq '.plugins[0].name = "newskill" | .plugins[0].homepage = "https://github.com/tkxlab-ai/newskill"' \
        .claude-plugin/marketplace.json > m.new && mv m.new .claude-plugin/marketplace.json
    rm -f .gitx/marketplace-target
    bash "$GMK" register --repo tkxlab-ai/marketplace >"$tmp/out" 2>&1; rc=$?
    [ "$rc" = 0 ] || { echo "  ❌ T1: rc=$rc"; cat "$tmp/out"; exit 1; }
    grep -q '^tkxlab-ai/marketplace$' .gitx/marketplace-target || { echo "  ❌ T1: marker not written"; exit 1; }
    src=$(_central | jq -c '.plugins[] | select(.name == "newskill") | .source')
    [ "$src" = '{"source":"url","url":"https://github.com/tkxlab-ai/newskill.git"}' ] \
        || { echo "  ❌ T1: central entry source is $src"; exit 1; }
    grep -qx "pr merge 7 --squash --delete-branch --match-head-commit $(command git --git-dir="$MOCK_BARE" rev-parse main)" "$MOCK_STATE/calls.log" \
        || { echo "  ❌ T1: merge not by PR number pinned to the pushed SHA"; cat "$MOCK_STATE/calls.log"; exit 1; }
    echo "  ✅ T1: register happy path — url entry merged by PR number, pinned to pushed SHA"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T28: register rejects a url / legacy repo carrying an embedded newline ---
(
    set -e; tmp=$(_scratch_skill); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    install_mock_gh
    for f in '.plugins[0].source = {source:"url", url:"https://github.com/o/r.git\nhttps://evil.example/x"}' \
             '.plugins[0].source = {source:"github", repo:"o/r\nevil"}'; do
        jq "$f" "$ROOT/tests/fixtures/marketplace.json" | jq '{name, owner, plugins: [.plugins[0]]}' > .claude-plugin/marketplace.json
        MOCK_GH_API_RC=1 bash "$GMK" register --repo tkxlab-ai/marketplace --dry-run >"$tmp/out" 2>&1; rc=$?
        [ "$rc" = 1 ] || { echo "  ❌ T28: accepted ($f) rc=$rc"; cat "$tmp/out"; exit 1; }
    done
    echo "  ✅ T28: register rejects multi-line url / legacy repo"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T29: bump refuses a central url with an embedded newline (no push, no PR) ---
(
    set -e; _bump_env '{"source":"url","url":"https://github.com/tkxlab-ai/GitX.git\nhttps://evil.example/x"}' 1.2.0
    trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    before=$(_refs)
    bash "$GMK" bump --version v1.3.0 >"$tmp/out" 2>&1; rc=$?
    [ "$rc" != 0 ] || { echo "  ❌ T29: accepted multi-line central url"; exit 1; }
    [ "$before" = "$(_refs)" ] || { echo "  ❌ T29: remote refs changed"; exit 1; }
    if grep -q '^pr ' "$MOCK_STATE/calls.log" 2>/dev/null; then echo "  ❌ T29: PR calls made"; exit 1; fi
    echo "  ✅ T29: bump refuses multi-line central url"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# _foreign_pr CROSS HEAD_OID — plant an open PR with head name bump-gitx-v1.3.0
_foreign_pr() {
    jq -nc --argjson x "$1" --arg o "$2" '[{number:99, headRefName:"bump-gitx-v1.3.0", headRefOid:$o,
        isCrossRepository:$x, headRepositoryOwner:{login:"someone"}, baseRefName:"main"}]' > "$MOCK_STATE/extra-prs.json"
}

# --- T30: fork (cross-repository) PR with the same head name → refuse, never merge ---
(
    set -e; _bump_env "$LEGACY_SRC" 1.2.0; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    _foreign_pr true 1111111111111111111111111111111111111111
    before=$(_refs)
    bash "$GMK" bump --version v1.3.0 >"$tmp/out" 2>"$tmp/err"; rc=$?
    [ "$rc" != 0 ] || { echo "  ❌ T30: expected non-zero"; exit 1; }
    if grep -q '^pr merge' "$MOCK_STATE/calls.log"; then echo "  ❌ T30: merge attempted"; exit 1; fi
    [ "$before" = "$(_refs)" ] || { echo "  ❌ T30: remote refs changed"; exit 1; }
    echo "  ✅ T30: cross-repository PR with same head name → refused, no merge"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T31: verified leftover branch, but the open same-repo PR sits at another SHA → refuse ---
(
    set -e; _bump_env "$LEGACY_SRC" 1.2.0; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    _plant_branch '.plugins[1].version = "1.3.0" | .plugins[1].source = {source:"url", url:"https://github.com/tkxlab-ai/GitX.git"}'
    _foreign_pr false 2222222222222222222222222222222222222222
    before=$(_refs)
    bash "$GMK" bump --version v1.3.0 >"$tmp/out" 2>"$tmp/err"; rc=$?
    [ "$rc" != 0 ] || { echo "  ❌ T31: expected non-zero"; exit 1; }
    grep -q 'resuming' "$tmp/err" || { echo "  ❌ T31: did not reach the verified-branch path"; cat "$tmp/err"; exit 1; }
    if grep -qE '^pr (create|merge)' "$MOCK_STATE/calls.log"; then echo "  ❌ T31: PR create/merge attempted"; exit 1; fi
    [ "$before" = "$(_refs)" ] || { echo "  ❌ T31: remote refs changed"; exit 1; }
    echo "  ✅ T31: same-repo PR at an unverified head SHA → refused, no merge"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T32: verified leftover branch + fork PR at that very SHA → still refused ---
(
    set -e; _bump_env "$LEGACY_SRC" 1.2.0; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
    _plant_branch '.plugins[1].version = "1.3.0" | .plugins[1].source = {source:"url", url:"https://github.com/tkxlab-ai/GitX.git"}'
    _foreign_pr true "$(command git --git-dir="$MOCK_BARE" rev-parse refs/heads/bump-gitx-v1.3.0)"
    bash "$GMK" bump --version v1.3.0 >"$tmp/out" 2>"$tmp/err"; rc=$?
    [ "$rc" != 0 ] || { echo "  ❌ T32: expected non-zero"; exit 1; }
    if grep -qE '^pr (create|merge)' "$MOCK_STATE/calls.log"; then echo "  ❌ T32: PR create/merge attempted"; exit 1; fi
    echo "  ✅ T32: cross-repository PR at the verified SHA → refused"
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# --- T27 (i): fixture gitx entry is the url form ---
src=$(jq -c '.plugins[] | select(.name == "gitx") | .source' "$ROOT/tests/fixtures/marketplace.json")
if [ "$src" = "$URL_SRC" ]; then
    ok "T27: fixture gitx entry uses url source"
else
    fail "T27: fixture gitx source is $src"
fi

echo "SUMMARY: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
