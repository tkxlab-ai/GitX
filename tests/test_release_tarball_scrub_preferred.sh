#!/bin/bash
# test_release_tarball_scrub_preferred.sh — v1.1.7 hardening (Gotcha #33).
#
# `scripts/release.sh:build_source_tarball` was strengthened in commit
# `3e55e14` to prefer the project's own `scripts/scrub-tarball.sh`
# (git-archive-based, .gitattributes export-ignore honoured) when present
# and falls back to the legacy rsync-staging mode otherwise. The original
# commit shipped without TDD coverage; this test pins both branches.
#
# Why the scrub path matters: rsync staging does NOT honour .gitignore /
# .gitattributes, so private dirs like .planning/ and .archive/ leaked into
# the source tarball on three consecutive 1by1 releases (v0.5.3, v0.6.0,
# v0.6.1). The scrub-tarball.sh path eliminates the class of bug — but a
# silent fallback to rsync would silently re-introduce the leak. The
# functional cases below assert which branch fires under which conditions.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_release_tarball_scrub_preferred.sh ══"

# ── Static 1: scrub-tarball.sh preferred-path block exists ───────────────
if grep -qE 'PROJECT_SCRUB="\$PROJECT_ROOT/scripts/scrub-tarball\.sh"' "$RELEASE_SH"; then
    ok "PROJECT_SCRUB points at \$PROJECT_ROOT/scripts/scrub-tarball.sh"
else
    fail "PROJECT_SCRUB missing or pointing at wrong path"
fi

# ── Static 2: branch guarded by both -x test AND git-repo check ───────────
# Both must be true to take the new path. Either alone would be unsafe.
if grep -qE 'if \[ -x "\$PROJECT_SCRUB" \] && git -C "\$PROJECT_ROOT" rev-parse --git-dir' "$RELEASE_SH"; then
    ok "scrub-path guarded by both executable test AND git-repo check"
else
    fail "scrub-path guard malformed (must require both -x AND git-repo)"
fi

# ── Static 3: dry-run mode of new path emits a marker line ─────────────────
# Without dry-run support inside the new branch, dry-run would silently
# invoke the real scrub script — that's a real foot-gun.
if awk '/PROJECT_SCRUB="\$PROJECT_ROOT\/scripts\/scrub-tarball\.sh"/,/^    fi$/' "$RELEASE_SH" \
        | grep -qE '\[dry-run\]'; then
    ok "scrub-path branch has [dry-run] marker (no accidental execution)"
else
    fail "scrub-path branch missing [dry-run] guard"
fi

# ── Static 4: rsync fallback STILL exists below the scrub branch ──────────
# Removing the fallback would break every project that doesn't ship
# scrub-tarball.sh, including this very repo. The fallback is mandatory.
if awk '/^build_source_tarball\(\)/,/^\}/' "$RELEASE_SH" \
        | grep -qE 'Staging source.*rsync mode'; then
    ok "rsync fallback path preserved with explicit 'rsync mode' marker"
else
    fail "rsync fallback path appears removed or marker missing"
fi

# ── Static 5: scrub-path returns 0 explicitly so fallback is NOT reached ──
# A missing return would let control fall through into rsync, double-baking
# the tarball. The new branch must return 0 immediately after success.
if awk '/PROJECT_SCRUB="\$PROJECT_ROOT\/scripts\/scrub-tarball\.sh"/,/^    fi$/' "$RELEASE_SH" \
        | grep -qE '^[[:space:]]+return 0$'; then
    ok "scrub-path returns 0 — no fall-through into rsync"
else
    fail "scrub-path missing 'return 0' — risks double-baking tarball"
fi

# ── Static 6: history comment cites the 1by1 motivation ───────────────────
# Documents WHY this fix exists. Without the why, future readers will
# wonder if the rsync fallback can be removed (it cannot — only projects
# with scrub-tarball.sh are immune to the leak class).
if awk '/PROJECT_SCRUB="\$PROJECT_ROOT\/scripts\/scrub-tarball\.sh"/,/^    fi$/' "$RELEASE_SH" \
        | grep -qE '1by1' \
   || grep -B 12 'PROJECT_SCRUB="\$PROJECT_ROOT/scripts/scrub-tarball\.sh"' "$RELEASE_SH" \
        | grep -qE '1by1'; then
    ok "scrub-path retains '1by1' historical context comment"
else
    fail "scrub-path missing 1by1 historical comment — future readers will lose context"
fi

# ── Behavioral: planted scrub fixture is invoked by dry-run ────────────────
# Build a minimal fixture project: git-tracked, has scripts/scrub-tarball.sh.
# Run release.sh --dry-run; assert the marker line for the scrub path
# appears and the rsync-mode marker does NOT.
FIX_SCRUB=$(mktemp -d)
trap 'rm -rf "$FIX_SCRUB" "${FIX_NO_SCRUB:-}"' EXIT

cd "$FIX_SCRUB"
git init -b main -q
git config user.email "t@t" && git config user.name "t"

mkdir -p scripts skills/dummy/scripts tests
cat > skills/dummy/SKILL.md <<'EOF'
---
name: dummy
description: A test fixture skill.
---
# dummy
EOF
echo "v0.1.1" > VERSION
echo "v0.1.1" > skills/dummy/VERSION

cat > scripts/scrub-tarball.sh <<'EOF'
#!/bin/bash
# Stub scrub script — should be invoked by the new path when conditions met.
echo "STUB SCRUB INVOKED"
exit 0
EOF
chmod +x scripts/scrub-tarball.sh

# Match dual-source so check_dual_source() does not abort before we reach
# build_source_tarball. We're not testing dual-source here, so make it a
# trivial pass.
for f in scan-credentials.sh release-sanitize.sh release.sh release-audit.sh; do
    : > "scripts/$f"
    : > "skills/dummy/scripts/$f"
done

# Minimal CHANGELOG so release.sh CHANGELOG gate doesn't abort early.
cat > CHANGELOG.md <<'EOF'
# Changelog
## v0.1.1 — 2026-05-07
- placeholder
EOF
mkdir -p Release
cp CHANGELOG.md Release/CHANGELOG.md

# Minimal tests/run_all.sh that does nothing.
cat > tests/run_all.sh <<'EOF'
#!/bin/bash
echo "Suite Results: ✅0 suites passed / ❌0 suites failed"
exit 0
EOF
chmod +x tests/run_all.sh

git add -A && git commit -q -m "fixture"

# Run release.sh in dry-run mode. Capture stdout for marker scan. We accept
# any exit code — release.sh runs many phases and may abort before
# build_source_tarball under this minimal fixture; what matters is whether
# the scrub-path marker appeared BEFORE the abort.
out_scrub=$(env -u PROJECT_NAME -u SKILL_NAME PROJECT_ROOT="$FIX_SCRUB" \
    bash "$RELEASE_SH" --dry-run v0.1.1 2>&1 || true)

if echo "$out_scrub" | grep -qE 'Building source tarball via .*scrub-tarball\.sh'; then
    ok "fixture WITH scrub-tarball.sh — new path marker appeared in dry-run"
else
    fail "fixture WITH scrub-tarball.sh — new path NOT taken (got rsync fallback or aborted earlier)"
fi

if echo "$out_scrub" | grep -qE 'Staging source.*rsync mode'; then
    fail "fixture WITH scrub-tarball.sh — rsync fallback fired (should not)"
else
    ok "fixture WITH scrub-tarball.sh — rsync fallback did NOT fire (correct)"
fi

# ── Behavioral: fixture WITHOUT scrub-tarball.sh — rsync fallback fires ───
FIX_NO_SCRUB=$(mktemp -d)
cd "$FIX_NO_SCRUB"
git init -b main -q
git config user.email "t@t" && git config user.name "t"

mkdir -p scripts skills/dummy/scripts tests
cat > skills/dummy/SKILL.md <<'EOF'
---
name: dummy
description: A test fixture skill.
---
# dummy
EOF
echo "v0.1.1" > VERSION
echo "v0.1.1" > skills/dummy/VERSION

# NOTE: deliberately NO scripts/scrub-tarball.sh here.

for f in scan-credentials.sh release-sanitize.sh release.sh release-audit.sh; do
    : > "scripts/$f"
    : > "skills/dummy/scripts/$f"
done

cat > CHANGELOG.md <<'EOF'
# Changelog
## v0.1.1 — 2026-05-07
- placeholder
EOF
mkdir -p Release
cp CHANGELOG.md Release/CHANGELOG.md

cat > tests/run_all.sh <<'EOF'
#!/bin/bash
echo "Suite Results: ✅0 suites passed / ❌0 suites failed"
exit 0
EOF
chmod +x tests/run_all.sh

git add -A && git commit -q -m "fixture-nogprotect"

out_no_scrub=$(env -u PROJECT_NAME -u SKILL_NAME PROJECT_ROOT="$FIX_NO_SCRUB" \
    bash "$RELEASE_SH" --dry-run v0.1.1 2>&1 || true)

if echo "$out_no_scrub" | grep -qE 'Staging source.*rsync mode'; then
    ok "fixture WITHOUT scrub-tarball.sh — rsync fallback marker appeared (correct)"
else
    fail "fixture WITHOUT scrub-tarball.sh — rsync fallback NOT taken (or pipeline aborted earlier)"
fi

if echo "$out_no_scrub" | grep -qE 'Building source tarball via .*scrub-tarball\.sh'; then
    fail "fixture WITHOUT scrub-tarball.sh — new path fired (impossible: file absent)"
else
    ok "fixture WITHOUT scrub-tarball.sh — new path correctly did NOT fire"
fi

cd "$ROOT"
echo ""; echo "─── $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
