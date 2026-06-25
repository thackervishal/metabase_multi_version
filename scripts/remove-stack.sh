#!/usr/bin/env bash
# Nukes all runtime state for a chosen stack version and deletes its env file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

load_common_env

# ── Discover versions and datasets ───────────────────────────────────────────

versions=()
while IFS= read -r f; do
  versions+=("$(basename "$f" .env | tr -d '\r')")
done < <(
  find "$STACK_ROOT/env/mb_versions" -maxdepth 1 -name "*.env" ! -name "template.env.example" \
  | sort -V -r
)

datasets=()
while IFS= read -r f; do
  datasets+=("$(basename "$f" .env)")
done < <(find "$STACK_ROOT/env/dwh_source" -maxdepth 1 -name "*.env" | sort)

if [[ ${#versions[@]} -eq 0 ]]; then
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

# ── Build menu (one entry per version) ───────────────────────────────────────

labels=()
for version in "${versions[@]}"; do
  label="$version"
  for dataset in "${datasets[@]}"; do
    if is_running "$version" "$dataset"; then
      label+="  (running — will be stopped)"
      break
    fi
  done
  labels+=("$label")
done

echo
echo "Select a stack to remove:"
echo "  Nukes all runtime state for the chosen version and deletes its env file."
echo

for i in "${!labels[@]}"; do
  printf "  %2d)  %s\n" "$((i + 1))" "${labels[$i]}"
done
echo

selected_version=""
while true; do
  read -rp "Enter number (or q to quit): " choice </dev/tty
  case "$choice" in
    q|Q) exit 0 ;;
    ""|*[!0-9]*)
      echo "  Please enter a number from 1 to ${#labels[@]}, or q to quit."
      ;;
    *)
      if [[ "$choice" -ge 1 && "$choice" -le "${#labels[@]}" ]]; then
        selected_version="${versions[$((choice - 1))]}"
        break
      fi
      echo "  Please enter a number from 1 to ${#labels[@]}, or q to quit."
      ;;
  esac
done

env_file="$STACK_ROOT/env/mb_versions/${selected_version}.env"

echo
echo "Remove stack: ${selected_version}"
echo "  → nuke all dataset combos + delete env/mb_versions/${selected_version}.env"
echo

read -rp "Are you sure? This cannot be undone. [y/N]: " confirm </dev/tty
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# ── Nuke all dataset combos, then delete env file ────────────────────────────

echo
for dataset in "${datasets[@]}"; do
  echo "Nuking ${selected_version} / ${dataset}..."
  "$SCRIPT_DIR/nuke.sh" "$selected_version" "$dataset" --keep-env
done

echo
for dataset in "${datasets[@]}"; do
  if load_stack_env "$selected_version" "$dataset" 2>/dev/null; then
    container_name="mb-${MB_VERSION}-${dataset}-${METABASE_PORT}-admin"
    bash "$SCRIPT_DIR/firefox-container.sh" "$container_name" --remove 2>/dev/null || true
    log_dir="$STACK_ROOT/metabot-debug-logs/${COMPOSE_PROJECT_NAME}"
    if [[ -d "$log_dir" ]]; then
      rm -rf "$log_dir"
      echo "Removed metabot-debug-logs/${COMPOSE_PROJECT_NAME}"
    fi
  fi
done

echo "Deleting env/mb_versions/${selected_version}.env"
rm "$env_file"

echo
echo "Stack ${selected_version} removed."
