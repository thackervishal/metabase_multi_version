#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/../common.sh"

VERSION="${1:?version is required}"
DATASET_KEY="${2:?dataset is required}"
SNAPSHOT_PREFIX="${3:?snapshot prefix is required}"
TARGET="${4:-all}"

require_command docker

load_stack_env "$VERSION" "$DATASET_KEY"

restore_service() {
  local service_name="$1"
  local username="$2"
  local password="$3"
  local database_name="$4"
  local snapshot_file="$5"

  if [[ ! -f "$snapshot_file" ]]; then
    echo "Snapshot file not found: $snapshot_file" >&2
    exit 1
  fi

  echo "Restoring $snapshot_file"
  cat "$snapshot_file" | compose exec -T "$service_name" sh -lc "PGPASSWORD='$password' psql -v ON_ERROR_STOP=1 -U '$username' '$database_name'"
}

compose up -d app-db sample-dwh

case "$TARGET" in
  all)
    restore_service app-db "$MB_APP_DB_USER" "$MB_APP_DB_PASSWORD" "$MB_APP_DB_NAME" "$SNAPSHOT_DIR/${SNAPSHOT_PREFIX}-app-db.sql"
    restore_service sample-dwh "$SAMPLE_DB_USER" "$SAMPLE_DB_PASSWORD" "$SAMPLE_DB_NAME" "$SNAPSHOT_DIR/${SNAPSHOT_PREFIX}-sample-dwh.sql"
    ;;
  app-db)
    restore_service app-db "$MB_APP_DB_USER" "$MB_APP_DB_PASSWORD" "$MB_APP_DB_NAME" "$SNAPSHOT_DIR/${SNAPSHOT_PREFIX}-app-db.sql"
    ;;
  sample-dwh)
    restore_service sample-dwh "$SAMPLE_DB_USER" "$SAMPLE_DB_PASSWORD" "$SAMPLE_DB_NAME" "$SNAPSHOT_DIR/${SNAPSHOT_PREFIX}-sample-dwh.sql"
    ;;
  *)
    echo "Unsupported TARGET: $TARGET" >&2
    exit 1
    ;;
esac

mkdir -p "$STACK_STATE_DIR"
touch "$METABASE_SEED_MARKER"
echo "Restore complete."