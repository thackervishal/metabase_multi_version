#!/usr/bin/env bash
# Polls the remote-sync bare repo for new commits and auto-pulls them into
# the browsable checkout (see ensure_remote_sync_checkout in common.sh).
#
# There's no practical way to react to the push itself: the metabase
# container has no git binary at all (Remote Sync is pure JGit, in-process)
# and no visibility into the host checkout path even if it did, so a
# server-side post-receive hook on the bare repo is a dead end here. Polling
# the bare repo's own ref is the simple, portable alternative — no extra
# dependencies (fswatch/inotifywait aren't reliably available cross-platform,
# notably not on Windows Git Bash).
#
# Run in its own terminal and leave it running while you work; Ctrl-C to stop.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

VERSION="${1:?version is required}"
DATASET_KEY="${2:?dataset is required}"
POLL_SECONDS="${3:-2}"

require_command git

load_stack_env "$VERSION" "$DATASET_KEY"

if [[ "${ENABLE_REMOTE_SYNC}" != "true" ]]; then
  echo "ENABLE_REMOTE_SYNC is not true for ${VERSION} [${DATASET_KEY}] — nothing to watch." >&2
  exit 1
fi

repo_dir="$(remote_sync_repo_dir)"
checkout_dir="$(remote_sync_checkout_dir)"

# `cd` into the target dir and run git with no -C/--git-dir, rather than
# passing an absolute /c/... path as a git argument. Confirmed live: with
# MSYS_NO_PATHCONV=1 or MSYS2_ARG_CONV_EXCL set (a common Git-Bash-on-Windows
# workaround for Docker's own volume-mount path mangling — see
# normalize_native_path in common.sh, the same fix applied there via
# cygpath), MSYS stops auto-translating POSIX paths into Windows form
# specifically when spawning a *native* child process like git.exe, while
# bash's own builtins (cd, [[ -d ]]) are unaffected since they never needed
# that translation. The result: `git -C "$posix_path"` fails with "cannot
# change to '...': No such file or directory" for a directory that
# verifiably exists — bash's own `cd` always resolves it correctly
# regardless of that env var, since no path ever crosses into a subprocess's
# argv. (Using cd here rather than normalize_native_path deliberately —
# this runs in a 2s poll loop, and cd is a shell builtin where
# normalize_native_path would mean an extra cygpath subprocess every tick.)
git_in_checkout() { ( cd "$checkout_dir" && git "$@" ); }
git_in_repo()     { ( cd "$repo_dir" && git "$@" ); }

if [[ ! -d "$checkout_dir" ]]; then
  echo "No checkout at ${checkout_dir} yet — run 'make start' for this stack first (it creates the checkout automatically)." >&2
  exit 1
fi

if [[ ! -d "$checkout_dir/.git" ]]; then
  echo "${checkout_dir} exists but isn't a git checkout (no .git found) — remove it and run 'make start' again to recreate it." >&2
  exit 1
fi

# Wrapped rather than a bare command substitution: a bare `x="$(git ...)"`
# still exits under `set -e` on failure, but only after letting git's own
# `fatal: ...` line print straight to the terminal — confusing when the goal
# is one of the friendly messages above. Capturing stderr here guarantees
# that never leaks through, whatever the failure turns out to be.
if ! branch="$(git_in_checkout branch --show-current 2>&1)"; then
  echo "Failed to read the checkout's branch at ${checkout_dir}:" >&2
  echo "  $branch" >&2
  exit 1
fi
if [[ -z "$branch" ]]; then
  echo "Could not determine the checkout's current branch at ${checkout_dir}." >&2
  exit 1
fi

echo "Watching ${repo_dir} (branch: ${branch})"
echo "Auto-pulling into ${checkout_dir} every ${POLL_SECONDS}s — Ctrl-C to stop."
echo

last="$(git_in_repo rev-parse "refs/heads/${branch}" 2>/dev/null || true)"
while true; do
  sleep "$POLL_SECONDS"
  current="$(git_in_repo rev-parse "refs/heads/${branch}" 2>/dev/null || true)"
  if [[ -n "$current" && "$current" != "$last" ]]; then
    echo "[$(date '+%H:%M:%S')] New push detected (${current:0:7}) — pulling..."
    if git_in_checkout pull --quiet; then
      echo "[$(date '+%H:%M:%S')] Checkout updated."
    else
      echo "[$(date '+%H:%M:%S')] Pull failed — check ${checkout_dir} for local changes/conflicts." >&2
    fi
    last="$current"
  fi
done
