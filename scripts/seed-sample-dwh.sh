#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

VERSION="${1:?version is required}"
DATASET_KEY="${2:?dataset is required}"

require_command docker

load_stack_env "$VERSION" "$DATASET_KEY"
mkdir -p "$STACK_STATE_DIR"

if [[ -f "$SAMPLE_DB_SEED_MARKER" && "${FORCE:-0}" != "1" ]]; then
  echo "Sample DB seed marker found for ${COMPOSE_PROJECT_NAME}. Skipping warehouse seed."
  exit 0
fi

if [[ "$DATASET_KEY" == sample-mysql* ]]; then
  echo "MySQL QA image is pre-seeded — no warehouse seed to apply for ${COMPOSE_PROJECT_NAME}."
elif [[ "$DATASET_KEY" == clickhouse-nyctaxi* ]]; then
  nyctaxi_dir="$STACK_ROOT/data/clickhouse-nyctaxi"
  if [[ -z "$(find "$nyctaxi_dir" -maxdepth 1 -name '*.parquet' -print -quit 2>/dev/null)" ]]; then
    echo "No Parquet files found in ${nyctaxi_dir}." >&2
    echo "Run 'bash scripts/download-nyctaxi-data.sh <year>' once, then retry." >&2
    exit 1
  fi
  echo "Creating file-backed view over NYC taxi Parquet data for ${COMPOSE_PROJECT_NAME}/${SAMPLE_DB_NAME}"
  compose exec -T sample-dwh clickhouse-client \
    --user "$SAMPLE_DB_USER" --password "$SAMPLE_DB_PASSWORD" \
    --query "CREATE OR REPLACE VIEW ${SAMPLE_DB_NAME}.nyc_taxi_trips_files AS SELECT * FROM file('nyctaxi/yellow_tripdata_*.parquet', Parquet)"
  echo "NYC taxi file view (${SAMPLE_DB_NAME}.nyc_taxi_trips_files) ready for ${COMPOSE_PROJECT_NAME}."
else
  sql_file="$STACK_ROOT/seed/sample-dwh/person_profiles_json.sql"
  if [[ ! -f "$sql_file" ]]; then
    echo "SQL file not found: $sql_file" >&2
    exit 1
  fi

  # The qa-databases image reports "ready to accept connections" (what the
  # sample-dwh healthcheck polls) before it finishes bulk-loading data —
  # primary/foreign key constraints on tables like "people" are added in a
  # final ALTER TABLE batch after the inserts, so a seed applied right after
  # the healthcheck passes can race that batch and fail with "there is no
  # unique constraint matching given keys for referenced table people".
  # Wait for the people PK to actually exist before applying our seed.
  echo "Waiting for sample warehouse data load to finish on ${COMPOSE_PROJECT_NAME}..."
  people_pk_attempts=30
  people_pk_ready=0
  for ((attempt = 1; attempt <= people_pk_attempts; attempt++)); do
    if compose exec -T sample-dwh sh -lc "PGPASSWORD='$SAMPLE_DB_PASSWORD' psql -tA -U '$SAMPLE_DB_USER' -d '$SAMPLE_DB_NAME' -c \"select 1 from pg_constraint where conrelid = 'public.people'::regclass and contype = 'p'\"" 2>/dev/null | grep -q '^1$'; then
      people_pk_ready=1
      break
    fi
    sleep 2
  done
  if [[ "$people_pk_ready" != "1" ]]; then
    echo "Sample warehouse data load did not finish in time (people table has no primary key yet)." >&2
    exit 1
  fi

  echo "Applying sample warehouse JSON seed to ${COMPOSE_PROJECT_NAME}/${SAMPLE_DB_NAME}"
  compose exec -T sample-dwh sh -lc "PGPASSWORD='$SAMPLE_DB_PASSWORD' psql -v ON_ERROR_STOP=1 -U '$SAMPLE_DB_USER' '$SAMPLE_DB_NAME'" <"$sql_file"
  echo "Sample warehouse JSON seed complete for ${COMPOSE_PROJECT_NAME}."
fi

touch "$SAMPLE_DB_SEED_MARKER"