# Vendored: Anthropic skill-creator

This directory contains a frozen subset of [anthropics/skills/skills/skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator), Apache-2.0 licensed. Used by `gitx-release` when system Claude Code's plugin marketplace cache is missing or older than this snapshot (see `scripts/lib/skill-creator-version.sh` decision matrix).

## Files vendored (standalone-runnable subset)

| File | Purpose |
|---|---|
| `scripts/quick_validate.py` (102 lines) | SKILL.md spec validator — agentskills.io 6 rules |
| `scripts/package_skill.py` (137 lines) | `.skill` zip packager — calls quick_validate first |
| `scripts/utils.py` | frontmatter parsing helpers (depend of above) |
| `scripts/__init__.py` | Python module marker (empty) |
| `LICENSE.txt` | Apache 2.0 attribution (required by license) |
| `VERSION` | pinning metadata (upstream commit + date + source URL) |

**Not vendored** (LLM-only, depend on `claude` subprocess + subagents): `run_eval.py`, `run_loop.py`, `improve_description.py`, `aggregate_benchmark.py`, `generate_report.py`, `eval-viewer/`. These are creation/iteration tools, not packaging.

## Manual upgrade procedure

`gitx-release` does NOT auto-sync upstream — vendored snapshot is intentionally frozen for reproducibility. Upgrade is an explicit human action with diff review.

```bash
# 1. Clone latest upstream into temp
TMP=$(mktemp -d)
git clone --depth=1 https://github.com/anthropics/skills "$TMP/skills"

# 2. Inspect upstream changes since vendored pinning
VENDORED_COMMIT=$(awk -F= '/^upstream_commit=/ {print $2}' VERSION | tr -d ' ')
cd "$TMP/skills"
git log --oneline "$VENDORED_COMMIT..HEAD" -- skills/skill-creator/

# 3. If diff is acceptable, copy fresh files into vendored
cd /path/to/gitx-release/scripts/vendored/skill-creator
cp "$TMP/skills/skills/skill-creator/scripts/quick_validate.py" scripts/
cp "$TMP/skills/skills/skill-creator/scripts/package_skill.py" scripts/
cp "$TMP/skills/skills/skill-creator/scripts/utils.py" scripts/
# (re-check if upstream LICENSE changed; usually stable)

# 4. Update VERSION pinning (replace upstream_commit, upstream_date, vendored_at)
NEW_HASH=$(cd "$TMP/skills" && git log -1 --format="%H" -- skills/skill-creator/)
NEW_DATE=$(cd "$TMP/skills" && git log -1 --format="%ci" -- skills/skill-creator/ | awk '{print $1}')
# Edit VERSION: set upstream_commit=$NEW_HASH, upstream_date=$NEW_DATE, vendored_at=$(date +%Y-%m-%d)

# 5. Dual-source sync (vendored must mirror skills/gitx-release/scripts/vendored/)
cp -R scripts/vendored/skill-creator/. skills/gitx-release/scripts/vendored/skill-creator/

# 6. Run full test suite + self-bake to confirm no behavior regression
bash tests/run_all.sh
bash scripts/gitx-release.sh --version v<next>

# 7. Cleanup
rm -rf "$TMP"
```

## When to upgrade

- **Don't** unless there's a specific bug fix or feature you need
- Check upstream's CHANGELOG / commit log first
- Vendored snapshot is part of reproducibility contract — upgrading is a deliberate decision that goes into `release(vX.Y.Z)` commit message

## License

Apache 2.0, see `LICENSE.txt`. The original work is © Anthropic; the vendored snapshot retains that attribution per Apache 2.0 §4.
