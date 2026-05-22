#!/usr/bin/env bash
# Interactively create a new version env file and optionally start the stack.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

common_env="$STACK_ROOT/env/common.env"
if [[ ! -f "$common_env" ]]; then
  echo "Missing env/common.env — copy from env/common.env.example and fill in values." >&2
  exit 1
fi

export DATASET="" MB_VERSION=""
set -a
# shellcheck disable=SC1090
source "$common_env"
set +a
configure_optional_tool_paths

# ── Discover datasets ─────────────────────────────────────────────────────────

datasets=()
while IFS= read -r f; do
  datasets+=("$(basename "$f" .env)")
done < <(find "$STACK_ROOT/env/dwh_source" -maxdepth 1 -name "*.env" | sort)

if [[ ${#datasets[@]} -eq 0 ]]; then
  echo "No dataset profiles found in env/dwh_source/." >&2
  exit 1
fi

# ── Prompt for major.minor ────────────────────────────────────────────────────

echo
read -rp "Metabase major.minor version (e.g. 1.61): " major_minor </dev/tty
if [[ ! "$major_minor" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid format — enter as <major>.<minor> e.g. 1.61" >&2
  exit 1
fi

# ── Fetch tags from Docker Hub ────────────────────────────────────────────────

echo
echo "Fetching available ${major_minor} builds from Docker Hub..."

tags_json="$(curl -fsSL \
  "https://hub.docker.com/v2/repositories/metabase/metabase-enterprise/tags?page_size=50&name=v${major_minor}." \
  2>/dev/null)" || {
  echo "Failed to reach Docker Hub. Check your internet connection." >&2
  exit 1
}

available_tags=()
while IFS= read -r tag; do
  [[ -n "$tag" ]] && available_tags+=("$tag")
done < <(
  echo "$tags_json" | jq -r \
    --arg prefix "v${major_minor}." \
    '.results[].name
      | select(startswith($prefix))
      | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"))
      | select(test("beta|rc|alpha"; "i") | not)' \
  | sort -r
)

if [[ ${#available_tags[@]} -eq 0 ]]; then
  echo "No stable builds found for ${major_minor} on Docker Hub." >&2
  echo "Check the version number and try again." >&2
  exit 1
fi

# ── Prompt for float vs pin ───────────────────────────────────────────────────

latest="${available_tags[0]}"
stripped="${latest#v}"
floating_tag="${stripped%.*}.x"

echo
echo "Available builds for ${major_minor} (newest first):"
echo

for i in "${!available_tags[@]}"; do
  printf "  %2d)  %s\n" "$((i + 1))" "${available_tags[$i]}"
done

echo
echo "  f)  Float on latest patch  →  MB_IMAGE_TAG=${floating_tag}  (auto-pulls newer bugfixes on make start)"
echo

image_tag=""
while true; do
  read -rp "Enter number to pin, or f to float [f]: " choice </dev/tty
  choice="${choice:-f}"
  case "$choice" in
    f|F)
      image_tag="$floating_tag"
      break
      ;;
    ""|*[!0-9]*)
      echo "  Enter a number from 1 to ${#available_tags[@]}, or f."
      ;;
    *)
      if [[ "$choice" -ge 1 && "$choice" -le "${#available_tags[@]}" ]]; then
        image_tag="${available_tags[$((choice - 1))]#v}"
        break
      fi
      echo "  Enter a number from 1 to ${#available_tags[@]}, or f."
      ;;
  esac
done

# ── Check env file doesn't already exist ─────────────────────────────────────

env_file="$STACK_ROOT/env/mb_versions/${image_tag}.env"
if [[ -f "$env_file" ]]; then
  echo
  echo "Stack env file already exists: env/mb_versions/${image_tag}.env" >&2
  echo "Remove it first or choose a different tag." >&2
  exit 1
fi

# ── Suggest ports based on existing env files ─────────────────────────────────

max_metabase=2900
max_appdb=15392
max_sampledwh=15393

while IFS= read -r f; do
  port="$(grep -E '^METABASE_PORT=' "$f" 2>/dev/null | cut -d= -f2 || true)"
  if [[ -n "$port" && "$port" -gt "$max_metabase" ]]; then
    max_metabase="$port"
  fi
  port="$(grep -E '^APP_DB_PORT=' "$f" 2>/dev/null | cut -d= -f2 || true)"
  if [[ -n "$port" && "$port" -gt "$max_appdb" ]]; then
    max_appdb="$port"
  fi
  port="$(grep -E '^SAMPLE_DB_PORT=' "$f" 2>/dev/null | cut -d= -f2 || true)"
  if [[ -n "$port" && "$port" -gt "$max_sampledwh" ]]; then
    max_sampledwh="$port"
  fi
done < <(
  find "$STACK_ROOT/env/mb_versions" -maxdepth 1 -name "*.env" ! -name "template.env.example" 2>/dev/null \
  || true
)

sug_metabase=$(( max_metabase + 100 ))
sug_appdb=$(( max_appdb + 10 ))
sug_sampledwh=$(( max_sampledwh + 10 ))

# ── Prompt for ports ──────────────────────────────────────────────────────────

echo
echo "Port assignments — press Enter to accept each suggestion."
echo "If there is a conflict on start, edit env/mb_versions/${image_tag}.env and retry."
echo

read -rp "  METABASE_PORT  [${sug_metabase}]: " metabase_port </dev/tty
metabase_port="${metabase_port:-$sug_metabase}"

read -rp "  APP_DB_PORT    [${sug_appdb}]: " appdb_port </dev/tty
appdb_port="${appdb_port:-$sug_appdb}"

read -rp "  SAMPLE_DB_PORT [${sug_sampledwh}]: " sampledwh_port </dev/tty
sampledwh_port="${sampledwh_port:-$sug_sampledwh}"

# ── Write env file ────────────────────────────────────────────────────────────

cat > "$env_file" <<EOF
MB_IMAGE_TAG=${image_tag}
METABASE_PORT=${metabase_port}
APP_DB_PORT=${appdb_port}
SAMPLE_DB_PORT=${sampledwh_port}
EOF

echo
echo "Created env/mb_versions/${image_tag}.env"

# ── Select dataset (auto if only one) ─────────────────────────────────────────

if [[ ${#datasets[@]} -eq 1 ]]; then
  selected_dataset="${datasets[0]}"
else
  echo
  echo "Select a dataset:"
  for i in "${!datasets[@]}"; do
    printf "  %2d)  %s\n" "$((i + 1))" "${datasets[$i]}"
  done
  echo
  while true; do
    read -rp "Enter number: " dchoice </dev/tty
    if [[ "$dchoice" =~ ^[0-9]+$ && "$dchoice" -ge 1 && "$dchoice" -le "${#datasets[@]}" ]]; then
      selected_dataset="${datasets[$((dchoice - 1))]}"
      break
    fi
    echo "  Please enter a number from 1 to ${#datasets[@]}."
  done
fi

# ── Optionally start ──────────────────────────────────────────────────────────

echo
read -rp "Start the stack now? [Y/n]: " start_now </dev/tty
start_now="${start_now:-Y}"

if [[ "$start_now" =~ ^[Yy]$ ]]; then
  echo
  exec "$SCRIPT_DIR/start.sh" "$image_tag" "$selected_dataset"
else
  echo
  echo "Run 'make start' when ready."
fi
