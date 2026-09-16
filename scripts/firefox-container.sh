#!/usr/bin/env bash
# Creates (or verifies) a Firefox Multi-Account Container for a Metabase stack.
# Writes directly to the default profile's containers.json without stopping Firefox.
# The new container only becomes visible in Firefox after a restart.
#
# Exit codes:
#   0  Container already existed — nothing to do.
#   1  Skipped — Firefox not installed or profile not found.
#   2  Container just created — user should restart Firefox to see it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

# Load common.env so JQ_BIN (if set) is picked up
common_env="$STACK_ROOT/env/common.env"
if [[ -f "$common_env" ]]; then
  export DATASET="" MB_VERSION=""
  set -a
  # shellcheck disable=SC1090
  source "$common_env"
  set +a
fi
configure_optional_tool_paths

CONTAINER_NAME="${1:?Usage: firefox-container.sh <container-name> [--remove]}"
MODE="${2:-}"

# ── Firefox installed check ───────────────────────────────────────────────────

firefox_is_installed() {
  case "$(uname -s)" in
    CYGWIN*|MINGW*|MSYS*)
      [[ -x "/c/Program Files/Mozilla Firefox/firefox.exe" ]] ||
      [[ -x "/c/Program Files (x86)/Mozilla Firefox/firefox.exe" ]] ||
      command -v firefox >/dev/null 2>&1
      ;;
    Darwin*)
      [[ -d "/Applications/Firefox.app" ]] || command -v firefox >/dev/null 2>&1
      ;;
    *)
      command -v firefox >/dev/null 2>&1
      ;;
  esac
}

# ── Locate Firefox profiles.ini ───────────────────────────────────────────────

find_profiles_ini() {
  case "$(uname -s)" in
    CYGWIN*|MINGW*|MSYS*)
      local win_appdata="${APPDATA:-$(cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r\n')}"
      normalize_shell_path "${win_appdata}/Mozilla/Firefox/profiles.ini"
      ;;
    Darwin*)
      echo "$HOME/Library/Application Support/Firefox/profiles.ini"
      ;;
    *)
      if [[ -f "$HOME/.mozilla/firefox/profiles.ini" ]]; then
        echo "$HOME/.mozilla/firefox/profiles.ini"
      else
        echo "$HOME/.config/mozilla/firefox/profiles.ini"
      fi
      ;;
  esac
}

# ── Find default profile directory ────────────────────────────────────────────

find_profile_dir() {
  local ini="$1"
  local base_dir
  base_dir="$(dirname "$ini")"

  # [Install...] section's Default= is the most reliable pointer to the active profile
  local rel_path
  rel_path="$(awk '
    /^\[Install/ { in_install=1; next }
    /^\[/        { in_install=0 }
    in_install && /^Default=/ { sub(/^Default=/, ""); print; exit }
  ' "$ini")"

  if [[ -n "$rel_path" ]]; then
    echo "$base_dir/$rel_path"
    return 0
  fi

  # Fallback: Profile section marked Default=1
  rel_path="$(awk '
    /^\[Profile/ { in_profile=1; path=""; is_default=0; next }
    /^\[/        { if (in_profile && is_default && path != "") { print path; exit } in_profile=0 }
    in_profile && /^Path=/     { sub(/^Path=/, ""); path=$0 }
    in_profile && /^Default=1/ { is_default=1 }
    END                        { if (in_profile && is_default && path != "") print path }
  ' "$ini")"

  if [[ -n "$rel_path" ]]; then
    echo "$base_dir/$rel_path"
    return 0
  fi

  return 1
}


# ── Pick a color deterministically from the container name ────────────────────

pick_color() {
  local name="$1"
  local colors=("blue" "turquoise" "green" "yellow" "orange" "red" "pink" "purple")
  local hash=0 i c
  for ((i = 0; i < ${#name}; i++)); do
    printf -v c '%d' "'${name:$i:1}"
    hash=$(( (hash * 31 + c) % ${#colors[@]} ))
  done
  echo "${colors[$hash]}"
}

# ── Add container to containers.json ─────────────────────────────────────────

add_container() {
  local name="$1"
  local profile_dir="$2"
  local containers_json="$profile_dir/containers.json"
  local containers_json_native
  containers_json_native="$(normalize_native_path "$containers_json")"

  if [[ ! -f "$containers_json" ]]; then
    # Firefox only writes containers.json once a custom container exists.
    printf '{"version":5,"lastUserContextId":0,"identities":[]}\n' > "$containers_json"
  fi

  # Skip if container already exists
  local existing
  existing="$(jq -r --arg n "$name" '.identities[] | select(.name == $n) | .name' "$containers_json_native")"
  if [[ -n "$existing" ]]; then
    return 0
  fi

  local color
  color="$(pick_color "$name")"

  local last_id new_id
  last_id="$(jq '.lastUserContextId' "$containers_json_native")"
  new_id=$(( last_id + 1 ))

  local tmp
  tmp="$(mktemp)"
  jq --arg name "$name" \
     --arg color "$color" \
     --argjson id "$new_id" \
     '.lastUserContextId = $id |
      .identities += [{
        "userContextId": $id,
        "public": true,
        "icon": "circle",
        "color": $color,
        "name": $name
      }]' "$containers_json_native" > "$tmp"
  mv "$tmp" "$containers_json"

  echo "Created Firefox container '${name}' (${color})."
}

# ── Remove container from containers.json ────────────────────────────────────

remove_container() {
  local name="$1"
  local profile_dir="$2"
  local containers_json="$profile_dir/containers.json"
  local containers_json_native
  containers_json_native="$(normalize_native_path "$containers_json")"

  [[ -f "$containers_json" ]] || return 0

  local existing
  existing="$(jq -r --arg n "$name" '.identities[] | select(.name == $n) | .name' "$containers_json_native" 2>/dev/null || true)"
  [[ -n "$existing" ]] || return 0

  local tmp
  tmp="$(mktemp)"
  jq --arg name "$name" 'del(.identities[] | select(.name == $name))' "$containers_json_native" > "$tmp"
  mv "$tmp" "$containers_json"
  echo "Removed Firefox container '${name}'."
}

# ── Main ──────────────────────────────────────────────────────────────────────

if ! firefox_is_installed; then
  exit 1
fi

profiles_ini="$(find_profiles_ini)"
[[ -f "$profiles_ini" ]] || exit 1

profile_dir="$(find_profile_dir "$profiles_ini")" || exit 1

if [[ "$MODE" == "--remove" ]]; then
  remove_container "$CONTAINER_NAME" "$profile_dir"
  exit 0
fi

# Check existence before touching Firefox — only close it if we actually need to create the container
containers_json="$profile_dir/containers.json"
containers_json_native="$(normalize_native_path "$containers_json")"

if [[ -f "$containers_json" ]]; then
  existing="$(jq -r --arg n "$CONTAINER_NAME" \
    '.identities[] | select(.name == $n) | .name' "$containers_json_native" 2>/dev/null || true)"
  if [[ -n "$existing" ]]; then
    exit 0  # already exists, nothing to do
  fi
fi

add_container "$CONTAINER_NAME" "$profile_dir"
exit 2  # just created — caller should tell user to restart Firefox
