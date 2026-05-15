# Skill Assets

This directory is reserved for skill-specific static assets (images, templates, sample data) that need to ship inside the `.skill` bundle.

Currently empty by design — the TKX release pipeline is a pure-Bash tool and does not require bundled assets.

## Why this file exists

Upstream `skill-creator` strips empty directories from the `.skill` zip, which then breaks our own post-release audit (§6 requires `.skill` to contain `assets/`). Keeping this README here ensures `assets/` is preserved inside the bundle and that `diff -r bundle .skill` stays clean.

Remove this file only if/when `assets/` gains real content.
