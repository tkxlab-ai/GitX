# The GitX Journey

How GitX grew, how its releases are reviewed, which models helped build it, and what comes next. For what GitX does today, see the [README](../README.md); for every change, see the [changelog](../CHANGELOG.md).

---

## Development history

GitX did not begin as a release tool. It began as a refusal to ship on faith.

**2026-04-22 — prototype.** The first build (`v0.9.4`) already carried four critical test-driven fixes. `v0.9.5` was withdrawn before it shipped; the failure became a permanent test and a gate. That set the pattern: every mistake becomes a rule the pipeline enforces.

**Late April to early May — first stable release, proven on other projects.** `v1.0.0` reached stable on 2026-04-29. The `v1.1.x` line proved the pipeline on projects other than itself by releasing a sibling skill, added checksum verification to the installer, and learned to cope with file-sync tools after real cross-machine incidents. `v1.5.0` unified installation across four agent CLIs; `v1.6.0` added `gitx-init`.

**2026-05-15 — the discipline sprint.** Fifteen releases in one day (`v1.7.0` through `v1.9.3`) closed a whole class of credential-handling problems in the GitHub publish runbook, built layered protection around private working files, and completed the public project page.

**2026-05-16 to 05-20 — documentation as a contract.** `v1.9.8` found the root cause of stale README numbers and added the `§0f` gate. `v1.10.0` introduced deterministic README generation and the `§0g`/`§0h`/`§0i` gates. `v1.11.0` split documentation into an independent bilingual pipeline with a fail-closed contract and brought CI's shellcheck gate into the pipeline. `v1.12.x` hardened that contract through several review rounds: a repo-local hero image, strict link checking, the Chinese changelog, and a fix for a check that had let English text slip into the Chinese README.

**2026-11 — `v1.13.0`.** A hermetic test runner (each suite in a clean environment, judged by its own summary line), a guard against fragile test idioms, the `gitx-marketplace` command and automatic marketplace bump, and an optional step that publishes each release to a private Gitea release repository with byte-for-byte verification.

**At `v1.12.3` (2026-05-20):** 28 days from the first prototype, with fifteen releases on the busiest day. Current counts are always in the README badges, which are generated from the code.

---

## How releases are reviewed

Review is a gate, not a courtesy. Authoring and review are done by different parties: every release-affecting change is reviewed by an independent reviewer and by a second model, each checking its findings against the code and the history, repeated until both agree there is nothing left to fix. A green local run is necessary but not sufficient; a change is done when CI is green and the published page matches the contract.

---

## Multi-model collaboration

GitX is built by setting models against each other rather than trusting any one of them:

| Model | Role |
|---|---|
| Claude (Opus / Sonnet) | primary authoring, test-driven implementation, pipeline reasoning |
| OpenAI Codex | adversarial review — challenges design, assumptions and leaks |
| Google Gemini | independent second opinion |

Findings are checked against ground truth (code, git history, changelog), never accepted on authority. That is also why the build-metrics line in the README counts tokens across models and sessions.

---

## What comes next

- Extend the bilingual contract from the README and changelog to `INSTALL.md`, `SKILL.md` and the per-command docs.
- Bring the sibling skills (1by1X, ClaudeMeX, HandoffX) onto the same documentation standard.
- Make the central marketplace the single install surface for the whole skill family.

---

## Thanks

To the practice of policy as code, to the projen lineage that showed documentation can be generated deterministically, and to the multi-model review loop that keeps a self-publishing tool honest.
