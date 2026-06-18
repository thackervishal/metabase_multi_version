#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

require_command docker

retention_days="${IMAGE_GC_RETENTION_DAYS:-30}"
retention_seconds="$((retention_days * 24 * 60 * 60))"
marker_dir="$(image_gc_dir)"
now="$(date +%s)"
removed_any=false

if [[ ! -d "$marker_dir" ]]; then
  echo "No retained Metabase images are pending cleanup."
  exit 0
fi

shopt -s nullglob
for marker_path in "$marker_dir"/*.nuked-at; do
  unset NUKED_AT IMAGE_REF
  # shellcheck disable=SC1090
  source "$marker_path"

  if [[ -z "${NUKED_AT:-}" || -z "${IMAGE_REF:-}" ]]; then
    rm -f "$marker_path"
    continue
  fi

  if ! docker image inspect "$IMAGE_REF" >/dev/null 2>&1; then
    rm -f "$marker_path"
    continue
  fi

  if image_has_container_references "$IMAGE_REF"; then
    continue
  fi

  if (( now - NUKED_AT < retention_seconds )); then
    continue
  fi

  echo "Removing expired retained image ${IMAGE_REF}..."
  if docker image rm "$IMAGE_REF" >/dev/null 2>&1; then
    rm -f "$marker_path"
    removed_any=true
  fi
done

if [[ "$removed_any" == false ]]; then
  echo "No retained Metabase images are old enough to remove."
fi