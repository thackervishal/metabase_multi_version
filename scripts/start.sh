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
wait_for_service_health app-db 30 10
wait_for_service_health sample-dwh 30 10

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

MCP_URL="http://127.0.0.1:${METABASE_PORT}/api/metabase-mcp"

mcp_result=0
if claude_bin="$(resolve_claude_bin)"; then
  "$claude_bin" mcp remove "$COMPOSE_PROJECT_NAME" -s project 2>/dev/null || true
  "$claude_bin" mcp add --transport http "$COMPOSE_PROJECT_NAME" \
    "$MCP_URL" \
    --header "x-api-key: ${MB_AUTOMATION_API_KEY}" \
    -s project >/dev/null 2>&1 || mcp_result=1
  if [[ $mcp_result -eq 0 ]]; then
    "$claude_bin" mcp list 2>/dev/null || true
  fi
else
  mcp_result=2
fi

CLI_URL="http://127.0.0.1:${METABASE_PORT}"

# seed-metabase.sh already called ensure_mb_cli (resolves MB_CMD and logs the
# profile in, keyed by COMPOSE_PROJECT_NAME — same key MCP registration uses
# above) to drive collection/card/dashboard creation via the CLI. Re-run it
# here so the summary below reflects real status even on a skipped-seed run.
cli_result=0
ensure_mb_cli || cli_result=$?

SEP="------------------------------------------------------------"
echo
echo "$SEP"
echo "  Stack ready: ${COMPOSE_PROJECT_NAME}"
echo "$SEP"
echo "  Metabase        http://localhost:${METABASE_PORT}"
echo "    admin         ${MB_ADMIN_EMAIL}  /  ${MB_ADMIN_PASSWORD}"
echo "    analyst       ${MB_ANALYST_EMAIL}  /  ${MB_ANALYST_PASSWORD}"
echo "    sales         ${MB_SALES_EMAIL}  /  ${MB_SALES_PASSWORD}"
case $mcp_result in
  0) echo "    MCP server    ${COMPOSE_PROJECT_NAME}"
     echo "                  ${MCP_URL}"
     echo "                  open a new Claude session to use it" ;;
  1) echo "    MCP server    registration failed"
     echo "                  manual: claude mcp add --transport http ${COMPOSE_PROJECT_NAME} ${MCP_URL} --header \"x-api-key: ${MB_AUTOMATION_API_KEY}\" -s project" ;;
  2) echo "    MCP server    claude CLI not found, registration skipped"
     echo "                  manual: claude mcp add --transport http ${COMPOSE_PROJECT_NAME} ${MCP_URL} --header \"x-api-key: ${MB_AUTOMATION_API_KEY}\" -s project" ;;
esac
case $cli_result in
  0) echo "    Metabase CLI  profile ${COMPOSE_PROJECT_NAME}"
     echo "                  ${MB_CMD[*]} --profile ${COMPOSE_PROJECT_NAME} db list" ;;
  1) echo "    Metabase CLI  login failed"
     echo "                  manual: MB_API_KEY=${MB_AUTOMATION_API_KEY} ${MB_CMD[*]} auth login --profile ${COMPOSE_PROJECT_NAME} --url ${CLI_URL}" ;;
  2) echo "    Metabase CLI  mb not installed and npx not found, login skipped" ;;
esac
echo
echo "  App DB (PG)     localhost:${APP_DB_PORT}  db=${MB_APP_DB_NAME}"
echo "                  ${MB_APP_DB_USER}  /  ${MB_APP_DB_PASSWORD}"
echo
echo "  Sample DWH (${SAMPLE_DB_TYPE})  localhost:${SAMPLE_DB_PORT}  db=${SAMPLE_DB_NAME}"
echo "                  ${SAMPLE_DB_USER}  /  ${SAMPLE_DB_PASSWORD}"
if [[ "${ENABLE_EMAIL}" == "true" ]] || [[ "${ENABLE_WEBHOOKS}" == "true" ]] || [[ "${ENABLE_SAML}" == "true" ]]; then
  echo
  if [[ "${ENABLE_EMAIL}" == "true" ]]; then
    echo "  Mailpit         http://localhost:${MAILPIT_UI_PORT:-8025}"
  fi
  if [[ "${ENABLE_WEBHOOKS}" == "true" ]]; then
    echo "  Webhooks        http://localhost:${WEBHOOK_PORT:-9000}/s/${WEBHOOK_SESSION_ID}"
  fi
  if [[ "${ENABLE_SAML}" == "true" ]]; then
    echo "  Keycloak        http://keycloak:${KEYCLOAK_PORT:-8180}  admin / admin"
  fi
fi
case $ff_result in
  0) echo; echo "  Firefox tab     ${container_name}" ;;
  2) echo; echo "  Firefox tab     ${container_name}  (restart Firefox to use)" ;;
esac
echo "$SEP"
echo
