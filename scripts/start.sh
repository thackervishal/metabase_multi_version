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

IMAGE_REF="$(metabase_image_ref)"

bash "$SCRIPT_DIR/shared-services.sh" ensure-network

if [[ "${ENABLE_EMAIL}" == "true" || "${ENABLE_WEBHOOKS}" == "true" || "${ENABLE_SAML}" == "true" ]]; then
  bash "$SCRIPT_DIR/shared-services.sh" ensure
fi

refresh_metabase_image
clear_image_gc_marker "$IMAGE_REF"

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

mkdir -p "$STACK_ROOT/metabot-debug-logs/$COMPOSE_PROJECT_NAME"
chmod o+w "$STACK_ROOT/metabot-debug-logs/$COMPOSE_PROJECT_NAME"
compose up -d metabase
wait_for_metabase
"$SCRIPT_DIR/seed-metabase.sh" "$VERSION" "$DATASET_KEY"

if [[ "${ENABLE_WEBHOOKS}" == "true" ]]; then
  webhook_internal_url="http://webhook-tester:8080/${WEBHOOK_SESSION_ID}"
  existing="$(curl -fsS "http://127.0.0.1:${METABASE_PORT}/api/channel" \
    -H "x-api-key: ${MB_AUTOMATION_API_KEY}" \
    | jq -r --arg url "$webhook_internal_url" \
        '.[] | select(.details.url == $url) | .name' 2>/dev/null || true)"
  if [[ -z "$existing" ]]; then
    curl -fsS -X POST "http://127.0.0.1:${METABASE_PORT}/api/channel" \
      -H "Content-Type: application/json" \
      -H "x-api-key: ${MB_AUTOMATION_API_KEY}" \
      -d "$(jq -nc \
        --arg name "Local Webhook Tester (${MB_VERSION})" \
        --arg url "$webhook_internal_url" \
        '{name: $name, description: "Auto-created by make start.", type: "channel/http",
          details: {url: $url, "auth-method": "none", "fe-form-type": "none"}}')" \
      >/dev/null
    echo "Webhook channel created."
  fi
  # Prime the session so /s/<uuid> works immediately on first click.
  # Without this, webhook-tester redirects to a new random UUID until
  # the first real POST arrives and creates the session.
  curl -fsS -X POST "http://127.0.0.1:${WEBHOOK_PORT:-9000}/${WEBHOOK_SESSION_ID}" \
    -H "Content-Type: application/json" \
    -d "{\"source\":\"make start\",\"message\":\"Webhook session initialized for stack ${MB_VERSION} — ready to receive Metabase alerts.\"}" \
    >/dev/null 2>&1 || true
fi

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
if [[ "${ENABLE_EMAIL}" == "true" ]]; then
  echo "  Mailpit (email):  http://localhost:${MAILPIT_UI_PORT:-8025}"
fi
if [[ "${ENABLE_WEBHOOKS}" == "true" ]]; then
  echo "  Webhook tester:   http://localhost:${WEBHOOK_PORT:-9000}/s/${WEBHOOK_SESSION_ID}"
fi
if [[ "${ENABLE_SAML}" == "true" ]]; then
  echo "  Keycloak admin:   http://localhost:${KEYCLOAK_PORT:-8180}  (admin / admin)"
fi
