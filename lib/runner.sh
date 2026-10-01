#!/usr/bin/env bash
# Collection discovery + execution loop shared by run-tests.sh and ci.sh.
# Sourced (never executed) by both entrypoints.

# Defaults; override by exporting before calling run_suite().
: "${ODA_PODMAN_IMAGE:=docker.io/jetbrains/intellij-http-client}"
: "${ODA_ENV_NAME:=dev}"
: "${ODA_ENV_FILE:=http-client.env.json}"
: "${ODA_LOG_LEVEL:=BASIC}"

# These are deliberately global, not local to run_suite: cleanup_reports is
# installed as an EXIT trap and runs after run_suite has returned, so a local
# would already be out of scope and trip `set -u`.
ODA_REPORT_ROOT="${ODA_REPORT_ROOT:-}"
ODA_KEEP_REPORTS="${ODA_KEEP_REPORTS:-0}"

cleanup_reports() {
  if [[ "${ODA_KEEP_REPORTS:-0}" -eq 0 && -n "${ODA_REPORT_ROOT:-}" \
    && -d "${ODA_REPORT_ROOT:-}" ]]; then
    rm -rf "$ODA_REPORT_ROOT"
  fi
}
trap cleanup_reports EXIT

# run_suite <report_root> <script_dir>
#
# Runs every root-level .http file with a full infrastructure reset in front of
# it, records one index row per collection, prints the summary, and returns
# non-zero when anything failed.
run_suite() {
  local report_root="$1"
  local script_dir="$2"
  local index_file="$report_root/index.tsv"

  ODA_REPORT_ROOT="$report_root"
  ODA_KEEP_REPORTS=0

  : >"$index_file"

  local -a http_files=()
  while IFS= read -r -d '' f; do
    http_files+=("$f")
  done < <(find "$script_dir" -maxdepth 1 -name '*.http' -print0 | sort -z)

  if [[ ${#http_files[@]} -eq 0 ]]; then
    echo "No .http files found in $script_dir" >&2
    return 1
  fi

  echo "=== Found ${#http_files[@]} .http files to run ==="
  echo ""

  local http_file filename report_dir log_file report_file rc

  for http_file in "${http_files[@]}"; do
    filename="$(basename "$http_file")"
    echo "=== Running: $filename ==="

    report_dir="$report_root/$filename"
    mkdir -p "$report_dir"
    log_file="$report_dir/console.log"

    # --report writes JUnit XML to reports/report.xml inside the container's
    # working directory; that path is bind-mounted to a per-collection folder
    # so reports from different collections never collide.
    # --no-progress keeps non-TTY CI logs free of progress-bar redraws.
    # The exit code is captured instead of aborting so that one broken
    # collection cannot hide the results of the remaining ones.
    rc=0
    podman run --rm \
      -v "$script_dir:/workdir:z" \
      -v "$report_dir:/workdir/reports:z" \
      -w /workdir \
      "$ODA_PODMAN_IMAGE" \
      --env-file "$ODA_ENV_FILE" \
      --env "$ODA_ENV_NAME" \
      -L "$ODA_LOG_LEVEL" \
      --no-progress \
      --report \
      -D \
      "/workdir/$filename" 2>&1 | tee "$log_file" || rc=$?

    report_file="$report_dir/report.xml"
    if [[ ! -f "$report_file" ]]; then
      report_file="$(find "$report_dir" -maxdepth 1 -name '*.xml' -print -quit \
        2>/dev/null || true)"
    fi

    printf '%s\t%s\t%s\t%s\n' \
      "$filename" "$rc" "${report_file:-}" "$log_file" >>"$index_file"

    echo "=== Finished: $filename (exit code: $rc) ==="
    echo ""
  done

  local summary_rc=0
  print_summary "$index_file" || summary_rc=$?
  echo ""

  if [[ "$summary_rc" -ne 0 ]]; then
    ODA_KEEP_REPORTS=1
    echo "=== Test run FAILED ==="
    echo "JUnit reports and console logs kept in: $report_root"
    return 1
  fi

  echo "=== Test run PASSED ==="
  return 0
}
