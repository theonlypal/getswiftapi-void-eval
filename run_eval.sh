#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./run_eval.sh [openai|anthropic|all] [--via-swiftapi]

Runs the canonical eval runner(s) already present in this repository and stages
the most recent successful invocation into results/latest/.
EOF
}

fail() {
  echo
  echo "FAILURE"
  echo "$1" >&2
  exit 1
}

missing_modules() {
  "$PYTHON" - "$@" <<'PY'
import importlib.util
import sys

missing = [name for name in sys.argv[1:] if importlib.util.find_spec(name) is None]
if missing:
    print(" ".join(missing))
    raise SystemExit(1)
PY
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

MODE="openai"
VIA_SWIFTAPI=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    openai|anthropic|all)
      MODE="$1"
      ;;
    --via-swiftapi)
      VIA_SWIFTAPI=1
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
  shift
done

if [ -x "$ROOT/.venv/bin/python" ]; then
  PYTHON="$ROOT/.venv/bin/python"
else
  PYTHON="$(command -v python3 || true)"
fi

[ -n "${PYTHON:-}" ] || fail "python3 was not found. Create the virtualenv with: python3 -m venv .venv"

if [ -x "$ROOT/.venv/bin/pip" ]; then
  PIP_INSTALL_CMD="$ROOT/.venv/bin/pip install -r requirements.txt"
else
  PIP_INSTALL_CMD="$PYTHON -m pip install -r requirements.txt"
fi

for path in \
  "prompts/artifact.txt" \
  "prompts/controls.txt" \
  "prompts/system.txt" \
  "eval/run_openai.py" \
  "eval/run_anthropic.py" \
  "requirements.txt"
do
  [ -f "$ROOT/$path" ] || fail "Required file is missing: $path"
done

if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/.env"
  set +a
fi

case "$MODE" in
  all)
    PROVIDERS="openai anthropic"
    ;;
  *)
    PROVIDERS="$MODE"
    ;;
esac

RUN_MODE="direct"
if [ "$VIA_SWIFTAPI" -eq 1 ]; then
  RUN_MODE="swiftapi"
fi

for provider in $PROVIDERS; do
  case "$provider" in
    openai)
      if ! missing="$(missing_modules openai dotenv 2>/dev/null)"; then
        fail "Missing Python dependencies for OpenAI run: $missing. Install them with: $PIP_INSTALL_CMD"
      fi
      [ -n "${OPENAI_API_KEY:-}" ] || fail "OPENAI_API_KEY is not set. Export it or place it in .env before running ./run_eval.sh $MODE"
      ;;
    anthropic)
      if ! missing="$(missing_modules anthropic dotenv 2>/dev/null)"; then
        fail "Missing Python dependencies for Anthropic run: $missing. Install them with: $PIP_INSTALL_CMD"
      fi
      [ -n "${ANTHROPIC_API_KEY:-}" ] || fail "ANTHROPIC_API_KEY is not set. Export it or place it in .env before running ./run_eval.sh $MODE"
      ;;
  esac
done

if [ "$VIA_SWIFTAPI" -eq 1 ]; then
  if ! missing="$(missing_modules swiftapi 2>/dev/null)"; then
    fail "Missing Python dependencies for SwiftAPI mode: $missing. Install them with: $PIP_INSTALL_CMD"
  fi
  [ -n "${SWIFTAPI_KEY:-}" ] || fail "SWIFTAPI_KEY is not set. Export it or place it in .env before running ./run_eval.sh $MODE --via-swiftapi"
fi

RESULTS_ROOT="$ROOT/results"
STAGING_DIR="$RESULTS_ROOT/.latest_tmp"
LATEST_DIR="$RESULTS_ROOT/latest"
RUN_STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_ID="run_${RUN_STAMP}"
STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
GIT_COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
FULL_COMMAND="./run_eval.sh $MODE"
if [ "$VIA_SWIFTAPI" -eq 1 ]; then
  FULL_COMMAND="$FULL_COMMAND --via-swiftapi"
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

run_provider() {
  local provider="$1"
  local runner=""
  local provider_dir="$STAGING_DIR/$provider"
  local raw_dir="$provider_dir/raw"
  local records_dir="$provider_dir/records"
  local attestation_dir="$provider_dir/attestations"
  local runlog="$provider_dir/run.log"
  local started_at completed_at file_count record_count attestation_count status

  case "$provider" in
    openai)
      runner="eval/run_openai.py"
      ;;
    anthropic)
      runner="eval/run_anthropic.py"
      ;;
    *)
      fail "Unsupported provider: $provider"
      ;;
  esac

  mkdir -p "$raw_dir" "$records_dir"
  if [ "$VIA_SWIFTAPI" -eq 1 ]; then
    mkdir -p "$attestation_dir"
  fi
  started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  set +e
  {
    echo "provider=$provider"
    echo "mode=$RUN_MODE"
    echo "runner=$runner"
    echo "python=$PYTHON"
    echo "run_stamp=$RUN_STAMP"
    echo "run_id=$RUN_ID"
    echo "started_at_utc=$started_at"
    echo "results_dir=$raw_dir"
    echo "records_dir=$records_dir"
    if [ "$VIA_SWIFTAPI" -eq 1 ]; then
      echo "attestations_dir=$attestation_dir"
    fi
    echo "command=$FULL_COMMAND"
    echo
    if [ "$VIA_SWIFTAPI" -eq 1 ]; then
      GETSWIFTAPI_RESULTS_DIR="$raw_dir" \
      GETSWIFTAPI_RUN_STAMP="$RUN_STAMP" \
      GETSWIFTAPI_RUN_ID="$RUN_ID" \
      GETSWIFTAPI_MODE="$RUN_MODE" \
      GETSWIFTAPI_COMMAND="$FULL_COMMAND" \
      GETSWIFTAPI_GIT_COMMIT="$GIT_COMMIT" \
      "$PYTHON" "$ROOT/$runner" --via-swiftapi
    else
      GETSWIFTAPI_RESULTS_DIR="$raw_dir" \
      GETSWIFTAPI_RUN_STAMP="$RUN_STAMP" \
      GETSWIFTAPI_RUN_ID="$RUN_ID" \
      GETSWIFTAPI_MODE="$RUN_MODE" \
      GETSWIFTAPI_COMMAND="$FULL_COMMAND" \
      GETSWIFTAPI_GIT_COMMIT="$GIT_COMMIT" \
      "$PYTHON" "$ROOT/$runner"
    fi
  } 2>&1 | tee "$runlog"
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    echo
    echo "FAILURE"
    echo "provider: $provider"
    echo "runlog: $runlog"
    echo "staging directory: $STAGING_DIR"
    exit "$status"
  fi

  file_count="$(find "$raw_dir" -type f | wc -l | tr -d '[:space:]')"
  record_count="$(find "$records_dir" -type f | wc -l | tr -d '[:space:]')"
  attestation_count=0
  if [ -d "$attestation_dir" ]; then
    attestation_count="$(find "$attestation_dir" -type f | wc -l | tr -d '[:space:]')"
  fi
  [ "${file_count:-0}" -gt 0 ] || fail "The $provider runner exited successfully but did not write any output files to $raw_dir"
  [ "${record_count:-0}" -gt 0 ] || fail "The $provider runner exited successfully but did not write any per-case records to $records_dir"

  completed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  {
    echo "provider=$provider"
    echo "mode=$RUN_MODE"
    echo "runner=$runner"
    echo "python=$PYTHON"
    echo "run_stamp=$RUN_STAMP"
    echo "run_id=$RUN_ID"
    echo "started_at_utc=$started_at"
    echo "completed_at_utc=$completed_at"
    echo "raw_dir=results/latest/$provider/raw"
    echo "records_dir=results/latest/$provider/records"
    if [ "$VIA_SWIFTAPI" -eq 1 ]; then
      echo "attestations_dir=results/latest/$provider/attestations"
    fi
    echo "runlog=results/latest/$provider/run.log"
    echo "file_count=$file_count"
    echo "record_count=$record_count"
    echo "attestation_count=$attestation_count"
    echo "command=$FULL_COMMAND"
  } > "$provider_dir/manifest.txt"
}

for provider in $PROVIDERS; do
  run_provider "$provider"
done

COMPLETED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
{
  echo "mode=$MODE"
  echo "run_mode=$RUN_MODE"
  echo "run_stamp=$RUN_STAMP"
  echo "run_id=$RUN_ID"
  echo "started_at_utc=$STARTED_AT"
  echo "completed_at_utc=$COMPLETED_AT"
  echo "python=$PYTHON"
  echo "git_commit=$GIT_COMMIT"
  echo "providers=$PROVIDERS"
  echo "command=$FULL_COMMAND"
  echo "canonical_entrypoints=eval/run_openai.py eval/run_anthropic.py"
} > "$STAGING_DIR/manifest.txt"

{
  echo "status=success"
  echo "run_mode=$RUN_MODE"
  echo "run_stamp=$RUN_STAMP"
  echo "completed_at_utc=$COMPLETED_AT"
} > "$STAGING_DIR/run.success"

rm -rf "$LATEST_DIR"
mv "$STAGING_DIR" "$LATEST_DIR"

echo
echo "SUCCESS"
echo "providers: $MODE"
echo "run mode: $RUN_MODE"
echo "run stamp: $RUN_STAMP"
echo "latest manifest: $LATEST_DIR/manifest.txt"
for provider in $PROVIDERS; do
  echo "$provider raw outputs: $LATEST_DIR/$provider/raw"
  echo "$provider records: $LATEST_DIR/$provider/records"
  if [ "$VIA_SWIFTAPI" -eq 1 ]; then
    echo "$provider attestations: $LATEST_DIR/$provider/attestations"
  fi
  echo "$provider runlog: $LATEST_DIR/$provider/run.log"
done
