#!/usr/bin/env bash
# Nukes all runtime state for a chosen stack version and deletes its env file.
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
  echo "No stack env files found in env/mb_versions/." >&2
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

# ── Build menu (one entry per env file, version+dataset read from inside it) ──

labels=()
versions_for_idx=()
datasets_for_idx=()
env_files_for_idx=()
for env_file_path in "${env_file_paths[@]}"; do
  version="$(grep -E '^MB_IMAGE_TAG=' "$env_file_path" 2>/dev/null | cut -d= -f2 | tr -d '\r' || true)"
  dataset="$(grep -E '^DATASET=' "$env_file_path" 2>/dev/null | cut -d= -f2 | tr -d '\r' || true)"
  [[ -z "$version" || -z "$dataset" ]] && continue
  label="${version}  [${dataset}]"
  if is_running "$version" "$dataset"; then
    label+="  (running — will be stopped)"
  fi
  labels+=("$label")
  versions_for_idx+=("$version")
  datasets_for_idx+=("$dataset")
  env_files_for_idx+=("$env_file_path")
done

echo
echo "Select a stack to remove:"
echo "  Stops containers, removes volumes, deletes the env file."
echo

for i in "${!labels[@]}"; do
  printf "  %2d)  %s\n" "$((i + 1))" "${labels[$i]}"
done
echo

selected_idx=""
while true; do
  read -rp "Enter number (or q to quit): " choice </dev/tty
  case "$choice" in
    q|Q) exit 0 ;;
    ""|*[!0-9]*)
      echo "  Please enter a number from 1 to ${#labels[@]}, or q to quit."
      ;;
    *)
      if [[ "$choice" -ge 1 && "$choice" -le "${#labels[@]}" ]]; then
        selected_idx="$((choice - 1))"
        break
      fi
      echo "  Please enter a number from 1 to ${#labels[@]}, or q to quit."
      ;;
  esac
done

selected_version="${versions_for_idx[$selected_idx]}"
selected_dataset="${datasets_for_idx[$selected_idx]}"
selected_env_file="${env_files_for_idx[$selected_idx]}"

echo
echo "Remove stack: ${selected_version}  [${selected_dataset}]"
echo "  → delete $(basename "$selected_env_file")"
echo

read -rp "Are you sure? This cannot be undone. [y/N]: " confirm </dev/tty
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# ── Nuke runtime state, then delete env file ──────────────────────────────────

echo
if [[ -n "$selected_dataset" ]]; then
  echo "Nuking ${selected_version} / ${selected_dataset}..."
  "$SCRIPT_DIR/nuke.sh" "$selected_version" "$selected_dataset" --keep-env
  if load_stack_env "$selected_version" "$selected_dataset" 2>/dev/null; then
    container_name="mb-${MB_VERSION}-${selected_dataset}-${METABASE_PORT}-admin"
    bash "$SCRIPT_DIR/firefox-container.sh" "$container_name" --remove 2>/dev/null || true
    log_dir="$STACK_ROOT/metabot-debug-logs/${COMPOSE_PROJECT_NAME}"
    if [[ -d "$log_dir" ]]; then
      rm -rf "$log_dir"
      echo "Removed metabot-debug-logs/${COMPOSE_PROJECT_NAME}"
    fi
  fi
fi

echo "Deleting $(basename "$selected_env_file")"
rm "$selected_env_file"

echo
echo "Stack ${selected_version}  [${selected_dataset}] removed."
