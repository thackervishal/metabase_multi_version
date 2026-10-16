#!/usr/bin/env bash
# Health check for the ticket-RCA setup. No model tokens are used.
#   tools [N]    RCA MCP tools seen in the newest N transcripts (default 3) that are in
#                neither the allow list, the deny list, nor keep-on-prompt.txt, plus
#                allow entries that were not seen (possibly removed upstream).
#   laya         Laya version vs PyPI, torch pin, container state.
#   stats [DAYS] Token stats for /ticket-rca runs in transcripts from the last DAYS (default 30).
#   all          All of the above. Writes data/rca-health/<date>.md and stamps the run.
#   due          Prints DUE if the last "all" run is older than 7 days. Silent otherwise.
# Output holds names and sizes only, never message content.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="${RCA_SETTINGS:-$ROOT/.claude/settings.json}"
KEEP="$ROOT/.claude/skills/rca-maintenance/keep-on-prompt.txt"
OUT="$ROOT/data/rca-health"
# RCA servers whose tools settings.json governs. Keep in sync with scripts/setup-mcps.sh.
SERVER_RE='grafana|pylon|linear|notion|claude_ai_Slack'
WRITE_RE='__(create|update|delete|save|send|post|publish|merge|move|upload|set|submit|snooze|link|spawn|stop|restore|retire|mark|share|unshare|resolve|schedule|add|convert|duplicate|archive|remove|write|edit|manage|import|trigger|invite|update)[_-]'

transcript_dir() {
  local name
  name="$(basename "$ROOT" | sed 's/_/-/g')"
  ls -d "$HOME"/.claude/projects/*/ 2>/dev/null | grep -i -- "$name" | head -1
}

cmd_tools() {
  local n="${1:-3}" dir files seen
  dir="$(transcript_dir)"; [[ -n "$dir" ]] || { echo "No transcript folder found."; return 0; }
  files="$(ls -t "$dir"*.jsonl | head -"$n")"
  # Replay the harness's tool announcements (deferred_tools_delta) in order, so the result
  # is the set of tools actually available at the end of each session. Names merely typed
  # in the chat do not count.
  seen="$(for f in $files; do
    jq -n -r --arg re "$SERVER_RE" '
      [inputs | select(.attachment.type? == "deferred_tools_delta") | .attachment]
      | reduce .[] as $d ({};
          (reduce (($d.addedNames // []) + ($d.readdedNames // []))[] as $n (.; .[$n] = true))
          | (reduce ($d.removedNames // [])[] as $n (.; del(.[$n]))))
      | keys[] | select(test("^mcp__(?:" + $re + ")__"))' "$f" 2>/dev/null
  done | tr -d '\r' | sort -u)"
  local allow deny keep
  allow="$(jq -r '.permissions.allow[]' "$SETTINGS" | grep -E "^mcp__($SERVER_RE)__" | sort -u)"
  deny="$(jq -r '.permissions.deny[]' "$SETTINGS" | grep -E "^mcp__($SERVER_RE)__" | sort -u)"
  keep="$(grep -E '^mcp__' "$KEEP" 2>/dev/null | sort -u || true)"

  echo "## Tool lists (newest $n sessions)"
  echo "Seen: $(echo "$seen" | grep -c . || true)  Allowed: $(echo "$allow" | grep -c . || true)  Denied: $(echo "$deny" | grep -c . || true)  Kept on prompt: $(echo "$keep" | grep -c . || true)"
  local unclassified
  unclassified="$(comm -23 <(echo "$seen") <(printf '%s\n%s\n%s\n' "$allow" "$deny" "$keep" | sort -u) | grep . || true)"
  local writes reads
  writes="$(echo "$unclassified" | grep -E "$WRITE_RE" || true)"
  reads="$(echo "$unclassified" | grep -vE "$WRITE_RE" | grep . || true)"
  echo
  echo "### New tools that look like writes (deny these)"
  [[ -n "$writes" ]] && echo "$writes" | sed 's/^/- /' || echo "none"
  echo
  echo "### New tools that look read-only (allow, keep on prompt, or deny)"
  [[ -n "$reads" ]] && echo "$reads" | sed 's/^/- /' || echo "none"
  echo
  echo "### Allowed tools not seen recently (removed upstream, or renamed?)"
  local stale
  stale="$(comm -23 <(echo "$allow") <(echo "$seen") | grep . || true)"
  [[ -n "$stale" ]] && echo "$stale" | sed 's/^/- /' || echo "none"
}

cmd_laya() {
  echo "## Laya"
  local compose="$ROOT/compose/laya/compose.yml" pinned latest torch_pin
  pinned="$(grep -oE 'LAYA_VERSION:-[0-9.]+' "$compose" | head -1 | cut -d- -f2 | sed 's/^://')"
  torch_pin="$(grep -oE 'LAYA_TORCH_VERSION:-[0-9.]+' "$compose" | head -1 | sed 's/.*:-//')"
  latest="$(curl -fsS -m 10 https://pypi.org/pypi/laya/json 2>/dev/null | jq -r '.info.version' 2>/dev/null | tr -d '\r' || true)"
  echo "Pinned laya: ${pinned:-?}   PyPI latest: ${latest:-unreachable}   torch pin: ${torch_pin:-?}"
  if [[ -n "$latest" && -n "$pinned" && "$latest" != "$pinned" ]]; then
    if [[ "$(printf '%s\n%s\n' "$pinned" "$latest" | sort -V | tail -1)" == "$latest" ]]; then
      echo "UPDATE AVAILABLE: $pinned -> $latest. Check the release notes for breaking changes, then run: LAYA_VERSION=$latest make laya-up"
    fi
  else
    echo "laya is current."
  fi
  local state
  state="$(docker compose -f "$ROOT/compose/laya/compose.yml" ps --format '{{.State}} {{.Health}}' laya 2>/dev/null | tr -d '\r' | head -1 || true)"
  echo "Container: ${state:-not created}"
  if [[ "$state" == running* ]]; then
    echo "Laya is running and holds about 2 GB of VRAM. Stop it with: make laya-stop"
  fi
}

# One JSON object per /ticket-rca run found in a transcript.
runs_json() {
  jq -s -c '
    . as $rows
    | [ range(0; $rows|length) | select($rows[.].type=="assistant")
        | select([$rows[.].message.content[]? | select(.type=="tool_use" and .name=="Skill" and (.input.skill=="ticket-rca"))] | length > 0) ] as $starts
    | [ range(0; $starts|length) as $k
        | ($starts[$k]) as $s
        | (if $k+1 < ($starts|length) then $starts[$k+1] else ($rows|length) end) as $e
        | $rows[$s:$e] as $run
        | ($run | [ .[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") ]) as $uses
        | ($uses | map({(.id): .name}) | add // {}) as $names
        | ($run | [ .[] | select(.type=="user") | .message.content[]? | select(type=="object" and .type=="tool_result")
              | { tool: ($names[.tool_use_id] // "unknown"),
                  chars: (if (.content|type)=="string" then (.content|length)
                          else ([.content[]? | select(.type=="text") | .text | length] | add // 0) end) } ]) as $res
        | ($run | [ .[] | select(.type=="assistant") ] | group_by(.message.id) | map(.[-1].message.usage)) as $us
        | { date: ($rows[$s].timestamp[0:10]),
            ticket: (($uses | map(select(.name=="Skill")) | .[0].input.args // "") | (capture("issueNumber=(?<n>[0-9]+)").n // capture("^(?<n>[0-9]+)").n // "?")),
            turns: ($us | length),
            out_tokens: ($us | map(.output_tokens // 0) | add // 0),
            new_input: ($us | map(.input_tokens // 0) | add // 0),
            cache_write: ($us | map(.cache_creation_input_tokens // 0) | add // 0),
            cache_read: ($us | map(.cache_read_input_tokens // 0) | add // 0),
            result_chars: ($res | map(.chars) | add // 0),
            by_tool: ($res | group_by(.tool) | map({tool: .[0].tool, calls: length, chars: (map(.chars)|add), max: (map(.chars)|max)})),
            repeats: ($uses | map(select(.name != "Skill") | (.name + (.input|tostring))) | group_by(.) | map(select(length>1)) | length),
            full_messages_calls: ($uses | map(select(.name=="mcp__pylon__get_issue" and (.input.include_messages==true))) | length) } ]
    | .[]' "$1" 2>/dev/null | tr -d '\r'
}

cmd_stats() {
  local days="${1:-30}" dir all
  dir="$(transcript_dir)"; [[ -n "$dir" ]] || { echo "No transcript folder found."; return 0; }
  all="$(mktemp)"
  find "$dir" -maxdepth 1 -name '*.jsonl' -mtime -"$days" | while read -r f; do runs_json "$f"; done > "$all"
  echo "## Ticket-RCA token stats (last $days days)"
  if [[ ! -s "$all" ]]; then echo "No /ticket-rca runs found."; rm -f "$all"; return 0; fi
  jq -s -r '
    sort_by(.date) as $r
    | "Runs: \($r|length)",
      "",
      "| date | ticket | turns | output tok | new input | cache write | cache read | result tok (est) | repeat calls | full-message reads |",
      "|---|---|---|---|---|---|---|---|---|---|",
      ($r[] | "| \(.date) | \(.ticket) | \(.turns) | \(.out_tokens) | \(.new_input) | \(.cache_write) | \(.cache_read) | \((.result_chars/4)|floor) | \(.repeats) | \(.full_messages_calls) |"),
      "",
      "Average per run: output \(($r|map(.out_tokens)|add/length)|floor), cache write \(($r|map(.cache_write)|add/length)|floor), cache read \(($r|map(.cache_read)|add/length)|floor), results (est) \(($r|map(.result_chars)|add/length/4)|floor)",
      "",
      "### Heaviest tools across runs (result size, est. tokens)",
      ( [$r[].by_tool[]] | group_by(.tool) | map({tool: .[0].tool, calls: (map(.calls)|add), tok: ((map(.chars)|add)/4|floor), max_call_tok: ((map(.max)|max)/4|floor)}) | sort_by(-.tok) | .[0:8][]
        | "- \(.tool): \(.calls) calls, ~\(.tok) tokens, largest single call ~\(.max_call_tok)" ),
      "",
      ( ([$r[].by_tool[] | select(.tool|test("search|list_issues")) | .chars] | add // 0) as $s
        | ([$r[].by_tool[].chars] | add // 1) as $t
        | "Search-style tools (Slack/Notion/Pylon/Linear search, gh search) are \((100*$s/$t)|floor)% of result tokens. Laya only helps with this share." ),
      "",
      "### Observations",
      ( [$r[] | select(.repeats>0) | "run \(.ticket): \(.repeats) repeated identical tool call(s)"] +
        [$r[] | select(.full_messages_calls>1) | "run \(.ticket): \(.full_messages_calls) full-message reads of Pylon tickets (skill says only the ticket being worked)"] +
        [$r[] | .ticket as $t | .by_tool[] | select(.max > 20000) | "run \($t): one \(.tool) result was ~\((.max/4)|floor) tokens"] +
        [$r[] | select(.turns > 40) | "run \(.ticket): \(.turns) turns (long run; look for loops or missing early stop)"] ) as $o
      | (if ($o|length)==0 then "none" else ($o[] | "- " + .) end)
  ' "$all" | tr -d '\r'
  rm -f "$all"
}

cmd_due() {
  local stamp="$OUT/.last-run"
  if [[ ! -f "$stamp" ]] || [[ -n "$(find "$stamp" -mtime +7 2>/dev/null)" ]]; then
    echo "DUE"
  fi
}

cmd_all() {
  mkdir -p "$OUT"
  local report="$OUT/$(date +%F).md"
  { echo "# RCA health check $(date +%F)"; echo; cmd_tools 3; echo; cmd_laya; echo; cmd_stats 30; } | tee "$report"
  touch "$OUT/.last-run"
  echo; echo "(saved to data/rca-health/$(basename "$report"))"
}

case "${1:-all}" in
  tools) shift; cmd_tools "${1:-3}" ;;
  laya)  cmd_laya ;;
  stats) shift; cmd_stats "${1:-30}" ;;
  due)   cmd_due ;;
  all)   cmd_all ;;
  *) echo "Usage: rca-health.sh <tools [N]|laya|stats [DAYS]|due|all>" >&2; exit 1 ;;
esac
