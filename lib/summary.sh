#!/usr/bin/env bash
# Run summary built from the JUnit XML that `ijhttp --report` produces.
# Sourced (never executed) by run-tests.sh and ci.sh.
#
# Why XML rather than exit codes: ijhttp does not document an exit code for
# failed client.test() assertions (YouTrack IJPL-198145 shows a broken JS
# response handler still exiting 0), so exit codes are treated only as a coarse
# crash signal. The JUnit report is the authoritative pass/fail source.

# Index row format written by lib/runner.sh: name<TAB>rc<TAB>report<TAB>log
print_summary() {
  local index="$1"

  if [[ ! -s "$index" ]]; then
    echo "No results to summarise." >&2
    return 1
  fi

  if command -v python3 >/dev/null 2>&1; then
    print_summary_xml "$index"
  else
    echo "python3 not found; using the stdout-count fallback summary." >&2
    print_summary_fallback "$index"
  fi
}

# ──────────────────────────────────────────────────────────────────
# Primary summary: parse the JUnit XML reports
# ──────────────────────────────────────────────────────────────────
# Structure verified against real `ijhttp --report` output:
#   * root element is <testsuites>, child is <testsuite tests failures errors skip>
#   * every <testcase> carries classname="http.<REQUEST NAME>" -- that, not
#     @name, is the request identity; @name is "Response", "Response Handler",
#     or the client.test() label
#   * assertion failures AND transport errors are both <failure type="Error">;
#     <error> is effectively unused by ijhttp
#   * each request yields several <testcase> elements (one "Response", one per
#     assertion, one "Response Handler"), so requests are counted as distinct
#     classnames rather than as testcase count
print_summary_xml() {
  python3 - "$1" <<'PY'
import os
import sys
import xml.etree.ElementTree as ET

FRAMEWORK_CHECKS = {"Response", "Response Handler"}

index_path = sys.argv[1]
rows = []
failures = []
unreadable = []


def request_of(case):
    """ijhttp puts the request name in @classname as 'http.<NAME>'."""
    cls = case.get("classname") or ""
    if cls.startswith("http."):
        return cls[len("http."):]
    return cls or "<unnamed request>"


def first_line(text):
    for line in (text or "").strip().splitlines():
        if line.strip():
            return line.strip()
    return ""


with open(index_path, encoding="utf-8") as handle:
    for raw in handle:
        raw = raw.rstrip("\n")
        if not raw:
            continue
        fields = raw.split("\t")
        name = fields[0]
        rc = fields[1] if len(fields) > 1 else ""
        report = fields[2] if len(fields) > 2 else ""
        log = fields[3] if len(fields) > 3 else ""

        requests = checks = skipped = failed_requests = 0
        note = ""
        parse_ok = True

        if report and os.path.isfile(report):
            try:
                root = ET.parse(report).getroot()
                suites = (
                    [root] if root.tag == "testsuite" else root.findall(".//testsuite")
                )
                for suite in suites:
                    seen = {}
                    for case in suite.findall("testcase"):
                        request = request_of(case)
                        label = case.get("name") or ""
                        entry = seen.setdefault(
                            request, {"checks": 0, "failed": False, "msgs": []}
                        )
                        if label not in FRAMEWORK_CHECKS:
                            entry["checks"] += 1
                        if case.find("skipped") is not None:
                            skipped += 1

                        node = case.find("failure")
                        kind = "FAIL"
                        if node is None:
                            node = case.find("error")
                            kind = "ERROR"
                        if node is not None:
                            entry["failed"] = True
                            entry["msgs"].append(
                                (
                                    label if label not in FRAMEWORK_CHECKS else "request",
                                    kind,
                                    first_line(node.get("message") or node.text),
                                )
                            )

                    requests += len(seen)
                    for request, entry in seen.items():
                        checks += entry["checks"]
                        if entry["failed"]:
                            failed_requests += 1
                            for label, kind, message in entry["msgs"]:
                                failures.append((name, request, label, kind, message))
            except Exception as parse_error:  # noqa: BLE001
                parse_ok = False
                note = f"could not parse report: {parse_error}"
        else:
            # No JUnit report: fall back to ijhttp's own stdout counts.
            # None means "unknown" and must never reach the totals.
            requests = failed_requests = None
            status_line = ""
            counts = ""
            if log and os.path.isfile(log):
                with open(log, encoding="utf-8", errors="replace") as log_handle:
                    content = log_handle.read()
                if "RUN FAILED" in content:
                    status_line = "RUN FAILED"
                elif "RUN SUCCESSFUL" in content:
                    status_line = "RUN SUCCESSFUL"
                for line in reversed(content.splitlines()):
                    if " requests completed, " in line and " have failed tests" in line:
                        counts = line.strip()
                        break
            if counts:
                digits = "".join(c if c.isdigit() else " " for c in counts).split()
                if len(digits) >= 2:
                    requests, failed_requests = int(digits[0]), int(digits[1])
            if status_line == "RUN SUCCESSFUL" and rc == "0" and not failed_requests:
                note = "no JUnit report"
            else:
                parse_ok = False
                note = status_line or "no JUnit report produced"

        if not parse_ok or rc != "0" or (failed_requests or 0) > 0:
            status = "FAIL"
            note = note or (f"client exit code {rc}" if rc != "0" else "")
        else:
            status = "PASS"

        rows.append(
            (name, requests, checks, failed_requests, skipped, status, note)
        )

width = max([len(row[0]) for row in rows] + [4])
header = (
    f"{'FILE'.ljust(width)}  {'REQUESTS':>8}  {'CHECKS':>7}  "
    f"{'FAILED':>7}  {'SKIP':>5}  RESULT"
)
divider = "-" * len(header)

print()
print("=" * len(header))
print("TEST RUN SUMMARY")
print("=" * len(header))
print(header)
print(divider)
for name, requests, checks, failed, skipped, status, note in rows:
    req_txt = "?" if requests is None else str(requests)
    fail_txt = "?" if failed is None else str(failed)
    suffix = f"  ({note})" if note and status == "FAIL" else ""
    print(
        f"{name.ljust(width)}  {req_txt:>8}  {checks:7d}  {fail_txt:>7}  "
        f"{skipped:5d}  {status}{suffix}"
    )
print(divider)
# Unknown counts (no report, no stdout counts) are excluded from the totals
# rather than silently folded in as zero.
def total(index):
    return sum(row[index] for row in rows if row[index] is not None)

totals = [total(i) for i in range(1, 4)] + [total(4)]
overall = "PASS" if all(row[5] == "PASS" for row in rows) else "FAIL"
print(
    f"{'TOTAL'.ljust(width)}  {totals[0]:8d}  {totals[1]:7d}  {totals[2]:7d}  "
    f"{totals[3]:5d}  {overall}"
)
print("=" * len(header))

if failures:
    print()
    print("Failed requests:")
    for file_name, request, label, kind, message in failures:
        print(f"  [{kind}] {file_name} :: {request}")
        detail = f" - {message}" if message else ""
        print(f"      check \"{label}\"{detail}")

if unreadable:
    print()
    print("Reports that could not be read:")
    for file_name in unreadable:
        print(f"  - {file_name}")

print()


def plural(count, singular, suffix="s"):
    return f"{count} {singular}{'' if count == 1 else suffix}"


if overall == "PASS":
    print(
        f"Result: PASS ({plural(len(rows), 'file')}, "
        f"{plural(totals[0], 'request')}, 0 failed requests)"
    )
    sys.exit(0)
print(
    f"Result: FAIL ({plural(len(rows), 'file')}, "
    f"{plural(totals[2], 'failed request')}, {plural(totals[1], 'check')})"
)
sys.exit(1)
PY
}

# ──────────────────────────────────────────────────────────────────
# Fallback summary for hosts without python3
# ──────────────────────────────────────────────────────────────────
# ijhttp prints an authoritative "<n> requests completed, <m> have failed
# tests" line and a final RUN FAILED / RUN SUCCESSFUL, so the counts can be
# recovered from the console log without parsing XML.
print_summary_fallback() {
  local index="$1"
  local overall=0
  local line name rc report log counts

  printf '\n%s\n' "==================== TEST RUN SUMMARY (fallback) ===================="
  printf '%-32s %10s %10s  %s\n' "FILE" "REQUESTS" "FAILED" "RESULT"

  # Fields are split by hand rather than with `IFS=$'\t' read`: tab is an IFS
  # whitespace character, so `read` would collapse the empty report field of a
  # collection that produced no report and shift the log path into it.
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    name="${line%%$'\t'*}"
    line="${line#*$'\t'}"
    rc="${line%%$'\t'*}"
    line="${line#*$'\t'}"
    report="${line%%$'\t'*}"
    log="${line#*$'\t'}"

    local requests="?" failed="?" status="FAIL" note=""
    counts=""
    if [[ -n "$log" && -f "$log" ]]; then
      counts="$(grep -oE '[0-9]+ requests completed, [0-9]+ have failed tests' \
        "$log" 2>/dev/null | tail -1 || true)"
    fi
    if [[ -n "$counts" ]]; then
      requests="$(sed -E 's/^([0-9]+) requests completed.*/\1/' <<<"$counts")"
      failed="$(sed -E 's/.*, ([0-9]+) have failed tests.*/\1/' <<<"$counts")"
    fi

    if [[ "$rc" != "0" ]]; then
      note="  (exit $rc)"
    elif [[ -n "$report" && -s "$report" ]]; then
      status="PASS"
    elif [[ "$failed" == "0" && -n "$log" && -f "$log" ]] \
      && grep -q 'RUN SUCCESSFUL' "$log"; then
      status="PASS"
    else
      note="  (no report, run status unknown)"
    fi

    [[ "$status" == "FAIL" ]] && overall=1
    printf '%-32s %10s %10s  %s%s\n' \
      "$name" "$requests" "$failed" "$status" "$note"
  done <"$index"

  printf '%s\n' "------------------------------------------------------------------"
  if [[ "$overall" -eq 0 ]]; then
    echo "Result: PASS"
  else
    echo "Result: FAIL"
  fi
  return "$overall"
}