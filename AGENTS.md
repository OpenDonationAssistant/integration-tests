# PROJECT KNOWLEDGE BASE

**Generated:** 2026-09-25
**Commit:** 60c70fc
**Branch:** main

## OVERVIEW
This repository is a flat collection of JetBrains HTTP Client request collections for exercising OpenDonationAssistant (ODA) APIs. It is an integration-test/request-workspace repository, not an application: there is no application source, package manifest, build system, or CI workflow.

## STRUCTURE
```text
.
├── *.http                 # 20 request collections; all runner-discovered tests live at root
├── login.http             # Shared OAuth password-grant request and global token setup
├── http-client.env.json   # Local-only HTTP Client environment; ignored by Git
├── run-tests.sh           # Destructive per-collection integration runner (VERBOSE)
├── ci.sh                  # Same suite for non-interactive use (BASIC logging)
├── lib/                   # Shared runner library, sourced by both entrypoints
│   ├── setup.sh           # `setup()` infrastructure reset
│   ├── runner.sh          # Collection discovery + Podman execution loop
│   └── summary.sh         # JUnit-XML run summary and fallback
├── test.json              # Inert copy-file payload template; not referenced by the suite
└── .gitignore             # Excludes the local environment file
```

Request files are grouped by product/service domain rather than directory: actions, alerts, automation, config, recipients, gateways, subscriptions, history, print, widgets (`donaton`, `media`, `reel`, `toplist`), and integrations (`kick`, `max`, `streamelements`, `twitch`, `vk`).

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Authenticate a collection | `login.http` | Stores the user access token in `client.global.token`; `recipient.http` also stores `admin-token`. |
| Run a scenario | Relevant root `*.http` file | Most authenticated collections start with `run ./login.http`. Requests execute top-to-bottom. |
| Pass state between requests | Response/pre-request scripts | Uses `client.global.set(...)` for IDs, tokens, and timestamps. |
| Check async events | `STOMP_API_ENDPOINT` requests | The local STOMP capture service is polled through HTTP; suites commonly clear queues first. |
| Run all collections | `run-tests.sh` or `ci.sh` | Both run the identical suite and print the same summary; only the log level differs. Discovers every root-level `*.http`; no filter or namespace guard exists. |
| Change reset/loop/summary logic | `lib/*.sh` | Both entrypoints are thin wrappers; edit the library, not the entrypoints. |
| Configure endpoints/credentials | `http-client.env.json` | Local `dev` profile; contains secrets and must remain untracked. |
| Inspect webhook examples | `twitch.http`, `vk.http` | Example catalogs; neither file has response assertions. |
| Inspect a domain flow | File named after the service | Several files combine setup, payment, event verification, and cleanup in one collection. |

## REQUEST CONVENTIONS
- Name request sections with `###`; uppercase descriptive names are dominant.
- Use environment variables for service endpoints and credentials.
- Use `Authorization: Bearer {{token}}`; admin-only operations use `Bearer {{admin-token}}`.
- Use `client.global.set(...)` and `client.global.get(...)` to carry IDs and derived state.
- Use `{{$uuid}}` / `{{$timestamp}}` for generated values.
- Use `client.test("...", function () { client.assert(...); })` in response scripts for behavior checks.
- Keep request execution order and state dependencies explicit when changing a collection.
- Add cleanup for created widgets/actions/subscriptions; several existing scenarios rely on the runner's infrastructure reset instead.

## RUNNER
`./run-tests.sh` and `./ci.sh` are the two entrypoints; both source `lib/setup.sh`, `lib/summary.sh`, and `lib/runner.sh` and run the identical suite, differing only in log level (`ODA_LOG_LEVEL`: `VERBOSE` locally, `BASIC` in CI). For **each** root-level `.http` file the runner:

1. Stops the user `container-postgres` service.
2. Deletes `/tmp/postgres` with `sudo`.
3. Starts PostgreSQL.
4. Deletes all pods visible to the active Kubernetes context.
5. Sleeps for 30 seconds.
6. Restarts the user `capture-stomp` service.
7. Runs the collection with the unpinned `docker.io/jetbrains/intellij-http-client` image through non-interactive Podman, using `http-client.env.json`, environment `dev`, `--no-progress`, `-D`, and `--report`.

### Run summary
`ijhttp --report` writes JUnit XML to `reports/report.xml` inside the container. The runner bind-mounts that path to a per-collection directory under a temp root, so reports never collide, then prints one table at the end of the run:

```text
FILE       REQUESTS   CHECKS   FAILED   SKIP  RESULT
bad.http          2        1        1      0  FAIL  (client exit code 1)
good.http         1        1        0      0  PASS
TOTAL             3        2        1      0  FAIL
```

`REQUESTS` counts distinct request names, not `<testcase>` elements — each request also emits framework-generated `Response` and `Response Handler` cases. Failed requests are listed below the table with the failing check and message. The runner exits non-zero on failure and keeps the reports, printing their location; on success the temp root is deleted.

Report structure, verified against real output: root is `<testsuites>`; request identity is `testcase/@classname` (`http.<NAME>`) while `@name` is `Response`, `Response Handler`, or the `client.test()` label; assertion failures and transport errors are both `<failure type="Error">`, and `<error>` is effectively unused.

Pass/fail comes from the report, **not** the exit code: ijhttp documents no exit code for failed assertions (IJPL-198145 shows a broken JS response handler still exiting `0`), so the exit code is treated only as a crash signal. Without `python3`, `lib/summary.sh` falls back to ijhttp's own `<n> requests completed, <m> have failed tests` stdout line. Override the temp root with `ODA_REPORT_ROOT`, the settle delay with `ODA_SETTLE_SECONDS`, and the image with `ODA_PODMAN_IMAGE`.

Required host prerequisites include `systemctl --user`, `sudo`, `kubectl`, Podman, local ODA services, the two user services, and network access to configured authentication/container endpoints. `python3` is optional (summary fallback). `set -euo pipefail` makes the runner fail immediately on errors. A full run is long and should not be treated as a lightweight test command.

## SECURITY & ENVIRONMENT
- `http-client.env.json` is ignored, not encrypted. Keep it local and never copy its values into documentation, fixtures, or commits.
- Treat active/commented credentials, JWTs, client secrets, and token-like overlay paths in request files as secrets. Do not reproduce them in new files or logs.
- Several suites call production or external services, including authentication, a direct Kick URL, VK media, and fixed broadcaster/account data. Validate authorization before running them.
- `run-tests.sh` and `ci.sh` have no Kubernetes context confirmation. Verify the current context and local data before invoking either.

## KNOWN LIMITATIONS / CAVEATS
- `twitch.http`, `vk.http`, `kick.http`, `max.http`, `news.http`, `print.http`, `streamelements.http`, and `subscriptions.http` are examples/smoke requests with limited or no assertions.
- Some scenarios use fixed IDs, usernames, timestamps, external metadata, and hard-coded cleanup gaps; these are environment-sensitive.
- `streamelements.http` depends on `streamerbottoken` populated by `recipient.http`; the dependency is not enforced by the file itself.
- Several async wait helpers call `wait(ms)` without an explicit `await`; do not assume the delay semantics without checking the HTTP Client behavior.
- `test.json` is not discovered by the runner and has no verified consumers.
- No CI configuration or build manifest exists in this repository.

## CODE MAP
| Symbol / entry | Location | Role |
|----------------|----------|------|
| `setup()` | `lib/setup.sh` | Resets PostgreSQL, Kubernetes pods, and STOMP capture. |
| `run_suite()` | `lib/runner.sh` | Discovers, runs, and indexes every root-level `*.http` file. |
| `print_summary()` | `lib/summary.sh` | Parses the JUnit reports into the final pass/fail table. |
| `SCRIPT_DIR` | `run-tests.sh` / `ci.sh` | Resolves request-file paths independent of caller directory. |
| Shared OAuth login | `login.http` | Establishes `token` global state. |
| Admin login and feature setup | `recipient.http` | Establishes `admin-token` and integration state. |
| EventSub example catalog | `twitch.http` | Sends challenge and notification payload examples. |

## COMMANDS
```bash
# Read-only repository inspection
git status --short --branch
git diff --stat

# Intended full suite (DESTRUCTIVE; requires review of Kubernetes context and local data)
./run-tests.sh   # local, VERBOSE
./ci.sh          # non-interactive, BASIC
```

Do not run `./run-tests.sh` as part of documentation generation or routine validation.

## NOTES
The repository has no nested source hierarchy, so a single root `AGENTS.md` is sufficient. Keep this file focused on repository-specific facts; update it when runner behavior, environment variables, or request-collection conventions change.
