#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/../common.sh"

VERSION="${1:?version is required}"
DATASET_KEY="${2:?dataset is required}"
TARGET="${3:-all}"

require_command docker
require_command date

load_stack_env "$VERSION" "$DATASET_KEY"
mkdir -p "$SNAPSHOT_DIR"

timestamp="$(date +%Y%m%d-%H%M%S)"

dump_service() {
  local service_name="$1"
  local username="$2"
  local password="$3"
  local database_name="$4"
  local output_file="$5"

  echo "Creating snapshot $output_file"
  compose exec -T "$service_name" sh -lc "PGPASSWORD='$password' pg_dump --clean --if-exists --no-owner --no-privileges -U '$username' '$database_name'" >"$output_file"
}

case "$TARGET" in
  all)
    dump_service app-db "$MB_APP_DB_USER" "$MB_APP_DB_PASSWORD" "$MB_APP_DB_NAME" "$SNAPSHOT_DIR/${timestamp}-app-db.sql"
    dump_service sample-db "$SAMPLE_DB_USER" "$SAMPLE_DB_PASSWORD" "$SAMPLE_DB_NAME" "$SNAPSHOT_DIR/${timestamp}-sample-db.sql"
    ;;
  app-db)
    dump_service app-db "$MB_APP_DB_USER" "$MB_APP_DB_PASSWORD" "$MB_APP_DB_NAME" "$SNAPSHOT_DIR/${timestamp}-app-db.sql"
    ;;
  sample-db)
    dump_service sample-db "$SAMPLE_DB_USER" "$SAMPLE_DB_PASSWORD" "$SAMPLE_DB_NAME" "$SNAPSHOT_DIR/${timestamp}-sample-db.sql"
    ;;
  *)
    echo "Unsupported TARGET: $TARGET" >&2
    exit 1
    ;;
esac

echo "Snapshot complete. Prefix: ${timestamp}"