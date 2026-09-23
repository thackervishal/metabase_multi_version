# Agent reference: driving Metabot chat directly (no browser)

Read this only when you need to exercise Metabot's actual chat/tool-calling path against a stack — e.g. reproducing a Metabot bug where the question is "what did the LLM's tool actually receive," not just "what does the REST API return." Not needed for routine repo work — `CLAUDE.md` covers everything needed day-to-day.

## Enabling Metabot on an existing stack

Flip `ENABLE_METABOT=true` in the stack's `env/mb_versions/*.env` file, then re-run `make start MB_VERSION=<v> DATASET=<d>` — this recreates just the `metabase` container (not destructive, no data loss) with `compose/metabot-overlay.yml` applied. Requires a real, non-placeholder `MB_LLM_ANTHROPIC_API_KEY` (or other provider key) in `env/common.env`; if it's a placeholder, Metabot will be enabled but every chat call will fail at the LLM proxy step. **A live chat turn makes a real, billed call to that provider** — confirm with the user before triggering one, the same as any other action with a real external cost.

## Calling `agent-streaming` directly with curl

The endpoint is `POST /api/metabot/agent-streaming` — **not** `/api/ee/metabot/...`. Metabot's route is registered without the `/ee` prefix despite living in the EE codebase; check `resources/openapi/openapi.json` for the real mounted path rather than inferring it from `enterprise/backend/src/metabase_enterprise/api_routes/routes.clj`'s `ee-routes-map` key names.

Auth: the same `x-api-key: $MB_AUTOMATION_API_KEY` header used everywhere else in this repo works fine here — no session cookie needed.

**The malli schema for the request body can differ between the deployed image tag and whatever's checked out in your local `metabase` source tree.** On `v1.63.16.1`, the endpoint 400'd until the body included `"state": {}` and `"history": []`, neither of which appeared in the version of `src/metabase/metabot/api.clj` in a `main`-tracking local checkout at the time. Don't trust a local source read alone for the exact request shape against an older deployed tag — send a minimal body first and let the live server's own 400 `specific-errors` tell you what's actually missing; add keys one at a time.

Minimal working body against `v1.63.16.1`:

```json
{
  "message": "What filters does the dashboard I'm currently viewing have?",
  "context": {
    "user_is_viewing": [{ "type": "dashboard", "id": 10, "name": "sample_dwh_pg15 Overview" }]
  },
  "conversation_id": "<a fresh UUID>",
  "state": {},
  "history": []
}
```

`context.user_is_viewing[].type` is one of `dashboard`, `document`, `code_editor`, `adhoc`, `question`, `metric`, `model` (`metabase.metabot.context/item-types`). `conversation_id` must be a UUID string not previously used.

```bash
CONV_ID=$(python3 -c "import uuid; print(uuid.uuid4())")   # fine for pure computation with no file paths involved
curl -s -N -X POST "http://127.0.0.1:$PORT/api/metabot/agent-streaming" \
  -H "x-api-key: $MB_AUTOMATION_API_KEY" -H "Content-Type: application/json" \
  --data @request.json -o response.sse -w "%{http_code}\n"
```

The response is a **Vercel-AI-SDK-style SSE stream**, not one JSON object — use `curl -N` (no buffering) and read the saved file, don't try to `jq` it directly. Useful line prefixes:

- `9:{"toolCallId":...,"toolName":"...","args":"..."}` — a tool call the agent made, with its exact arguments.
- `a:{"toolCallId":...,"result":"..."}` — that tool's raw result, i.e. **exactly what the LLM saw**. This is the ground truth for "does the tool return field X" — far more reliable than reading the final NL answer, which can hallucinate around a gap in the tool data (confirmed live: asked whether a dashboard had filters, got a confident "no filters configured" answer when the tool's `read_resource` result for `metabase://dashboard/<id>` carried no `parameters` at all, even though the dashboard genuinely had one).
- `0:"..."` — streamed text deltas of the final answer, concatenate to get the full reply.
- `d:{"finishReason":...}` — end of stream.

## Wiring a dashboard filter via the `mb` CLI (for building a test fixture)

To reproduce anything filter-related you generally need a dashboard with a real filter wired to a real card/field. Two calls, no UI needed:

```bash
mb dashboard update <dashboard-id> --profile <profile> \
  --body '{"parameters":[{"id":"<8-hex-chars>","name":"Created At","slug":"created_at","type":"date/all-options","sectionId":"date"}]}'

mb dashboard update-dashcard <dashboard-id> <dashcard-id> --profile <profile> \
  --body '{"parameter_mappings":[{"parameter_id":"<same-id>","card_id":<card-id>,"target":["dimension",["field",<field-id>,null]]}]}'
```

`dashboard update` with only a `parameters` key is a partial patch — it does not clobber existing `dashcards`. Get `<field-id>` from `GET /api/card/<card-id>`'s `result_metadata[].id` (or `field_ref`) for the column you want the filter to target. Get `<dashcard-id>` from `mb dashboard cards <dashboard-id> --json`.

## Reproducing a specific LLM response deterministically, via a local stand-in provider

For a bug that depends on *what the model's response contains* (e.g. a tool call for a name outside the current profile's tool set) rather than on a normal, working completion, don't rely on a real provider call — it's non-deterministic and, for a hallucination-shaped bug, may not reproduce on demand at all. Instead, point Metabase's outbound Anthropic calls at a small local HTTP server you control that always answers with a scripted SSE response:

- `llm-anthropic-api-base-url` (setting `MB_LLM_ANTHROPIC_API_BASE_URL`) is the override point — confirm it applied via `GET /api/setting` and check that entry's `is_env_setting` is `true`, not just that the var is set on the host. **`compose/metabot-overlay.yml` only forwards an explicit allow-list of `MB_LLM_*` vars into the container** — a var missing from that list is silently never seen by Metabase no matter what's in the env file. See the `ENABLE_METABOT` bullet in `CLAUDE.md` for the current list.
- Point it at `http://host.docker.internal:<port>` (not `127.0.0.1`/`localhost`) — the container needs to reach a server running on the host.
- The stand-in server doesn't need to be smart: reply to every `POST /v1/messages` with the same canned Anthropic-shaped SSE stream (`message_start` → `content_block_start` for a `tool_use` block → `content_block_delta` `input_json_delta` chunks → `content_block_stop` → `message_delta` with `stop_reason: "tool_use"` → `message_stop`), regardless of what request body it receives. It also doesn't need to validate the `x-api-key` header, which conveniently sidesteps needing a working real key at all.
- This kind of server won't enforce Anthropic's own tool_use/tool_result pairing rule the way the real API does, so a bug whose customer-visible symptom is "the *next* real Anthropic call 400s" won't reproduce that symptom against this stand-in — it'll just keep answering instead of rejecting. That's fine: it isolates and proves the Metabase-side half of the bug (what happens to an unanswered tool call) independently of the provider-side half (what a strict provider does when it later sees the broken history), which is usually the half that's actually in question.
- Trigger a turn with `profile_id` set directly in the request body (see the minimal working body above) to land on the exact profile/tool-set you're testing, rather than trying to reconstruct a `context.user_is_viewing` shape that would route there implicitly.
- `GET /api/bug-reporting/details` (auth: same `x-api-key`) returns the same JSON the Admin > Troubleshooting > Help page shows, useful for pasting a stack's version/system info into a bug report without opening the UI.
