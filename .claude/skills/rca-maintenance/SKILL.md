---
name: rca-maintenance
description: Weekly health check for the ticket-RCA setup. Finds new or removed MCP tools (new write tools must be denied), checks whether Laya has an update, and reads token stats from past /ticket-rca runs to suggest optimizations. Use when the user asks to check tool lists, update Laya, review token use, or improve RCA, or when ticket-rca says the check is due.
---

# RCA maintenance

The script does the measuring and uses no model tokens. You interpret its output and propose changes. Do not read transcripts yourself. The script output holds names and sizes only.

## Steps

1. Run `bash scripts/rca-health.sh all`. It prints a report and saves it to `data/rca-health/<date>.md` (gitignored). Read only that output.

2. Tool lists. The report compares the tools the servers offered recently with `.claude/settings.json`.
   - "Look like writes": propose adding each to `permissions.deny`. Never allow a write tool.
   - "Look read-only": ask for each one: allow, keep on prompt (add it to `.claude/skills/rca-maintenance/keep-on-prompt.txt`), or deny. Recommend deny unless a recent ticket needed it.
   - "Allowed tools not seen": remove them from `allow`.
   - Settings are the safety policy. Show the exact edit and wait for approval. Afterward run `jq` to check that the file is valid JSON and that no tool is in both `allow` and `deny`.

3. Laya. If the report says UPDATE AVAILABLE:
   - Read the release notes (PyPI or the project's GitHub releases) and give the breaking changes in two lines.
   - Ask before rebuilding. The rebuild reinstalls PyTorch, which is several GB.
   - After approval: change the `LAYA_VERSION` default in `compose/laya/compose.yml`, run `make laya-up`, then `bash scripts/laya.sh check` and one test request. Update the pin in `.github/agent-laya.md`.
   - If Laya is running and no ticket needs it, suggest `make laya-stop`.

4. Token stats. Use the table and the observations.
   - Compare with the previous report in `data/rca-health/` (average result tokens and output tokens per run).
   - Give the top three optimizations, each with its number. Examples: a heavy tool needs a limit or field list, a repeated call needs a skill rule, a long run needs an earlier stop, full-message reads should be avoided.
   - Propose the concrete edit (skill text, `settings.json`, or CLAUDE.md). Ask before applying.
   - Laya is worth keeping only if search-style tools are a large share of result tokens (the report prints the share). With fewer than five runs, say the sample is small.
   - Cache read tokens are the whole conversation re-read each turn. Fewer turns and a smaller always-loaded context lower it more than trimming one tool result does.
   - A run is counted from the `/ticket-rca` call to the next `/ticket-rca` call or the end of the session. Work done after the ticket in the same session is included, so the numbers are only clean when each ticket has its own session. If cache read is in the millions while result tokens are in the thousands, the cause is a long session, and the fix is one ticket per session.

5. Add a short "Decisions" section to the saved report with what was changed and what was declined. Do not commit anything unless the user asks.

## Output

Ten lines or fewer: tool drift, Laya status, the top three optimizations with numbers, and what you need approved. Plain sentences, no em dash, full URLs only.

## Cadence

The `ticket-rca` skill runs `bash scripts/rca-health.sh due` at the end of each run and says so when the check is more than seven days old. To run the report unattended, schedule `bash scripts/rca-health.sh all` with Windows Task Scheduler or cron. It uses no tokens, and the report lands in `data/rca-health/`. Ask the user before creating a scheduled task.
