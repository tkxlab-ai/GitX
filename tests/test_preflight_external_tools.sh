#!/bin/bash
# test_preflight_external_tools.sh — v1.0.8 hardening (Arch #3).
# README claims "pure Bash, no external deps" but the pipeline actually
# requires `tar`, `gzip`, `unzip`, `rsync`, `awk`, `sed`, `grep`, `find`,
# `diff`, and `shasum`/`sha256sum`. Only the SHA tools were gated. A missing
# rsync/unzip aborts mid-flight with a cryptic error. This test asserts
# release.sh probes each hard-prereq up front and prints a clear message.
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE="$ROOT/scripts/release.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_preflight_external_tools.sh ══"

# Static: function exists and probes the expected tools
if grep -qE 'preflight_external_tools|preflight_externals' "$RELEASE"; then
    ok "release.sh defines preflight_external_tools()"
else
    fail "release.sh missing preflight_external_tools()"
fi

block=$(awk '/^preflight_external_tools\(\)|^preflight_externals\(\)/,/^\}/' "$RELEASE")
required_tools=(rsync tar gzip unzip awk sed grep find diff)
for t in "${required_tools[@]}"; do
    # Match either explicit `command -v <tool>` or the tool listed in a
    # for-loop array of tool names that's then iterated through `command -v`.
    if echo "$block" | grep -qE "command -v ($t|\"\$[a-zA-Z_]+\")|for [a-zA-Z_]+ in[^;]*\b$t\b" ; then
        ok "preflight probes for '$t'"
    else
        fail "preflight does not probe for '$t'"
    fi
done

# Sha probe: at least one of shasum/sha256sum
if echo "$block" | grep -qE 'shasum|sha256sum'; then
    ok "preflight probes for shasum/sha256sum (any one)"
else
    fail "preflight does not probe for SHA tool"
fi

# Static: function emits a labelled "Missing required external tools" message
# (verifies the user-facing error contract — exact wording matters for
# operator triage and downstream documentation).
if echo "$block" | grep -qE 'Missing required external tools'; then
    ok "preflight prints labelled 'Missing required external tools' message"
else
    fail "preflight does not print the labelled missing-deps message"
fi

# Static: preflight is invoked from main flow before destructive ops
main_flow=$(awk '/^# ============================================================$/,0' "$RELEASE")
if echo "$main_flow" | grep -qE '^preflight_external_tools$|^preflight_external_tools '; then
    ok "preflight_external_tools called from main flow"
else
    fail "preflight_external_tools defined but never called"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
