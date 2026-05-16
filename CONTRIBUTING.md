# Contributing

[English](CONTRIBUTING.md) · [中文](CONTRIBUTING_CN.md)

Contributions of code, docs, tests, and feedback to GitX are welcome.

## Development setup

```bash
git clone https://github.com/tkxlab-ai/GitX.git
cd GitX

bash --version              # 3.2+ (POSIX) required
which shellcheck            # recommended: brew install shellcheck

bash tests/run_all.sh       # run the full suite
```

## Workflow — strict TDD

1. **RED** — write a failing test (`tests/test_*.sh`) first; confirm it FAILs.
2. **GREEN** — minimal change to pass it.
3. **REFACTOR** — clean up; keep the whole suite green.
4. **Commit** — describe which policy changed / which Gotcha was fixed
   (write the *why*, not the *what*).

## Testing requirements

- New behavior ships with a test.
- Bug fixes ship with a regression test that reproduces the bug first.
- `bash tests/run_all.sh` must be fully green before merge.
- Cross-platform: tests must pass on macOS **and** Linux (no GNU-only flags).

## Commit / PR conventions

```
<type>: <description>

<optional body explaining WHY>

Refs: <issue or policy §>
```

Types: `feat` / `fix` / `refactor` / `docs` / `test` / `chore` / `perf` / `ci`

### PR checklist

- [ ] `bash tests/run_all.sh` → all green
- [ ] New/changed policy lines cite `references/TKX_*.md`
- [ ] If `scripts/*.sh` changed: ran `bash scripts/sync-dual-source.sh`
      (dual-source policy v2.3 §8.1 #14)
- [ ] If SKILL.md changed: `version:` / dual-source aligned
- [ ] Change has a matching Gotcha / Dev Log entry (when applicable)

## Code style

- Shell: `set -euo pipefail`, clear names, no silent fallback.
- Errors: raised explicitly with an actionable fix hint (no placeholder
  error strings).
- Comments explain **why**, not what.
- Files ≤ 800 lines, functions ≤ 50 lines.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).

## License

Contributions are released under the [MIT License](LICENSE).
