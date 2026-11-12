---
name: gitx-marketplace
description: Register / bump / list this skill in the TKX central marketplace.
---

# gitx-marketplace

TKX skills marketplace registration helper. Three subcommands:

- `gitx-marketplace register --repo OWNER/REPO` — first-time setup. Creates
  `.gitx/marketplace-target` marker (gitignored, per-machine). Adds an entry
  to the marketplace via PR + squash-merge.
- `gitx-marketplace bump [--version vX.Y.Z]` — update the marketplace entry's
  `version` field. Auto-invoked by `gitx-release` after each successful
  release when the marker is present.
- `gitx-marketplace list [--repo OWNER/REPO]` — read-only marketplace listing.

All subcommands support `--dry-run`. See SOP Phase 9 for the full flow.

## Why
Solo / small-team skill authors should be able to publish to a shared
marketplace without hand-editing JSON or remembering per-release flags. After
a one-time `register`, every `gitx-release` keeps the marketplace in sync.

## When NOT to run
- The skill is private / single-tenant — skip `register`, no marker.
- You want a one-off release without marketplace sync — use
  `gitx-release --skip-marketplace`.
- The marketplace repo has branch protection that blocks squash-merge —
  v1.13.0 sync mode fails; a future v1.13.x adds `--queue-merge` for
  branch-protected marketplaces.

## See also
- `references/gitx-sop/GITHUB_RELEASE_SOP.template.md` Phase 9
- `docs/superpowers/specs/2026-05-20-v1.13.0-marketplace-helper-design.md`
