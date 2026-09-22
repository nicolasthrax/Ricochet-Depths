#!/usr/bin/env bash
# Runs the headless dry-run simulator. Output is a lower-bound estimate of run length.
set -euo pipefail
cd "$(dirname "$0")/.."
LUAU_BIN="${LUAU_BIN:-luau}" python3 tests/run.py tools/dryrun.luau
