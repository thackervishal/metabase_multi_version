#!/usr/bin/env bash
# Interactive stack picker — invoked by make start/stop/nuke when MB_VERSION is not supplied.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

action="${1:?Usage: pick.sh <start|stop|nuke>}"

load_common_env

# ── Discover configured stacks ────────────────────────────────────────────────
# Each env file encodes both version and dataset in its name (e.g.
# 1.62.2.x_sample-pg15.env). MB_IMAGE_TAG and DATASET are read from file
# content so that pick.sh passes clean values to downstream scripts.

env_file_paths=()
while IFS= read -r f; do
  env_file_paths+=("$f")
done < <(
  find "$STACK_ROOT/env/mb_versions" -maxdepth 1 -name "*.env" ! -name "template.env.example" \
  | sort -V -r
)

if [[ ${#env_file_paths[@]} -eq 0 ]]; then
  echo "No stacks configured yet (no version env files in env/mb_versions/)."
  if [[ "$action" == "start" ]]; then
    echo
    read -rp "Would you like to create your first stack now? [Y/n] " answer </dev/tty
    case "${answer,,}" in
      ""|y|yes)
        echo
        exec "$SCRIPT_DIR/new-stack.sh"
        ;;
    esac
  fi
  echo "Run 'make new' to create a stack."
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

# ── Build menu entries ────────────────────────────────────────────────────────

labels=()
combos=()
for env_file_path in "${env_file_paths[@]}"; do
  version="$(grep -E '^MB_IMAGE_TAG=' "$env_file_path" 2>/dev/null | cut -d= -f2 | tr -d '\r' || true)"
  dataset="$(grep -E '^DATASET=' "$env_file_path" 2>/dev/null | cut -d= -f2 | tr -d '\r' || true)"
  stack_label="$(grep -E '^STACK_LABEL=' "$env_file_path" 2>/dev/null | cut -d= -f2- | tr -d '\r"' || true)"
  [[ -z "$version" || -z "$dataset" ]] && continue  # skip incomplete env files

  if is_running "$version" "$dataset"; then
    running=true
  else
    running=false
  fi

  label="${version}  [${dataset}]"
  [[ -n "$stack_label" ]] && label+="  \"${stack_label}\""

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

# Guard: already-running stack selected for start — nothing to do
if [[ "$action" == "start" ]] && is_running "$selected_version" "$selected_dataset"; then
  echo "Stack ${selected_version} [${selected_dataset}] is already running — nothing to do. Enjoy!"
  exit 0
fi

echo
echo "${action^} stack: ${selected_version}  [${selected_dataset}]"
echo "  → make ${action} MB_VERSION=${selected_version} DATASET=${selected_dataset}"
echo
exec "$SCRIPT_DIR/${action}.sh" "$selected_version" "$selected_dataset"
