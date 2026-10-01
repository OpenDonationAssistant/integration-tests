#!/usr/bin/env bash
# Infrastructure reset executed before every .http collection.
# Sourced (never executed) by run-tests.sh and ci.sh.

setup() {
  local settle_seconds="${ODA_SETTLE_SECONDS:-30}"

  echo "=== Setup: stopping container-postgres ==="
  systemctl --user stop container-postgres

  echo "=== Setup: removing /tmp/postgres ==="
  sudo rm -rf /tmp/postgres

  echo "=== Setup: starting container-postgres ==="
  systemctl --user start container-postgres

  echo "=== Setup: deleting all k8s pods ==="
  # -r is required: without it xargs still invokes `kubectl delete` when the
  # cluster is already empty, the call errors, and `set -e` aborts the run.
  kubectl get pods -o name | xargs -r kubectl delete

  echo "=== Setup: waiting ${settle_seconds}s ==="
  sleep "$settle_seconds"

  echo "=== Setup: restarting capture-stomp ==="
  systemctl --user restart capture-stomp

  echo "=== Setup: done ==="
  echo ""
}
