# INSTALL — Complete install / upgrade / uninstall / maintenance reference for gitx-release

> README.md describes **what gitx-release is**. This document describes **how to install, upgrade, uninstall, and maintain it** — every command annotated.

---

## 📖 Table of Contents

- [0. File location cheat sheet](#0-file-location-cheat-sheet)
- [1. Install](#1-install)
  - [1.1 Method A — Source + install.sh (recommended)](#11-method-a--source--installsh-recommended)
  - [1.2 Method B — Single `.skill` file](#12-method-b--single-skill-file)
  - [1.3 Method C — Manual directory copy](#13-method-c--manual-directory-copy)
  - [1.4 Method D — curl one-liner](#14-method-d--curl-one-liner)
  - [1.5 Remote / SSH deployment](#15-remote--ssh-deployment)
- [2. First-time project initialization](#2-first-time-project-initialization)
- [3. Upgrade](#3-upgrade)
- [4. Uninstall](#4-uninstall)
- [5. Verify / Self-check](#5-verify--self-check)
- [6. Release (developers)](#6-release-developers)
- [7. Daily maintenance commands](#7-daily-maintenance-commands)
- [8. Troubleshooting](#8-troubleshooting)

---

## 0. File location cheat sheet

```
~/.agents/skills/gitx-release/         # Canonical install (Codex + Gemini auto-discovery)
├── SKILL.md                            # Skill entry / system prompt
├── VERSION                             # Sidecar version (v1.x.y)
├── scripts/
│   ├── gitx-release.sh                 # /gitx-release wrapper (auto-bump + ship)
│   ├── release.sh                      # Main release pipeline (12 functions)
│   ├── release-audit.sh                # Deep audit (40+ static checks)
│   ├── release-sanitize.sh             # Sanity scan (6 categories)
│   ├── scan-credentials.sh             # Credential pattern detector
│   ├── lib/
│   │   ├── install-output-style.sh     # Unified install.sh output helper
│   │   ├── skill-creator-version.sh    # Vendored skill-creator decision matrix
│   │   └── detect-project.sh           # PROJECT_NAME / SKILL_NAME auto-detect
│   └── vendored/skill-creator/         # Anthropic skill-creator frozen snapshot
├── references/                         # Policy + cross-CLI guideline + INSTALL standard
└── agents/codex-commands.txt           # Codex CLI command aliases

~/.claude/skills/gitx-release           # symlink → canonical (Claude Code)
~/.config/opencode/skills/gitx-release  # symlink → canonical (OpenCode)
```

> One install populates all four CLIs (Claude Code / OpenCode / Codex / Gemini) via the canonical + symlinks pattern. Codex CLI exposes `$gitx-release` from `agents/codex-commands.txt`.

---

## 1. Install

### 1.1 Method A — Source + install.sh (recommended)

For long-term upgrades, team deployment, or CI.

```bash
git clone https://github.com/tkxlab-ai/Git_Release_Skill.git
cd Git_Release_Skill
./install.sh                     # Install (renders 6-checkpoint banner)
./install.sh --dry-run           # Preview without writing
./install.sh --force             # Overwrite existing install
./install.sh --help              # Full flag reference
```

The installer renders a unified 6-checkpoint banner across all TKX skills (output of `./install.sh` or `./install.sh --force` — the live install path):

```
===============================================================
  📦  gitx-release Installation  v1.5.0
===============================================================
🔐  Checkpoint 1/6 — Integrity verification
🔍  Checkpoint 2/6 — Preflight
📂  Checkpoint 3/6 — Install canonical
🔗  Checkpoint 4/6 — Symlinks
🧹  Checkpoint 5/6 — Legacy cleanup
✓  Checkpoint 6/6 — Validation
===============================================================
  🎉  gitx-release v1.5.0 installed
===============================================================
```

`./install.sh --dry-run` stops after Checkpoint 3 (Dry-run preview) since later checkpoints would mutate the filesystem; the success banner suffixes `(dry-run)` in that mode.

### 1.2 Method B — Single `.skill` file

For out-of-band distribution (email, shared drive, scp).

```bash
mkdir -p ~/.agents/skills ~/.claude/skills ~/.config/opencode/skills
unzip -o git_release_skill-v<VERSION>.skill -d ~/.agents/skills/
chmod +x ~/.agents/skills/gitx-release/scripts/*.sh
ln -sfn ~/.agents/skills/gitx-release ~/.claude/skills/gitx-release
ln -sfn ~/.agents/skills/gitx-release ~/.config/opencode/skills/gitx-release
```

### 1.3 Method C — Manual directory copy

Maximum transparency, zero install script.

```bash
cp -R skills/gitx-release ~/.agents/skills/gitx-release
chmod +x ~/.agents/skills/gitx-release/scripts/*.sh
ln -sfn ~/.agents/skills/gitx-release ~/.claude/skills/gitx-release
ln -sfn ~/.agents/skills/gitx-release ~/.config/opencode/skills/gitx-release
```

### 1.4 Method D — curl one-liner

**Not supported for gitx-release.** A pure `curl ... | bash` install of `install.sh` alone cannot work — the installer requires the full bundle (SKILL.md, VERSION, scripts/, scripts/lib/install-output-style.sh, references/, agents/), all bundled inside the `.skill` zip. Use **Method B** (download the `.skill` bundle then run `unzip`) or **Method A** (clone the source repo) instead.

If a fetch-and-install one-liner is needed, combine Method B with a curl step:

```bash
# Example: fetch a published .skill bundle then install
VER=v1.5.0
curl -fsSL https://example.tkxlab.ai/releases/git_release_skill-${VER}/git_release_skill-${VER}.skill -o /tmp/g.skill
unzip -o /tmp/g.skill -d ~/.agents/skills/
chmod +x ~/.agents/skills/gitx-release/scripts/*.sh
ln -sfn ~/.agents/skills/gitx-release ~/.claude/skills/gitx-release
ln -sfn ~/.agents/skills/gitx-release ~/.config/opencode/skills/gitx-release
```

> The example URL above is illustrative — substitute your organization's release host. The TKX canonical distribution is Gitea LAX (SSH); for off-prem deployment publish the `.skill` to a trusted CDN.

### 1.5 Remote / SSH deployment

```bash
# Push source then install
scp -r Git_Release_Skill/ user@remote:~/
ssh user@remote 'cd ~/Git_Release_Skill && ./install.sh'

# Or push .skill bundle
scp Release/git_release_skill-v<VERSION>/git_release_skill-v<VERSION>.skill user@remote:~/
ssh user@remote 'unzip -o ~/git_release_skill-v<VERSION>.skill -d ~/.agents/skills/'
```

---

## 2. First-time project initialization

gitx-release auto-detects `skills/<name>/SKILL.md` layout, so most projects need no per-project init. For non-standard projects (or to bootstrap a full release-guideline package covering both Bash skills and macOS apps), use the `gitx-init` subcommand (v1.6.0+, dual templates).

---

## 3. Upgrade

### 3.1 Source users

```bash
cd ~/Git_Release_Skill
git pull
./install.sh --force
```

### 3.2 `.skill` single-file users

```bash
unzip -o git_release_skill-v<NEW>.skill -d ~/.agents/skills/
chmod +x ~/.agents/skills/gitx-release/scripts/*.sh
```

### 3.3 Sync existing project state

Run `./scripts/gitx-release.sh --dry-run` in the consuming project — it surfaces any pipeline drift from the new gitx-release contract.

### 3.4 Post-upgrade verification

```bash
cat ~/.agents/skills/gitx-release/VERSION                    # → v<NEW>
bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh --help
```

---

## 4. Uninstall

### 4.1 Full uninstall

```bash
rm -rf ~/.agents/skills/gitx-release
rm -f  ~/.claude/skills/gitx-release
rm -f  ~/.config/opencode/skills/gitx-release
rm -rf ~/.codex/skills/gitx-release                          # legacy duplicate
```

### 4.2 Project-level only

```bash
rm -rf /path/to/project/.claude/skills/gitx-release
```

### 4.3 Wipe project release artefacts (DESTRUCTIVE)

```bash
rm -rf /path/to/project/Release/
```

> Destroys all historical release tarballs + audit logs + checksums. Only do this if you have remote git tags / GitHub Releases for every shipped version.

---

## 5. Verify / Self-check

### 5.1 Inside Claude Code

```
/                    # /gitx-release should appear in the command list
GitX release         # Natural-language trigger
```

### 5.2 Command line

```bash
ls ~/.agents/skills/gitx-release/SKILL.md && echo "skill present"
bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh --help
bash ~/.agents/skills/gitx-release/scripts/release-sanitize.sh ~/.agents/skills/gitx-release
```

---

## 6. Release (developers)

### 6.1 One command

```bash
./scripts/gitx-release.sh                  # Auto-bump patch + full pipeline
./scripts/release.sh v<VERSION>            # Explicit version
```

### 6.2 What release.sh does

1. Preflight (version consistency, CHANGELOG gate)
2. Run regression tests (`tests/run_all.sh`)
3. Dual-source byte-identical check
4. Build `.skill` + source tarball + full tarball
5. Sanity scan (staging + bundle, both must pass)
6. Flatten docs + generate attestations (SBOM + TOKEN_USAGE)
7. Deep Audit (40+ checks must all pass)
8. Atomic `Release/latest` symlink update

### 6.3 Sanity is unskippable

No `FORCE=1` bypass. Failure aborts release with non-zero exit. See `references/TKX_Git_Release_policy_and_process.md` for the full 1091-line policy.

---

## 7. Daily maintenance commands

### 7.1 Audit a previously shipped release

```bash
bash ~/.agents/skills/gitx-release/scripts/release-audit.sh v<VERSION>
```

### 7.2 Re-run sanity scan on any directory

```bash
bash ~/.agents/skills/gitx-release/scripts/release-sanitize.sh /path/to/dir
```

### 7.3 Sync dual-source manually (release.sh enforces it automatically)

```bash
bash ~/.agents/skills/gitx-release/scripts/sync-dual-source.sh
```

### 7.4 Verify checksums of a release artefact

```bash
cd Release/git_release_skill-v<VERSION>/
shasum -a 256 -c checksums.txt
```

### 7.5 Inspect vendored skill-creator pinning

```bash
cat ~/.agents/skills/gitx-release/scripts/vendored/skill-creator/VERSION
```

---

## 8. Troubleshooting

### 8.1 "Bash 4+ recommended" warning

macOS ships `/bin/bash` 3.2. Install bash 4+ via Homebrew (`brew install bash`) and ensure it is first in `$PATH`. The installer still proceeds — it only warns.

### 8.2 "Already installed" error

Run `./install.sh --force` to overwrite the existing canonical install + symlinks. The installer is idempotent.

### 8.3 "Missing required file" error

The release bundle is incomplete. Re-download the `.skill` or re-clone the source repo. Compare bundle contents against `Release/<version>/checksums.txt`.

### 8.4 Integrity check failed

The bundle has been tampered or corrupted in transit. Re-download from a trusted source. `install.sh` refuses to install when `checksums.txt` mismatches any file.

### 8.5 `/gitx-release` not appearing in Claude Code

```bash
ls -la ~/.claude/skills/gitx-release         # should symlink to ~/.agents/skills/
claude --version                              # ensure skills are supported
# Inside Claude Code: /reload-plugins
```

### 8.6 Sanity scan keeps failing on legitimate content

Add allow-list entries to `.sanitize-ignore` in the project root. See `references/TKX_Git_Release_policy_and_process.md` §5.

---

More design context in [README.md](./README.md). Full policy in [references/TKX_Git_Release_policy_and_process.md](./references/TKX_Git_Release_policy_and_process.md).
