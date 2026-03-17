# Example runs

`results/latest/` stores the most recent successful `./run_eval.sh` invocation.

Per provider:
- `raw/` — raw text outputs and raw provider payloads
- `records/` — deterministic per-case metadata records
- `attestations/` — SwiftAPI verification responses when `--via-swiftapi` is used
- `run.log` — terminal log for the invocation
- `manifest.txt` — provider-level summary
