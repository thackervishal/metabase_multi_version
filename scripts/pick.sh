#!/usr/bin/env bash
# Interactive stack picker — invoked by make start/stop/nuke when MB_VERSION is not supplied.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

action="${1:?Usage: pick.sh <start|stop|nuke>}"

common_env="$STACK_ROOT/env/common.env"
if [[ ! -f "$common_env" ]]; then
  echo "Missing env/common.env — copy from env/common.env.example and fill in values." >&2
  exit 1
fi

# Pre-set vars referenced in common.env to avoid set -u errors before a stack is chosen.
export DATASET="" MB_VERSION=""

set -a
# shellcheck disable=SC1090
source "$common_env"
set +a
configure_optional_tool_paths

# ── Discover available versions and datasets ──────────────────────────────────

versions=()
while IFS= read -r f; do
  versions+=("$(basename "$f" .env)")
done < <(
  find "$STACK_ROOT/env/mb_versions" -maxdepth 1 -name "*.env" ! -name "template.env.example" \
  | sort -r
)

datasets=()
while IFS= read -r f; do
  datasets+=("$(basename "$f" .env)")
done < <(
  find "$STACK_ROOT/env/dwh_source" -maxdepth 1 -name "*.env" | sort
)

if [[ ${#versions[@]} -eq 0 ]]; then
  echo "No version env files found in env/mb_versions/." >&2
  echo "Create one from env/mb_versions/template.env.example." >&2
  exit 1
fi

if [[ ${#datasets[@]} -eq 0 ]]; then
  echo "No dataset profiles found in env/dwh_source/." >&2
  exit 1
fi

# ── Detect running stacks ─────────────────────────────────────────────────────

running_projects="$(docker compose ls 2>/dev/null \
  | awk 'NR>1 && $2 ~ /^running/ { print $1 }' || true)"

project_name_for() {
  local vk dk
  vk="$(sanitize_key "$1")"
  dk="$(sanitize_key "$2")"
  echo "${STACK_PROJECT_PREFIX}_${vk}_${dk}"
}

is_running() {
  local project
  project="$(project_name_for "$1" "$2")"
  grep -qx "$project" <<< "$running_projects" 2>/dev/null || return 1
}

# ── Build menu entries ────────────────────────────────────────────────────────

labels=()
combos=()
for version in "${versions[@]}"; do
  for dataset in "${datasets[@]}"; do
    if is_running "$version" "$dataset"; then
      running=true
    else
      running=false
    fi

    label="${version}  [${dataset}]"

    case "$action" in
      start)
        [[ "$running" == "true" ]] && label+="  (already running)"
        labels+=("$label")
        combos+=("$version $dataset")
        ;;
      stop)
        [[ "$running" == "true" ]] || continue
        labels+=("$label")
        combos+=("$version $dataset")
        ;;
      nuke)
        [[ "$running" == "true" ]] && label+="  (running)"
        labels+=("$label")
        combos+=("$version $dataset")
        ;;
    esac
  done
done

if [[ ${#labels[@]} -eq 0 ]]; then
  case "$action" in
    stop)  echo "No stacks are currently running." ;;
    start) echo "No version env files found. Create one from env/mb_versions/template.env.example." ;;
    nuke)  echo "No stacks configured." ;;
  esac
  exit 0
fi

# ── Show menu and prompt ──────────────────────────────────────────────────────

echo
case "$action" in
  start) echo "Select a stack to start:" ;;
  stop)  echo "Select a running stack to stop:" ;;
  nuke)  echo "Select a stack to nuke (removes containers, volumes, and seed markers):" ;;
esac
echo

for i in "${!labels[@]}"; do
  printf "  %2d)  %s\n" "$((i + 1))" "${labels[$i]}"
done
echo

selected_version=""
selected_dataset=""

while true; do
  read -rp "Enter number (or q to quit): " choice </dev/tty
  case "$choice" in
    q|Q)
      exit 0
      ;;
    ""|*[!0-9]*)
      echo "  Please enter a number from 1 to ${#labels[@]}, or q to quit."
      ;;
    *)
      if [[ "$choice" -ge 1 && "$choice" -le "${#labels[@]}" ]]; then
        selected="${combos[$((choice - 1))]}"
        selected_version="${selected%% *}"
        selected_dataset="${selected##* }"
        break
      fi
      echo "  Please enter a number from 1 to ${#labels[@]}, or q to quit."
      ;;
  esac
done

# Guard: block starting an already-running stack
if [[ "$action" == "start" ]] && is_running "$selected_version" "$selected_dataset"; then
  echo "Stack ${selected_version} is already running. Use 'make stop' first." >&2
  exit 1
fi

echo
echo "${action^} stack: ${selected_version}  [${selected_dataset}]"
echo "  → make ${action} MB_VERSION=${selected_version} DATASET=${selected_dataset}"
echo
exec "$SCRIPT_DIR/${action}.sh" "$selected_version" "$selected_dataset"
