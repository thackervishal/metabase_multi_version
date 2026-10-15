#!/usr/bin/env bash
# Registers the shared (non-stack) MCP servers for ticket RCA in this repo's
# project config (.mcp.json, gitignored). Safe to re-run: skips servers that
# already exist. Auth is OAuth and stored per machine by Claude Code, so run
# /mcp in a session afterward to sign in to each one.
#
# Per-stack Metabase MCP entries are NOT handled here. `make start` adds those.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# name|url  (HTTP transport, OAuth). Add new servers here.
SERVERS=(
  "grafana|https://grafana-mcp.monitoring.metabase.com/mcp"
  "pylon|https://mcp.usepylon.com"
  "notion|https://mcp.notion.com/mcp"
  "linear|https://mcp.linear.app/mcp"
)

if ! claude_bin="$(resolve_claude_bin)"; then
  echo "No claude binary found. Add the servers by hand:" >&2
  for entry in "${SERVERS[@]}"; do
    echo "  claude mcp add --transport http --scope project ${entry%%|*} ${entry#*|}" >&2
  done
  exit 1
fi

cd "$STACK_ROOT"

for entry in "${SERVERS[@]}"; do
  name="${entry%%|*}"
  url="${entry#*|}"
  if "$claude_bin" mcp get "$name" >/dev/null 2>&1; then
    echo "$name: already configured"
    continue
  fi
  "$claude_bin" mcp add --transport http --scope project "$name" "$url" >/dev/null
  echo "$name: added"
done

echo "Next: open a Claude session here, run /mcp, and sign in to each server."
