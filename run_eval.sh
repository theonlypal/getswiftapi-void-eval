#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./run_eval.sh [openai|anthropic|all]

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

MODE="${1:-openai}"
case "$MODE" in
  openai|anthropic|all)
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

RESULTS_ROOT="$ROOT/results"
STAGING_DIR="$RESULTS_ROOT/.latest_tmp"
LATEST_DIR="$RESULTS_ROOT/latest"
RUN_STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
GIT_COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

run_provider() {
  local provider="$1"
  local runner=""
  local provider_dir="$STAGING_DIR/$provider"
  local raw_dir="$provider_dir/raw"
  local runlog="$provider_dir/run.log"
  local started_at completed_at file_count status

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

  mkdir -p "$raw_dir"
  started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  set +e
  {
    echo "provider=$provider"
    echo "runner=$runner"
    echo "python=$PYTHON"
    echo "run_stamp=$RUN_STAMP"
    echo "started_at_utc=$started_at"
    echo "results_dir=$raw_dir"
    echo
    GETSWIFTAPI_RESULTS_DIR="$raw_dir" \
    GETSWIFTAPI_RUN_STAMP="$RUN_STAMP" \
    "$PYTHON" "$ROOT/$runner"
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
  [ "${file_count:-0}" -gt 0 ] || fail "The $provider runner exited successfully but did not write any output files to $raw_dir"

  completed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  {
    echo "provider=$provider"
    echo "runner=$runner"
    echo "python=$PYTHON"
    echo "run_stamp=$RUN_STAMP"
    echo "started_at_utc=$started_at"
    echo "completed_at_utc=$completed_at"
    echo "raw_dir=results/latest/$provider/raw"
    echo "runlog=results/latest/$provider/run.log"
    echo "file_count=$file_count"
  } > "$provider_dir/manifest.txt"
}

for provider in $PROVIDERS; do
  run_provider "$provider"
done

COMPLETED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
{
  echo "mode=$MODE"
  echo "run_stamp=$RUN_STAMP"
  echo "started_at_utc=$STARTED_AT"
  echo "completed_at_utc=$COMPLETED_AT"
  echo "python=$PYTHON"
  echo "git_commit=$GIT_COMMIT"
  echo "providers=$PROVIDERS"
  echo "canonical_entrypoints=eval/run_openai.py eval/run_anthropic.py"
} > "$STAGING_DIR/manifest.txt"

{
  echo "status=success"
  echo "run_stamp=$RUN_STAMP"
  echo "completed_at_utc=$COMPLETED_AT"
} > "$STAGING_DIR/run.success"

rm -rf "$LATEST_DIR"
mv "$STAGING_DIR" "$LATEST_DIR"

echo
echo "SUCCESS"
echo "mode: $MODE"
echo "run stamp: $RUN_STAMP"
echo "latest manifest: $LATEST_DIR/manifest.txt"
for provider in $PROVIDERS; do
  echo "$provider raw outputs: $LATEST_DIR/$provider/raw"
  echo "$provider runlog: $LATEST_DIR/$provider/run.log"
done
