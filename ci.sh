#!/usr/bin/env bash
# CI runner: identical suite to run-tests.sh, tuned for non-interactive use.
# Runs without a TTY, suppresses the progress bar, keeps the default BASIC log
# level for readable CI output, and exits non-zero if any collection fails.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/setup.sh
source "$SCRIPT_DIR/lib/setup.sh"
# shellcheck source=lib/summary.sh
source "$SCRIPT_DIR/lib/summary.sh"
# shellcheck source=lib/runner.sh
source "$SCRIPT_DIR/lib/runner.sh"

export ODA_LOG_LEVEL="${ODA_LOG_LEVEL:-BASIC}"

REPORT_ROOT="${ODA_REPORT_ROOT:-$(mktemp -d)}"
run_suite "$REPORT_ROOT" "$SCRIPT_DIR"
