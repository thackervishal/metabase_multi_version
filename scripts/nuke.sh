#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

VERSION="${1:?version is required}"
DATASET_KEY="${2:?dataset is required}"
KEEP_ENV="${3:-}"

require_command docker
start_docker_desktop
load_stack_env "$VERSION" "$DATASET_KEY"

compose down --remove-orphans
docker volume rm "$APP_DB_VOLUME" "$SAMPLE_DB_VOLUME" >/dev/null 2>&1 || true
rm -f "$SAMPLE_DB_SEED_MARKER"
rm -f "$METABASE_SEED_MARKER"

if [[ "$KEEP_ENV" != "--keep-env" ]]; then
  env_file="$STACK_ROOT/env/mb_versions/${VERSION}.env"
  if [[ -f "$env_file" ]]; then
    echo
    read -rp "Also delete env/mb_versions/${VERSION}.env? [y/N]: " remove_env </dev/tty
    if [[ "$remove_env" =~ ^[Yy]$ ]]; then
      rm "$env_file"
      echo "Deleted env/mb_versions/${VERSION}.env"
      container_name="mb-${MB_VERSION}-${DATASET}-${METABASE_PORT}-admin"
      bash "$SCRIPT_DIR/firefox-container.sh" "$container_name" --remove 2>/dev/null || true
      log_dir="$STACK_ROOT/metabot-debug-logs/${COMPOSE_PROJECT_NAME}"
      if [[ -d "$log_dir" ]]; then
        rm -rf "$log_dir"
        echo "Removed metabot-debug-logs/${COMPOSE_PROJECT_NAME}"
      fi
    fi
  fi
fi