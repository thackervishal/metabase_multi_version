#!/usr/bin/env bash

set -euo pipefail

STACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

start_docker_desktop() {
  case "$(uname -s)" in
    CYGWIN*|MINGW*|MSYS*)
      docker desktop start
      ;;
  esac
}

normalize_shell_path() {
  local raw_path="$1"

  if [[ "$raw_path" =~ ^[A-Za-z]:[\\/].* ]] && command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$raw_path"
    return
  fi

  echo "$raw_path" | sed 's#\\#/#g'
}

normalize_docker_path() {
  local raw_path="$1"

  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$raw_path"
    return
  fi

  echo "$raw_path"
}

configure_optional_tool_paths() {
  local jq_path

  if [[ -z "${JQ_BIN:-}" ]]; then
    return
  fi

  jq_path="$(normalize_shell_path "$JQ_BIN")"
  if [[ ! -x "$jq_path" ]]; then
    echo "Configured JQ_BIN does not exist or is not executable: $JQ_BIN" >&2
    exit 1
  fi

  export JQ_BIN="$jq_path"
  export PATH="$(dirname "$jq_path"):$PATH"
}

sanitize_key() {
  echo "$1" | tr '.-' '__'
}

load_stack_env() {
  if [[ $# -ne 2 ]]; then
    echo "load_stack_env expects: <version> <dataset>" >&2
    exit 1
  fi

  local version="$1"
  local dataset="$2"
  local common_env="$STACK_ROOT/env/common.env"
  local version_env="$STACK_ROOT/env/mb_versions/${version}.env"
  local dataset_env="$STACK_ROOT/env/dwh_source/${dataset}.env"

  for required_file in "$common_env" "$version_env" "$dataset_env"; do
    if [[ ! -f "$required_file" ]]; then
      echo "Missing required env file: $required_file" >&2
      if [[ "$required_file" == "$common_env" ]]; then
        echo "Copy env/common.env.example to env/common.env and update the values." >&2
      fi
      exit 1
    fi
  done

  export MB_VERSION="$version"
  export DATASET="$dataset"

  set -a
  # shellcheck disable=SC1090
  source "$common_env"
  # shellcheck disable=SC1090
  source "$version_env"
  # shellcheck disable=SC1090
  source "$dataset_env"
  set +a

  configure_optional_tool_paths

  export MB_IMAGE_TAG="${MB_IMAGE_TAG:-$version}"

  local version_key
  local dataset_key
  version_key="$(sanitize_key "$version")"
  dataset_key="$(sanitize_key "$dataset")"

  export COMPOSE_PROJECT_NAME="${STACK_PROJECT_PREFIX}_${version_key}_${dataset_key}"
  export APP_DB_VOLUME="${COMPOSE_PROJECT_NAME}_appdb"
  export SAMPLE_DB_VOLUME="${COMPOSE_PROJECT_NAME}_${dataset_key}_data"

  export SAMPLE_DB_DISPLAY_NAME="${SAMPLE_DB_DISPLAY_NAME:-${dataset_key}}"
  export SEED_COLLECTION_NAME="${SEED_COLLECTION_NAME:-${DATASET_NAME:-$SAMPLE_DB_DISPLAY_NAME} Seeded Content}"
  export MB_SITE_NAME="${MB_SITE_NAME:-Metabase ${MB_VERSION} Local Stack}"
  export MB_APPLICATION_NAME="${MB_APPLICATION_NAME:-${MB_VERSION} Metabase}"
  export MB_ANALYTICS_PII_RETENTION_ENABLED="${MB_ANALYTICS_PII_RETENTION_ENABLED:-true}"
  export MB_CHECK_FOR_UPDATES="${MB_CHECK_FOR_UPDATES:-false}"
  export MB_ENABLE_EMBEDDING_INTERACTIVE="${MB_ENABLE_EMBEDDING_INTERACTIVE:-true}"
  export MB_ENABLE_EMBEDDING_SIMPLE="${MB_ENABLE_EMBEDDING_SIMPLE:-true}"
  export MB_ENABLE_EMBEDDING_SDK="${MB_ENABLE_EMBEDDING_SDK:-true}"
  export MB_ENABLE_EMBEDDING_STATIC="${MB_ENABLE_EMBEDDING_STATIC:-true}"
  export MB_EMBEDDING_SECRET_KEY="${MB_EMBEDDING_SECRET_KEY:-0123456789abcdef0123456789abcdef}"
  export MB_SDK_ENCRYPTION_VALIDATION_KEY="${MB_SDK_ENCRYPTION_VALIDATION_KEY:-0123456789abcdef0123456789abcdef}"
  export MB_EMBEDDING_APP_ORIGINS_INTERACTIVE="${MB_EMBEDDING_APP_ORIGINS_INTERACTIVE:-http://localhost:3000 http://localhost:3001 http://127.0.0.1:3000 http://127.0.0.1:3001}"
  export MB_EMBEDDING_APP_ORIGINS_SDK="${MB_EMBEDDING_APP_ORIGINS_SDK:-http://localhost:3000 http://localhost:3001 http://127.0.0.1:3000 http://127.0.0.1:3001}"
  export MB_PERSISTED_MODELS_ENABLED="${MB_PERSISTED_MODELS_ENABLED:-true}"
  export MB_QUERY_CACHING_MAX_KB="${MB_QUERY_CACHING_MAX_KB:-10240}"
  export MB_QUERY_CACHING_MAX_TTL="${MB_QUERY_CACHING_MAX_TTL:-3600}"
  export DEFAULT_CACHE_POLICY_DURATION="${DEFAULT_CACHE_POLICY_DURATION:-1}"
  export DEFAULT_CACHE_POLICY_UNIT="${DEFAULT_CACHE_POLICY_UNIT:-hours}"
  export DEFAULT_CACHE_POLICY_REFRESH_AUTOMATICALLY="${DEFAULT_CACHE_POLICY_REFRESH_AUTOMATICALLY:-false}"
  export DATABASE_CACHE_POLICY_DURATION="${DATABASE_CACHE_POLICY_DURATION:-1}"
  export DATABASE_CACHE_POLICY_UNIT="${DATABASE_CACHE_POLICY_UNIT:-hours}"
  export DATABASE_CACHE_POLICY_REFRESH_AUTOMATICALLY="${DATABASE_CACHE_POLICY_REFRESH_AUTOMATICALLY:-false}"
  export MB_TRANSFORMS_ENABLED="${MB_TRANSFORMS_ENABLED:-true}"
  export MB_AI_FEATURES_ENABLED="${MB_AI_FEATURES_ENABLED:-true}"
  export MB_METABOT_ENABLED="${MB_METABOT_ENABLED:-true}"
  export MB_LLM_METABOT_PROVIDER="${MB_LLM_METABOT_PROVIDER:-anthropic/claude-sonnet-4-6}"
  export MB_LLM_ANTHROPIC_API_KEY="${MB_LLM_ANTHROPIC_API_KEY:-}"

  export STACK_STATE_DIR="$STACK_ROOT/.state"
  export SAMPLE_DB_SEED_MARKER="$STACK_STATE_DIR/${COMPOSE_PROJECT_NAME}.sample-dwh-seeded"
  export METABASE_SEED_MARKER="$STACK_STATE_DIR/${COMPOSE_PROJECT_NAME}.metabase-seeded"
  export SNAPSHOT_DIR="$STACK_ROOT/snapshots/${COMPOSE_PROJECT_NAME}"
}

refresh_metabase_image() {
  local image="metabase/metabase-enterprise:v${MB_IMAGE_TAG}"
  local old_id new_id
  old_id="$(docker images -q "$image" 2>/dev/null)"
  docker pull "$image"
  new_id="$(docker images -q "$image" 2>/dev/null)"
  if [[ -n "$old_id" && "$old_id" != "$new_id" ]]; then
    echo "Removing outdated image ${old_id}."
    docker rmi "$old_id" 2>/dev/null || true
  fi
}

compose() {
  local docker_stack_root
  docker_stack_root="$(normalize_docker_path "$STACK_ROOT")"

  docker compose \
    -p "$COMPOSE_PROJECT_NAME" \
    -f "$docker_stack_root/compose/base.yml" \
    -f "$docker_stack_root/compose/datasets/${DATASET}.yml" \
    "$@"
}

ensure_external_volumes() {
  require_command docker
  docker volume create "$APP_DB_VOLUME" >/dev/null
  docker volume create "$SAMPLE_DB_VOLUME" >/dev/null
}

service_container_id() {
  local service_name="$1"
  compose ps -q "$service_name"
}

wait_for_service_health() {
  local service_name="$1"
  local max_attempts="$2"
  local sleep_seconds="$3"
  local container_id
  local status
  local attempt

  container_id="$(service_container_id "$service_name")"
  if [[ -z "$container_id" ]]; then
    echo "Service $service_name did not create a container." >&2
    return 1
  fi

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id")"

    case "$status" in
      healthy)
        return 0
        ;;
      exited|dead)
        echo "Service $service_name failed with status: $status" >&2
        return 1
        ;;
    esac

    sleep "$sleep_seconds"
  done

  echo "Service $service_name did not become healthy in time." >&2
  return 1
}

wait_for_metabase() {
  require_command curl

  echo "Waiting for Metabase on port ${METABASE_PORT}"

  local attempt=0
  until curl -fsS "http://127.0.0.1:${METABASE_PORT}/api/health" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge 30 ]]; then
      echo "Metabase did not become healthy in time." >&2
      return 1
    fi
    sleep 2
  done

  echo "Metabase is responding."
}