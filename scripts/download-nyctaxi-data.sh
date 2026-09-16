#!/usr/bin/env bash
# One-time download of NYC TLC taxi trip data (Parquet) for the
# clickhouse-nyctaxi dataset. NOT run automatically by make new/start/nuke —
# run this by hand once. Every clickhouse-nyctaxi stack bind-mounts the same
# downloaded folder read-only (see compose/datasets/clickhouse-nyctaxi.yml),
# so re-running `make new`/`make start` — even after `make nuke` — never
# re-downloads anything.
#
# Usage: bash scripts/download-nyctaxi-data.sh [year] [taxi-type]
#   year:      four-digit year, defaults to 2025 (the most recent fully-published year)
#   taxi-type: yellow (default) | green | fhv | fhvhv

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

require_command curl

YEAR="${1:-2025}"
TAXI_TYPE="${2:-yellow}"

if [[ ! "$YEAR" =~ ^[0-9]{4}$ ]]; then
  echo "Invalid year: $YEAR (expected e.g. 2024)" >&2
  exit 1
fi

DEST_DIR="$STACK_ROOT/data/clickhouse-nyctaxi"
mkdir -p "$DEST_DIR"

echo "Downloading ${TAXI_TYPE} taxi trip data for ${YEAR} into ${DEST_DIR}"
echo "(already-downloaded months are skipped — safe to re-run)"
echo

for month in 01 02 03 04 05 06 07 08 09 10 11 12; do
  file_name="${TAXI_TYPE}_tripdata_${YEAR}-${month}.parquet"
  dest_path="${DEST_DIR}/${file_name}"
  url="https://d37ci6vzurychx.cloudfront.net/trip-data/${file_name}"

  if [[ -f "$dest_path" ]]; then
    echo "  ${file_name} — already downloaded, skipping"
    continue
  fi

  echo "  ${file_name} — downloading..."
  # --retry-all-errors: plain --retry only covers transport-level failures
  # (timeouts, 5xx) — a local write hiccup (e.g. antivirus scanning the file
  # mid-write, common on Windows) is a different error class and needs this
  # to actually get retried instead of failing the whole file on one stall.
  if ! curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 -o "${dest_path}.part" "$url"; then
    echo "    Failed to download ${url} (not yet published, or a persistent network/write error) — skipping." >&2
    rm -f "${dest_path}.part"
    continue
  fi
  mv "${dest_path}.part" "$dest_path"
done

echo
echo "Done. Files in ${DEST_DIR}:"
find "$DEST_DIR" -maxdepth 1 -name "*.parquet" -exec basename {} \; | sort
