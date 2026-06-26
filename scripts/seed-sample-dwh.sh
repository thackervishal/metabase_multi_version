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
else
  sql_file="$STACK_ROOT/seed/sample-dwh/person_profiles_json.sql"
  if [[ ! -f "$sql_file" ]]; then
    echo "SQL file not found: $sql_file" >&2
    exit 1
  fi
  echo "Applying sample warehouse JSON seed to ${COMPOSE_PROJECT_NAME}/${SAMPLE_DB_NAME}"
  compose exec -T sample-dwh sh -lc "PGPASSWORD='$SAMPLE_DB_PASSWORD' psql -v ON_ERROR_STOP=1 -U '$SAMPLE_DB_USER' '$SAMPLE_DB_NAME'" <"$sql_file"
  echo "Sample warehouse JSON seed complete for ${COMPOSE_PROJECT_NAME}."
fi

touch "$SAMPLE_DB_SEED_MARKER"