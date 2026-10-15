#!/usr/bin/env bash
# Start/stop the local Laya decision-model server (see .github/agent-laya.md).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

normalize_docker_path() {
  local raw_path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$raw_path"
    return
  fi
  echo "$raw_path" | sed 's#\\#/#g'
}

if [[ -f "$STACK_ROOT/env/common.env" ]]; then
  # common.env references vars such as DATASET that only stack scripts define.
  set +u -a
  # shellcheck disable=SC1091
  source "$STACK_ROOT/env/common.env"
  set -u +a
fi

LAYA_COMPOSE="$(normalize_docker_path "$STACK_ROOT")/compose/laya/compose.yml"
KEY_FILE="$STACK_ROOT/.state/laya-api-key"
PORT="${LAYA_PORT:-8787}"

laya_compose() {
  docker compose -f "$LAYA_COMPOSE" "$@"
}

# One key per machine, kept out of env files and `ps` output. World-readable on
# purpose: the container user (uid 10001) must read the bind-mounted secret on
# Linux, and the server only listens on 127.0.0.1.
ensure_key() {
  if [[ ! -s "$KEY_FILE" ]]; then
    mkdir -p "$STACK_ROOT/.state"
    printf '%s' "laya_$(openssl rand -hex 24 | tr -d '\r')" > "$KEY_FILE"
    chmod 644 "$KEY_FILE"
    echo "Created API key file: .state/laya-api-key"
  fi
}

case "${1:?Usage: laya.sh <up|stop|down|status|check|logs>}" in
  up)
    command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }
    ensure_key
    echo "Starting Laya (first run builds the image and downloads model weights; this can take several minutes)..."
    laya_compose up -d --build
    echo "Waiting for the server to become healthy..."
    for _ in $(seq 1 90); do
      state="$(laya_compose ps --format '{{.Health}}' laya 2>/dev/null | tr -d '\r' || true)"
      if [[ "$state" == "healthy" ]]; then
        echo "Laya is up: http://127.0.0.1:${PORT}  (key in .state/laya-api-key)"
        exit 0
      fi
      sleep 5
    done
    echo "Laya did not become healthy in 7.5 minutes. See: bash scripts/laya.sh logs" >&2
    exit 1
    ;;
  stop)
    laya_compose stop
    ;;
  down)
    laya_compose down
    echo "Model cache volume kept. Remove it with: docker volume rm laya_laya_hf"
    ;;
  status)
    ensure_key
    if curl -fsS -m 3 -H "Authorization: Bearer $(cat "$KEY_FILE")" "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
      echo "Laya is up on http://127.0.0.1:${PORT}"
    else
      echo "Laya is not reachable on http://127.0.0.1:${PORT}"
      exit 1
    fi
    ;;
  check)
    # Confirms the GPU is really used (not a silent CPU fallback).
    laya_compose exec -T laya python -c \
      "import torch; print('cuda available:', torch.cuda.is_available()); print('device:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'none')"
    ;;
  logs)
    laya_compose logs --tail 80 laya
    ;;
  *)
    echo "Usage: laya.sh <up|stop|down|status|check|logs>" >&2
    exit 1
    ;;
esac
