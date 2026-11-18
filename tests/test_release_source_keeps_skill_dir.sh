#!/bin/bash
# test_release_source_keeps_skill_dir.sh — the public source tarball of a
# root-SKILL.md project keeps skills/<name>/ (and only it), and the Deep
# Audit guards that layout.
# Why: Codex plugins discover skills only under a plugin's skills/ dir, and
# the source tarball becomes the public GitHub main that Codex installs from.
# exit: 0 all pass, 1 any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== test_release_source_keeps_skill_dir.sh ==="

FIX=$(mktemp -d)
FAKE_HOME=$(mktemp -d)
WORK=$(mktemp -d)
trap 'rm -rf "$FIX" "$FAKE_HOME" "$WORK"' EXIT

VERSION="v0.0.1"
SKILL="demo"
PROJ="demo-proj"

# ── Fixture: root SKILL.md + skills/demo/ + skills/other/ + skills/demo-workspace/
mkdir -p "$FIX/skills/$SKILL/references" "$FIX/skills/$SKILL/assets" \
         "$FIX/skills/$SKILL/agents" "$FIX/skills/$SKILL/scripts/lib" \
         "$FIX/skills/other" "$FIX/skills/${SKILL}-workspace" \
         "$FIX/scripts/lib" "$FIX/tests" "$FIX/Release"
printf '# References\n\nPlaceholder.\n\nLine 4.\n\nLine 6.\n' > "$FIX/skills/$SKILL/references/README.md"
printf '# Assets\n\nNo binary assets.\n' > "$FIX/skills/$SKILL/assets/README.md"
printf '%s\n' "\$$SKILL" > "$FIX/skills/$SKILL/agents/codex-commands.txt"
{
    printf -- '---\nname: %s\ndescription: Root-layout fixture skill for source tarball tests.\n---\n' "$SKILL"
    printf '# Demo\n\n## When to Trigger\n\nUse for tests.\n\n## Steps / Execution Flow\n\n'
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '%s. Step %s\n' "$i" "$i"; done
} > "$FIX/skills/$SKILL/SKILL.md"
cp "$FIX/skills/$SKILL/SKILL.md" "$FIX/SKILL.md"
printf '%s\n' "$VERSION" > "$FIX/skills/$SKILL/VERSION"
printf -- '---\nname: other\ndescription: Another skill that must not ship.\n---\n# Other\n' > "$FIX/skills/other/SKILL.md"
printf 'scratch eval output\n' > "$FIX/skills/${SKILL}-workspace/notes.txt"

printf '#!/bin/bash\n# Minimal test runner stub.\necho "Tests: 0 suites"\nexit 0\n' > "$FIX/tests/run_all.sh"
chmod +x "$FIX/tests/run_all.sh"
printf '# Demo — Release History\n\n## %s — 2026-01-01\n\nInitial fixture release.\n\n---\n' "$VERSION" > "$FIX/Release/CHANGELOG.md"
printf '# Demo\n\nFixture.\n\n## Installation\n\nRun `./install.sh`.\n\n## Usage / Quick Start\n\nUse it.\n\n## Contributing\n\nSee CONTRIBUTING.md.\n\n## License\n\nMIT\n' > "$FIX/README.md"
printf '# Test Scenarios\n\n## Scenario 1\n\nInstall.\n\n## Scenario 2\n\nVersion.\n' > "$FIX/TEST-SCENARIOS.md"
printf '# Install\n\n## Requirements\n\n- Claude Code\n\n## Install steps\n\n./install.sh\n\n## Uninstall\n\nRemove.\n\n## Upgrade / Update\n\nRe-run with --force.\n' > "$FIX/INSTALL.md"
cat > "$FIX/install.sh" <<'EOF'
#!/bin/bash
# install.sh — fixture install stub
# usage: ./install.sh [--dry-run] [--force] [--help]
set -euo pipefail
for arg in "$@"; do
    case "$arg" in
        --dry-run) echo "[dry-run] would install"; exit 0 ;;
        --help)    echo "Usage: $0 [--dry-run] [--force] [--help]"; exit 0 ;;
    esac
done
echo "Fixture install.sh executed."
EOF
chmod +x "$FIX/install.sh"
printf 'MIT License\n\nCopyright (c) 2026 Fixture Author\n\nPermission is hereby granted, free of charge, to any person obtaining a copy\nof this software, to deal in the Software without restriction.\n' > "$FIX/LICENSE"
printf '# Contributing\n\n## Development\n\nRun tests.\n\n## Pull Request / Commit Conventions\n\n- Conventional commits.\n' > "$FIX/CONTRIBUTING.md"

for s in release-sanitize.sh scan-credentials.sh release-audit.sh emit-sbom.sh emit-token-usage.sh; do
    cp "$REAL/scripts/$s" "$FIX/scripts/"
done
cp "$REAL/scripts/lib/detect-project.sh" "$FIX/scripts/lib/"
chmod +x "$FIX/scripts/"*.sh
# Dual-source mirror: skills/<name>/scripts/ must equal scripts/ byte-for-byte.
cp "$FIX/scripts/"*.sh "$FIX/skills/$SKILL/scripts/"
cp "$FIX/scripts/lib/detect-project.sh" "$FIX/skills/$SKILL/scripts/lib/"

# ── a. full release.sh run → tarball layout ─────────────────────────────────
echo "-- a. release.sh source tarball keeps only skills/$SKILL/"
set +e
out=$(HOME="$FAKE_HOME" PROJECT_ROOT="$FIX" PROJECT_NAME="$PROJ" SKILL_NAME="$SKILL" \
      bash "$REAL/scripts/release.sh" "$VERSION" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
    ok "release.sh exits 0 on root-layout fixture"
else
    fail "release.sh exited $rc"
    grep '❌' <<<"$out" | head -20 | sed 's/^/     /' || true
    tail -15 <<<"$out" | sed 's/^/     /'
fi

RD="$FIX/Release/${PROJ}-${VERSION}"
TAR="$RD/${PROJ}-${VERSION}-source.tar.gz"
LIST=$(tar tzf "$TAR" 2>/dev/null || true)
P="${PROJ}-${VERSION}"
grep -qxF "$P/skills/$SKILL/SKILL.md" <<<"$LIST" \
    && ok "tarball has skills/$SKILL/SKILL.md" || fail "tarball lacks skills/$SKILL/SKILL.md"
grep -q "^$P/skills/$SKILL/scripts/" <<<"$LIST" \
    && ok "tarball has skills/$SKILL/scripts/" || fail "tarball lacks skills/$SKILL/scripts/"
grep -qxF "$P/SKILL.md" <<<"$LIST" \
    && ok "tarball still has root SKILL.md" || fail "tarball lost root SKILL.md"
grep -q "^$P/skills/other" <<<"$LIST" \
    && fail "tarball ships skills/other" || ok "tarball has no skills/other"
grep -q "^$P/skills/${SKILL}-workspace" <<<"$LIST" \
    && fail "tarball ships skills/${SKILL}-workspace" || ok "tarball has no skills/${SKILL}-workspace"

# ── b. standalone audit: PASS as built; FAIL once skills/demo/SKILL.md is gone
echo "-- b. standalone release-audit.sh guards the layout"
run_audit() {
    HOME="$FAKE_HOME" PROJECT_ROOT="$FIX" PROJECT_NAME="$PROJ" SKILL_NAME="$SKILL" \
        bash "$FIX/scripts/release-audit.sh" "$VERSION" 2>&1
}
set +e
aout=$(run_audit); arc=$?
set -e
if [ "$arc" -eq 0 ]; then
    ok "standalone audit passes on the built release"
else
    fail "standalone audit exited $arc on the built release"
    grep '❌' <<<"$aout" | head -20 | sed 's/^/     /' || true
fi

[ -f "$TAR" ] && cp "$TAR" "$WORK/orig.tar.gz"
# $1 = shell snippet run inside the extracted tree; $2 = expected ❌ title.
tamper_and_audit() {
    rm -rf "$WORK/x"; mkdir -p "$WORK/x"
    tar xzf "$WORK/orig.tar.gz" -C "$WORK/x"
    (cd "$WORK/x/$P" && eval "$1")
    (cd "$WORK/x" && tar czf "$TAR" "$P")
    # Re-hash so the audit fails on layout, not on a checksum mismatch.
    : > "$WORK/chk"
    while read -r _h name; do
        (cd "$RD" && shasum -a 256 "$name") >> "$WORK/chk"
    done < "$RD/checksums.txt"
    cp "$WORK/chk" "$RD/checksums.txt"
    local tout trc
    set +e
    tout=$(run_audit); trc=$?
    set -e
    if [ "$trc" -ne 0 ] && grep -qF "❌ $2" <<<"$tout"; then
        ok "audit FAILs: $2 (after: $1)"
    else
        fail "audit did not flag '$2' (rc=$trc, after: $1)"
        grep '❌' <<<"$tout" | head -20 | sed 's/^/     /' || true
    fi
}
if [ -f "$WORK/orig.tar.gz" ]; then
    tamper_and_audit "rm -f skills/$SKILL/SKILL.md" "含 SKILL.md (root + skills/$SKILL/)"
    tamper_and_audit "mkdir -p skills/other && printf 'x\n' > skills/other/SKILL.md" "不含 *-workspace / 其他 skills/*"
else
    fail "no source tarball to tamper with"
fi

# ── c. root SKILL.md, no skills/: rsync staging segment alone succeeds ───────
echo "-- c. rsync staging without skills/ (function boundary)"
SEG="$WORK/seg.sh"
awk '/^    SKILL_EXCLUDE=\(\)$/{p=1} p{print} p && /"\$PROJECT_ROOT\/" "\$STAGE_SUB\/"/{exit}' \
    "$REAL/scripts/release.sh" > "$SEG"
LEG="$WORK/legacy"
mkdir -p "$LEG/scripts"
cp "$FIX/SKILL.md" "$FIX/README.md" "$LEG/"
printf '#!/bin/bash\n' > "$LEG/scripts/tool.sh"
STG="$WORK/stage"
mkdir -p "$STG"
if [ ! -s "$SEG" ]; then
    fail "could not extract the rsync staging segment from release.sh"
elif PROJECT_ROOT="$LEG" STAGE_SUB="$STG" PROJECT_NAME="$PROJ" SKILL_NAME="$SKILL" \
     bash -c 'set -euo pipefail; run() { "$@"; }; . "$1"' _ "$SEG"; then
    if [ -f "$STG/SKILL.md" ] && [ -f "$STG/scripts/tool.sh" ] && [ ! -e "$STG/skills" ]; then
        ok "staging succeeds without skills/ and stages root files"
    else
        fail "staging ran but staged tree is wrong"
    fi
else
    fail "rsync staging segment errored on a project without skills/"
fi

echo ""
echo "Results: ✅$PASS / ❌$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
