#!/usr/bin/env bash
# Local runner: executes every root-level .http collection and prints a
# pass/fail summary parsed from the ijhttp JUnit XML reports.
#
# This is the same suite ci.sh runs; the only difference is the log level,
# which is VERBOSE here so request/response bodies are visible while debugging.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/setup.sh
source "$SCRIPT_DIR/lib/setup.sh"
# shellcheck source=lib/summary.sh
source "$SCRIPT_DIR/lib/summary.sh"
# shellcheck source=lib/runner.sh
source "$SCRIPT_DIR/lib/runner.sh"

export ODA_LOG_LEVEL="${ODA_LOG_LEVEL:-VERBOSE}"

REPORT_ROOT="$(mktemp -d)"
run_suite "$REPORT_ROOT" "$SCRIPT_DIR"