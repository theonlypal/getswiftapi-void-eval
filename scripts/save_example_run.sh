#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/save_example_run.sh <openai|anthropic> <direct|swiftapi>

Copies the most recent staged run from results/latest into the committed example
directories under artifacts/ and attestations/.
EOF
}

fail() {
  echo "$1" >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROVIDER="${1:-}"
MODE="${2:-}"

case "$PROVIDER" in
  openai|anthropic) ;;
  *) usage >&2; exit 1 ;;
esac

case "$MODE" in
  direct|swiftapi) ;;
  *) usage >&2; exit 1 ;;
esac

LATEST_PROVIDER_DIR="$ROOT/results/latest/$PROVIDER"
[ -d "$LATEST_PROVIDER_DIR" ] || fail "Missing staged provider directory: $LATEST_PROVIDER_DIR"

SUMMARY_FILE="$LATEST_PROVIDER_DIR/case_summary.json"
[ -f "$SUMMARY_FILE" ] || fail "Missing case summary: $SUMMARY_FILE"

ACTUAL_MODE="$(python3 - "$SUMMARY_FILE" <<'PY'
import json
import sys
from pathlib import Path
summary = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
print(summary["mode"])
PY
)"
[ "$ACTUAL_MODE" = "$MODE" ] || fail "Latest $PROVIDER run is mode=$ACTUAL_MODE, not mode=$MODE"

ARTIFACT_DIR="$ROOT/artifacts/$PROVIDER-$MODE"
ATTESTATION_DIR="$ROOT/attestations/$PROVIDER-$MODE"

rm -rf "$ARTIFACT_DIR" "$ATTESTATION_DIR"
mkdir -p "$ARTIFACT_DIR" "$ROOT/attestations"

cp "$ROOT/results/latest/manifest.txt" "$ARTIFACT_DIR/top_manifest.txt"
cp "$LATEST_PROVIDER_DIR/manifest.txt" "$ARTIFACT_DIR/manifest.txt"
cp "$LATEST_PROVIDER_DIR/case_summary.json" "$ARTIFACT_DIR/case_summary.json"
cp "$LATEST_PROVIDER_DIR/run.log" "$ARTIFACT_DIR/run.log"
cp -R "$LATEST_PROVIDER_DIR/raw" "$ARTIFACT_DIR/raw"
cp -R "$LATEST_PROVIDER_DIR/records" "$ARTIFACT_DIR/records"

if [ -d "$LATEST_PROVIDER_DIR/attestations" ]; then
  cp -R "$LATEST_PROVIDER_DIR/attestations" "$ATTESTATION_DIR"
fi
