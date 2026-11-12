#!/bin/bash
# test_release_wrapper_git_repo.sh — one-command wrapper against a REAL,
# committed git fixture running the REAL release.sh (no stubs).
# Why: test_gitx_release_one_command.sh stubs release.sh in a non-git dir, so
# it never saw release.sh's clean-tree preflight (v1.12.3 round-12) reject the
# very VERSION / CHANGELOG files the wrapper bumps by design — one-command
# release was broken in every git repo and no test noticed.
# exit: 0 all pass, 1 any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== test_release_wrapper_git_repo.sh ==="

SKILL="my-skill"
PROJ="fixproj"
TMPROOT=$(mktemp -d)
trap 'chmod -R u+w "$TMPROOT" 2>/dev/null || true; rm -rf "$TMPROOT"' EXIT
FAKE_HOME="$TMPROOT/home"
mkdir -p "$FAKE_HOME"

_git() { git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

# Fixture content mirrors tests/test_release_pipeline_smoke.sh (which is known
# to satisfy docs-audit + Deep Audit) — copied, not shared, so each suite can
# evolve its fixture independently.
build_git_fixture() {
    local fix="$1" with_scrub="${2:-0}"
    mkdir -p "$fix/skills/$SKILL/agents" "$fix/skills/$SKILL/references" \
             "$fix/skills/$SKILL/assets" "$fix/scripts/lib" "$fix/tests" "$fix/Release"

    cat > "$fix/skills/$SKILL/references/README.md" <<'EOF'
# References

This skill has no external reference documents at this time.

Placeholder reference file to satisfy audit §6b line-count threshold.

Future versions may include additional reference materials.
EOF
    cat > "$fix/skills/$SKILL/assets/README.md" <<'EOF'
# Assets

This skill has no binary assets.
EOF
    printf '%s\n' '$my-skill' > "$fix/skills/$SKILL/agents/codex-commands.txt"
    cat > "$fix/skills/$SKILL/SKILL.md" <<'EOF'
---
name: my-skill
description: Minimal fixture skill for pipeline smoke testing.
---
# My Skill

## When to Trigger

Use this skill for testing the release pipeline.

## Steps / Execution Flow

1. Do thing A
2. Do thing B
3. Verify result

This skill is a minimal fixture for smoke testing the release.sh pipeline.
It has enough content to pass the audit line-count thresholds.
Line 13 of content.
Line 14 of content.
Line 15 of content.
Line 16 of content.
Line 17 of content.
Line 18 of content.
Line 19 of content.
Line 20 of content.
Line 21 of content.
EOF
    printf 'v0.0.1\n' > "$fix/skills/$SKILL/VERSION"
    printf 'v0.0.1\n' > "$fix/VERSION"

    cat > "$fix/tests/run_all.sh" <<'EOF'
#!/bin/bash
# Minimal test runner stub for fixture project.
echo "Tests: 0 suites (fixture stub)"
exit 0
EOF
    chmod +x "$fix/tests/run_all.sh"

    cat > "$fix/Release/CHANGELOG.md" <<'EOF'
# Fixproj — Release History

记录各版本的关键变化。最新版本在最上面。

## v0.0.1 — 2026-01-01

Initial release of the fixture skill for pipeline smoke testing.

Artifacts: `Release/fixproj-v0.0.1/`

---
EOF

    cat > "$fix/README.md" <<'EOF'
# Fixproj

A minimal fixture skill for smoke testing the release pipeline.

## Installation

Run `./install.sh` to install.

## Usage / Quick Start

Trigger the skill via Claude Code.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development guidelines.

## License

MIT
EOF
    cat > "$fix/TEST-SCENARIOS.md" <<'EOF'
# Test Scenarios

Smoke test scenarios for the fixture skill.

## Scenario 1: Basic Installation

Install the skill and verify it triggers.

## Scenario 2: Version Check

Verify the correct version is installed.
EOF
    cat > "$fix/INSTALL.md" <<'EOF'
# Install

## Requirements

- Claude Code

## Install steps

```bash
./install.sh
```

## Uninstall

Remove the skill directory.

## Upgrade / Update

Re-run install.sh with --force.
EOF
    cat > "$fix/install.sh" <<'EOF'
#!/bin/bash
# install.sh — fixture install stub
# usage: ./install.sh [--dry-run] [--force] [--help]
# exit: 0 success, 1 failure
set -euo pipefail
DRY_RUN=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
        --help)    echo "Usage: $0 [--dry-run] [--force] [--help]"; exit 0 ;;
    esac
done
[ "$DRY_RUN" = "1" ] && echo "[dry-run] would install" && exit 0
mkdir -p "$HOME/.claude/skills"
echo "Fixture install.sh executed."
EOF
    chmod +x "$fix/install.sh"
    cat > "$fix/LICENSE" <<'EOF'
MIT License

Copyright (c) 2026 Fixture Author

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so.
EOF
    cat > "$fix/CONTRIBUTING.md" <<'EOF'
# Contributing

## Development

1. Clone the repo
2. Run tests: `bash tests/run_all.sh`
3. Build: no build step required

## Pull Request / Commit Conventions

- Use conventional commits: `feat:`, `fix:`, `docs:`, `chore:`
- Submit changes via PR against main
- All tests must pass before merging
EOF

    # The wrapper invokes its SIBLING release.sh, which resolves every helper
    # from its own dir ($SKILL_ROOT) — so the fixture carries the full pipeline.
    local f
    for f in release.sh release-sanitize.sh release-audit.sh scan-credentials.sh \
             emit-sbom.sh emit-token-usage.sh gitx-release.sh gitx-marketplace.sh \
             docs-audit.sh docs-pipeline.sh; do
        cp "$REAL/scripts/$f" "$fix/scripts/$f"
    done
    # install-output-style.sh is deliberately NOT copied: shipping it opts the
    # project into Deep Audit's install.sh banner standard, which the fixture's
    # stub install.sh does not follow (release.sh itself never sources it).
    cp "$REAL/scripts/lib/detect-project.sh" "$REAL/scripts/lib/skill-creator-version.sh" "$fix/scripts/lib/"
    cp -R "$REAL/scripts/vendored" "$fix/scripts/vendored"
    chmod +x "$fix/scripts/"*.sh
    # Dual-source gate: mirror everything; only scrub-tarball.sh (added below)
    # stays root-only, which _filter_dual_source_drift tolerates.
    mkdir -p "$fix/skills/$SKILL/scripts"
    cp -R "$fix/scripts/." "$fix/skills/$SKILL/scripts/"

    printf 'fixture-%s\n' "$RANDOM$RANDOM" > "$fix/FIXTURE-MARKER.txt"
    # Without export-ignore, `git archive HEAD` ships Release/CHANGELOG.md and
    # Deep Audit §5 rejects any Release/ member of the source tarball.
    printf '/Release export-ignore\n' > "$fix/.gitattributes"

    ( cd "$fix" && git init -q && _git add -A && _git commit -qm init )

    if [ "$with_scrub" = "1" ]; then
        # release.sh invokes scrub without cd — archive THE FIXTURE explicitly.
        cat > "$fix/scripts/scrub-tarball.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
out="$1"; prefix="$2"; ref="${3:-HEAD}"
git -C "${PROJECT_ROOT:?}" archive --format=tar --prefix="$prefix/" "$ref" | gzip -n > "$out"
EOF
        chmod +x "$fix/scripts/scrub-tarball.sh"
        ( cd "$fix" && _git add -A && _git commit -qm scrub )
    fi
}

# Runs the wrapper exactly as an operator would (names auto-detected). Output
# lands in "$1.out"; returns the wrapper's exit code.
run_wrapper() {
    local fix="$1" rc
    set +e
    ( cd "$TMPROOT" && env -u PROJECT_NAME -u SKILL_NAME -u _GITX_WRAPPER_DIRTY_OK \
        HOME="$FAKE_HOME" PROJECT_ROOT="$fix" \
        bash "$fix/scripts/gitx-release.sh" --skip-marketplace ) > "$fix.out" 2>&1
    rc=$?
    set -e
    return "$rc"
}

show_tail() { echo "     --- last 40 lines of $1 ---"; tail -40 "$1" | sed 's/^/     /'; }

# Cross-lane dependencies make two known failures provisional (still counted
# as FAIL here — final acceptance is the controller's). Flag them so a reader
# can tell them apart from a real regression.
note_provisional() {
    local out="$1" emails
    emails=$(sed -n '/EMAIL ADDRESSES/,/敏感信息/p' "$out" | grep -E '^[^ ].*:[0-9]+:' || true)
    if [ -n "$emails" ] && ! grep -qv 'gitx-marketplace.sh:.*noreply@github.com' <<<"$emails"; then
        echo "  ⚠️  PROVISIONAL (Lane A): only sanitizer hit is noreply@github.com in gitx-marketplace.sh"
    elif grep -q 'bad substitution' "$out" && grep -q '11k' "$out"; then
        echo "  ⚠️  PROVISIONAL (Lane B): Deep Audit §11k bad substitution on bash 3.2"
    fi
}

_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
_sum()   { cksum < "$1"; }

# ── C1 (a): committed git repo, rsync path → wrapper release succeeds ───────
FIX="$TMPROOT/c1a/$PROJ"; mkdir -p "$(dirname "$FIX")"
build_git_fixture "$FIX"
rc=0; run_wrapper "$FIX" || rc=$?
if [ "$rc" -eq 0 ] && [ -d "$FIX/Release/$PROJ-v0.0.2" ]; then
    ok "C1a: wrapper release in a committed git repo exits 0 and builds Release/$PROJ-v0.0.2/"
else
    fail "C1a: wrapper exited $rc (release dir present: $([ -d "$FIX/Release/$PROJ-v0.0.2" ] && echo yes || echo no))"
    show_tail "$FIX.out"
    note_provisional "$FIX.out"
fi

# ── C1 (b): a real uncommitted tracked edit is still rejected ────────────────
FIX="$TMPROOT/c1b/$PROJ"; mkdir -p "$(dirname "$FIX")"
build_git_fixture "$FIX"
echo "dirty" >> "$FIX/README.md"
rc=0; run_wrapper "$FIX" || rc=$?
if [ "$rc" -ne 0 ] && grep -q 'uncommitted tracked changes' "$FIX.out"; then
    ok "C1b: modified README.md (not wrapper-written) still aborts the preflight"
else
    fail "C1b: expected non-zero + 'uncommitted tracked changes' (rc=$rc)"
    show_tail "$FIX.out"
fi

# ── C1 (c): untracked-not-gitignored file still rejected ────────────────────
FIX="$TMPROOT/c1c/$PROJ"; mkdir -p "$(dirname "$FIX")"
build_git_fixture "$FIX"
printf 'README.md\n' > "$FIX/.release-flatten"
rc=0; run_wrapper "$FIX" || rc=$?
if [ "$rc" -ne 0 ] && grep -q 'untracked-not-gitignored' "$FIX.out"; then
    ok "C1c: untracked .release-flatten still aborts the preflight"
else
    fail "C1c: expected non-zero + 'untracked-not-gitignored' (rc=$rc)"
    show_tail "$FIX.out"
fi

# ── C1 (d): a hand-set allowlist cannot excuse a non-wrapper path ───────────
FIX="$TMPROOT/c1d/$PROJ"; mkdir -p "$(dirname "$FIX")"
build_git_fixture "$FIX"
echo "dirty" >> "$FIX/README.md"
set +e
( cd "$TMPROOT" && HOME="$FAKE_HOME" PROJECT_ROOT="$FIX" PROJECT_NAME="$PROJ" SKILL_NAME="$SKILL" \
  _GITX_WRAPPER_DIRTY_OK="README.md" bash "$FIX/scripts/release.sh" v0.0.1 ) > "$FIX.out" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ] && grep -q 'uncommitted tracked changes' "$FIX.out"; then
    ok "C1d: _GITX_WRAPPER_DIRTY_OK=README.md does not excuse a dirty README"
else
    fail "C1d: hand-set allowlist excused README.md (rc=$rc)"
    show_tail "$FIX.out"
fi

# ── C1 (e): unborn HEAD (files staged, no commit) fails closed ──────────────
FIX="$TMPROOT/c1e/$PROJ"; mkdir -p "$(dirname "$FIX")"
build_git_fixture "$FIX"
rm -rf "$FIX/.git"
( cd "$FIX" && git init -q && _git add -A )
rc=0; run_wrapper "$FIX" || rc=$?
if [ "$rc" -ne 0 ] && grep -q 'cannot verify clean working tree' "$FIX.out"; then
    ok "C1e: unborn HEAD → preflight fails closed (diff-index error is not 'clean')"
else
    fail "C1e: unborn HEAD passed the preflight or wrong message (rc=$rc)"
    show_tail "$FIX.out"
fi

# ── C1 (f): the allowlist does not leak into the project's own test run ─────
FIX="$TMPROOT/c1f/$PROJ"; mkdir -p "$(dirname "$FIX")"
build_git_fixture "$FIX"
cat > "$FIX/tests/run_all.sh" <<'EOF'
#!/bin/bash
echo "LEAK-PROBE=${_GITX_WRAPPER_DIRTY_OK:-unset}"
exit 1
EOF
( cd "$FIX" && _git add -A && _git commit -qm probe )
rc=0; run_wrapper "$FIX" || rc=$?
if grep -q '^LEAK-PROBE=unset$' "$FIX.out"; then
    ok "C1f: tests/run_all.sh does not inherit _GITX_WRAPPER_DIRTY_OK"
else
    fail "C1f: allowlist leaked into child processes: $(grep LEAK-PROBE "$FIX.out" | head -1)"
fi

# ── C1 (g): committed Release symlink → refused before the wrapper log write ─
FIX="$TMPROOT/c1g/$PROJ"; mkdir -p "$(dirname "$FIX")"
build_git_fixture "$FIX"
OUT_REL="$TMPROOT/c1g/outside-release"
mv "$FIX/Release" "$OUT_REL"; ln -s "$OUT_REL" "$FIX/Release"
( cd "$FIX" && _git add -A && _git commit -qm relsymlink )
rc=0; run_wrapper "$FIX" || rc=$?
if [ "$rc" -eq 5 ] && grep -q 'symlink' "$FIX.out" && [ ! -e "$OUT_REL/logs" ]; then
    ok "C1g: Release symlink → exit 5, no log written into the link target"
else
    fail "C1g: rc=$rc, logs in target: $([ -e "$OUT_REL/logs" ] && echo yes || echo no)"
    show_tail "$FIX.out"
fi

# ── C1b (a): scrub (git-archive) path ships the bumped VERSION sidecars ─────
FIX="$TMPROOT/c1ba/$PROJ"; mkdir -p "$(dirname "$FIX")"
build_git_fixture "$FIX" 1
rc=0; run_wrapper "$FIX" || rc=$?
TARBALL="$FIX/Release/$PROJ-v0.0.2/$PROJ-v0.0.2-source.tar.gz"
if [ "$rc" -eq 0 ] && [ -f "$TARBALL" ]; then
    ok "C1b-a: scrub-path wrapper release exits 0 with a source tarball"
    X="$TMPROOT/c1ba-x"; mkdir -p "$X"
    tar -xzf "$TARBALL" -C "$X"
    S="$X/$PROJ-v0.0.2"
    [ "$(cat "$S/VERSION" 2>/dev/null)" = "v0.0.2" ] \
        && ok "C1b-a: tarball root VERSION = v0.0.2" \
        || fail "C1b-a: tarball root VERSION = '$(cat "$S/VERSION" 2>/dev/null)' (expected v0.0.2)"
    [ "$(cat "$S/skills/$SKILL/VERSION" 2>/dev/null)" = "v0.0.2" ] \
        && ok "C1b-a: tarball skills/$SKILL/VERSION = v0.0.2" \
        || fail "C1b-a: tarball skills/$SKILL/VERSION = '$(cat "$S/skills/$SKILL/VERSION" 2>/dev/null)'"
    if [ -f "$S/FIXTURE-MARKER.txt" ] && cmp -s "$S/FIXTURE-MARKER.txt" "$FIX/FIXTURE-MARKER.txt"; then
        ok "C1b-a: FIXTURE-MARKER.txt matches — the fixture repo (not cwd) was archived"
    else
        fail "C1b-a: FIXTURE-MARKER.txt missing/mismatched — wrong repo archived"
    fi
    rel_hits=$(tar -tzf "$TARBALL" | grep -c "^$PROJ-v0.0.2/Release/" || true)
    [ "$rel_hits" -eq 0 ] \
        && ok "C1b-a: no Release/ entries in the source tarball" \
        || fail "C1b-a: $rel_hits Release/ entries in the source tarball"
else
    fail "C1b-a: scrub-path wrapper exited $rc (tarball present: $([ -f "$TARBALL" ] && echo yes || echo no))"
    show_tail "$FIX.out"
    note_provisional "$FIX.out"
fi

# Asserts the wrapper refused BEFORE writing: non-zero + 'symlink', target
# bytes AND mtime intact (rollback cp would restore bytes but bump mtime),
# and release.sh never started (no detected-block in the wrapper log).
assert_refused_before_write() {
    local label="$1" fix="$2" target="$3" sum0="$4" mt0="$5" rc="$6" logs
    if [ "$rc" -ne 0 ] && grep -q 'symlink' "$fix.out"; then
        ok "$label: wrapper exits $rc with a symlink refusal"
    else
        fail "$label: expected non-zero + 'symlink' (rc=$rc)"
        show_tail "$fix.out"
    fi
    if [ "$(_sum "$target")" = "$sum0" ] && [ "$(_mtime "$target")" = "$mt0" ]; then
        ok "$label: outside target bytes + mtime unchanged"
    else
        fail "$label: outside target was written through the symlink"
    fi
    logs=$(cat "$fix"/Release/logs/*.log 2>/dev/null || true)
    if ! grep -q 'Running regression' "$fix.out" && ! grep -q -- '--- detected ---' <<<"$logs"; then
        ok "$label: stopped before update_skill_versions (release.sh never ran)"
    else
        fail "$label: wrapper proceeded past the version bump"
    fi
}

# ── C1b (b): committed skills/<skill>/VERSION is a symlink to an outside file
FIX="$TMPROOT/c1bb/$PROJ"; mkdir -p "$(dirname "$FIX")"
build_git_fixture "$FIX" 1
SENT="$TMPROOT/c1bb/sentinel"
printf 'v0.0.1\n' > "$SENT"; touch -t 200001010000 "$SENT"
rm "$FIX/skills/$SKILL/VERSION"; ln -s "$SENT" "$FIX/skills/$SKILL/VERSION"
( cd "$FIX" && _git add -A && _git commit -qm symlink )
sum0=$(_sum "$SENT"); mt0=$(_mtime "$SENT")
rc=0; run_wrapper "$FIX" || rc=$?
assert_refused_before_write "C1b-b" "$FIX" "$SENT" "$sum0" "$mt0" "$rc"

# ── C1b (c): committed skills/<skill> dir is a symlink to an outside dir ────
FIX="$TMPROOT/c1bc/$PROJ"; mkdir -p "$(dirname "$FIX")"
build_git_fixture "$FIX" 1
OUTSIDE="$TMPROOT/c1bc/outside-skill"
mv "$FIX/skills/$SKILL" "$OUTSIDE"; ln -s "$OUTSIDE" "$FIX/skills/$SKILL"
touch -t 200001010000 "$OUTSIDE/VERSION"
( cd "$FIX" && _git add -A && _git commit -qm symlinkdir )
sum0=$(_sum "$OUTSIDE/VERSION"); mt0=$(_mtime "$OUTSIDE/VERSION")
rc=0; run_wrapper "$FIX" || rc=$?
assert_refused_before_write "C1b-c" "$FIX" "$OUTSIDE/VERSION" "$sum0" "$mt0" "$rc"

# ── C1b (d)(e): overlay helper unit tests (eval-extracted) ──────────────────
eval "$(awk '/^overlay_wrapper_versions_into_stage\(\) *\{/,/^\}/' "$REAL/scripts/release.sh")"
if ! type overlay_wrapper_versions_into_stage >/dev/null 2>&1; then
    fail "C1b-d/e: overlay_wrapper_versions_into_stage not defined in scripts/release.sh"
else
    O="$TMPROOT/ovl"; ROOT_O="$O/root"
    mkdir -p "$ROOT_O/skills/$SKILL" "$ROOT_O/Release"
    printf 'v0.0.2\n' > "$ROOT_O/VERSION"; printf 'v0.0.2\n' > "$ROOT_O/skills/$SKILL/VERSION"
    printf '# new\n' > "$ROOT_O/Release/CHANGELOG.md"
    DIRTY="VERSION
skills/$SKILL/VERSION
Release/CHANGELOG.md"
    _ovl() { ( _GITX_WRAPPER_DIRTY_OK="$DIRTY" overlay_wrapper_versions_into_stage "$ROOT_O" "$1" ) >/dev/null 2>&1; }

    ST="$O/stage-ok"; mkdir -p "$ST/skills/$SKILL"
    printf 'v0.0.1\n' > "$ST/VERSION"; printf 'v0.0.1\n' > "$ST/skills/$SKILL/VERSION"
    rc=0; _ovl "$ST" || rc=$?
    if [ "$rc" -eq 0 ] && [ "$(cat "$ST/VERSION")" = "v0.0.2" ] \
        && [ "$(cat "$ST/skills/$SKILL/VERSION")" = "v0.0.2" ] && [ ! -e "$ST/Release" ]; then
        ok "C1b-d: overlay copies both VERSION sidecars and never Release/CHANGELOG.md"
    else
        fail "C1b-d: positive overlay wrong (rc=$rc)"
    fi

    ST="$O/stage-link"; mkdir -p "$ST/skills/$SKILL"; SENT="$O/sentinel"
    printf 'keep\n' > "$SENT"; ln -s "$SENT" "$ST/skills/$SKILL/VERSION"
    rc=0; _ovl "$ST" || rc=$?
    [ "$rc" -ne 0 ] && [ "$(cat "$SENT")" = "keep" ] \
        && ok "C1b-d: staged VERSION symlink → non-zero, outside sentinel unchanged" \
        || fail "C1b-d: staged VERSION symlink not refused (rc=$rc, sentinel=$(cat "$SENT"))"

    ST="$O/stage-dirlink"; mkdir -p "$ST" "$O/outside-dir"; ln -s "$O/outside-dir" "$ST/skills"
    rc=0; _ovl "$ST" || rc=$?
    [ "$rc" -ne 0 ] && [ ! -e "$O/outside-dir/$SKILL" ] \
        && ok "C1b-d: staged parent-dir symlink → non-zero, nothing written outside" \
        || fail "C1b-d: staged parent-dir symlink not refused (rc=$rc)"

    ST="$O/stage-ro"; mkdir -p "$ST"; chmod 555 "$ST"
    rc=0; _ovl "$ST" || rc=$?
    chmod 755 "$ST"
    [ "$rc" -ne 0 ] \
        && ok "C1b-e: read-only stage (cp/mkdir fails) → non-zero (error propagates)" \
        || fail "C1b-e: read-only stage returned 0 — copy failure swallowed"

    # Caller-controlled env must not steer writes outside the stage or ship
    # an untracked VERSION from an arbitrary subtree.
    # root/../../x resolves to $TMPROOT/x — the source must exist, or the
    # old code would skip it on `[ -f ]` and the test would pass vacuously.
    mkdir -p "$TMPROOT/x" "$O/x" "$ROOT_O/node_modules/p" "$O/deep/a/b"
    printf 'evil\n' > "$TMPROOT/x/VERSION"
    printf 'evil\n' > "$O/x/VERSION"
    printf 'v9.9.9\n' > "$ROOT_O/node_modules/p/VERSION"
    ST="$O/deep/a/b/stage-trav"; mkdir -p "$ST"
    rc=0
    ( _GITX_WRAPPER_DIRTY_OK="../../x/VERSION
/etc/VERSION
skills/../VERSION
node_modules/p/VERSION" overlay_wrapper_versions_into_stage "$ROOT_O" "$ST" ) >/dev/null 2>&1 || rc=$?
    if [ ! -e "$O/deep/a/x" ] && [ ! -e "$O/deep/x" ] && [ "$(cat "$O/x/VERSION")" = "evil" ] \
        && [ -z "$(find "$ST" -mindepth 1 2>/dev/null)" ]; then
        ok "C1b-f: '..' / absolute / node_modules entries ignored — nothing written outside or into the stage (rc=$rc)"
    else
        fail "C1b-f: overlay honoured a traversal/non-sidecar entry: $(find "$O/deep" "$ST" -mindepth 1 | head -5 | tr '\n' ' ')"
    fi
fi

echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
