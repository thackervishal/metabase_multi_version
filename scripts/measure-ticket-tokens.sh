#!/usr/bin/env bash
# Sum tool-result sizes per tool for a Claude Code session, to see where tokens go.
# Usage: scripts/measure-ticket-tokens.sh <marker> [transcript.jsonl]
#   marker      text that appears in the first message of the run, e.g. a Pylon ticket number
#   transcript  defaults to the newest session for this repo under ~/.claude/projects
# Output is sizes only (no content). ~tokens is chars / 4, a rough estimate that
# ignores model output and the cost of re-reading context on every turn.
set -euo pipefail

MARKER="${1:?Usage: measure-ticket-tokens.sh <marker> [transcript.jsonl]}"
TRANSCRIPT="${2:-}"

if [[ -z "$TRANSCRIPT" ]]; then
  slug="$(pwd -W 2>/dev/null || pwd)"
  slug="$(echo "$slug" | sed -E 's#[:\\/_.]#-#g; s#--+#-#g' )"
  dir="$(ls -d "$HOME"/.claude/projects/*/ 2>/dev/null | grep -i -- "$(basename "$(pwd)" | sed 's/_/-/g')" | head -1 || true)"
  [[ -n "$dir" ]] || { echo "No transcript folder found; pass the .jsonl path." >&2; exit 1; }
  TRANSCRIPT="$(ls -t "$dir"*.jsonl | head -1)"
fi

jq -s -r --arg m "$MARKER" '
  (to_entries | map(select((.value | tostring) | contains($m))) | .[0].key) as $start
  | if $start == null then error("marker not found in transcript") else . end
  | .[$start:] as $rows
  | ($rows | [ .[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | {(.id): .name} ] | add // {}) as $names
  | [ $rows[] | select(.type=="user") | .message.content[]? | select(type=="object" and .type=="tool_result")
      | { name: ($names[.tool_use_id] // "unknown"),
          chars: ( if (.content|type)=="string" then (.content|length)
                   else ([.content[]? | select(.type=="text") | .text | length] | add // 0) end ) } ]
  | group_by(.name)
  | map({tool: .[0].name, calls: length, chars: (map(.chars)|add), biggest: (map(.chars)|max)})
  | sort_by(-.chars)
  | (["tool","calls","chars","~tokens","biggest_call_chars"] | @tsv),
    (.[] | [.tool, .calls, .chars, ((.chars/4)|floor), .biggest] | @tsv),
    ("TOTAL\t\t" + ((map(.chars)|add // 0)|tostring) + "\t" + (((map(.chars)|add // 0)/4)|floor|tostring))
' "$TRANSCRIPT" | column -t -s $'\t' | cut -c1-120
