#!/bin/bash
# test_rebrand_single_canonical_name.sh — v1.1.0 BDD acceptance test
#
# SCENARIO: After the v1.1.0 rebrand, exactly one canonical name —
# `gitx-release` — is used everywhere in the project. The old name
# `git-release-pipeline` no longer appears in any path-meaningful
# position; it survives only inside CHANGELOG history, archived
# Gotchas, and deprecated-alias notes.
#
# This test was written FIRST (TDD RED) before the rename began. When
# the rename is complete, every assertion below must be GREEN.
#
# Why lowercase `gitx-release` (not `GitX-Release`):
#   macOS HFS+ is case-insensitive. `GitX-Release/` and `gitx-release/`
#   collide on default macOS filesystems (Decision 2026-04-30, Gotcha #16).
#   The "GitX-Release" brand survives in human-readable doc titles +
#   descriptions; the canonical filesystem identifier is lowercase.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_rebrand_single_canonical_name.sh ══"

# Allow-list of files where the legacy name MAY still appear:
#   - Release/CHANGELOG.md & CHANGELOG.md (history; v1.0.x entries)
#   - Release/git_release_skill-v*/                 (frozen historical artifacts)
#   - HANDOFF.md / HANDOFF.archive.md               (gitignored, history)
#   - tests/test_rebrand_single_canonical_name.sh   (this file references the old name in comments)
#   - agents/codex-commands.txt (deprecated-alias)  (must mark $git-release-pipeline as deprecated)

is_allowed_legacy_path() {
    local p="$1"
    case "$p" in
        ./CHANGELOG.md|*/CHANGELOG.md) return 0 ;;
        ./Release/git_release_skill-v*|./Release/gitx-release-v*) return 0 ;;
        ./HANDOFF.md|./HANDOFF.archive.md) return 0 ;;
        # handoff v2 four-piece + pre-v2 backup: internal user-level work
        # memory (same class as HANDOFF.md), legitimately preserves the
        # project's historical name; never shipped to the public mirror.
        ./HANDOFF.md.pre-v2-backup|./HANDOFF.md.bak) return 0 ;;
        ./GOTCHAS.md|./Handoff_Logs/*|./Handoff_Decisions/*|./Handoff_Logs.archive/*) return 0 ;;
        ./tests/test_rebrand_single_canonical_name.sh) return 0 ;;
        # gitignored cache / private dirs — never tracked, never shipped.
        # .github-publish-wt: the gitx-sop per-release publish worktree
        # (own .git → public mirror only); it holds an extracted source
        # snapshot that legitimately carries the project name. Transient,
        # gitignored, never in the private repo nor any tarball.
        ./.i18n-cache/*|./.omc/*|./.cache/*|./memory/*|./.github-publish-wt/*) return 0 ;;
        # graphify knowledge graph + local Claude instruction: gitignored,
        # release-excluded, never shipped. GRAPH_REPORT.md is regenerated
        # from Handoff_* history that legitimately preserves the legacy
        # name — same defensive class as .github-publish-wt (five-facet
        # symmetric parity; never tracked, never in any tarball).
        ./graphify-out/*|./CLAUDE.md) return 0 ;;
        # gitignored Syncthing conflict quarantine — pre-3e55e14 snapshots
        # of CHANGELOG.md / VERSION / release.sh that may legitimately
        # reference the legacy name in their preserved historical content.
        ./.syncthing-quarantine-*/*) return 0 ;;
        # mac-release sibling-skill design docs reference the legacy name
        # when describing inherited Gotchas + the migration history. These
        # docs are reference material, not live config.
        ./docs/superpowers/specs/*|./docs/superpowers/plans/*) return 0 ;;
        # gitignored personal review notes — not in git, not shipped
        ./REVIEW.md|./GitHub_STANDARD_ANALYSIS.md) return 0 ;;
        # install.sh + codex-commands.txt INTENTIONALLY mention the legacy
        # name — install.sh for cleanup of prior installs, codex-commands.txt
        # for the deprecated-alias grace period.
        ./install.sh) return 0 ;;
        */agents/codex-commands.txt) return 0 ;;
        # INSTALL.md documents the user-facing migration path: legacy
        # paths to delete during uninstall + deprecated-alias note. The
        # legacy name appears as deletion targets, not as live config.
        ./INSTALL.md) return 0 ;;
        # agents/README.md documents the deprecated-alias sunset plan
        # (5th-pass review #4 moved the documentation out of the
        # codex-commands.txt to avoid Codex parser risk on `#`-comment lines).
        */agents/README.md) return 0 ;;
        # Tests that verify the deprecated-alias contract on codex-commands.txt
        # legitimately mention $git-release-pipeline (the alias name).
        ./tests/test_codex_skill_metadata.sh) return 0 ;;
        ./tests/test_install_sh_runtime.sh) return 0 ;;
        ./tests/test_audit_codex_command_selectors.sh) return 0 ;;
        # Boss-signed bilingual README templates deliberately document
        # $git-release-pipeline as the deprecated Codex selector alias
        # (the inline comment reads: "deprecated alias of $gitx-release;
        # codex-commands.txt only — not a slash command"). This is a
        # documented-legacy reference, not a live path/identifier.
        ./references/readme/README.template.md) return 0 ;;
        ./references/readme/README_CN.template.md) return 0 ;;
        ./skills/gitx-release/references/readme/README.template.md) return 0 ;;
        ./skills/gitx-release/references/readme/README_CN.template.md) return 0 ;;
    esac
    return 1
}

# ── Test 1: skill folder renamed to gitx-release (root + bundle) ──
if [ -d "$ROOT/skills/gitx-release" ]; then
    ok "skills/gitx-release/ exists (canonical bundle path)"
else
    fail "skills/gitx-release/ missing — folder not renamed"
fi
if [ -d "$ROOT/skills/git-release-pipeline" ]; then
    fail "skills/git-release-pipeline/ still exists — old folder not removed"
else
    ok "skills/git-release-pipeline/ removed"
fi

# ── Test 2: SKILL.md frontmatter name field is gitx-release ──
for skill_md in "$ROOT/SKILL.md" "$ROOT/skills/gitx-release/SKILL.md"; do
    [ -f "$skill_md" ] || continue
    name_field=$(awk '/^---$/{c++; next} c==1 && /^name:/{print $2; exit}' "$skill_md")
    if [ "$name_field" = "gitx-release" ]; then
        ok "$(basename "$(dirname "$skill_md")")/SKILL.md name: gitx-release"
    else
        fail "$skill_md name: '$name_field' (expected 'gitx-release')"
    fi
done

# ── Test 3: install.sh installs to ~/.agents/skills/gitx-release/ ──
if grep -qE 'SKILL_NAME="gitx-release"|SKILL_NAME=gitx-release' "$ROOT/install.sh"; then
    ok "install.sh SKILL_NAME=gitx-release"
else
    fail "install.sh still uses git-release-pipeline as SKILL_NAME"
fi

# ── Test 4: slash command shim removed (no commands/*.md) ──
if [ -f "$ROOT/commands/GitX-release.md" ] || [ -f "$ROOT/commands/gitx-release.md" ]; then
    fail "commands/ still ships a slash command shim — should be removed (skill auto-promotion handles it)"
else
    ok "commands/ slash command shim removed"
fi

# ── Test 5: Codex commands manifest uses $gitx-release as primary ──
codex_manifest="$ROOT/agents/codex-commands.txt"
if [ -f "$codex_manifest" ]; then
    if head -1 "$codex_manifest" | grep -qE '^\$gitx-release$'; then
        ok "agents/codex-commands.txt: \$gitx-release is first/primary alias"
    else
        fail "agents/codex-commands.txt: \$gitx-release not first; got: $(head -1 "$codex_manifest")"
    fi
    if grep -qE '^\$git-release-pipeline$' "$codex_manifest"; then
        # Codex parses codex-commands.txt as a flat selector list — comments
        # are not safe inside it (5th-pass review #4). The deprecation
        # contract is documented in agents/README.md instead.
        readme="$ROOT/agents/README.md"
        if [ -f "$readme" ] && grep -qiE 'deprecat|sunset|v1\.2\.0' "$readme"; then
            ok "legacy \$git-release-pipeline retained, deprecation documented in agents/README.md"
        else
            fail "legacy \$git-release-pipeline alias kept without deprecation documentation"
        fi
    else
        ok "legacy \$git-release-pipeline alias removed entirely"
    fi
fi

# ── Test 6: no source file outside the allow-list contains 'git-release-pipeline' ──
violators=()
while IFS= read -r f; do
    is_allowed_legacy_path "$f" && continue
    violators+=("$f")
done < <(grep -rl "git-release-pipeline" \
            --include='*.sh' --include='*.md' --include='*.txt' --include='*.yaml' \
            "$ROOT" 2>/dev/null \
          | sed "s|^$ROOT|.|")
if [ "${#violators[@]}" -eq 0 ]; then
    ok "no non-allowed source files reference legacy 'git-release-pipeline'"
else
    fail "${#violators[@]} files still reference legacy 'git-release-pipeline':"
    printf '       %s\n' "${violators[@]}" | head -10
fi

# ── Test 7: brand is "GitX" (v1.7.0 pure-brand rename) ──
# Canonical filesystem id stays lowercase `gitx-release` (Test 2); the
# human-readable brand collapsed from "GitX-Release"/"Git Release Pipeline"
# to just "GitX". Assert: new brand present ≥2 in README+SKILL AND the old
# "GitX-Release" / "GitX Release" / "Git Release Pipeline" brand strings are
# gone from those two doc surfaces.
# pipefail-safe (Gotcha #36): grep exits 1 on no-match; wrap with || true so
# the pipeline never aborts this set -euo pipefail script.
brand_count=$( { grep -hoE '(^|[^a-z./$-])GitX([^A-Za-z-]|$)' "$ROOT/README.md" "$ROOT/SKILL.md" 2>/dev/null || true; } | wc -l | tr -d ' ')
old_brand=$( { grep -hoE 'GitX[ -]Release|Git Release Pipeline' "$ROOT/README.md" "$ROOT/SKILL.md" 2>/dev/null || true; } | wc -l | tr -d ' ')
if [ "$brand_count" -ge 2 ] && [ "$old_brand" -eq 0 ]; then
    ok "brand is 'GitX' in README.md + SKILL.md ($brand_count occurrences, 0 legacy brand)"
else
    fail "brand contract: GitX count=$brand_count (want ≥2), legacy brand count=$old_brand (want 0)"
fi

# ── Test 8: VERSION at v1.1.0 or later (post-rebrand baseline) ──
# The rebrand landed in v1.1.0; subsequent v1.1.x patch bumps still satisfy
# the post-rebrand contract. Reject anything earlier than v1.1.0.
ver=$(cat "$ROOT/VERSION")
case "$ver" in
    v1.1.[0-9]*|v1.1[0-9].*|v1.[2-9].*|v[2-9].*)
        ok "VERSION is $ver (>= v1.1.0 post-rebrand baseline)"
        ;;
    *)
        fail "VERSION = $ver (expected v1.1.0 or later for post-rebrand)"
        ;;
esac
if [ -f "$ROOT/skills/gitx-release/VERSION" ]; then
    bundle_ver=$(cat "$ROOT/skills/gitx-release/VERSION")
    [ "$bundle_ver" = "$ver" ] && ok "bundle VERSION matches root: $bundle_ver" \
                              || fail "bundle VERSION ($bundle_ver) != root VERSION ($ver)"
fi

# ── Test 9: dual-source byte-identity (post-rename invariant still holds) ──
# v1.4.0: --exclude __pycache__ — Python writes bytecode cache when vendored
# scripts/vendored/skill-creator/scripts/*.py is imported. The cache is
# transient + machine-specific and not part of distribution (release.sh
# also sets PYTHONDONTWRITEBYTECODE=1 to prevent regeneration, but stale
# caches from earlier runs may persist).
if [ -d "$ROOT/skills/gitx-release/scripts" ]; then
    drift=$(diff -rq --exclude='__pycache__' --exclude='*.pyc' \
                  "$ROOT/scripts" "$ROOT/skills/gitx-release/scripts" 2>&1 \
            | grep -v "^Only in.*scripts: release-rogue.sh" || true)
    if [ -z "$drift" ]; then
        ok "dual-source scripts/ byte-identical to skills/gitx-release/scripts/"
    else
        fail "dual-source drift after rename:"
        echo "$drift" | head -5 | sed 's/^/       /'
    fi
fi

# ── Test 10: CHANGELOG documents the rename as a breaking change ──
if grep -qE 'rename|rebrand|breaking|gitx-release' "$ROOT/Release/CHANGELOG.md" 2>/dev/null \
   && grep -qE '## v1\.1\.0' "$ROOT/Release/CHANGELOG.md" 2>/dev/null; then
    ok "Release/CHANGELOG.md has v1.1.0 entry mentioning rename/rebrand"
else
    fail "Release/CHANGELOG.md missing v1.1.0 entry or rename description"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
