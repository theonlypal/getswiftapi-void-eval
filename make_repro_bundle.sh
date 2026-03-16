#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./make_repro_bundle.sh

Packages the most recent successful ./run_eval.sh invocation into a zip bundle.
EOF
}

fail() {
  echo
  echo "FAILURE"
  echo "$1" >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

case "${1:-}" in
  "")
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

for cmd in ditto find shasum; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Required command not found: $cmd"
done

LATEST_DIR="$ROOT/results/latest"
[ -f "$LATEST_DIR/run.success" ] || fail "No successful eval output is staged in results/latest. Run ./run_eval.sh openai, ./run_eval.sh anthropic, or ./run_eval.sh all first."
[ -f "$LATEST_DIR/manifest.txt" ] || fail "results/latest/manifest.txt is missing."

HAS_PROVIDER=0
for provider in openai anthropic; do
  if [ -f "$LATEST_DIR/$provider/manifest.txt" ]; then
    HAS_PROVIDER=1
  fi
done
[ "$HAS_PROVIDER" -eq 1 ] || fail "results/latest does not contain any successful provider outputs."

STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
BUNDLE_DIR="$ROOT/reproducibility_bundle"
ZIP_PATH="$ROOT/reproducibility_bundle_${STAMP}.zip"
CHECKSUM_PATH="$ROOT/checksums_${STAMP}.sha256"
GIT_COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"
cp -R "$LATEST_DIR" "$BUNDLE_DIR/results_latest"

{
  echo "# Full Report"
  echo
  echo "- Generated at (UTC): $GENERATED_AT"
  echo "- Repository path: $ROOT"
  echo "- Git commit: $GIT_COMMIT"
  echo
  echo "## Canonical eval entrypoints"
  echo "- \`eval/run_openai.py\`"
  echo "- \`eval/run_anthropic.py\`"
  echo
  echo "## Successful invocation packaged here"
  sed 's/^/- /' "$LATEST_DIR/manifest.txt"
  echo
  echo "## Included files"
  find "$BUNDLE_DIR/results_latest" -type f | sort | sed "s|^$BUNDLE_DIR/|- |"
  echo
  echo "## Notes"
  echo "- This bundle only includes files from the most recent successful \`./run_eval.sh\` invocation staged in \`results/latest/\`."
  echo "- No GitHub release or published external artifact is implied by this bundle."
} > "$BUNDLE_DIR/Full_Report.md"

(
  cd "$BUNDLE_DIR"
  find . -type f ! -name 'SHA256SUMS.txt' | sort | while IFS= read -r file; do
    shasum -a 256 "$file"
  done
) > "$BUNDLE_DIR/SHA256SUMS.txt"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$BUNDLE_DIR" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" | tee "$CHECKSUM_PATH"

echo
echo "SUCCESS"
echo "bundle directory: $BUNDLE_DIR"
echo "bundle zip: $ZIP_PATH"
echo "checksum file: $CHECKSUM_PATH"
