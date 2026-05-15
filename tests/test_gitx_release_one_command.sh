#!/bin/bash
# test_gitx_release_one_command.sh — one-command GitX release contract
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$PROJECT_ROOT/scripts/gitx-release.sh"
INSTALL_SH="$PROJECT_ROOT/install.sh"
RELEASE_SH="$PROJECT_ROOT/scripts/release.sh"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_gitx_release_one_command.sh ══"

if [ -x "$WRAPPER" ]; then
    ok "scripts/gitx-release.sh exists and is executable"
else
    fail "scripts/gitx-release.sh missing or not executable"
fi

# v1.1.0 rebrand: commands/GitX-release.md was deliberately removed.
# Claude Code now auto-promotes the renamed `gitx-release` skill folder
# directly to /gitx-release; the manual shim was the source of the
# duplicate-entry tacit-knowledge tax. Verify the SKILL.md `name:` field
# still drives the slash command.
if grep -q '^name: gitx-release$' "$PROJECT_ROOT/SKILL.md" \
    && grep -q '^name: gitx-release$' "$PROJECT_ROOT/skills/gitx-release/SKILL.md"; then
    ok "SKILL.md name=gitx-release in both root + bundle (Claude Code auto-promotes to /gitx-release)"
else
    fail "SKILL.md name field missing or wrong (expected 'gitx-release')"
fi

# install.sh must wire the wrapper. v1.1.0: removed the .claude/commands
# install step, so we assert wrapper installation via canonical path only.
if grep -q 'scripts/gitx-release.sh' "$INSTALL_SH" && grep -q '\.agents/skills' "$INSTALL_SH"; then
    ok "install.sh installs GitX wrapper to canonical path"
else
    fail "install.sh does not install GitX wrapper"
fi

if [ -f "$WRAPPER" ] && grep -q 'next_patch_version' "$WRAPPER" \
    && grep -q 'update_skill_versions' "$WRAPPER" \
    && grep -q 'ensure_changelog_entry' "$WRAPPER" \
    && grep -q 'release.sh' "$WRAPPER"; then
    ok "GitX wrapper auto-bumps version, updates metadata/changelog, and delegates to release.sh"
else
    fail "GitX wrapper lacks required one-command release flow"
fi

# NOTE (v1.1.0): the gitx-release skill itself ships no commands/ folder,
# but `release.sh` is a GENERIC pipeline used by any downstream skill —
# projects that DO ship commands/ rely on this flattening branch. This
# assertion guards the generic contract, not gitx-release specifically.
if grep -q 'commands' "$RELEASE_SH" && grep -q 'cp -R "$SKILL_SRC_DIR/commands"' "$RELEASE_SH"; then
    ok "release.sh retains generic commands/ flattening branch (for downstream skills)"
else
    fail "release.sh dropped generic commands/ flatten — breaks downstream skills that ship slash commands"
fi

if grep -q 'cp -R "$SKILL_SRC_DIR/agents"' "$RELEASE_SH"; then
    ok "release.sh flattens agents/ Codex metadata into release artifacts"
else
    fail "release.sh does not flatten agents/ Codex metadata for release-dir installs"
fi

FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p \
    "$FIXTURE/project/skills/demo-skill" \
    "$FIXTURE/project/Release" \
    "$FIXTURE/scripts/lib"
cp "$WRAPPER" "$FIXTURE/scripts/gitx-release.sh"
cp "$PROJECT_ROOT/scripts/lib/detect-project.sh" "$FIXTURE/scripts/lib/detect-project.sh"
chmod +x "$FIXTURE/scripts/gitx-release.sh"
cat > "$FIXTURE/scripts/release.sh" <<'EOF'
#!/bin/bash
echo "fake release invoked: $*"
echo "fake release project: ${PROJECT_ROOT:-missing}"
mkdir -p "$PROJECT_ROOT/Release/project-$1"
exit 0
EOF
chmod +x "$FIXTURE/scripts/release.sh"
cat > "$FIXTURE/project/skills/demo-skill/SKILL.md" <<'EOF'
---
name: demo-skill
description: Demo skill for GitX release logging test.
---
EOF
printf 'v0.0.1\n' > "$FIXTURE/project/skills/demo-skill/VERSION"
printf 'v0.0.1\n' > "$FIXTURE/project/VERSION"

if env -u PROJECT_NAME -u SKILL_NAME PROJECT_ROOT="$FIXTURE/project" bash "$FIXTURE/scripts/gitx-release.sh" --version v0.0.2 > "$FIXTURE/stdout.txt" 2>&1; then
    log_file=$(find "$FIXTURE/project/Release/logs" -name 'gitx-release-*.log' -type f | head -1)
    release_log=$(find "$FIXTURE/project/Release/project-v0.0.2" -name 'gitx-release-*.log' -type f | head -1)
    release_log_sum="${release_log}.sha256"
    if command -v shasum >/dev/null 2>&1; then
        log_sum_ok=$(cd "$(dirname "$release_log")" && shasum -a 256 -c "$(basename "$release_log_sum")" >/dev/null 2>&1; echo $?)
    elif command -v sha256sum >/dev/null 2>&1; then
        log_sum_ok=$(cd "$(dirname "$release_log")" && sha256sum -c "$(basename "$release_log_sum")" >/dev/null 2>&1; echo $?)
    else
        log_sum_ok=1
    fi
    if [ -n "$log_file" ] \
        && [ -n "$release_log" ] \
        && [ -f "$release_log_sum" ] \
        && grep -q 'event=gitx_release_start' "$log_file" \
        && grep -q 'project_root=' "$log_file" \
        && grep -q 'skill_name=demo-skill' "$log_file" \
        && grep -q 'version=v0.0.2' "$log_file" \
        && grep -q 'fake release invoked: v0.0.2' "$log_file" \
        && grep -q 'exit_code=0' "$log_file" \
        && grep -q 'exit_code=0' "$release_log" \
        && [ "$log_sum_ok" -eq 0 ]; then
        ok "GitX wrapper writes diagnostic logs globally and inside the release dir"
    else
        fail "GitX wrapper did not write the expected diagnostic log"
    fi
else
    fail "GitX wrapper logging fixture failed: $(cat "$FIXTURE/stdout.txt")"
fi

FAIL_FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$FAIL_FIXTURE"' EXIT
mkdir -p \
    "$FAIL_FIXTURE/project/skills/demo-skill" \
    "$FAIL_FIXTURE/project/Release" \
    "$FAIL_FIXTURE/scripts/lib"
cp "$WRAPPER" "$FAIL_FIXTURE/scripts/gitx-release.sh"
cp "$PROJECT_ROOT/scripts/lib/detect-project.sh" "$FAIL_FIXTURE/scripts/lib/detect-project.sh"
chmod +x "$FAIL_FIXTURE/scripts/gitx-release.sh"
cat > "$FAIL_FIXTURE/scripts/release.sh" <<'EOF'
#!/bin/bash
echo "fake release hard failure"
exit 7
EOF
chmod +x "$FAIL_FIXTURE/scripts/release.sh"
cat > "$FAIL_FIXTURE/project/skills/demo-skill/SKILL.md" <<'EOF'
---
name: demo-skill
description: Demo skill for GitX release failure logging test.
---
EOF
printf 'v0.0.1\n' > "$FAIL_FIXTURE/project/skills/demo-skill/VERSION"
printf 'v0.0.1\n' > "$FAIL_FIXTURE/project/VERSION"
cat > "$FAIL_FIXTURE/project/Release/CHANGELOG.md" <<'EOF'
# Demo — Release History

## v0.0.1 — 2026-01-01

Stable baseline before failed release.

---
EOF

set +e
env -u PROJECT_NAME -u SKILL_NAME PROJECT_ROOT="$FAIL_FIXTURE/project" bash "$FAIL_FIXTURE/scripts/gitx-release.sh" --version v0.0.2 > "$FAIL_FIXTURE/stdout.txt" 2>&1
fail_status=$?
set -e
fail_log=$(find "$FAIL_FIXTURE/project/Release/logs" -name 'gitx-release-*.log' -type f | head -1)
if [ "$fail_status" -eq 7 ] \
    && [ -n "$fail_log" ] \
    && grep -q 'fake release hard failure' "$fail_log" \
    && grep -q 'exit_code=7' "$fail_log" \
    && grep -q 'Diagnostic log:' "$FAIL_FIXTURE/stdout.txt"; then
    ok "GitX wrapper preserves diagnostic log on release failure"
else
    fail "GitX wrapper did not preserve failure diagnostics"
fi

LEGACY_FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$FAIL_FIXTURE" "$LEGACY_FIXTURE"' EXIT
mkdir -p \
    "$LEGACY_FIXTURE/project/old/1by1-skill-dev" \
    "$LEGACY_FIXTURE/scripts/lib"
cp "$WRAPPER" "$LEGACY_FIXTURE/scripts/gitx-release.sh"
cp "$PROJECT_ROOT/scripts/lib/detect-project.sh" "$LEGACY_FIXTURE/scripts/lib/detect-project.sh"
chmod +x "$LEGACY_FIXTURE/scripts/gitx-release.sh"
cat > "$LEGACY_FIXTURE/project/old/1by1-skill-dev/SKILL.md" <<'EOF'
---
name: 1by1
description: Legacy flat skill for GitX upgrade guideline logging test.
---
EOF

set +e
env -u PROJECT_NAME -u SKILL_NAME PROJECT_ROOT="$LEGACY_FIXTURE/project" bash "$LEGACY_FIXTURE/scripts/gitx-release.sh" --dry-run > "$LEGACY_FIXTURE/stdout.txt" 2>&1
legacy_status=$?
set -e
legacy_log=$(find "$LEGACY_FIXTURE/project/Release/logs" -name 'gitx-release-*.log' -type f 2>/dev/null | head -1 || true)
legacy_guide="$LEGACY_FIXTURE/project/GitX_Upgrade_Guideline.md"
if [ "$legacy_status" -ne 0 ] \
    && [ -f "$legacy_guide" ] \
    && [ -n "$legacy_log" ] \
    && grep -q 'GitX_Upgrade_Guideline.md' "$legacy_log" \
    && grep -q 'old/1by1-skill-dev/SKILL.md' "$legacy_log" \
    && grep -q 'event=gitx_release_start' "$legacy_log" \
    && grep -q 'exit_code=' "$legacy_log" \
    && grep -q 'Diagnostic log:' "$LEGACY_FIXTURE/stdout.txt"; then
    ok "GitX wrapper logs legacy project guideline failures"
else
    fail "GitX wrapper did not log legacy guideline failure: $(cat "$LEGACY_FIXTURE/stdout.txt")"
fi

if [ "$(tr -d '[:space:]' < "$FAIL_FIXTURE/project/skills/demo-skill/VERSION")" = "v0.0.1" ] \
    && [ "$(tr -d '[:space:]' < "$FAIL_FIXTURE/project/VERSION")" = "v0.0.1" ] \
    && grep -qF 'Stable baseline before failed release.' "$FAIL_FIXTURE/project/Release/CHANGELOG.md" \
    && ! grep -qF '## v0.0.2 ' "$FAIL_FIXTURE/project/Release/CHANGELOG.md"; then
    ok "GitX wrapper rolls back VERSION and CHANGELOG after release failure"
else
    fail "GitX wrapper left bumped VERSION or CHANGELOG after release failure"
fi

POST_FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$FAIL_FIXTURE" "$POST_FIXTURE"' EXIT
mkdir -p \
    "$POST_FIXTURE/project/skills/demo-skill" \
    "$POST_FIXTURE/project/Release" \
    "$POST_FIXTURE/scripts/lib" \
    "$POST_FIXTURE/bin"
cp "$WRAPPER" "$POST_FIXTURE/scripts/gitx-release.sh"
cp "$PROJECT_ROOT/scripts/lib/detect-project.sh" "$POST_FIXTURE/scripts/lib/detect-project.sh"
chmod +x "$POST_FIXTURE/scripts/gitx-release.sh"
cat > "$POST_FIXTURE/scripts/release.sh" <<'EOF'
#!/bin/bash
mkdir -p "$PROJECT_ROOT/Release/project-$1"
exit 0
EOF
chmod +x "$POST_FIXTURE/scripts/release.sh"
cat > "$POST_FIXTURE/project/skills/demo-skill/SKILL.md" <<'EOF'
---
name: demo-skill
description: Demo skill for GitX release post-commit diagnostic failure test.
---
EOF
printf 'v0.0.1\n' > "$POST_FIXTURE/project/skills/demo-skill/VERSION"
printf 'v0.0.1\n' > "$POST_FIXTURE/project/VERSION"
cat > "$POST_FIXTURE/bin/shasum" <<'EOF'
#!/bin/bash
exit 9
EOF
chmod +x "$POST_FIXTURE/bin/shasum"

set +e
env -u PROJECT_NAME -u SKILL_NAME PATH="$POST_FIXTURE/bin:$PATH" PROJECT_ROOT="$POST_FIXTURE/project" bash "$POST_FIXTURE/scripts/gitx-release.sh" --version v0.0.2 > "$POST_FIXTURE/stdout.txt" 2>&1
post_status=$?
set -e
if [ "$post_status" -eq 9 ] \
    && [ "$(tr -d '[:space:]' < "$POST_FIXTURE/project/skills/demo-skill/VERSION")" = "v0.0.2" ] \
    && [ "$(tr -d '[:space:]' < "$POST_FIXTURE/project/VERSION")" = "v0.0.2" ] \
    && grep -qF '## v0.0.2 ' "$POST_FIXTURE/project/Release/CHANGELOG.md"; then
    ok "GitX wrapper does not roll back committed release after post-release diagnostic failure"
else
    fail "GitX wrapper rolled back committed release after post-release diagnostic failure"
fi

DUP_FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$FAIL_FIXTURE" "$POST_FIXTURE" "$DUP_FIXTURE"' EXIT
mkdir -p \
    "$DUP_FIXTURE/project/skills/demo-skill" \
    "$DUP_FIXTURE/project/Release/project-v0.0.2" \
    "$DUP_FIXTURE/scripts/lib"
cp "$WRAPPER" "$DUP_FIXTURE/scripts/gitx-release.sh"
cp "$PROJECT_ROOT/scripts/lib/detect-project.sh" "$DUP_FIXTURE/scripts/lib/detect-project.sh"
chmod +x "$DUP_FIXTURE/scripts/gitx-release.sh"
cat > "$DUP_FIXTURE/scripts/release.sh" <<'EOF'
#!/bin/bash
echo "BUG: release.sh should not be invoked for an already successful version" >&2
exit 66
EOF
chmod +x "$DUP_FIXTURE/scripts/release.sh"
cat > "$DUP_FIXTURE/project/skills/demo-skill/SKILL.md" <<'EOF'
---
name: demo-skill
description: Demo skill for GitX duplicate release guard test.
---
EOF
printf 'v0.0.2\n' > "$DUP_FIXTURE/project/skills/demo-skill/VERSION"
printf 'v0.0.2\n' > "$DUP_FIXTURE/project/VERSION"
ln -sfn project-v0.0.2 "$DUP_FIXTURE/project/Release/latest"

set +e
env -u PROJECT_NAME -u SKILL_NAME PROJECT_ROOT="$DUP_FIXTURE/project" bash "$DUP_FIXTURE/scripts/gitx-release.sh" --version v0.0.2 > "$DUP_FIXTURE/stdout.txt" 2>&1
dup_status=$?
set -e
if [ "$dup_status" -eq 1 ] \
    && grep -q 'already exists' "$DUP_FIXTURE/stdout.txt" \
    && grep -q 'Refusing duplicate release' "$DUP_FIXTURE/stdout.txt" \
    && ! grep -q 'BUG: release.sh should not be invoked' "$DUP_FIXTURE/stdout.txt" \
    && [ -d "$DUP_FIXTURE/project/Release/project-v0.0.2" ] \
    && [ "$(readlink "$DUP_FIXTURE/project/Release/latest")" = "project-v0.0.2" ] \
    && [ "$(tr -d '[:space:]' < "$DUP_FIXTURE/project/skills/demo-skill/VERSION")" = "v0.0.2" ]; then
    ok "GitX wrapper refuses duplicate release before invoking release.sh"
else
    fail "GitX wrapper did not safely refuse duplicate release: $(cat "$DUP_FIXTURE/stdout.txt")"
fi

DANGLING_FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$FAIL_FIXTURE" "$POST_FIXTURE" "$DUP_FIXTURE" "$DANGLING_FIXTURE"' EXIT
mkdir -p \
    "$DANGLING_FIXTURE/project/skills/demo-skill" \
    "$DANGLING_FIXTURE/project/Release" \
    "$DANGLING_FIXTURE/scripts/lib"
cp "$WRAPPER" "$DANGLING_FIXTURE/scripts/gitx-release.sh"
cp "$PROJECT_ROOT/scripts/lib/detect-project.sh" "$DANGLING_FIXTURE/scripts/lib/detect-project.sh"
chmod +x "$DANGLING_FIXTURE/scripts/gitx-release.sh"
cat > "$DANGLING_FIXTURE/scripts/release.sh" <<'EOF'
#!/bin/bash
echo "BUG: release.sh should not be invoked from dangling latest state" >&2
exit 67
EOF
chmod +x "$DANGLING_FIXTURE/scripts/release.sh"
cat > "$DANGLING_FIXTURE/project/skills/demo-skill/SKILL.md" <<'EOF'
---
name: demo-skill
description: Demo skill for GitX dangling latest guard test.
---
EOF
printf 'v0.0.2\n' > "$DANGLING_FIXTURE/project/skills/demo-skill/VERSION"
printf 'v0.0.2\n' > "$DANGLING_FIXTURE/project/VERSION"
ln -sfn project-v0.0.2 "$DANGLING_FIXTURE/project/Release/latest"

set +e
env -u PROJECT_NAME -u SKILL_NAME PROJECT_ROOT="$DANGLING_FIXTURE/project" bash "$DANGLING_FIXTURE/scripts/gitx-release.sh" --version v0.0.2 > "$DANGLING_FIXTURE/stdout.txt" 2>&1
dangling_status=$?
set -e
if [ "$dangling_status" -eq 1 ] \
    && grep -q 'Release/latest already points to project-v0.0.2' "$DANGLING_FIXTURE/stdout.txt" \
    && grep -q 'inconsistent Release/latest state' "$DANGLING_FIXTURE/stdout.txt" \
    && ! grep -q 'BUG: release.sh should not be invoked' "$DANGLING_FIXTURE/stdout.txt" \
    && [ "$(readlink "$DANGLING_FIXTURE/project/Release/latest")" = "project-v0.0.2" ] \
    && [ ! -d "$DANGLING_FIXTURE/project/Release/project-v0.0.2" ]; then
    ok "GitX wrapper refuses same-version release from dangling latest state"
else
    fail "GitX wrapper did not safely refuse dangling latest state: $(cat "$DANGLING_FIXTURE/stdout.txt")"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
