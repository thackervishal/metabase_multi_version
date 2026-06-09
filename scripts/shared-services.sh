#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

normalize_docker_path() {
  local raw_path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$raw_path"
    return
  fi
  echo "$raw_path" | sed 's#\\#/#g'
}

SHARED_PROJECT="mb_shared"
SHARED_NETWORK="mb_shared"
SHARED_COMPOSE="$(normalize_docker_path "$STACK_ROOT")/compose/shared-services.yml"

ensure_shared_network() {
  if ! docker network inspect "$SHARED_NETWORK" >/dev/null 2>&1; then
    echo "Creating shared Docker network '${SHARED_NETWORK}'..."
    docker network create "$SHARED_NETWORK" >/dev/null
  fi
}

shared_services_running() {
  docker compose ls 2>/dev/null \
    | awk 'NR>1 { print $1 }' \
    | grep -qx "$SHARED_PROJECT" 2>/dev/null
}

case "${1:?Usage: shared-services.sh <up|down|ensure>}" in
  up)
    ensure_shared_network
    echo "Starting shared services..."
    docker compose -p "$SHARED_PROJECT" -f "$SHARED_COMPOSE" up -d
    echo "  Mailpit (email) UI: http://localhost:${MAILPIT_UI_PORT:-8025}"
    echo "  Webhook receiver:   http://localhost:${WEBHOOK_PORT:-9000}"
    ;;
  stop)
    echo "Stopping shared services..."
    docker compose -p "$SHARED_PROJECT" -f "$SHARED_COMPOSE" stop
    ;;
  down)
    echo "Removing shared services..."
    docker compose -p "$SHARED_PROJECT" -f "$SHARED_COMPOSE" down
    ;;
  ensure)
    ensure_shared_network
    if ! shared_services_running; then
      echo "Starting shared services..."
      docker compose -p "$SHARED_PROJECT" -f "$SHARED_COMPOSE" up -d
    fi
    ;;
  *)
    echo "Unknown command: $1. Use up, down, or ensure." >&2
    exit 1
    ;;
esac
