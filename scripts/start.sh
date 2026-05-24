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

container_name="mb-${MB_VERSION}-${DATASET}-${METABASE_PORT}-admin"

ff_result=0
bash "$SCRIPT_DIR/firefox-container.sh" "$container_name" || ff_result=$?

echo "Stack is ready at localhost:${METABASE_PORT}"
case $ff_result in
  0) echo "  Open it in the Firefox container '${container_name}'." ;;
  2) echo "  Firefox container '${container_name}' created — restart Firefox to use it." ;;
  1) echo "  Tip: install Firefox + the Multi-Account Containers extension for an isolated session per stack." ;;
esac