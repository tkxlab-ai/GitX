# `mac-release` — design spec

> **Status**: design (2026-05-06) — pending implementation approval
> **Driver**: TKX
> **Co-author**: Claude Opus 4.7 (1M context)
> **Spec brainstormed via**: `superpowers:brainstorming` while sitting in `Git_Release_Skill` (gitx-release v1.1.6) — the analog skill this one is patterned on.

## 1. One-line scope

Toolchain-agnostic Mac app release pipeline. **Sign + notarize + staple + DMG/ZIP + verify gates + provenance**, with stack-specific adapters for **Swift**, **Tauri 2.0**, and **Go** in v0.1.0.

The skill produces a local `Release/<product>-vX.Y.Z/` directory ready for the operator to upload to GitHub Releases via `gh release create`. Per TKX policy §10.10, the skill never auto-tags, never auto-pushes, never auto-publishes.

---

## 2. Goals and Non-Goals

### Goals
1. **Single uniform pipeline** for sign / notarize / staple / DMG / verify across Swift, Tauri 2.0, Go — only the build phase varies per stack.
2. **Empirically-grounded gates** — capability rules tuned against real Tauri 2.x apps (AiPromptX), Swift bundle conventions tuned against real Swift projects (MacAudit), Go CLI conventions tuned against real Go projects (Please_Continue).
3. **Operator-controlled publish** — local artifacts only; operator decides when and how to upload to GitHub.
4. **Reproducible source release** — deterministic source tarball via `git archive HEAD` (`tar --owner=0 --group=0 --numeric-owner` + `LC_ALL=C sort` + `gzip -n` + `SOURCE_DATE_EPOCH`).
5. **Pattern parity with gitx-release** — same `release.sh` named-phases backbone, same `release-audit.sh` post-release deep audit, same wrapper rollback semantics (Gotcha #17), same gate-then-ship invariant (Gotcha #25), same dual-source byte-identical contract.

### Non-Goals (v0.1.0)
1. **iOS releases** — separate cert chain (3rd Party Mac Developer Application), separate distribution path (TestFlight, ASC API). A future `ios-release` skill or v1.0+ extension. Out of scope.
2. **Mac App Store distribution** — different cert (3rd Party Mac Developer), different submission path (`xcrun altool --upload-app`). Mentioned in roadmap; not v0.1.0.
3. **Auto-update mechanisms** (Sparkle, Tauri's built-in updater) — v0.2+ work. v0.1.0 ships notarized DMGs and ZIPs that users install manually.
4. **CI signing** — the skill assumes operator's keychain has the Developer ID Application cert. Headless CI cert provisioning (e.g., via fastlane match, GitHub Actions secrets) is the operator's problem in v0.1.0.
5. **Fancy DMG layouts** — basic drag-to-Applications DMG only. Background images / custom layouts / license windows are v0.2+ via `.mac-release/dmg-resources/`.
6. **TKX policy v2.x port for Mac** — the existing `references/TKX_Git_Release_policy_and_process.md` is skill-project-shaped. mac-release ships its own `TKX_Mac_Release_policy.md` derived from but not identical to the gitx-release policy. Cross-references both ways.

---

## 3. Architecture

### 3.1 Standalone repo

`mac-release` lives in a new sibling repo `Mac_Release_Skill/`, parallel to `Git_Release_Skill/`. Reasoning (locked in Q4 of brainstorming):

- **Different audiences**. gitx-release ships to Bash-skill authors; mac-release ships to Mac app developers. Forcing one community to install the other is wrong.
- **Different release cadences**. gitx-release evolves with skill packaging concerns; mac-release evolves with Apple toolchain churn (notarytool flag changes, Tauri 2.x updates, Sparkle migrations). Coupling them in one repo means each fix bumps the other's version.
- **Self-bake discipline**. mac-release IS a Bash skill (not a Mac app). It self-bakes via gitx-release. Keeping them in separate repos preserves the clean self-bake contract.

Vendoring tax for shared generic primitives (`scan-credentials.sh`, `emit-sbom.sh`, `release-sanitize.sh`) is ~100–200 lines and refreshed via `scripts/sync-from-gitx-release.sh` one-shot helper. Lesser evil than a shared library at this scale.

### 3.2 Repo layout (target shape)

```
Mac_Release_Skill/
├── VERSION                                  (gitx-release pattern; sidecar)
├── CHANGELOG.md
├── README.md / INSTALL.md / LICENSE / SECURITY.md / CONTRIBUTING.md
├── install.sh                               (verifies checksums.txt before write; gitx-release pattern)
├── Release/                                 (per-version dirs; gitignored except CHANGELOG.md)
├── scripts/
│   ├── mac-release.sh                       (wrapper — auto-bump, run pipeline, sentinel reminders)
│   ├── release.sh                           (full pipeline; 15 named phases)
│   ├── release-audit.sh                     (post-release deep audit; ~12 sections, ~80 gates target)
│   ├── release-sanitize.sh                  (vendored from gitx-release)
│   ├── scan-credentials.sh                  (vendored from gitx-release)
│   ├── emit-sbom.sh                         (vendored from gitx-release)
│   ├── adapters/
│   │   ├── swift.sh                         (Package.swift / xcodebuild / .app packaging)
│   │   ├── tauri.sh                         (cargo tauri build + capability audit)
│   │   └── go.sh                            (go build × 2 archs + lipo + optional .app wrap)
│   ├── lib/
│   │   ├── manifest.sh                      (TOML loader for .mac-release/manifest.toml)
│   │   ├── capability-audit.sh              (Tauri-specific; classifies hard/soft/allowlisted)
│   │   ├── codesign-pipeline.sh             (sign + verify; toolchain-agnostic)
│   │   └── notarize-pipeline.sh             (notarytool submit + wait + staple)
│   └── sync-from-gitx-release.sh            (refresh vendored generic primitives)
├── skills/
│   └── mac-release/                         (canonical bundle; install.sh symlinks point here)
│       ├── SKILL.md
│       ├── VERSION
│       ├── scripts/                         (byte-identical to root scripts/; dual-source from day one)
│       ├── references/
│       │   └── TKX_Mac_Release_policy.md
│       ├── assets/
│       │   └── manifest.template.toml       (starter for new projects)
│       ├── agents/
│       │   └── codex-commands.txt           ($mac-release selector)
│       └── commands/
│           └── mac-release.md               (Claude Code slash command entry)
├── tests/
│   ├── run_all.sh
│   ├── test_manifest_parse.sh
│   ├── test_capability_audit.sh
│   ├── test_swift_adapter.sh
│   ├── test_tauri_adapter.sh
│   ├── test_go_adapter.sh
│   ├── test_codesign_verify.sh
│   ├── test_notarize_pipeline.sh            (mocked; e2e gated by env)
│   ├── test_release_pipeline_smoke.sh
│   └── fixtures/
│       ├── tiny-swift-app/
│       ├── tiny-tauri-app/
│       └── tiny-go-cli/
└── docs/
    └── ...
```

### 3.3 The spine + adapters split

- **Common spine** (`release.sh` + `lib/codesign-pipeline.sh` + `lib/notarize-pipeline.sh` + `release-audit.sh`) handles sign / notarize / staple / DMG / verify uniformly across all stacks.
- **Per-stack adapter** (`adapters/<stack>.sh`) handles only the **build phase** + **stack-specific gates**. Each adapter is ~150 lines.
- **Manifest as single source of truth** (`.mac-release/manifest.toml` per project). Loaded once at pipeline start; values exported as env vars to downstream phases.

---

## 4. Pipeline phases (15 named functions in `release.sh`)

Fixed order. Each phase has explicit inputs, outputs, and failure semantics. No hidden globals between phases except the loaded manifest.

| # | Phase | Reads | Writes | Failure → |
|---|---|---|---|---|
| 1 | `load_manifest` | `.mac-release/manifest.toml` | env: `STACK`, `IDENTITY`, `NOTARY_PROFILE`, `BUILD_HOOK`, etc. | exit 2 (config error, no rollback) |
| 2 | `preflight_external_tools` | system PATH | OK / list of missing | exit 1 before any state changes |
| 3 | `preflight_signing_identity` | keychain | OK / "no Developer ID for $TEAM_ID" | exit 1; offers `mac-release setup` hint |
| 4 | `preflight_notary_profile` | keychain | OK / "no notarytool profile $NOTARY_PROFILE" | exit 1; offers `mac-release setup` hint |
| 5 | `version_bump` (skipped if explicit version arg) | `VERSION` sidecar | new VERSION + skill-bundle copy | rollback on later failure (Gotcha #17) |
| 6 | `update_changelog` | `CHANGELOG.md` | inserts `## v<new> — <date>` + sentinel | rollback on later failure |
| 7 | `run_build_hook` | `BUILD_HOOK` (project-side) + adapter | `$BUILD_OUTPUT` (.app or universal binary) | exit 1; pipeline returns non-zero |
| 8 | `run_stack_specific_audits` | `$BUILD_OUTPUT` + manifest | OK / Tauri capability hard-fails / Swift SPM bundle gotcha / Go host-leak | exit 1 |
| 9 | `build_source_tarball` | `git archive HEAD` | `<product>-vX.Y.Z-source.tar.gz` (deterministic) | exit 1 |
| 10 | `codesign_artifact` | identity + hardened-runtime + entitlements | signed `.app` or binary | exit 1 |
| 11 | `notarize_and_staple` | notarytool profile | submitted ZIP, ticket-stapled `.app` | exit 1 (mid-pipeline retry via `mac-release verify`) |
| 12 | `package_dmg_or_zip` | stapled `.app` (or naked binary) | `<product>-vX.Y.Z.dmg` (signed at DMG level) **OR** `<product>-vX.Y.Z.zip` for naked binaries | exit 1 |
| 13 | `generate_attestations` | all artifacts | `checksums.txt` (LC_ALL=C sorted), `sbom.cyclonedx.json`, `RELEASE_NOTES.md` | exit 1 |
| 14 | `run_deep_audit` | `Release/<product>-vX.Y.Z/` | ~80 gate verdicts | exit 1; latest symlink NOT updated |
| 15 | `update_latest_symlink` | atomic `ln -sfn` | `Release/latest → <product>-vX.Y.Z` | only runs if §14 passed |

### 4.1 Invariants (borrowed from gitx-release v1.0.5+ hardening)

- **Gate-then-ship**: §14 (deep audit) runs BEFORE §15 (latest symlink update). The pipeline never points `Release/latest` at unaudited artifacts. Same lesson as gitx-release Gotcha #25.
- **Wrapper rollback**: if §6+ fails after VERSION/CHANGELOG were bumped (§5/§6), the wrapper restores both before exit. If §14 fails after artifacts are built, artifacts are cleaned up; latest stays at previous version. Same as Gotcha #17.
- **`_GITX_INTERNAL_INLINE` provenance equivalent**: `release-audit.sh --inline` requires `_MAC_RELEASE_INTERNAL_INLINE=1` env (set by `release.sh`). Standalone callers of audit cannot bypass strict gates via CLI flag alone. Same as Gotcha #27.

### 4.2 End-state at success (`Release/<product>-vX.Y.Z/`)

```
<product>-vX.Y.Z.dmg                       (.app stack only — notarized + stapled, signed at DMG level)
<product>-vX.Y.Z.app.zip                   (.app stack only — notarized + stapled; for direct download)
<product>-vX.Y.Z.zip                       (binary stack only — notarized universal binary)
<product>-vX.Y.Z-source.tar.gz             (deterministic git-archive of source)
checksums.txt                              (sha256 of all artifacts above; LC_ALL=C sorted)
sbom.cyclonedx.json                        (CycloneDX 1.5)
RELEASE_NOTES.md                           (3 install paths: DMG / app.zip / from-source)
CHANGELOG.md                               (flattened cumulative)
mac-release-<timestamp>-<version>.log      (diagnostic log; sha256-attested)
```

Last line of stdout: copy-pasteable `gh release create vX.Y.Z --draft --notes-file Release/<product>-vX.Y.Z/RELEASE_NOTES.md <assets>` command. Operator pastes when ready.

---

## 5. Adapter contract: `.mac-release/manifest.toml`

Single source of truth per project. Validated at pipeline start (§1: `load_manifest`).

```toml
# .mac-release/manifest.toml — required at project root for mac-release

[product]
name        = "MacAudit"               # display name; affects bundle filename
identifier  = "com.macaudit.gui"       # CFBundleIdentifier; matches Info.plist
stack       = "swift"                  # swift | tauri | go

[build]
hook        = "scripts/build.sh"       # produces $BUILD_OUTPUT at known path
output      = "build/MyApp.app"        # path the hook produces, relative to PROJECT_ROOT
bundle_type = "app"                    # app | binary | framework

[sign]
identity         = "Developer ID Application: token hu (NN8425LUVZ)"
hardened_runtime = true
entitlements     = ".mac-release/entitlements.plist"   # optional; relative to PROJECT_ROOT
team_id          = "NN8425LUVZ"

[notarize]
profile = "MAC_RELEASE_NOTARY"         # name of stored notarytool keychain profile

[distribute]
formats = ["dmg"]                      # for [bundle_type=app]: dmg | zip | both
                                       # for [bundle_type=binary]: zip (only)

# Stack-specific blocks — only the matching one is read
[tauri]
config_path     = "src-tauri/tauri.conf.json"
capabilities    = "src-tauri/capabilities"
sidecars        = []                   # list of sidecar binary paths to sign individually
updater_format  = "tauri-native"       # v0.2+; Tauri's own updater bundle format

[swift]
spm_resource_bundle = true             # the Bundle.module gotcha — places .bundle in Contents/Resources/
xcode_project       = ""               # if non-empty, use xcodebuild instead of swift build

[go]
strip_symbols = true                   # -ldflags="-s -w"
universal     = true                   # build arm64 + amd64, lipo merge
wrap_as_app   = false                  # if true, wrap naked binary in .app bundle
```

### 5.1 Validation rules

- `[product].stack` must be one of `swift`, `tauri`, `go`. Other values → exit 2.
- `[build].bundle_type = "app"` requires `[distribute].formats` to contain at least one of `dmg | zip`.
- `[build].bundle_type = "binary"` requires `[distribute].formats = ["zip"]` (DMG meaningless for naked CLI; spec rejects DMG for binary type with clear error).
- `[sign].identity` regex: `^Developer ID Application: .+ \([A-Z0-9]{10}\)$`. Rejects malformed values before keychain lookup.
- `[notarize].profile` is a freeform string (whatever name the operator stored via `xcrun notarytool store-credentials`).
- Stack-specific block (`[tauri]` / `[swift]` / `[go]`) is required if and only if `[product].stack` matches.

### 5.2 Capability allowlist file (Tauri only)

```toml
# .mac-release/capability-allowlist.toml — optional; only read for stack="tauri"

[[capability_allowlist]]
capability    = "core:webview:allow-create-webview"
scope_pattern = "*"                    # any scope, any value
reason        = "Required for the OAuth login flow's secondary webview"
approved_by   = "TKX 2026-05-06"

[[capability_allowlist]]
capability    = "csp:null"
reason        = "App does not load remote content into webview; CSP not applicable"
approved_by   = "TKX 2026-05-06"
```

Validation: every entry MUST have non-empty `reason` and `approved_by`. Empty values → exit 2 (refuses to ship un-justified bypass; mirrors `.sanitize-ignore`'s discipline).

---

## 6. Per-stack adapter specs

### 6.1 Swift adapter (`scripts/adapters/swift.sh`)

**Build phase**: invokes `[build].hook` from manifest. Project's hook script is responsible for running `swift build -c release --arch arm64 --arch x86_64` (SPM) **or** `xcodebuild archive` (Xcode), producing the `.app` at `[build].output`.

**Stack-specific gates** (§8 of pipeline):
1. **SPM resource bundle placement**: if `[swift].spm_resource_bundle = true`, verify any `*.bundle` directories are under `Contents/Resources/`, NOT `Contents/MacOS/`. (Gotcha already documented in MacAudit's `build_app.sh`.)
2. **Universal binary**: `lipo -info "$APP/Contents/MacOS/$EXECUTABLE"` shows `Mach-O universal binary with 2 architectures: arm64 amd64`.
3. **Info.plist completeness**: `CFBundleIdentifier`, `CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleExecutable`, `LSMinimumSystemVersion` all present and non-empty.
4. **Privacy manifest** (`PrivacyInfo.xcprivacy`): warn-only in v0.1.0; promote to hard gate when Apple tightens enforcement.

**Sample project hook** (project's own `scripts/build.sh release`, ~10 lines):

```bash
#!/bin/bash
set -e
swift build -c release --arch arm64 --arch x86_64 --build-path .spm-build/release
# (project's existing build_app.sh chassis handles .app packaging — keep that)
./scripts/build_app.sh release
echo "$PROJECT_ROOT/release/v$VERSION/MyApp-$VERSION.app" > .mac-release/build-output
```

### 6.2 Tauri 2.0 adapter (`scripts/adapters/tauri.sh`)

**Build phase**: invokes `[build].hook` which should run `cargo tauri build --target universal-apple-darwin`. Tauri's own bundler produces a `.app` and (optionally) a DMG. **mac-release strips Tauri's own signing and re-signs via the common pipeline** — predictable, single signing chain across all stacks.

**Stack-specific gates** (§8 of pipeline):
1. **CSP audit**: parse `[tauri].config_path` (`tauri.conf.json`); if `app.security.csp == null` → soft-warn (Tauri 2.x default; flag for review). Allowlist via `capability-allowlist.toml` with `capability = "csp:null"`.
2. **Capability audit**: walk `[tauri].capabilities/*.json` files; classify each permission per the policy in §7 (hard-fail / soft-warn / pass / allowlisted).
3. **Sidecar binaries**: each path in `[tauri].sidecars` gets individually `codesign`'d with the same identity + hardened runtime BEFORE the parent `.app` is sealed. Audit verifies each sidecar's TeamIdentifier matches parent.
4. **Frontend `dist/` integrity**: `dist/` (or whatever Tauri's `frontendDist` resolves to) exists and contains `index.html`. Empty `dist/` is a build bug.
5. **`cargo tauri info` clean**: Rust + node + Tauri CLI versions match Cargo.lock; no version-skew warnings.

### 6.3 Go adapter (`scripts/adapters/go.sh`)

**Build phase**: invokes `[build].hook` which should produce per-arch binaries and `lipo`-merge them. If `[go].wrap_as_app = false` (CLI), output is a naked Mach-O. If `wrap_as_app = true` (rare; GUI Go tools), adapter wraps it in `.app` bundle structure.

**Stack-specific gates** (§8 of pipeline):
1. **Universal arch slices**: `lipo -info "$BUILD_OUTPUT"` shows both `arm64` and `amd64`.
2. **Symbol strip**: if `[go].strip_symbols = true`, verify binary doesn't contain debug symbols (`nm "$BIN" | grep -c '__DWARF'` should be 0).
3. **Host library leak**: `otool -L "$BIN"` shows only `/usr/lib/` and `/System/` paths. NO `/opt/homebrew/lib/`, `/usr/local/lib/`, or other host-toolchain paths. Hard-fail on any such leak.
4. **`go version` embedded matches Cargo... I mean `go.mod`'s `go` directive**.
5. **Module path username sweep**: `grep '/Users/' "$BUILD_OUTPUT" 2>&1 | head` — naked binaries can embed Go module paths; verify no host-user-name leak. (See §14: cross-username ghost gotcha.)

**Distribution-format constraint**: Go CLI defaults to `[distribute].formats = ["zip"]`. DMG is rejected for `bundle_type = "binary"` because a naked CLI in a DMG window with drag-to-Applications is an awkward UX.

**Notarization-stapling caveat**: `xcrun stapler staple` doesn't work on naked Mach-O binaries (only `.app` / `.pkg` / `.dmg`). Notarization itself works (zip + submit + Apple records ticket server-side); `spctl -a -t install` validates online. The skill emits a clear note in `RELEASE_NOTES.md`: "first-launch online check required (no offline stapling for naked CLI)".

---

## 7. Tauri capability policy (empirically validated)

Validated against the AiPromptX project (`~/tkbox/Cloud_Coding/AiPromptX/src-tauri/`) — a real Tauri 2.x app with disciplined capability scoping.

### 7.1 Hard-fail list (release blocked)

These capabilities, when granted with these patterns, are functionally privilege-escalation:

| Capability | Trigger | Rationale |
|---|---|---|
| `shell:allow-execute` | granted without `scope` array | Allows arbitrary command execution. RCE vector. |
| `fs:allow-write-file` | scoped to `**` / `$HOME/**` / `/` | Allows writing arbitrary files, including replacing system binaries. Privilege escalation. |
| `fs:allow-write-text-file` | same as above | Same as above. |
| `webview:allow-evaluate` | granted at all | Allows JS injection from Rust → webview. Rarely legitimate; if used, must be allowlisted. |

NOTE: `shell:allow-open` (open URL in browser) is the **safe** counterpart and is NOT on the hard-fail list. AiPromptX uses `shell:allow-open` correctly to open auth/privacy URLs.

### 7.2 Soft-warn list (release proceeds, operator review encouraged)

| Capability | Trigger | Rationale |
|---|---|---|
| `csp: null` | in `tauri.conf.json` `app.security.csp` | Tauri 2.x default. Common but worth flagging — many apps eventually load remote content into webview. |
| `core:webview:allow-create-webview` | granted | Lower-risk than `evaluate`, but webviews can be misused. Flag for review. |
| `fs:default` | granted | Broad-default file system permissions. Tauri's built-in default; flag for review. |
| `http:default` | granted | Same as above for HTTP. |
| `shell:default` | granted | Same as above for shell. |
| `dialog:allow-open` | with `extensions: ["*"]` | Broader than typical use. |
| `http:allow-request` | without origin scope | Should usually be scoped to specific provider URLs (AiPromptX does this correctly). |

### 7.3 Allowlist mechanism

Operator overrides via `.mac-release/capability-allowlist.toml`. Each entry MUST have non-empty `reason` and `approved_by` — empty allowlist entries fail validation (refuses to ship un-justified bypass).

### 7.4 Empirical calibration result

AiPromptX's `main.json` capability file:
- 0 hard-fail triggers ✅
- 1 soft-warn (`csp: null` in `tauri.conf.json`)
- 1 likely soft-warn (`fs:default`)

A disciplined Tauri app passes hard-fail and trips 1–2 soft-warns. That's the right calibration: strict enough to block real RCE configs, lenient enough not to block disciplined Tauri 2.x apps using framework defaults.

---

## 8. Mac-specific deep audit gates (`release-audit.sh`)

Patterned on gitx-release's `release-audit.sh` (170 gates in v1.1.6). v0.1.0 target: ~80 gates across ~12 sections. Will grow toward 150+ via TDD as bugs are discovered (same trajectory gitx-release followed).

**Section structure** (target counts):

| § | Section | Gate count | Purpose |
|---|---|---|---|
| 1 | Basic existence | 3 | Release dir, primary artifact, source tarball exist |
| 2 | Flattened docs | 10 | README / INSTALL / LICENSE / CONTRIBUTING / CHANGELOG / RELEASE_NOTES / SKILL.md (if applicable) flattened correctly |
| 3 | Doc-root sync | 7 | Flattened docs match project-root sources |
| 4 | CHANGELOG correctness | 3 | Top entry matches version, no TODO placeholder, non-empty entry |
| 5 | Source tarball content | 12 | Contains expected files, excludes `Release/`, `.git/`, build artifacts, `.DS_Store`, etc. |
| 6 | Bundle / binary content | 10 | `.app` structure (Info.plist / MacOS / Resources) OR naked binary universal arch slices |
| 7 | Mac-specific signing gates | 12 | codesign valid, TeamIdentifier matches, hardened runtime flag set, entitlements file matches manifest, deep verify (`codesign --verify --deep`), spctl `-a -t install` accepts, no quarantine xattr, signature timestamp valid |
| 8 | Notarization | 5 | Stapler ticket present (.app/.pkg/.dmg only), `xcrun stapler validate` accepts, ticket sha matches Apple's submission record |
| 9 | DMG content (when applicable) | 6 | DMG mounts cleanly, contains expected `.app`, signed at DMG level, layout valid |
| 10 | Provenance | 8 | checksums.txt covers all artifacts (.app/.dmg/.zip/source.tar.gz/install paths), sha256 verifies, SBOM lists artifacts |
| 11 | Stack-specific (Tauri only when present) | 4 | CSP / capability audit results, sidecar signing |
| 12 | RELEASE_NOTES quality | 3 | Has version, date, install instructions for each format |

**Inline-mode provenance**: same `_MAC_RELEASE_INTERNAL_INLINE=1` env pattern as gitx-release's `_GITX_INTERNAL_INLINE`. Standalone audit runs in strict mode; in-pipeline audit (called by `release.sh`) runs with relaxed `Release/latest` symlink check (skip rather than fail) because latest hasn't been flipped yet (gate-then-ship).

---

## 9. Test strategy (three layers)

### 9.1 Unit tests (fast, no external deps)

`tests/test_manifest_parse.sh`, `tests/test_capability_audit.sh`, version-detection logic, manifest validation. Pure logic; runs in <5 seconds. Always runs in `tests/run_all.sh`.

### 9.2 Fixture tests (medium speed, no Apple round-trip)

`tests/test_codesign_verify.sh` against pre-signed fixtures in `tests/fixtures/`. Synthesizes minimal `.app` bundles, runs codesign-pipeline locally with the operator's identity, verifies all gates. Runs in <30 seconds. Always runs in `tests/run_all.sh` IF an identity is available (skipped with explicit notice if no Developer ID cert in keychain).

### 9.3 End-to-end tests (gated by env)

`tests/test_notarize_pipeline.sh` does a full sign + submit + wait + staple round-trip on a tiny fixture app. Gated by `MAC_RELEASE_E2E=1` env — never runs unless operator opts in. CI never runs e2e (no signing identity in headless cloud); operator runs it before release. Round-trip is 1–10 minutes depending on Apple notary load.

### 9.4 Smoke test

`tests/test_release_pipeline_smoke.sh` runs the full pipeline against a fixture project with all phases except notarization. Validates phase ordering, rollback on injected failures, gate-then-ship invariant. Runs in <60 seconds.

---

## 10. First-run UX

### 10.1 `mac-release setup` subcommand

First-time operator setup. Walks through:

1. **Verify Developer ID cert in keychain**: `security find-identity -v -p codesigning` — if no Developer ID found, instructs operator to import via Keychain Access.
2. **Generate app-specific password prompt**: prints URL `https://appleid.apple.com/account/manage` and instructions to create app-specific password named e.g. "mac-release notarization".
3. **Store notarytool credentials**: prompts for Apple ID + Team ID + app-specific password, runs `xcrun notarytool store-credentials MAC_RELEASE_NOTARY --apple-id <email> --team-id <team> --password <pw>`. Confirms storage.
4. **Validates by listing recent submissions**: `xcrun notarytool history --keychain-profile MAC_RELEASE_NOTARY` (empty list = first-time, expected).
5. **Prints next-steps**: how to add `.mac-release/manifest.toml` to a project, how to invoke `/mac-release`.

Setup is idempotent — re-running checks state and only updates what's missing.

### 10.2 First sample manifest (in `assets/manifest.template.toml`)

Every project gets a starter manifest. The template has annotated examples for all three stacks; project chooses one and deletes the others.

### 10.3 Cross-username ghost preflight (one-time, manual)

Spec recommends operator runs `grep -r '/Users/<old-username>' .` before first `mac-release` invocation, and resolves any hits (rename, delete, or `.sanitize-ignore`). Mac releases will surface this aggressively because release-sanitize.sh hard-fails on absolute user paths. Documented in README "First-time setup" section, NOT enforced by skill (out-of-scope auto-fix).

---

## 11. Distribution channels (v0.1.0)

| Channel | Format | Stacks | Notes |
|---|---|---|---|
| Direct download | `<product>-vX.Y.Z.dmg` | swift, tauri (if `bundle_type=app`) | Notarized + stapled at both .app and DMG level |
| Direct download | `<product>-vX.Y.Z.app.zip` | swift, tauri | Notarized + stapled .app, ditto-zipped for transit |
| Direct download | `<product>-vX.Y.Z.zip` | go (if `bundle_type=binary`) | Notarized universal binary; no stapling possible (naked Mach-O) |
| Source | `<product>-vX.Y.Z-source.tar.gz` | all | Deterministic git-archive; not signed (source release) |

**Roadmap (v0.2+)**:
- Sparkle-style update channel (Swift apps only): EdDSA key generation + `appcast.xml` + `sign_update`.
- Tauri 2.x native updater format: emit Tauri's update artifact + signature.
- PKG distribution: `productbuild` + component-plist (for IT/MDM deployments).
- Homebrew Cask emission: auto-update Cask formula via `brew bump-cask-pr`.

---

## 12. GitHub upload — operator-driven

Skill never runs `gh release create`. Per TKX policy §10.10. Last line of `mac-release` stdout is a copy-pasteable command:

```
gh release create vX.Y.Z --draft \
  --notes-file Release/<product>-vX.Y.Z/RELEASE_NOTES.md \
  Release/<product>-vX.Y.Z/<product>-vX.Y.Z.dmg \
  Release/<product>-vX.Y.Z/<product>-vX.Y.Z.app.zip \
  Release/<product>-vX.Y.Z/<product>-vX.Y.Z-source.tar.gz \
  Release/<product>-vX.Y.Z/checksums.txt \
  Release/<product>-vX.Y.Z/sbom.cyclonedx.json
```

Operator runs when ready; reviews draft on web UI; clicks Publish.

---

## 13. Implementation order (v0.1.0 phased)

Per Q1 of brainstorming, all three stacks ship in v0.1.0. Implementation order optimizes for "checkpoint at ~40% complete" — Swift first, because MacAudit is the most polished candidate and provides a real test bed.

| Phase | Deliverable | Estimated effort |
|---|---|---|
| **0.0 — Skill skeleton** | Repo created, install.sh chassis, manifest.sh TOML loader, mac-release.sh wrapper, basic tests/run_all.sh | 0.5 day |
| **0.1 — Common spine** | release.sh phases 1–6 + 9 + 13–15, codesign-pipeline.sh, notarize-pipeline.sh, release-audit.sh skeleton (~30 gates) | 1 day |
| **0.2 — Swift adapter** | adapters/swift.sh, swift-specific audit gates, MacAudit successfully ships v0.1.6 as notarized DMG | 1 day |
| **0.3 — Tauri adapter** | adapters/tauri.sh, capability-audit.sh (hard/soft/allowlisted classifier), AiPromptX successfully ships as notarized DMG | 1 day |
| **0.4 — Go adapter** | adapters/go.sh, naked-binary signing path, Please_Continue successfully ships as notarized ZIP | 0.5 day |
| **0.5 — Hardening** | TDD gap-fill, audit gate count to ~80, README/INSTALL/CONTRIBUTING content, first self-bake of mac-release v0.1.0 via gitx-release | 0.5 day |

**Total**: ~4.5 working days. Checkpoint at end of Phase 0.2 (~40%): MacAudit ships notarized DMG. Even if Tauri/Go phases reveal contract issues, Swift checkpoint is independently shippable.

---

## 14. Cross-cutting gotchas (surfaced from project audits this session)

These are project-side concerns that mac-release operators will encounter on first run. The spec documents them as "expected first-run friction" in README, NOT as silent auto-fix behaviors.

### 14.1 `/Users/<other-user>` ghost (4 of 4 audited projects)

Found in:
- `Coding_mac_system_audit/HANDOFF.md` (Quick Start references old-user path)
- `Handoff/Handoff_OldBackup_0504/` (entire backup tree)
- `ClaudeMeX/Claude_TKConfig_BAK_0504/` and `ClaudeMeX/.deprecated-20260420/`
- `Please_Continue/go.mod` line 1 (`module github.com/<old-user>/please-continue` — **structural**, not just a doc string)

Mac releases will hard-fail on these via release-sanitize.sh's absolute-user-path detector. Operator must clean up before first run. Spec recommends a one-time sweep:

```bash
find . -type d \( -iname '*BAK*' -o -iname '*backup*' -o -iname '*deprecated*' \) -prune -print
grep -r '/Users/<old-user>' . --include='*.md' --include='*.sh' --include='*.go' --include='*.swift'
```

Module path renames (Go) are structural — `go.mod` `module` directive determines all import paths. Either rename early or accept the path in published artifacts.

### 14.2 Sentinel-bait substring in CHANGELOG prose (Gotcha #31 from gitx-release)

mac-release inherits gitx-release's CHANGELOG sentinel mechanism. Spec must document: when writing CHANGELOG entries describing scanner test fixtures, do NOT include literal bait strings (the auto-entry HTML-comment opener, real public IPs, real-user-name paths, real-looking emails). Use semantic-equivalent descriptions ("the auto-entry placeholder marker", "a real-looking public IP", etc.). This is the same lesson Gotcha #31 documents in gitx-release HANDOFF — and this spec applies that same lesson to itself by NOT writing the literal substrings here.

### 14.3 Tauri 2.x `csp: null` default

Operators new to Tauri 2.x will see "soft warn: csp:null" on first run and may panic. Spec documents: "this warning is expected for Tauri 2.x apps that don't load remote content; allowlist via `capability-allowlist.toml` with reason = 'app does not load remote content', or set a real CSP if the app does load remote content."

### 14.4 SwiftPM `Bundle.module` resource accessor gotcha

SPM-generated `Bundle.module` accessor only searches `resourceURL` / `bundleURL`, not `Contents/MacOS/`. Resource bundles (e.g., font bundles) MUST be placed in `Contents/Resources/` of the .app, not `Contents/MacOS/`. MacAudit's existing `build_app.sh` documents this correctly; mac-release Swift adapter §8 audit enforces it.

---

## 15. Decisions log

Locked during 2026-05-06 brainstorming session via `superpowers:brainstorming`:

| # | Question | Locked answer | Rationale |
|---|---|---|---|
| Q1 | v0.1.0 scope | All three stacks (Swift + Tauri 2.0 + Go) | All three have real candidate projects. |
| Q2 | Distribution channels (v0.1.0) | DMG + ZIP + source tarball, all attached to a future GitHub Release by the operator. (Sparkle / PKG / Homebrew Cask deferred to v0.2+.) | Mac-app-developer norm; minimal viable v0.1.0. |
| Q3 | GitHub upload step | Local artifacts only; operator runs `gh release create` manually. Skill prints copy-pasteable command at end of stdout. | TKX §10.10 (no auto-tag, no auto-push); operator controls publish timing. |
| Q4 | Repo location | Standalone `Mac_Release_Skill/` (sibling to `Git_Release_Skill/`). | Different audiences, different cadences. |
| Q5 | Source tarball | mac-release produces own via `git archive HEAD`. | Stack-specific exclusions (.entitlements, tauri.conf.json, etc.); cleaner than depending on gitx-release at runtime. |
| Q6 | Adapter contract format | TOML at `.mac-release/manifest.toml`. | Native to Tauri (Cargo.toml) + Swift (Package.swift-shaped) + Go (go.mod-shaped). Strongly typed. |
| Q7 | Tauri capability policy | Two-tier (hard-fail / soft-warn) + mandatory-justification allowlist. Empirically calibrated against AiPromptX. | Hard-fail-only is too brittle; soft-warn-only gets ignored. Two-tier matches gitx-release's `.sanitize-ignore` pattern. |

Silent commits (no user interaction needed):
- Naming: `mac-release` / `Mac_Release_Skill/` / `/mac-release` / `$mac-release`.
- Repo layout mirrors `Git_Release_Skill/`.
- Command surface: `/mac-release` (full pipeline), sub-commands `setup`, `verify <version>`, `scan <dir>`. Internal phases not exposed.
- DMG layout: basic drag-to-Applications (v0.1.0); operator-tunable via `dmg-resources/` in v0.2+.
- DMG signing: sign .app inside, then sign DMG file itself.
- Test strategy: unit + fixture + E2E (gated by `MAC_RELEASE_E2E=1`).
- Sidecar binaries (Tauri): individually signed before parent .app sealed; audit verifies each TeamIdentifier.
- Implementation order: Swift first, Tauri second, Go third (within v0.1.0).
- VERSION source: VERSION sidecar primary; manifest can override; stack-specific fallback (Info.plist / Cargo.toml / go.mod) if neither present.
- CI/no-cert behavior: hard-fail with diagnostic hint by default; `--dry-run` flag for unsigned local builds.
- First-run setup: `mac-release setup` subcommand wraps `xcrun notarytool store-credentials`.
- Privacy manifest gate: warn-only in v0.1.0; promote to hard gate later.

---

## 16. Open questions / known limitations

- **Notarization round-trip variability**: 30s–10min depending on Apple notary load. Self-bake of mac-release itself (via gitx-release) doesn't hit this; project releases do. Spec accepts this as inherent.
- **No CI signing path in v0.1.0**: operator must run on a machine with the Developer ID cert. CI cert provisioning (fastlane match, GH Actions secrets) is roadmap.
- **TOML parser in Bash**: Bash has no native TOML support. Plan: shell out to `python3 -c "import tomllib; ..."` for parsing (Python 3.11+ has `tomllib` in stdlib). Fallback for older Python: `pip install tomli`. Documented as a `mac-release setup` preflight check.
- **DMG layout polish in v0.1.0 is bare**: drag-to-Applications icon + plain volume. Branded DMG (background image, custom layout) is v0.2+. No regression risk for v0.1.0 users; just less polished.
- **Sparkle / Tauri-native-updater format emission**: deferred to v0.2+ per Q2 scope decision. Spec has placeholders; implementation in later phase.
- **Privacy manifest enforcement**: warn-only in v0.1.0. Promote to hard gate when Apple tightens enforcement (current as of 2026-05-06: required only for App Store; direct-download apps unaffected).

---

## 17. Out of scope for v0.1.0 (explicit rejections)

- iOS / iPadOS / tvOS / watchOS releases.
- Mac App Store distribution (3rd Party Mac Developer cert + ASC submission).
- TestFlight integration.
- Auto-update channels (Sparkle / Tauri's native updater).
- Fancy DMG layouts.
- CI signing (headless cert provisioning).
- Cross-compilation (e.g., from Linux). Mac signing requires macOS host.
- Privacy manifest auto-generation.
- Code obfuscation / anti-tamper.
- Universal binary verification beyond `lipo -info` (no manual fat-header parsing).
- Reproducible-build proofs across machines (we get reproducible source tarballs and reproducible DMG layouts, not reproducible signed binaries — signing inserts timestamps).

---

## 18. Roadmap (post-v0.1.0)

- **v0.2** — Sparkle for Swift apps + Tauri's native updater format. EdDSA key management.
- **v0.3** — Branded DMG layouts. Custom backgrounds, drag-to-Applications icons, license windows.
- **v0.4** — Homebrew Cask emission (`brew bump-cask-pr` integration).
- **v0.5** — PKG distribution (`productbuild` + component-plist for MDM).
- **v1.0** — Stabilize contract; promote Privacy manifest gate to hard-fail; CI signing recipes.
- **v1.1+** — TestFlight + ASC API + Mac App Store path (separate skill `mac-app-store-release` more likely).

---

## Appendix A — Comparison to gitx-release

| Aspect | gitx-release | mac-release |
|---|---|---|
| Domain | Bash skill projects (`skills/<name>/SKILL.md`) | Mac apps (`.app` / naked binary) |
| Release artifact | `.skill` bundle + source tarball + full tarball | `.dmg` / `.app.zip` / naked-binary `.zip` + source tarball |
| Signing | None (plain Mach-O if any executables — but skills are Bash) | Developer ID Application + hardened runtime + entitlements + notarization + stapling |
| Toolchain | Bash, no per-stack adapter | Per-stack adapter (Swift / Tauri / Go) |
| Capability audit | N/A | Tauri-specific (hard/soft/allowlisted) |
| Distribution channels | Tarball / `.skill` only | DMG / ZIP / source tarball |
| Source tarball recipe | `rsync` with project-specific excludes | `git archive HEAD` (deterministic) |
| Audit gate count (target) | 170 (v1.1.6) | ~80 v0.1.0, growing toward 150 |
| Self-bake target | Self (eats own dog food) | gitx-release (mac-release IS a Bash skill) |

## Appendix B — Cross-references

- gitx-release HANDOFF Gotcha #17 (wrapper rollback) → mac-release inherits.
- gitx-release HANDOFF Gotcha #25 (gate-then-ship) → mac-release inherits.
- gitx-release HANDOFF Gotcha #27 (`--inline` provenance via env) → mac-release inherits as `_MAC_RELEASE_INTERNAL_INLINE`.
- gitx-release HANDOFF Gotcha #28 (path-anchored sanitize exclusions) → mac-release inherits via vendored release-sanitize.sh.
- gitx-release HANDOFF Gotcha #29 (CHANGELOG auto-entry sentinel + warn) → mac-release inherits.
- gitx-release HANDOFF Gotcha #30 (install.sh checksums.txt verification) → mac-release inherits.
- gitx-release HANDOFF Gotcha #31 (CHANGELOG prose containing scanner-bait substrings) → mac-release inherits this lesson; spec §14.2 documents.
- gitx-release HANDOFF Decision 2026-05-04 (graceful-degradation install.sh) → mac-release inherits.
- gitx-release HANDOFF Decision 2026-05-05 (IP hard-fail with allowlist) → mac-release inherits via vendored release-sanitize.sh.

---

*End of design spec. Implementation plan to follow via `superpowers:writing-plans` skill once spec is approved.*
