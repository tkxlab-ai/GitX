# Mac software release flow — {{PROJECT_NAME}}

Project type signal: `*.xcodeproj` / `Package.swift` / `src-tauri/Cargo.toml` detected.
Generated: {{DATE}} by gitx-release {{GITX_VERSION}}.

## Pipeline

1. `swift test` (or `xcodebuild test` / `cargo test`) — must be 0 fail.
2. Edit `Release/CHANGELOG.md` — top section: `## vX.Y.Z — {{DATE}}`.
3. Run `/mac-release` (the sibling `mac-release` skill — see `~/.agents/skills/mac-release/`).
4. Mac-release pipeline: build → codesign → notarize → staple → audit.
5. Manual `git push && git push --tags`.

## Expected artifacts

- `.app` / `.dmg` / `.pkg` (signed + notarized + stapled)
- Codesign team-id matches `.gitx/policy.md` claim
- Notarytool submission-id recorded
- `checksums.txt` + provenance log

## Sanity-scan red list for mac

In addition to TKX 6 categories (credentials / abs-path / email / public-IP / MAC / SSH-GPG):
- Apple Team ID literal (only the placeholder, never a real one in source)
- Provisioning profile UUID
- App-specific password literal

## See also

- `.gitx/policy.md` — project-level policy excerpt
- `RELEASE_GUIDELINE.md` — project-root index for dev-session AI Agent
- `~/.agents/skills/mac-release/SKILL.md` — sibling skill that runs the mac pipeline
