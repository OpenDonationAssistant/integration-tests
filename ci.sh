# ──────────────────────────────────────────────────────────────────
# Determine which .http files to run
# ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
http_files=()
while IFS= read -r -d '' f; do
  http_files+=("$f")
done < <(find "$SCRIPT_DIR" -maxdepth 1 -name '*.http' -print0 | sort -z)

if [[ ${#http_files[@]} -eq 0 ]]; then
  echo "No .http files found in $SCRIPT_DIR" >&2
  exit 1
fi

echo "=== Found ${#http_files[@]} .http files to run ==="
echo ""

# ──────────────────────────────────────────────────────────────────
# Run each .http file via the JetBrains HTTP Client container
# ──────────────────────────────────────────────────────────────────
PODMAN_IMAGE="docker.io/jetbrains/intellij-http-client"

for http_file in "${http_files[@]}"; do
  filename="$(basename "$http_file")"
  setup
  echo "=== Running: $filename ==="

  podman run --rm -it \
    -v "$SCRIPT_DIR:/workdir:z" \
    "$PODMAN_IMAGE" \
    --env-file http-client.env.json \
    --env dev \
    -L VERBOSE \
    -D \
    "/workdir/$filename"

  echo "=== Passed: $filename ==="
  echo ""
done

echo "=== All tests passed ==="
