# Skill release flow — {{PROJECT_NAME}}

Project type signal: `skills/<name>/SKILL.md` detected.
Generated: {{DATE}} by gitx-release {{GITX_VERSION}}.

## Pipeline

1. `bash tests/run_all.sh` — must be 0 fail.
2. Edit `Release/CHANGELOG.md` — top section: `## vX.Y.Z — {{DATE}}`.
3. Run `/gitx-release` (or `bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh`).
4. Deep Audit must report 0 FAIL.
5. Manual `git push && git push --tags` (gitx-release does NOT auto-push per TKX policy §10.10).

## Expected artifacts

- `.skill` bundle (~30-100 KB)
- Source tarball (deterministic, honors `$SOURCE_DATE_EPOCH`)
- Full tarball (includes `Release/<ver>/` tree)
- `checksums.txt` + `sbom.cyclonedx.json` + `TOKEN_USAGE.json`

## See also

- `.gitx/policy.md` — project-level policy excerpt
- `RELEASE_GUIDELINE.md` — project-root index for dev-session AI Agent
