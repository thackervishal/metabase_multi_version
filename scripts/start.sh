#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

VERSION="${1:?version is required}"
DATASET_KEY="${2:?dataset is required}"

require_command docker
start_docker_desktop
require_command jq

load_stack_env "$VERSION" "$DATASET_KEY"
refresh_metabase_image

cleanup_on_error() {
  echo "Startup failed. Stopping stack." >&2
  compose stop >/dev/null 2>&1 || true
}

trap cleanup_on_error ERR

ensure_external_volumes
compose up -d app-db sample-dwh
wait_for_service_health app-db 12 2
wait_for_service_health sample-dwh 12 2

"$SCRIPT_DIR/seed-sample-dwh.sh" "$VERSION" "$DATASET_KEY"

compose up -d metabase
wait_for_metabase
"$SCRIPT_DIR/seed-metabase.sh" "$VERSION" "$DATASET_KEY"

trap - ERR

echo "Stack is ready at http://localhost:${METABASE_PORT}"