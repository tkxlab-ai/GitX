# Scripts Index

Entry points for the release pipeline. Most users should call `scripts/release.sh` or `RELEASE_SCRIPT` (thin wrapper).

| Script | Role | Called By |
|--------|------|-----------|
| [`release.sh`](release.sh) | **Main entry** — full release pipeline (12 functions) | User / CI |
| [`release-audit.sh`](release-audit.sh) | Post-release 40+ item deep audit | release.sh / User |
| [`release-sanitize.sh`](release-sanitize.sh) | 6-dimension sensitive info scan | release.sh / User |
| [`emit-sbom.sh`](emit-sbom.sh) | CycloneDX 1.5 SBOM generator | release.sh (stage 2.7) |
| [`emit-token-usage.sh`](emit-token-usage.sh) | Runtime token cost estimator | release.sh (stage 2.7b) |
| [`scan-credentials.sh`](scan-credentials.sh) | Credential pattern scanner | release-sanitize.sh |
| [`sync-dual-source.sh`](sync-dual-source.sh) | Sync root scripts/ → skill bundle scripts/ | User / CI |

### Shared Library

| File | Role | Used By |
|------|------|---------|
| `lib/detect-project.sh` | Auto-detect PROJECT_NAME + SKILL_NAME | release.sh, release-audit.sh, sync-dual-source.sh |
