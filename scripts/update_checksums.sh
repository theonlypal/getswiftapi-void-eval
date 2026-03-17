#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: > "$ROOT/checksums.txt"
find artifacts attestations -type f 2>/dev/null | sort | while IFS= read -r file; do
  shasum -a 256 "$file"
done > "$ROOT/checksums.txt"
