#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_PROJECT="mb_shared"

all_projects=$(docker compose ls 2>/dev/null \
  | awk 'NR>1 { print $1 }' \
  | tr -d '\r' \
  | grep -E '^mb_' || true)

running_stacks=$(echo "$all_projects" | grep -v "^${SHARED_PROJECT}$" || true)

if [[ -z "$running_stacks" ]]; then
  echo "No stacks running."
else
  while IFS= read -r project; do
    echo "Stopping ${project}..."
    docker compose -p "$project" stop
  done <<< "$running_stacks"
fi

if echo "$all_projects" | grep -qx "$SHARED_PROJECT" 2>/dev/null; then
  bash "$SCRIPT_DIR/shared-services.sh" stop
fi

echo "All done. Have a good one."
