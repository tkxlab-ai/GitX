#!/bin/bash
# test_gitx_sop.sh — v1.7.0 gitx-sop subcommand BDD coverage.
#
# Tests grow one assertion per superpowers TDD cycle (red→green→refactor).
# Iron law: every new behavior gets a failing test FIRST, then minimal code.
#
# gitx-sop renders a parameterized GitHub-publish SOP template into the
# target project's .gitx/GITHUB_RELEASE_SOP.md. It is generate-only and
# NEVER executes git/gh — same model as gitx-init (SKILL.md constraint #1:
# git tag / git push / gh release stay manual, TKX policy §10.10).
#
# exit: 0=all pass, 1=any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$ROOT/scripts/gitx-sop.sh"
PASS=0; FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_gitx_sop.sh ══"

# === STATIC 1: wrapper exists at scripts/gitx-sop.sh + executable + shebang ===
if [ ! -f "$WRAPPER" ]; then
    fail "wrapper missing at $WRAPPER (cycle 1 RED expected here)"
elif [ ! -x "$WRAPPER" ]; then
    fail "wrapper present but not executable: $WRAPPER"
elif ! head -1 "$WRAPPER" | grep -qE '^#!.*/(bash|sh)$'; then
    fail "wrapper missing shebang line"
else
    ok "wrapper exists, executable, has shebang"
fi

# === STATIC 2: --help exits 0, output mentions flags + exit codes ===
if [ -x "$WRAPPER" ]; then
    help_out="$("$WRAPPER" --help 2>&1)"
    help_status=$?
    if [ "$help_status" -ne 0 ]; then
        fail "--help exited $help_status, expected 0"
    else
        missing=""
        for flag in --repo --project --force --dry-run --help; do
            grep -qF -- "$flag" <<<"$help_out" || missing="$missing $flag"
        done
        for c in 0 2 4; do
            grep -qE "^[[:space:]]*$c[[:space:]]" <<<"$help_out" || missing="$missing exit=$c"
        done
        if [ -z "$missing" ]; then
            ok "--help lists flags + exit codes"
        else
            fail "--help missing:$missing"
        fi
    fi
else
    fail "wrapper not executable; cannot test --help"
fi

# === STATIC 3: unknown flag exits 2 ===
if [ -x "$WRAPPER" ]; then
    "$WRAPPER" --not-a-real-flag >/dev/null 2>&1
    unk_status=$?
    if [ "$unk_status" -eq 2 ]; then
        ok "unknown flag exits 2"
    else
        fail "unknown flag exited $unk_status, expected 2"
    fi
fi

# === BEHAVIOR 1: --dry-run previews target + writes nothing ===
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"
    out="$( cd "$fx" && "$WRAPPER" --repo=acme/Foo --dry-run </dev/null 2>&1 )"
    dr_status=$?
    if [ "$dr_status" -ne 0 ]; then
        fail "--dry-run exited $dr_status, expected 0"
    elif [ -e "$fx/.gitx" ]; then
        fail "--dry-run wrote .gitx/ (should be no-op)"
    elif ! grep -qE '(would|preview|dry-run).*GITHUB_RELEASE_SOP\.md' <<<"$out"; then
        fail "--dry-run did not preview GITHUB_RELEASE_SOP.md (got: $(echo "$out" | head -1))"
    else
        ok "--dry-run previews target + writes nothing"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 2: non-dry-run writes .gitx/GITHUB_RELEASE_SOP.md non-empty ===
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"
    ( cd "$fx" && "$WRAPPER" --repo=acme/Foo --project=foo </dev/null >/dev/null 2>&1 )
    w_status=$?
    if [ "$w_status" -ne 0 ]; then
        fail "non-dry-run exited $w_status, expected 0"
    elif [ ! -s "$fx/.gitx/GITHUB_RELEASE_SOP.md" ]; then
        fail ".gitx/GITHUB_RELEASE_SOP.md missing or empty"
    else
        ok "non-dry-run writes non-empty .gitx/GITHUB_RELEASE_SOP.md"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 3: all {{...}} placeholders substituted ===
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"
    ( cd "$fx" && "$WRAPPER" --repo=acme/Foo --project=foo \
        --private-host=git.example.internal </dev/null >/dev/null 2>&1 )
    sop="$fx/.gitx/GITHUB_RELEASE_SOP.md"
    if grep -qE '\{\{[A-Z_]+\}\}' "$sop" 2>/dev/null; then
        leaked="$(grep -oE '\{\{[A-Z_]+\}\}' "$sop" | sort -u | tr '\n' ' ')"
        fail "unsubstituted placeholders in SOP: $leaked"
    elif ! grep -qF 'acme/Foo' "$sop"; then
        fail "rendered SOP does not contain repo slug acme/Foo"
    else
        ok "all {{...}} placeholders substituted"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 4: second run without --force exits 4 (idempotent guard) ===
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"
    ( cd "$fx" && "$WRAPPER" --repo=acme/Foo </dev/null >/dev/null 2>&1 )
    ( cd "$fx" && "$WRAPPER" --repo=acme/Foo </dev/null >/dev/null 2>&1 )
    second_status=$?
    if [ "$second_status" -eq 4 ]; then
        ok "second run without --force exits 4"
    else
        fail "second run exited $second_status, expected 4"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 5: --force overrides the idempotent guard ===
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"
    ( cd "$fx" && "$WRAPPER" --repo=acme/Foo </dev/null >/dev/null 2>&1 )
    ( cd "$fx" && "$WRAPPER" --repo=acme/Foo --force </dev/null >/dev/null 2>&1 )
    force_status=$?
    if [ "$force_status" -eq 0 ]; then
        ok "--force overrides idempotent guard"
    else
        fail "--force on second run exited $force_status, expected 0"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 6: rendered SOP carries the #1-#8 upgrade fixes ===
# Each fix is a content sentinel; this guards the iteration upgrade from
# silently regressing if the template is edited later.
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"
    ( cd "$fx" && "$WRAPPER" --repo=acme/Foo --project=foo </dev/null >/dev/null 2>&1 )
    sop="$fx/.gitx/GITHUB_RELEASE_SOP.md"
    miss=""
    grep -qE 'FIX #1.*GATE'                         "$sop" || miss="$miss#1"
    grep -qF 'runner exited non-zero) — aborting'    "$sop" || miss="$miss#1gate"
    grep -qF 'FIX #2'                                "$sop" || miss="$miss#2"
    grep -qF 'token still in remote URL'             "$sop" || miss="$miss#2scrub"
    grep -qE 'FIX #3.*ABORT'                         "$sop" || miss="$miss#3"
    grep -qF 'FIX #4'                                "$sop" || miss="$miss#4"
    grep -qF 'shasum -a 256 -c checksums.txt'        "$sop" || miss="$miss#4sha"
    grep -qF 'FIX #5'                                "$sop" || miss="$miss#5"
    grep -qF 'FIX #6'                                "$sop" || miss="$miss#6"
    grep -qF 'VER_BARE of v2.2.1 is 2.2.1'           "$sop" || miss="$miss#7"
    grep -qF 'FIX #8'                                "$sop" || miss="$miss#8"
    grep -qF 'does NOT auto-run'                     "$sop" || miss="$miss#noauto"
    if [ -z "$miss" ]; then
        ok "rendered SOP carries all #1-#8 upgrade fixes"
    else
        fail "SOP missing fix sentinels:$miss"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 7: codex-audit hardening — fixes are CORRECT not just present ===
# Guards the 4 defects codex review found (2025-05-15): #1 fragile log-grep
# gate, #2 push exit-code masked by | tail, #5 leak regex matching its own
# redaction placeholders, #4 GH_TOKEN used without being derived.
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"
    ( cd "$fx" && "$WRAPPER" --repo=acme/Foo --project=foo \
        --private-host=git.example.internal </dev/null >/dev/null 2>&1 )
    sop="$fx/.gitx/GITHUB_RELEASE_SOP.md"
    h=""
    # #1: gate on runner exit status, not a log fragment
    grep -qE '(if bash tests/run_all\.sh|! bash tests/run_all\.sh)' "$sop" || h="$h#1-exitgate"
    grep -qE "grep -qE '0 \(failures" "$sop" && h="$h#1-fragile-still-present"
    # #2: main push must not mask exit code via | tail; must abort before tag
    grep -qF 'git push origin main --force 2>&1 | tail' "$sop" && h="$h#2-pipe-mask"
    grep -qF 'main push failed' "$sop" || h="$h#2-no-abort"
    # #5: leak regex must not scan its own redaction placeholder names
    grep -qE 'private-port\|private-org' "$sop" && h="$h#5-placeholder-scan"
    # #4: GH_TOKEN must be derived (gh auth token) not assumed exported
    grep -qF 'gh auth token' "$sop" || h="$h#4-no-token-derive"
    if [ -z "$h" ]; then
        ok "codex-audit fixes are correct (#1 #2 #4 #5)"
    else
        fail "codex-audit regressions:$h"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 9: v1.7.4 "ready for other skills" hardening sentinels ===
# The 4 gaps the GitX self-publish session exposed, now in the template.
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"
    ( cd "$fx" && "$WRAPPER" --repo=acme/Foo --project=foo \
        --private-host=git.example.internal </dev/null >/dev/null 2>&1 )
    sop="$fx/.gitx/GITHUB_RELEASE_SOP.md"
    m=""
    # H1: Phase 4.5 portable — detect public-sanitize script, else generic
    #     fallback, and a MANDATORY post-redaction verification grep.
    grep -qF 'release-sanitize-public.sh' "$sop"        || m="$m H1-detect"
    grep -qF 'generic redaction fallback' "$sop"        || m="$m H1-fallback"
    grep -qF 'residual private marker'    "$sop"        || m="$m H1-verify"
    # H2: Rollback D deletes the leaked-snapshot tag, not just main.
    grep -qF 'tag built from the leaked snapshot' "$sop" || m="$m H2-tag"
    # H3: Phase 7 multi-release Latest re-assertion on backfill.
    grep -qF 'backfilling older releases' "$sop"        || m="$m H3-latest"
    # H4: Phase 8 completeness gate — every tag must have a Release.
    grep -qF 'has no GitHub Release'      "$sop"        || m="$m H4-gate"
    if [ -z "$m" ]; then
        ok "SOP carries all 4 v1.7.4 'ready-for-other-skills' fixes"
    else
        fail "SOP missing v1.7.4 hardening:$m"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 8: install.sh actually propagates commands/gitx-sop.md ===
# Functional (not grep): v1.7.1 — install.sh line 249 guarded on
# $SELF_DIR/commands but commands/ was bundle-only (no root commands/),
# so /gitx-sop + /gitx-init never reached an install. Install into a
# throwaway HOME and assert the slash shims land in the canonical.
if [ -x "$WRAPPER" ] && [ -f "$ROOT/install.sh" ]; then
    tmphome="$(mktemp -d)"
    ( cd "$ROOT" && HOME="$tmphome" bash install.sh --force >/dev/null 2>&1 )
    canon="$tmphome/.agents/skills/gitx-release/commands"
    if [ -f "$canon/gitx-sop.md" ] && [ -f "$canon/gitx-init.md" ]; then
        ok "install.sh propagates commands/{gitx-sop,gitx-init}.md to canonical"
    else
        fail "install.sh did NOT install commands/ shims (got: $(ls "$canon" 2>/dev/null | tr '\n' ' ')<-)"
    fi
    rm -rf "$tmphome"
fi

# === STATIC 4: SKILL.md "工作模式" table lists gitx-sop ===
SKILL_MD="$ROOT/skills/gitx-release/SKILL.md"
if [ -f "$SKILL_MD" ]; then
    if grep -qE 'gitx-sop.*scripts/gitx-sop\.sh|/gitx-sop' "$SKILL_MD"; then
        ok "SKILL.md table lists gitx-sop"
    else
        fail "SKILL.md missing gitx-sop row in 工作模式 table"
    fi
fi

# === STATIC 5: commands/gitx-sop.md slash shim exists with frontmatter ===
CMD_SHIM="$ROOT/skills/gitx-release/commands/gitx-sop.md"
if [ ! -f "$CMD_SHIM" ]; then
    fail "commands/gitx-sop.md slash shim missing"
elif ! head -3 "$CMD_SHIM" | grep -qE '^---[[:space:]]*$'; then
    fail "commands/gitx-sop.md missing YAML frontmatter delimiter"
elif ! grep -qE '^description:' "$CMD_SHIM"; then
    fail "commands/gitx-sop.md frontmatter missing description:"
elif ! grep -q 'gitx-sop.sh' "$CMD_SHIM"; then
    fail "commands/gitx-sop.md does not reference scripts/gitx-sop.sh"
else
    ok "commands/gitx-sop.md slash shim valid"
fi

# === STATIC 6: agents/codex-commands.txt declares \$gitx-sop (root + bundle) ===
for cct in "$ROOT/agents/codex-commands.txt" "$ROOT/skills/gitx-release/agents/codex-commands.txt"; do
    if [ -f "$cct" ]; then
        if grep -qE '^\$gitx-sop$' "$cct"; then
            ok "codex-commands.txt declares \$gitx-sop ($(basename "$(dirname "$(dirname "$cct")")"))"
        else
            fail "$cct missing \$gitx-sop"
        fi
    fi
done

# === STATIC 7: release-audit.sh has §0d gitx-sop gate (root + bundle) ===
for audit_sh in "$ROOT/scripts/release-audit.sh" "$ROOT/skills/gitx-release/scripts/release-audit.sh"; do
    if [ -f "$audit_sh" ]; then
        label="$(basename "$(dirname "$(dirname "$audit_sh")")")"
        if grep -qE '^audit_section_0_gitx_sop\(\)' "$audit_sh" \
           && grep -q '§0d' "$audit_sh" \
           && grep -q 'references/gitx-sop/' "$audit_sh"; then
            ok "release-audit.sh has §0d gitx-sop gate ($label)"
        else
            fail "$audit_sh missing §0d gitx-sop audit gate"
        fi
    fi
done

# === STATIC 8: gitx-sop.sh dual-source byte-identical (root vs bundle) ===
BUNDLE_WRAPPER="$ROOT/skills/gitx-release/scripts/gitx-sop.sh"
if [ -f "$BUNDLE_WRAPPER" ] && cmp -s "$WRAPPER" "$BUNDLE_WRAPPER"; then
    ok "gitx-sop.sh root vs bundle byte-identical"
else
    fail "gitx-sop.sh dual-source drift (root vs skills/gitx-release/scripts/)"
fi

# === summary ===
echo "Results: ✅$PASS passed / ❌$FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "FAIL"; exit 1
else
    echo "PASS"; exit 0
fi
