#!/bin/bash
# test_release_modern_path_sanity_input.sh — v1.1.8 hot-patch.
#
# v1.1.7 introduced detect-and-delegate in build_source_tarball: when the
# project ships scripts/scrub-tarball.sh, release.sh uses it (git-archive
# based, deterministic, gitignore-aware). This path `return 0` early
# WITHOUT setting STAGE / STAGE_SUB.
#
# But the next step in the pipeline — run_sanity_scans (line 490) — reads
# `$STAGE_SUB` directly. Under `set -euo pipefail`, this is an unbound
# variable abort the moment scrub-tarball path is taken.
#
# Effect: any project that vendors scripts/scrub-tarball.sh (1by1 v0.5+,
# any future cure adopter) cannot release. Self-bake of git_release_skill
# itself does NOT hit this because git_release_skill ships no scrub-tarball.sh
# (intentional: it's a project-level opt-in, not a skill-level dep).
#
# Fix: build_source_tarball modern path must satisfy the same downstream
# contract as legacy fallback — populate STAGE / STAGE_SUB / SKILL_STAGE.
# Cleanest: extract the just-built tarball back into STAGE so sanity scan
# sees the actual ship content. Register STAGE in CLEANUP_EXTRAS to avoid
# /tmp/ leak.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_release_modern_path_sanity_input.sh ══"

# === Static 1: modern scrub-tarball path sets STAGE_SUB before return ===
# Slice from `if [ -x "$PROJECT_SCRUB" ]` to the first `return 0` after.
MODERN_BLOCK=$(awk '/if \[ -x "\$PROJECT_SCRUB" \]/,/return 0/' "$RELEASE_SH")
if echo "$MODERN_BLOCK" | grep -qE 'STAGE_SUB='; then
    ok "modern scrub-tarball path assigns STAGE_SUB before return"
else
    fail "modern path returns without setting STAGE_SUB — run_sanity_scans aborts under set -u"
fi

# === Static 2: modern path also sets STAGE (parent dir, needed by tar -xzf -C) ===
if echo "$MODERN_BLOCK" | grep -qE '^[[:space:]]*STAGE=\$\(mktemp'; then
    ok "modern path creates STAGE via mktemp before return"
else
    fail "modern path missing STAGE=\$(mktemp -d) — tarball cannot be extracted for scan"
fi

# === Static 3: modern path also sets SKILL_STAGE (legacy parity) ===
if echo "$MODERN_BLOCK" | grep -qE 'SKILL_STAGE='; then
    ok "modern path assigns SKILL_STAGE (legacy parity for run_sanity_scans)"
else
    fail "modern path missing SKILL_STAGE — run_sanity_scans .skill stage logic broken"
fi

# === Static 4: modern path extracts tarball into STAGE so scan sees real content ===
# Either tar -xzf the just-built tarball, or rsync project content; tar is preferred
# (matches what's actually shipped).
if echo "$MODERN_BLOCK" | grep -qE 'tar .*-xz?f.*TAR_OUT|tar -xz.*-C "?\$STAGE'; then
    ok "modern path extracts \$TAR_OUT into \$STAGE for sanity scan input"
else
    fail "modern path does not populate \$STAGE with tarball content — scan has nothing to scan"
fi

# === Static 5: modern path registers STAGE in CLEANUP_EXTRAS (no /tmp/ leak) ===
if echo "$MODERN_BLOCK" | grep -qE 'CLEANUP_EXTRAS\+?=\("?\$STAGE'; then
    ok "modern path registers STAGE in CLEANUP_EXTRAS (no /tmp leak)"
else
    fail "modern path leaks STAGE in /tmp/ — fix introduces a new mktemp leak"
fi

# === Behavioral: dry-run release.sh on a fixture project that ships
# scrub-tarball.sh — must NOT abort, must complete sanity scan stage ===
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/skills/demo-skill" "$FIXTURE/scripts" "$FIXTURE/Release"
# Vendor a no-op scrub-tarball.sh that just creates an empty tarball
cat > "$FIXTURE/scripts/scrub-tarball.sh" <<'EOF'
#!/bin/bash
# Fake scrub-tarball.sh for test fixture: write minimal valid tarball.
OUT="$1"
PREFIX="$2"
mkdir -p "/tmp/.scrub_fixture/$PREFIX"
echo "fake-content" > "/tmp/.scrub_fixture/$PREFIX/README.md"
( cd "/tmp/.scrub_fixture" && tar -czf "$OUT" "$PREFIX" )
rm -rf "/tmp/.scrub_fixture"
exit 0
EOF
chmod +x "$FIXTURE/scripts/scrub-tarball.sh"
# Init real git repo so `git -C ... rev-parse --git-dir` succeeds
( cd "$FIXTURE" && git init -q 2>/dev/null && git add -A && \
  git -c user.email=t@t -c user.name=t commit -qm init 2>/dev/null ) || true
cat > "$FIXTURE/skills/demo-skill/SKILL.md" <<'EOF'
---
name: demo-skill
description: Demo for hot-patch test.
---
EOF
printf 'v0.0.1\n' > "$FIXTURE/skills/demo-skill/VERSION"
printf 'v0.0.1\n' > "$FIXTURE/VERSION"

# Slice build_source_tarball + run_sanity_scans into a self-contained script
SLICE=$(mktemp)
{
    echo '#!/bin/bash'
    echo 'set -euo pipefail'
    echo "PROJECT_ROOT='$FIXTURE'"
    echo "PROJECT_NAME=demo-skill"
    echo "SKILL_NAME=demo-skill"
    echo "VERSION=v0.0.1"
    echo "RELEASE_DIR='$FIXTURE/Release/demo-skill-v0.0.1'"
    echo "DRY_RUN=0"
    echo "SKILL_ROOT='$ROOT/scripts'"
    echo 'CLEANUP_EXTRAS=()'
    echo 'mkdir -p "$RELEASE_DIR"'
    echo 'run() { "$@"; }'
    sed -n '/^build_source_tarball()/,/^}$/p' "$RELEASE_SH"
    echo 'build_source_tarball'
    echo 'echo "STAGE_SUB after build = ${STAGE_SUB:-UNSET}"'
} > "$SLICE"

# Run the slice and check exit + STAGE_SUB defined
if bash "$SLICE" > "$FIXTURE/out.txt" 2>&1; then
    if grep -q 'STAGE_SUB after build = .*demo-skill-v0.0.1' "$FIXTURE/out.txt"; then
        ok "behavior: build_source_tarball returns with STAGE_SUB set (modern path)"
    else
        fail "behavior: STAGE_SUB unset/wrong after modern path: $(grep STAGE_SUB "$FIXTURE/out.txt")"
    fi
else
    fail "behavior: build_source_tarball aborts on modern path: $(tail -3 "$FIXTURE/out.txt" | tr '\n' ' | ')"
fi
rm -f "$SLICE"

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
