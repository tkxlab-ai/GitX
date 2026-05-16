# Agent Metadata

This directory holds CLI-specific metadata that Claude Code, Codex CLI,
Gemini CLI, and OpenCode read to expose this skill to their users.

## `codex-commands.txt`

One Codex `$` selector per line. Codex parses this file as a flat list of
selector strings — **do not put comments, headers, or blank lines inside
codex-commands.txt itself**, because Codex's parser may not tolerate them.
Anything you want to document about the entries lives here in `README.md`
or in `openai.yaml`.

### Current entries

| Selector | Status | Sunset |
|---|---|---|
| `$gitx-release` | **canonical** (v1.1.0+) | — |
| `$git-release-pipeline` | **deprecated alias** retained for one-version grace period | removed in v1.2.0 |

### v1.2.0 sunset checklist

When v1.2.0 ships:

1. Delete the `$git-release-pipeline` line from both
   `agents/codex-commands.txt` (root + bundle copy under
   `skills/gitx-release/agents/`).
2. Update the three tests that assert the deprecated alias is present:
   - `tests/test_codex_skill_metadata.sh`
   - `tests/test_install_sh_runtime.sh`
   - `tests/test_audit_codex_command_selectors.sh`
3. Remove the `SKILL_NAME_LEGACY` cleanup block in `install.sh`
   (lines around the `Removed legacy duplicate Codex visible alias
   skills` echo) once enough of the user base has run `./install.sh
   --force` post-rebrand.
4. Add a CHANGELOG entry for v1.2.0 noting the alias removal as a
   breaking change.

## `openai.yaml`

Codex / OpenAI Skills metadata: `display_name`, `short_description`,
`default_prompt`. Used by `/skills` browser to render the skill entry.
