#!/bin/sh
# laya-serve reads LAYA_API_KEY but not LAYA_API_KEY_FILE (only upstream's own
# Docker entrypoint does). Load the key from the mounted secret file, and refuse
# to start without one so the server can never run unauthenticated.
set -eu

if [ -z "${LAYA_API_KEY_FILE:-}" ] || [ ! -s "$LAYA_API_KEY_FILE" ]; then
  echo "laya: LAYA_API_KEY_FILE is missing or empty. Refusing to start without auth." >&2
  exit 1
fi

LAYA_API_KEY="$(cat "$LAYA_API_KEY_FILE")"
export LAYA_API_KEY

exec "$@"
