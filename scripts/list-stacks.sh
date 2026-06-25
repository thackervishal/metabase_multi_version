#!/usr/bin/env bash
# Show all configured stacks with their ports and running status.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

load_common_env

# ── Discover versions and datasets ───────────────────────────────────────────

versions=()
while IFS= read -r f; do
  versions+=("$(basename "$f" .env)")
done < <(
  find "$STACK_ROOT/env/mb_versions" -maxdepth 1 -name "*.env" ! -name "template.env.example" \
  | sort -V -r
)

datasets=()
while IFS= read -r f; do
  datasets+=("$(basename "$f" .env)")
done < <(find "$STACK_ROOT/env/dwh_source" -maxdepth 1 -name "*.env" | sort)

if [[ ${#versions[@]} -eq 0 ]]; then
  echo
  echo "No stacks configured. Run 'make new' to create one."
  echo
  exit 0
fi

# ── Detect running stacks ─────────────────────────────────────────────────────

running_projects="$(docker compose ls 2>/dev/null \
  | awk 'NR>1 && $2 ~ /^running/ { print $1 }' || true)"

is_running() {
  local project
  project="$(project_name_for "$1" "$2")"
  grep -qx "$project" <<< "$running_projects" 2>/dev/null || return 1
}

# ── Print table ───────────────────────────────────────────────────────────────

echo
echo "Configured stacks:"
echo
printf "  %-22s  %-6s  %s\n" "STACK" "PORT" "STATUS"
printf "  %-22s  %-6s  %s\n" "----------------------" "------" "------"

for version in "${versions[@]}"; do
  env_file="$STACK_ROOT/env/mb_versions/${version}.env"
  port="$(grep -E '^METABASE_PORT=' "$env_file" 2>/dev/null | cut -d= -f2 || echo '?')"

  running_datasets=()
  for dataset in "${datasets[@]}"; do
    is_running "$version" "$dataset" && running_datasets+=("$dataset")
  done

  if [[ ${#running_datasets[@]} -gt 0 ]]; then
    status="running  [${running_datasets[*]}]  →  http://localhost:${port}"
  else
    status="stopped"
  fi

  printf "  %-22s  %-6s  %s\n" "$version" "$port" "$status"
done

echo
