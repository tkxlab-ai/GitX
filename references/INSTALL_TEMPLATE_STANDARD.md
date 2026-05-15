# INSTALL.md — Unified Standard for TKX Skills

> Authoritative template for the `INSTALL.md` shipped in every TKX skill release. All TKX skills (gitx-release / mac-release / handoff / 1by1 / ClaudeMeX / future) MUST follow this 8-section schema. Enforced by `release-audit.sh §0b`. Companion: `scripts/lib/install-output-style.sh` enforces matching runtime output from `install.sh`.

## Why this exists

Five TKX skills previously shipped five different `INSTALL.md` flavours (40–478 lines, mixed ZH/EN, divergent section ordering, missing file-location cheat sheets, missing maintenance commands). Boss flagged this as unprofessional. This document is the single source of truth so every skill installs and reads the same way.

## How to use this template

1. Copy this file into `<skill-root>/Release/<version>/INSTALL.md` at release time (or have `release.sh:flatten_docs` copy it).
2. Replace every `<SKILL_NAME>` / `<COMMAND>` / `<TRIGGER>` / `<VERSION>` / `<MAINTENANCE_SUBSECTIONS>` / `<TROUBLESHOOTING_SUBSECTIONS>` placeholder.
3. Keep all 8 top-level sections (`## 0` through `## 8`) — `release-audit.sh §0b` greps for these headings and FAILs if any is missing.
4. Subsection 7 (Maintenance) and Subsection 8 (Troubleshooting) are skill-specific — populate with real commands, but use the same `### X.Y` numbering pattern.

---

# Template starts below this line — verbatim copy with placeholders filled

```markdown
# INSTALL — Complete install / upgrade / uninstall / maintenance reference for <SKILL_NAME>

> README.md describes **what this skill is**. This document describes **how to install, upgrade, uninstall, and maintain it** — every command annotated.

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
~/.agents/skills/<SKILL_NAME>/         # Canonical install (Codex + Gemini CLI native discovery)
├── SKILL.md                            # Skill entry / system prompt
├── VERSION                             # Sidecar version (single-line semver)
├── scripts/*.sh                        # Helpers (release / audit / sanity / etc.)
├── scripts/lib/                        # Shared libraries (vendored install-output-style.sh)
├── references/*.md                     # Detailed command specs
└── assets/                             # Templates / fixtures

~/.claude/skills/<SKILL_NAME>           # symlink → canonical (Claude Code)
~/.config/opencode/skills/<SKILL_NAME>  # symlink → canonical (OpenCode)
```

> One install populates all four CLIs (Claude Code / OpenCode / Codex / Gemini) via the canonical + symlinks pattern.

---

## 1. Install

### 1.1 Method A — Source + install.sh (recommended)

For users who want long-term upgrades, team deployment, or CI.

```bash
git clone https://github.com/<ORG>/<SKILL_NAME>.git
cd <SKILL_NAME>
./install.sh                     # Global install
./install.sh --dry-run           # Preview without writing
./install.sh --force             # Overwrite existing install
./install.sh --help              # Full flag reference
```

### 1.2 Method B — Single `.skill` file

For users who got the `.skill` bundle out-of-band (email, shared drive, scp).

```bash
mkdir -p ~/.agents/skills ~/.claude/skills ~/.config/opencode/skills
unzip -o <SKILL_NAME>-v<VERSION>.skill -d ~/.agents/skills/
chmod +x ~/.agents/skills/<SKILL_NAME>/scripts/*.sh
ln -sfn ~/.agents/skills/<SKILL_NAME> ~/.claude/skills/<SKILL_NAME>
ln -sfn ~/.agents/skills/<SKILL_NAME> ~/.config/opencode/skills/<SKILL_NAME>
```

### 1.3 Method C — Manual directory copy

Maximum transparency, zero install script.

```bash
cp -R skills/<SKILL_NAME> ~/.agents/skills/<SKILL_NAME>
chmod +x ~/.agents/skills/<SKILL_NAME>/scripts/*.sh
ln -sfn ~/.agents/skills/<SKILL_NAME> ~/.claude/skills/<SKILL_NAME>
ln -sfn ~/.agents/skills/<SKILL_NAME> ~/.config/opencode/skills/<SKILL_NAME>
```

### 1.4 Method D — curl one-liner

A pure `curl <install.sh> | bash` install **cannot work** for skills built on this template: the installer requires the full bundle (SKILL.md, VERSION, scripts/, scripts/lib/install-output-style.sh, references/, agents/). Method A (clone) and Method B (`.skill` download + unzip) are the supported paths.

If a fetch-and-install one-liner is needed, combine Method B with a curl step:

```bash
VER=v<VERSION>
curl -fsSL https://<your-release-host>/releases/<SKILL_NAME>-${VER}.skill -o /tmp/s.skill
unzip -o /tmp/s.skill -d ~/.agents/skills/
chmod +x ~/.agents/skills/<SKILL_NAME>/scripts/*.sh
ln -sfn ~/.agents/skills/<SKILL_NAME> ~/.claude/skills/<SKILL_NAME>
ln -sfn ~/.agents/skills/<SKILL_NAME> ~/.config/opencode/skills/<SKILL_NAME>
```

> Substitute `<your-release-host>` for your organization's release host (Gitea, GitHub Releases, internal CDN, etc.). Skills MUST keep this section to satisfy `release-audit.sh §0b INSTALL.md heading present: 1. Install`.

### 1.5 Remote / SSH deployment

```bash
# Push source
scp -r <SKILL_NAME>/ user@remote:~/
ssh user@remote 'cd ~/<SKILL_NAME> && ./install.sh'

# Or push .skill bundle
scp Release/<SKILL_NAME>-v<VERSION>.skill user@remote:~/
ssh user@remote 'unzip -o ~/<SKILL_NAME>-v<VERSION>.skill -d ~/.agents/skills/'
```

---

## 2. First-time project initialization

<!-- Skill-specific: e.g. handoff /handoff-init, gitx-release no-op, mac-release first-run setup -->

---

## 3. Upgrade

### 3.1 Source users

```bash
cd ~/<SKILL_NAME>
git pull
./install.sh --force
```

### 3.2 `.skill` single-file users

```bash
unzip -o <SKILL_NAME>-v<NEW>.skill -d ~/.agents/skills/
chmod +x ~/.agents/skills/<SKILL_NAME>/scripts/*.sh
```

### 3.3 Sync existing project state to new template

<!-- Skill-specific: e.g. /handoff-tidy, gitx audit re-run -->

### 3.4 Post-upgrade verification

```bash
cat ~/.agents/skills/<SKILL_NAME>/VERSION         # Should show v<NEW>
bash ~/.agents/skills/<SKILL_NAME>/scripts/<verify>.sh
```

---

## 4. Uninstall

### 4.1 Full uninstall (keep project data)

```bash
rm -rf ~/.agents/skills/<SKILL_NAME>
rm -f  ~/.claude/skills/<SKILL_NAME>
rm -f  ~/.config/opencode/skills/<SKILL_NAME>
```

### 4.2 Project-level only

```bash
rm -rf /path/to/project/.claude/skills/<SKILL_NAME>
```

### 4.3 Wipe project data (DESTRUCTIVE)

<!-- Skill-specific: which files in the project belong to this skill -->

---

## 5. Verify / Self-check

### 5.1 Inside Claude Code

```
/                    # /<COMMAND> should appear in the command list
<TRIGGER>            # Natural-language trigger should match the skill
```

### 5.2 Command line

```bash
ls ~/.agents/skills/<SKILL_NAME>/SKILL.md && echo "✅ skill present"
bash ~/.agents/skills/<SKILL_NAME>/scripts/<verify>.sh
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
2. Run regression tests
3. Dual-source byte-identical check
4. Build `.skill` + source tarball + full tarball
5. Sanity scan (staging + bundle, both must pass)
6. Flatten docs + generate attestations
7. Deep Audit (40+ checks must all pass)
8. Atomic `Release/latest` symlink update

### 6.3 Sanity is unskippable

No `FORCE=1` bypass. Failure aborts release with non-zero exit.

---

## 7. Daily maintenance commands

<MAINTENANCE_SUBSECTIONS>
<!-- Skill-specific commands, numbered 7.1 / 7.2 / ... -->

---

## 8. Troubleshooting

<TROUBLESHOOTING_SUBSECTIONS>
<!-- Skill-specific issues, numbered 8.1 / 8.2 / ... -->

---

More design context in [README.md](./README.md).
```

---

# Audit enforcement

`release-audit.sh §0b` runs the following soft `warn` checks against every release `INSTALL.md`:

- Title line matches `^# INSTALL —` (em-dash, EN standard)
- `## 📖 Table of Contents` anchor present
- Each of the nine numbered top-level headings present (`## 0. File location cheat sheet`, `## 1. Install`, `## 2. First-time project initialization`, `## 3. Upgrade`, `## 4. Uninstall`, `## 5. Verify`, `## 6. Release`, `## 7. Daily maintenance commands`, `## 8. Troubleshooting`)

A missing heading surfaces as `⚠️ INSTALL.md heading present: <name> (soft warning — not counted as FAIL)`. Audit still PASSes overall — these are aspirational checks so legacy / fixture projects continue to ship. The visible ⚠️ pressure is intentional: each new release with a non-conformant `INSTALL.md` makes the gap obvious to operators.

`§0b` also runs hard `check` enforcement against `install.sh`, but **only when the bundle ships `scripts/lib/install-output-style.sh`** (the skill opted in to the standard). When the helper is shipped, install.sh must:

- `source` `scripts/lib/install-output-style.sh`
- call `install_banner_top`
- call `install_checkpoint`
- call `install_banner_bottom`

Missing any of those surfaces as `❌ install.sh ...` and the audit fails (counts toward FAIL total). When the helper is NOT shipped, install.sh checks degrade to a single soft warn — fixture / legacy projects keep working.

# Companion: install.sh runtime output

`scripts/lib/install-output-style.sh` provides the matching runtime banner / checkpoint / summary format. Every `install.sh` MUST `source` this helper and use its API (`install_style_init`, `install_banner_top`, `install_checkpoint`, `install_step_ok` / `install_step_warn` / `install_step_fail`, `install_banner_bottom`, `install_cli_table_begin` / `install_cli_row` / `install_cli_table_end`, `install_next_block` / `install_next_hint`) instead of bare `echo`. Enforced by `release-audit.sh §0b` (helper sourcing + banner-top + checkpoint + banner-bottom presence are hard-checked when the bundle ships the helper).
