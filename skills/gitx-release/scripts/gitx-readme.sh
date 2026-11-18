#!/bin/bash
# gitx-readme.sh — DEPRECATED thin shim (Boss-signed Q-A, v1.11.0).
# The deterministic bilingual doc generator is now scripts/docs-pipeline.sh.
# Retained as a ZERO-LOGIC forwarder so installed bundles, the README
# "Direct script entrypoints" table, release-audit.sh §0g, and any other
# caller keep working unchanged. Why a shim not a delete: deleting would
# break installed bundles + the signed README entrypoint table + every
# caller — net-negative churn the project exists to kill (frozen spec §6).
# All flags/modes/exit codes are docs-pipeline.sh's (it absorbed this
# script's logic in v1.11.0 T2; --check|--init|--force|--dry-run|--help|… ).
# usage: gitx-readme.sh [--check|--init|--force|--dry-run|--help|…]  (DEPRECATED — forwards to docs-pipeline.sh)
set -euo pipefail
_dp_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "⚠️  gitx-readme.sh is deprecated — forwarding to docs-pipeline.sh" >&2
exec bash "$_dp_dir/docs-pipeline.sh" "$@"
