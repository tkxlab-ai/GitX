## What and why

<!-- What does this change, and which release problem does it solve? Link the issue if there is one. -->

## Checklist

- [ ] A failing test was written first and now passes
- [ ] `bash tests/run_all.sh` is all green
- [ ] If `scripts/*.sh` changed: ran `bash scripts/sync-dual-source.sh` (the bundled copy must stay identical)
- [ ] If README or CHANGELOG changed: `bash scripts/docs-audit.sh` exits 0
- [ ] New or changed policy lines cite `references/TKX_Git_Release_policy_and_process.md`
- [ ] No tokens, private hostnames or home-directory paths in the diff

See [CONTRIBUTING.md](https://github.com/tkxlab-ai/GitX/blob/main/CONTRIBUTING.md) for the full workflow.
