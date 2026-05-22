#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

VERSION="${1:?version is required}"
DATASET_KEY="${2:?dataset is required}"

require_command docker
load_stack_env "$VERSION" "$DATASET_KEY"

compose down --remove-orphans
docker volume rm "$APP_DB_VOLUME" "$SAMPLE_DB_VOLUME" >/dev/null 2>&1 || true
rm -f "$SAMPLE_DB_SEED_MARKER"
rm -f "$METABASE_SEED_MARKER"