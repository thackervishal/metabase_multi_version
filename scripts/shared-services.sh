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

case "${1:?Usage: shared-services.sh <up|down|ensure|ensure-network>}" in
  up)
    ensure_shared_network
    echo "Starting shared services..."
    docker compose -p "$SHARED_PROJECT" -f "$SHARED_COMPOSE" \
      --profile email --profile webhooks --profile saml up -d
    echo "  Mailpit (email) UI: http://localhost:${MAILPIT_UI_PORT:-8025}"
    echo "  Webhook receiver:   http://localhost:${WEBHOOK_PORT:-9000}"
    echo "  Keycloak admin:     http://localhost:${KEYCLOAK_PORT:-8180}"
    ;;
  stop)
    echo "Stopping shared services..."
    docker compose -p "$SHARED_PROJECT" -f "$SHARED_COMPOSE" \
      --profile email --profile webhooks --profile saml stop
    ;;
  down)
    echo "Removing shared services..."
    docker compose -p "$SHARED_PROJECT" -f "$SHARED_COMPOSE" \
      --profile email --profile webhooks --profile saml down
    ;;
  ensure)
    ensure_shared_network
    profiles=()
    [[ "${ENABLE_EMAIL:-false}"    == "true" ]] && profiles+=(--profile email)
    [[ "${ENABLE_WEBHOOKS:-false}" == "true" ]] && profiles+=(--profile webhooks)
    [[ "${ENABLE_SAML:-false}"     == "true" ]] && profiles+=(--profile saml)
    if [[ ${#profiles[@]} -gt 0 ]]; then
      docker compose -p "$SHARED_PROJECT" -f "$SHARED_COMPOSE" "${profiles[@]}" up -d
    fi
    ;;
  ensure-network)
    ensure_shared_network
    ;;
  *)
    echo "Unknown command: $1. Use up, down, ensure, or ensure-network." >&2
    exit 1
    ;;
esac
