#!/usr/bin/env bash
# Show all configured stacks with their ports and running status.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

load_common_env

# ── Discover configured stacks ───────────────────────────────────────────────

env_file_paths=()
while IFS= read -r f; do
  env_file_paths+=("$f")
done < <(
  find "$STACK_ROOT/env/mb_versions" -maxdepth 1 -name "*.env" ! -name "template.env.example" \
  | sort -V -r
)

if [[ ${#env_file_paths[@]} -eq 0 ]]; then
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
printf "  %-22s  %-20s  %-6s  %-24s  %s\n" "STACK" "DATASET" "PORT" "LABEL" "STATUS"
printf "  %-22s  %-20s  %-6s  %-24s  %s\n" "----------------------" "--------------------" "------" "------------------------" "------"

for env_file_path in "${env_file_paths[@]}"; do
  version="$(grep -E '^MB_IMAGE_TAG=' "$env_file_path" 2>/dev/null | cut -d= -f2 | tr -d '\r' || true)"
  dataset="$(grep -E '^DATASET=' "$env_file_path" 2>/dev/null | cut -d= -f2 | tr -d '\r' || true)"
  port="$(grep -E '^METABASE_PORT=' "$env_file_path" 2>/dev/null | cut -d= -f2 || echo '?')"
  label="$(grep -E '^STACK_LABEL=' "$env_file_path" 2>/dev/null | cut -d= -f2- | tr -d '\r' || true)"

  if [[ -n "$version" && -n "$dataset" ]] && is_running "$version" "$dataset"; then
    status="running  →  http://localhost:${port}"
  else
    status="stopped"
  fi

  printf "  %-22s  %-20s  %-6s  %-24s  %s\n" "${version:-?}" "${dataset:-?}" "$port" "${label:--}" "$status"
done

echo
