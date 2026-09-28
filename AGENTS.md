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
├── run-tests.sh           # Destructive per-collection integration runner
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
| Run all collections | `run-tests.sh` | Discovers every root-level `*.http`; no filter or namespace guard exists. |
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
`./run-tests.sh` is the only orchestration command. For **each** root-level `.http` file it:

1. Stops the user `container-postgres` service.
2. Deletes `/tmp/postgres` with `sudo`.
3. Starts PostgreSQL.
4. Deletes all pods visible to the active Kubernetes context.
5. Sleeps for 30 seconds.
6. Restarts the user `capture-stomp` service.
7. Runs the collection with the unpinned `docker.io/jetbrains/intellij-http-client` image through interactive Podman, using `http-client.env.json`, environment `dev`, verbose logging, and `-D`.

Required host prerequisites include `systemctl --user`, `sudo`, `kubectl`, Podman, local ODA services, the two user services, and network access to configured authentication/container endpoints. `set -euo pipefail` makes the runner fail immediately on errors. A full run is long and should not be treated as a lightweight test command.

## SECURITY & ENVIRONMENT
- `http-client.env.json` is ignored, not encrypted. Keep it local and never copy its values into documentation, fixtures, or commits.
- Treat active/commented credentials, JWTs, client secrets, and token-like overlay paths in request files as secrets. Do not reproduce them in new files or logs.
- Several suites call production or external services, including authentication, a direct Kick URL, VK media, and fixed broadcaster/account data. Validate authorization before running them.
- `run-tests.sh` has no Kubernetes context confirmation. Verify the current context and local data before invoking it.

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
| `setup()` | `run-tests.sh:4` | Resets PostgreSQL, Kubernetes pods, and STOMP capture. |
| `SCRIPT_DIR` | `run-tests.sh:33` | Resolves request-file paths independent of caller directory. |
| HTTP collection loop | `run-tests.sh:52-64` | Runs sorted root-level `*.http` files through Podman. |
| Shared OAuth login | `login.http` | Establishes `token` global state. |
| Admin login and feature setup | `recipient.http` | Establishes `admin-token` and integration state. |
| EventSub example catalog | `twitch.http` | Sends challenge and notification payload examples. |

## COMMANDS
```bash
# Read-only repository inspection
git status --short --branch
git diff --stat

# Intended full suite (DESTRUCTIVE; requires review of Kubernetes context and local data)
./run-tests.sh
```

Do not run `./run-tests.sh` as part of documentation generation or routine validation.

## NOTES
The repository has no nested source hierarchy, so a single root `AGENTS.md` is sufficient. Keep this file focused on repository-specific facts; update it when runner behavior, environment variables, or request-collection conventions change.
