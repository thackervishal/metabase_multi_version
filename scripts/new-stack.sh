#!/usr/bin/env bash
# Interactively create a new version env file and optionally start the stack.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

load_common_env

# ── Discover datasets ─────────────────────────────────────────────────────────

datasets=()
while IFS= read -r f; do
  datasets+=("$(basename "$f" .env)")
done < <(find "$STACK_ROOT/env/dwh_source" -maxdepth 1 -name "*.env" | sort)

if [[ ${#datasets[@]} -eq 0 ]]; then
  echo "No dataset profiles found in env/dwh_source/." >&2
  exit 1
fi

# ── Fetch recent major.minor versions for the prompt hint ────────────────────

recent_majors=""
recent_majors_hint=""
_majors_raw="$(curl -fsSL \
  "https://hub.docker.com/v2/repositories/metabase/metabase-enterprise/tags?page_size=100&ordering=last_updated" \
  2>/dev/null \
  | jq -r '.results[].name
      | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"))
      | select(test("beta|rc|alpha"; "i") | not)
      | ltrimstr("v")
      | split(".")[0:2] | join(".")' \
  | tr -d '\r' \
  | sort -t. -k1,1n -k2,2n \
  | uniq \
  | tail -10 \
  || true)"

if [[ -n "$_majors_raw" ]]; then
  recent_majors="$(echo "$_majors_raw" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')"
  latest_major="$(echo "$_majors_raw" | tail -1 | tr -d '\r')"
fi

# ── Prompt for major ──────────────────────────────────────────────────────────

echo
echo "Let's create a new stack. Which Metabase version do you want?"
echo
if [[ -n "${recent_majors:-}" ]]; then
  echo "  Recent versions: ${recent_majors}"
  echo
fi
read -rp "Metabase major version (e.g. ${latest_major:-1.61}): " major_minor </dev/tty
if [[ ! "$major_minor" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid format — enter as e.g. 1.61" >&2
  exit 1
fi

# ── Fetch all stable tags for this major (one request) ───────────────────────

# 0.x = OSS (metabase/metabase), 1.x = Enterprise (metabase/metabase-enterprise)
if [[ "$major_minor" == 0.* ]]; then
  hub_repo="metabase/metabase"
  edition="OSS"
else
  hub_repo="metabase/metabase-enterprise"
  edition="Enterprise"
fi

echo
echo "Fetching available ${major_minor} builds from Docker Hub (${edition})..."

tags_json="$(curl -fsSL \
  "https://hub.docker.com/v2/repositories/${hub_repo}/tags?page_size=50&name=v${major_minor}." \
  2>/dev/null)" || {
  echo "Failed to reach Docker Hub. Check your internet connection." >&2
  exit 1
}

all_tags=()
while IFS= read -r tag; do
  [[ -n "$tag" ]] && all_tags+=("$tag")
done < <(
  echo "$tags_json" | jq -r \
    --arg prefix "v${major_minor}." \
    '.results[].name
      | select(startswith($prefix))
      | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"))
      | select(test("beta|rc|alpha"; "i") | not)' \
  | tr -d '\r' \
  | sort -V -r
)

if [[ ${#all_tags[@]} -eq 0 ]]; then
  echo "No stable builds found for ${major_minor} on Docker Hub." >&2
  echo "Check the version number and try again." >&2
  exit 0
fi

# ── Pick minor ────────────────────────────────────────────────────────────────

# Derive unique minor versions (X.Y.Z without the hotfix digit), newest first.
minor_list=()
declare -A seen_minors
for tag in "${all_tags[@]}"; do
  stripped="${tag#v}"
  minor="${stripped%.*}"
  if [[ -z "${seen_minors[$minor]+x}" ]]; then
    seen_minors["$minor"]=1
    minor_list+=("$minor")
  fi
done

echo
echo "Minor versions for ${major_minor} (newest first):"
echo

for i in "${!minor_list[@]}"; do
  minor="${minor_list[$i]}"
  label="$minor"
  if find "$STACK_ROOT/env/mb_versions" -maxdepth 1 -name "${minor}.[0-9]*_*.env" 2>/dev/null | grep -q .; then
    label+="  (stack exists)"
  fi
  printf "  %2d)  %s\n" "$((i + 1))" "$label"
done
echo

selected_minor=""
while true; do
  read -rp "Enter number (or q to quit): " choice </dev/tty
  case "$choice" in
    q|Q) exit 0 ;;
    *)
      if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#minor_list[@]}" ]]; then
        selected_minor="${minor_list[$((choice - 1))]}"
        break
      fi
      echo "  Please enter a number from 1 to ${#minor_list[@]}, or q to quit."
      ;;
  esac
done

# ── Pick hotfix or float ──────────────────────────────────────────────────────

hotfix_tags=()
for tag in "${all_tags[@]}"; do
  stripped="${tag#v}"
  [[ "${stripped%.*}" == "$selected_minor" ]] && hotfix_tags+=("$tag")
done

floating_tag="${selected_minor}.x"

echo
echo "Builds for ${selected_minor} (newest first):"
echo

for i in "${!hotfix_tags[@]}"; do
  tag="${hotfix_tags[$i]}"
  label="$tag"
  find "$STACK_ROOT/env/mb_versions" -maxdepth 1 -name "${tag#v}_*.env" 2>/dev/null | grep -q . && label+="  (stack exists)"
  printf "  %2d)  %s\n" "$((i + 1))" "$label"
done

float_label="Float on latest patch  →  MB_IMAGE_TAG=${floating_tag}  (auto-pulls newer bugfixes on make start)"
find "$STACK_ROOT/env/mb_versions" -maxdepth 1 -name "${floating_tag}_*.env" 2>/dev/null | grep -q . && float_label+="  (a variant exists)"
echo
echo "  f)  ${float_label}"
echo "  q)  Quit"
echo

image_tag=""
while true; do
  read -rp "Enter number to pin, f to float, or q to quit [f]: " choice </dev/tty
  choice="${choice:-f}"
  case "$choice" in
    q|Q)
      exit 0
      ;;
    f|F)
      image_tag="$floating_tag"
      break
      ;;
    *[!0-9]*)
      echo "  Enter a number from 1 to ${#hotfix_tags[@]}, f, or q."
      ;;
    *)
      if [[ "$choice" -ge 1 && "$choice" -le "${#hotfix_tags[@]}" ]]; then
        image_tag="${hotfix_tags[$((choice - 1))]#v}"
        break
      fi
      echo "  Enter a number from 1 to ${#hotfix_tags[@]}, f, or q."
      ;;
  esac
done

# ── Select dataset ────────────────────────────────────────────────────────────

if [[ ${#datasets[@]} -eq 1 ]]; then
  selected_dataset="${datasets[0]}"
  echo
  echo "Dataset: ${selected_dataset}"
else
  echo
  echo "Select a dataset:"
  for i in "${!datasets[@]}"; do
    printf "  %2d)  %s\n" "$((i + 1))" "${datasets[$i]}"
  done
  echo
  while true; do
    read -rp "Enter number (or q to quit): " dchoice </dev/tty
    case "$dchoice" in
      q|Q) exit 0 ;;
      *)
        if [[ "$dchoice" =~ ^[0-9]+$ && "$dchoice" -ge 1 && "$dchoice" -le "${#datasets[@]}" ]]; then
          selected_dataset="${datasets[$((dchoice - 1))]}"
          break
        fi
        echo "  Please enter a number from 1 to ${#datasets[@]}, or q to quit."
        ;;
    esac
  done
fi

# ── Check this (version, dataset) combination doesn't already exist ───────────

env_file="$STACK_ROOT/env/mb_versions/${image_tag}_${selected_dataset}.env"
if [[ -f "$env_file" ]]; then
  echo
  echo "Stack ${image_tag} [${selected_dataset}] is already configured — nothing to do."
  echo "Use 'make start' to start it, or 'make remove' to remove it first."
  exit 0
fi

# ── Suggest ports based on existing env files ─────────────────────────────────

max_metabase=3290
max_appdb=15392
max_sampledwh=15393

while IFS= read -r f; do
  port="$(grep -E '^METABASE_PORT=' "$f" 2>/dev/null | cut -d= -f2 || true)"
  if [[ -n "$port" && "$port" -gt "$max_metabase" ]]; then max_metabase="$port"; fi
  port="$(grep -E '^APP_DB_PORT=' "$f" 2>/dev/null | cut -d= -f2 || true)"
  if [[ -n "$port" && "$port" -gt "$max_appdb" ]]; then max_appdb="$port"; fi
  port="$(grep -E '^SAMPLE_DB_PORT=' "$f" 2>/dev/null | cut -d= -f2 || true)"
  if [[ -n "$port" && "$port" -gt "$max_sampledwh" ]]; then max_sampledwh="$port"; fi
done < <(
  find "$STACK_ROOT/env/mb_versions" -maxdepth 1 -name "*.env" ! -name "template.env.example" 2>/dev/null \
  || true
)

sug_metabase=$(( max_metabase + 10 ))
sug_appdb=$(( max_appdb + 10 ))
sug_sampledwh=$(( max_sampledwh + 10 ))

# ── Prompt for ports ──────────────────────────────────────────────────────────

echo
echo "Port assignments — press Enter to accept each suggestion."
echo "If there is a conflict on start, edit env/mb_versions/${image_tag}_${selected_dataset}.env and retry."
echo

read -rp "  METABASE_PORT  [${sug_metabase}]: " metabase_port </dev/tty
metabase_port="${metabase_port:-$sug_metabase}"

read -rp "  APP_DB_PORT    [${sug_appdb}]: " appdb_port </dev/tty
appdb_port="${appdb_port:-$sug_appdb}"

read -rp "  SAMPLE_DB_PORT [${sug_sampledwh}]: " sampledwh_port </dev/tty
sampledwh_port="${sampledwh_port:-$sug_sampledwh}"

# ── Optional shared services ──────────────────────────────────────────────────

echo
read -rp "Enable email capture (Mailpit)? [y/N]: " enable_email </dev/tty
enable_email="${enable_email:-N}"
[[ "$enable_email" =~ ^[Yy]$ ]] && enable_email_val=true || enable_email_val=false

read -rp "Enable webhook receiver? [y/N]: " enable_webhooks </dev/tty
enable_webhooks="${enable_webhooks:-N}"
[[ "$enable_webhooks" =~ ^[Yy]$ ]] && enable_webhooks_val=true || enable_webhooks_val=false

read -rp "Enable SAML SSO (Keycloak)? [y/N]: " enable_saml </dev/tty
enable_saml="${enable_saml:-N}"
[[ "$enable_saml" =~ ^[Yy]$ ]] && enable_saml_val=true || enable_saml_val=false

# ── Optional friendly name ────────────────────────────────────────────────────

echo
read -rp "Give this stack a friendly name (optional, e.g. 'testing keycloak'): " stack_label </dev/tty

# ── Write env file ────────────────────────────────────────────────────────────

cat > "$env_file" <<EOF
MB_IMAGE_TAG=${image_tag}
DATASET=${selected_dataset}
METABASE_PORT=${metabase_port}
APP_DB_PORT=${appdb_port}
SAMPLE_DB_PORT=${sampledwh_port}
ENABLE_EMAIL=${enable_email_val}
ENABLE_WEBHOOKS=${enable_webhooks_val}
ENABLE_SAML=${enable_saml_val}
EOF

if [[ -n "$stack_label" ]]; then
  echo "STACK_LABEL=\"${stack_label}\"" >> "$env_file"
fi

echo
echo "Created env/mb_versions/${image_tag}_${selected_dataset}.env"

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
