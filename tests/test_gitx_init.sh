#!/bin/bash
# test_gitx_init.sh — v1.6.0 gitx-init subcommand BDD coverage.
#
# Tests grow one assertion per superpowers TDD cycle (red→green→refactor).
# Iron law: every new behavior gets a failing test FIRST, then minimal code.
#
# Cycles will eventually cover (per references/gitx-init-design.md §7):
#   STATIC  — wrapper exists, --help, references master, SKILL.md table,
#             commands/ shim
#   BEHAVIOR — type=skill / mac / both / empty detection, --type=auto on
#             empty + non-TTY (exit 3), idempotent re-run, --force,
#             --dry-run, byte-identical templates
#
# exit: 0=all pass, 1=any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$ROOT/scripts/gitx-init.sh"
PASS=0; FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_gitx_init.sh ══"

# === STATIC 1: wrapper exists at scripts/gitx-init.sh + executable + shebang ===
if [ ! -f "$WRAPPER" ]; then
    fail "wrapper missing at $WRAPPER (cycle 1 RED expected here)"
elif [ ! -x "$WRAPPER" ]; then
    fail "wrapper present but not executable: $WRAPPER"
elif ! head -1 "$WRAPPER" | grep -qE '^#!.*/(bash|sh)$'; then
    fail "wrapper missing shebang line"
else
    ok "wrapper exists, executable, has shebang"
fi

# === STATIC 2: --help exits 0, output mentions all 5 type values + 4 exit codes ===
if [ -x "$WRAPPER" ]; then
    help_out="$("$WRAPPER" --help 2>&1)"
    help_status=$?
    if [ "$help_status" -ne 0 ]; then
        fail "--help exited $help_status, expected 0"
    else
        missing=""
        for t in auto skill mac both empty; do
            grep -qE "\b$t\b" <<<"$help_out" || missing="$missing $t"
        done
        for c in 0 2 3 4; do
            grep -qE "^[[:space:]]*$c[[:space:]]" <<<"$help_out" || missing="$missing exit=$c"
        done
        if [ -z "$missing" ]; then
            ok "--help lists 5 type values + 4 exit codes"
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

# === STATIC 4: invalid --type value exits 2 ===
if [ -x "$WRAPPER" ]; then
    "$WRAPPER" --type=banana >/dev/null 2>&1
    bad_type_status=$?
    if [ "$bad_type_status" -eq 2 ]; then
        ok "invalid --type value exits 2"
    else
        fail "--type=banana exited $bad_type_status, expected 2"
    fi
fi

# === BEHAVIOR 1: explicit --type=<value> + --dry-run reports that type ===
# Verifies the --type flag is wired through to the dry-run output for all
# four explicit values (auto excluded — auto needs signal-detection cycles).
if [ -x "$WRAPPER" ]; then
    for t in skill mac both empty; do
        empty_dir="$(mktemp -d)"
        out="$( cd "$empty_dir" && "$WRAPPER" --type="$t" --dry-run 2>&1 )"
        if grep -qE "project type:[[:space:]]+$t\b" <<<"$out"; then
            ok "--type=$t --dry-run reports 'project type: $t'"
        else
            fail "--type=$t --dry-run did not report 'project type: $t' (got: $(echo "$out" | head -1))"
        fi
        rm -rf "$empty_dir"
    done
fi

# === BEHAVIOR 2: --type=auto detects project type from filesystem signals ===
# Per references/gitx-init-design.md §2:
#   skill signal: skills/*/SKILL.md
#   mac signal:   *.xcodeproj OR Package.swift OR src-tauri/Cargo.toml
#   both signals → "both"; only one → that one; neither + non-TTY → exit 3.
# All sub-cases run with stdin redirected from /dev/null so the wrapper sees
# a non-TTY (which is the test-environment default anyway).
if [ -x "$WRAPPER" ]; then
    # 6a: skill-only fixture
    fx="$(mktemp -d)"; mkdir -p "$fx/skills/foo"; echo "name: foo" > "$fx/skills/foo/SKILL.md"
    out="$( cd "$fx" && "$WRAPPER" --type=auto --dry-run </dev/null 2>&1 )"
    grep -qE "project type:[[:space:]]+skill\b" <<<"$out" \
        && ok "auto-detect: skills/*/SKILL.md → skill" \
        || fail "auto-detect skill failed (got: $(echo "$out" | head -1))"
    rm -rf "$fx"

    # 6b: mac-only fixture (Package.swift)
    fx="$(mktemp -d)"; touch "$fx/Package.swift"
    out="$( cd "$fx" && "$WRAPPER" --type=auto --dry-run </dev/null 2>&1 )"
    grep -qE "project type:[[:space:]]+mac\b" <<<"$out" \
        && ok "auto-detect: Package.swift → mac" \
        || fail "auto-detect mac failed (got: $(echo "$out" | head -1))"
    rm -rf "$fx"

    # 6c: both fixtures
    fx="$(mktemp -d)"; mkdir -p "$fx/skills/foo"; echo "name: foo" > "$fx/skills/foo/SKILL.md"
    touch "$fx/Package.swift"
    out="$( cd "$fx" && "$WRAPPER" --type=auto --dry-run </dev/null 2>&1 )"
    grep -qE "project type:[[:space:]]+both\b" <<<"$out" \
        && ok "auto-detect: skill + mac signals → both" \
        || fail "auto-detect both failed (got: $(echo "$out" | head -1))"
    rm -rf "$fx"

    # 6d: neither + non-TTY → exit 3
    fx="$(mktemp -d)"
    ( cd "$fx" && "$WRAPPER" --type=auto --dry-run </dev/null >/dev/null 2>&1 )
    no_signal_status=$?
    if [ "$no_signal_status" -eq 3 ]; then
        ok "auto-detect: no signals + non-TTY → exit 3"
    else
        fail "auto-detect empty + non-TTY exited $no_signal_status, expected 3"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 3: successful run writes .gitx/ directory + RELEASE_GUIDELINE.md ===
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"; mkdir -p "$fx/skills/foo"; echo "name: foo" > "$fx/skills/foo/SKILL.md"
    ( cd "$fx" && "$WRAPPER" --type=skill </dev/null >/dev/null 2>&1 )
    run_status=$?
    if [ "$run_status" -ne 0 ]; then
        fail "non-dry-run --type=skill exited $run_status, expected 0"
    elif [ ! -d "$fx/.gitx" ]; then
        fail ".gitx/ directory not created"
    elif [ ! -f "$fx/RELEASE_GUIDELINE.md" ]; then
        fail "RELEASE_GUIDELINE.md not created at project root"
    else
        ok "non-dry-run writes .gitx/ and RELEASE_GUIDELINE.md"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 4: successful run writes .gitx/policy.md with non-empty content ===
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"; mkdir -p "$fx/skills/foo"; echo "name: foo" > "$fx/skills/foo/SKILL.md"
    ( cd "$fx" && "$WRAPPER" --type=skill </dev/null >/dev/null 2>&1 )
    if [ ! -f "$fx/.gitx/policy.md" ]; then
        fail ".gitx/policy.md not created"
    elif [ ! -s "$fx/.gitx/policy.md" ]; then
        fail ".gitx/policy.md is empty"
    else
        ok ".gitx/policy.md created with non-empty content"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 5: all {{...}} placeholders substituted in generated files ===
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"; mkdir -p "$fx/skills/foo"; echo "name: foo" > "$fx/skills/foo/SKILL.md"
    ( cd "$fx" && "$WRAPPER" --type=skill </dev/null >/dev/null 2>&1 )
    if grep -q '{{' "$fx/.gitx/policy.md" 2>/dev/null; then
        leaked="$(grep -oE '\{\{[A-Z_]+\}\}' "$fx/.gitx/policy.md" | sort -u | tr '\n' ' ')"
        fail "unsubstituted placeholders in policy.md: $leaked"
    else
        ok "all {{...}} placeholders substituted in .gitx/policy.md"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 6: second run without --force exits 4 (idempotent guard) ===
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"; mkdir -p "$fx/skills/foo"; echo "name: foo" > "$fx/skills/foo/SKILL.md"
    ( cd "$fx" && "$WRAPPER" --type=skill </dev/null >/dev/null 2>&1 )
    ( cd "$fx" && "$WRAPPER" --type=skill </dev/null >/dev/null 2>&1 )
    second_status=$?
    if [ "$second_status" -eq 4 ]; then
        ok "second run without --force exits 4"
    else
        fail "second run exited $second_status, expected 4"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 7: --force bypasses the idempotent guard ===
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"; mkdir -p "$fx/skills/foo"; echo "name: foo" > "$fx/skills/foo/SKILL.md"
    ( cd "$fx" && "$WRAPPER" --type=skill </dev/null >/dev/null 2>&1 )
    ( cd "$fx" && "$WRAPPER" --type=skill --force </dev/null >/dev/null 2>&1 )
    force_status=$?
    if [ "$force_status" -eq 0 ]; then
        ok "--force overrides idempotent guard"
    else
        fail "--force on second run exited $force_status, expected 0"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 8: --dry-run writes no filesystem state + previews actions ===
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"; mkdir -p "$fx/skills/foo"; echo "name: foo" > "$fx/skills/foo/SKILL.md"
    out="$( cd "$fx" && "$WRAPPER" --type=skill --dry-run </dev/null 2>&1 )"
    if [ -e "$fx/.gitx" ] || [ -e "$fx/RELEASE_GUIDELINE.md" ]; then
        fail "--dry-run wrote files: $(ls -la "$fx" | grep -vE '^total|skills$|\\.$')"
    elif ! grep -qE '(would|preview|dry-run).*\.gitx' <<<"$out"; then
        fail "--dry-run output did not preview .gitx actions (got: $(echo "$out" | head -2 | tr '\n' '|'))"
    else
        ok "--dry-run writes nothing + previews actions"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 9: scenarios/ files are type-conditional ===
# type=skill  → only .gitx/scenarios/skill-flow.md
# type=mac    → only .gitx/scenarios/mac-flow.md
# type=both   → both files present
# type=empty  → neither file present
if [ -x "$WRAPPER" ]; then
    for t in skill mac both empty; do
        fx="$(mktemp -d)"
        ( cd "$fx" && "$WRAPPER" --type="$t" </dev/null >/dev/null 2>&1 )
        skill_exists=0; mac_exists=0
        [ -f "$fx/.gitx/scenarios/skill-flow.md" ] && skill_exists=1
        [ -f "$fx/.gitx/scenarios/mac-flow.md" ] && mac_exists=1
        case "$t" in
            skill)  want_skill=1; want_mac=0 ;;
            mac)    want_skill=0; want_mac=1 ;;
            both)   want_skill=1; want_mac=1 ;;
            empty)  want_skill=0; want_mac=0 ;;
        esac
        if [ "$skill_exists" -eq "$want_skill" ] && [ "$mac_exists" -eq "$want_mac" ]; then
            ok "scenarios for --type=$t: skill=$skill_exists mac=$mac_exists"
        else
            fail "scenarios for --type=$t: want skill=$want_skill mac=$want_mac, got skill=$skill_exists mac=$mac_exists"
        fi
        rm -rf "$fx"
    done
fi

# === BEHAVIOR 10: RELEASE_GUIDELINE.md contains the 6 sentinel sections ===
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"; mkdir -p "$fx/skills/foo"; echo "name: foo" > "$fx/skills/foo/SKILL.md"
    ( cd "$fx" && "$WRAPPER" --type=skill </dev/null >/dev/null 2>&1 )
    missing=""
    for h in "Project type" "Quick start" "Pre-flight" "Audit gates" "Versioning policy" "Sanity-scan"; do
        grep -qF "$h" "$fx/RELEASE_GUIDELINE.md" 2>/dev/null || missing="$missing '$h'"
    done
    if [ -z "$missing" ]; then
        ok "RELEASE_GUIDELINE.md has 6 sentinel sections"
    else
        fail "RELEASE_GUIDELINE.md missing sections:$missing"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 11: non-dry-run auto-provisions Claude Code plugin manifest ===
# Emits .claude-plugin/plugin.json (kebab+lowercase name, version from target
# VERSION) and .gitx/marketplace-entry.json (github source, repo from origin
# basename). --dry-run must write neither.
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"
    mkdir -p "$fx/skills/Foo_Bar"
    echo "name: Foo_Bar" > "$fx/skills/Foo_Bar/SKILL.md"
    echo "v0.2.0" > "$fx/VERSION"
    ( cd "$fx" && git init -q && git remote add origin "git@example:tkxlab-ai/Foo.git" )
    ( cd "$fx" && "$WRAPPER" --type=skill </dev/null >/dev/null 2>&1 )

    pj="$fx/.claude-plugin/plugin.json"
    me="$fx/.gitx/marketplace-entry.json"
    if [ ! -f "$pj" ]; then
        fail ".claude-plugin/plugin.json not created"
    elif ! jq -e . "$pj" >/dev/null 2>&1; then
        fail ".claude-plugin/plugin.json is not valid JSON"
    else
        pj_name="$(jq -r .name "$pj")"
        pj_ver="$(jq -r .version "$pj")"
        if [ "$pj_name" != "foo-bar" ]; then
            fail "plugin.json name='$pj_name', expected kebab+lowercase 'foo-bar'"
        elif [ "$pj_ver" != "0.2.0" ]; then
            fail "plugin.json version='$pj_ver', expected semver-normalized '0.2.0' (v stripped)"
        else
            ok "plugin.json valid: name=foo-bar version=0.2.0"
        fi
    fi

    if [ ! -f "$me" ]; then
        fail ".gitx/marketplace-entry.json not created"
    elif ! jq -e . "$me" >/dev/null 2>&1; then
        fail ".gitx/marketplace-entry.json is not valid JSON"
    else
        me_src="$(jq -r .source.source "$me")"
        me_repo="$(jq -r .source.repo "$me")"
        if [ "$me_src" != "github" ]; then
            fail "marketplace-entry source.source='$me_src', expected 'github'"
        elif ! echo "$me_repo" | grep -qE '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
            fail "marketplace-entry source.repo='$me_repo' not owner/repo shape"
        elif [ "$(jq -r .name "$me")" != "foo-bar" ]; then
            fail "marketplace-entry name != plugin.json name"
        else
            ok "marketplace-entry.json valid: source=github repo=$me_repo"
        fi
    fi
    rm -rf "$fx"

    # --dry-run must write neither manifest file
    fx="$(mktemp -d)"
    mkdir -p "$fx/skills/Foo_Bar"
    echo "name: Foo_Bar" > "$fx/skills/Foo_Bar/SKILL.md"
    out="$( cd "$fx" && "$WRAPPER" --type=skill --dry-run </dev/null 2>&1 )"
    if [ -e "$fx/.claude-plugin" ] || [ -e "$fx/.gitx/marketplace-entry.json" ]; then
        fail "--dry-run wrote plugin manifest files"
    elif ! grep -qE 'would write:.*plugin\.json' <<<"$out"; then
        fail "--dry-run did not preview plugin.json (got: $(echo "$out" | tr '\n' '|'))"
    else
        ok "--dry-run writes no manifest + previews plugin.json"
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 12: hostile project dir name → JSON stays valid + repo kebab ===
# A dir basename containing a space, double-quote, and $(...) must not corrupt
# the heredoc-emitted JSON. Both manifests must be valid JSON and source.repo
# must be a kebab slug (no spaces/quotes), since plugin_repo_name() must
# normalize like plugin_name().
if [ -x "$WRAPPER" ]; then
    fx="$(mktemp -d)"
    weird="$fx/weird \"q\" \$(x) dir"
    mkdir -p "$weird/skills/foo"
    echo "name: foo" > "$weird/skills/foo/SKILL.md"
    ( cd "$weird" && "$WRAPPER" --type=skill </dev/null >/dev/null 2>&1 )

    pj="$weird/.claude-plugin/plugin.json"
    me="$weird/.gitx/marketplace-entry.json"
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$pj" 2>/dev/null; then
        fail "hostile dir: plugin.json is not valid JSON"
    elif ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$me" 2>/dev/null; then
        fail "hostile dir: marketplace-entry.json is not valid JSON"
    else
        h_repo="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source"]["repo"])' "$me")"
        if echo "$h_repo" | grep -qE '^tkxlab-ai/[a-z0-9-]+$'; then
            ok "hostile dir: both JSON valid, source.repo=$h_repo (kebab)"
        else
            fail "hostile dir: source.repo='$h_repo' not ^tkxlab-ai/[a-z0-9-]+$"
        fi
    fi
    rm -rf "$fx"
fi

# === BEHAVIOR 13: VERSION is semver-normalized (v-strip) + injection-safe ===
# (1) a GitX-style `v0.2.0` VERSION must emit bare `0.2.0` in plugin.json.
# (2) a hostile/multiline/quoted VERSION must NOT corrupt either heredoc JSON;
#     both files stay python3 json.load-clean and fall back to safe '0.0.0'.
if [ -x "$WRAPPER" ]; then
    # 13a: v-prefixed VERSION → bare semver
    fx="$(mktemp -d)"; mkdir -p "$fx/skills/foo"; echo "name: foo" > "$fx/skills/foo/SKILL.md"
    printf 'v0.2.0\n' > "$fx/VERSION"
    ( cd "$fx" && "$WRAPPER" --type=skill </dev/null >/dev/null 2>&1 )
    pj_ver="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$fx/.claude-plugin/plugin.json" 2>/dev/null)"
    if [ "$pj_ver" = "0.2.0" ]; then
        ok "VERSION 'v0.2.0' → plugin.json version '0.2.0' (v stripped)"
    else
        fail "VERSION 'v0.2.0' → plugin.json version '$pj_ver', expected '0.2.0'"
    fi
    rm -rf "$fx"

    # 13b: hostile multiline/quoted VERSION → both JSON valid + safe fallback
    fx="$(mktemp -d)"; mkdir -p "$fx/skills/foo"; echo "name: foo" > "$fx/skills/foo/SKILL.md"
    printf '1.0.0"evil\ninject' > "$fx/VERSION"
    ( cd "$fx" && "$WRAPPER" --type=skill </dev/null >/dev/null 2>&1 )
    pj="$fx/.claude-plugin/plugin.json"
    me="$fx/.gitx/marketplace-entry.json"
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$pj" 2>/dev/null; then
        fail "hostile VERSION: plugin.json is not valid JSON"
    elif ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$me" 2>/dev/null; then
        fail "hostile VERSION: marketplace-entry.json is not valid JSON"
    else
        hv_pj="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$pj")"
        hv_me="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$me")"
        if [ "$hv_pj" = "0.0.0" ] && [ "$hv_me" = "0.0.0" ]; then
            ok "hostile VERSION: both JSON valid, version=0.0.0 safe fallback"
        else
            fail "hostile VERSION: version pj='$hv_pj' me='$hv_me', expected '0.0.0'"
        fi
    fi
    rm -rf "$fx"
fi

# === STATIC 5: SKILL.md "工作模式" table lists gitx-init with triggers ===
SKILL_MD="$ROOT/skills/gitx-release/SKILL.md"
if [ -f "$SKILL_MD" ]; then
    if grep -qE 'gitx-init.*scripts/gitx-init\.sh|/gitx-init.*项目初始化' "$SKILL_MD"; then
        ok "SKILL.md table lists gitx-init"
    else
        fail "SKILL.md missing gitx-init row in 工作模式 table"
    fi
fi

# === STATIC 6: commands/gitx-init.md slash shim exists with frontmatter ===
# Frontmatter convention follows sibling TKX skills (1by1 / handoff): a
# `description:` field is sufficient; the slash name is derived from filename.
CMD_SHIM="$ROOT/skills/gitx-release/commands/gitx-init.md"
if [ ! -f "$CMD_SHIM" ]; then
    fail "commands/gitx-init.md slash shim missing"
elif ! head -3 "$CMD_SHIM" | grep -qE '^---[[:space:]]*$'; then
    fail "commands/gitx-init.md missing YAML frontmatter delimiter"
elif ! grep -qE '^description:' "$CMD_SHIM"; then
    fail "commands/gitx-init.md frontmatter missing description:"
elif ! grep -q 'gitx-init.sh' "$CMD_SHIM"; then
    fail "commands/gitx-init.md does not reference scripts/gitx-init.sh"
else
    ok "commands/gitx-init.md slash shim valid"
fi

# === STATIC 7: install.sh propagates commands/ so /gitx-init reaches Claude Code ===
if [ -f "$ROOT/install.sh" ]; then
    if grep -qE 'cp -R "?\$SELF_DIR/commands"?[[:space:]]+"?\$CANONICAL/commands"?' "$ROOT/install.sh"; then
        ok "install.sh propagates commands/ to canonical"
    else
        fail "install.sh does not propagate commands/ to canonical"
    fi
fi

# === STATIC 8: agents/codex-commands.txt declares \$gitx-init (root + bundle byte-identical) ===
for cct in "$ROOT/agents/codex-commands.txt" "$ROOT/skills/gitx-release/agents/codex-commands.txt"; do
    if [ -f "$cct" ]; then
        if grep -qE '^\$gitx-init$' "$cct"; then
            ok "codex-commands.txt declares \$gitx-init ($(basename "$(dirname "$(dirname "$cct")")"))"
        else
            fail "$cct missing \$gitx-init"
        fi
    fi
done

# === STATIC 9: release-audit.sh has §0c gitx-init gate (root + bundle) ===
for audit_sh in "$ROOT/scripts/release-audit.sh" "$ROOT/skills/gitx-release/scripts/release-audit.sh"; do
    if [ -f "$audit_sh" ]; then
        label="$(basename "$(dirname "$(dirname "$audit_sh")")")"
        if grep -qE '^audit_section_0_gitx_init\(\)' "$audit_sh" \
           && grep -q '§0c' "$audit_sh" \
           && grep -q 'references/gitx-init/' "$audit_sh"; then
            ok "release-audit.sh has §0c gitx-init gate ($label)"
        else
            fail "$audit_sh missing §0c gitx-init audit gate"
        fi
    fi
done

# === summary ===
echo "Results: ✅$PASS passed / ❌$FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "FAIL"; exit 1
else
    echo "PASS"; exit 0
fi
