---
name: instance-logs
description: Fetch Metabase logs for a customer's hosted Cloud instance from Grafana Loki, using the instance GUID. Use when a ticket needs logs from a hosted instance.
---

# Instance logs (Grafana Loki)

Use the `grafana` MCP tools. You have direct log access. Never ask the user to check logs. Only ask for the instance GUID.

## Steps

1. Look for the GUID in the ticket text, the Pylon custom fields, the account, or the conversation. If you find one, confirm it with the user before you query.
2. If there is none, ask the user for it. Do not query Grafana until you have it. Never guess a namespace.
3. Build the namespace: `hosting-` plus the first 16 hex characters of the GUID, with dashes removed.
   Example: `1e3f0152-27da-453a-adc0-4a0be5b10f95` becomes `hosting-1e3f015227da453a`.
4. Check the stream first with `query_loki_stats` on `{namespace="hosting-<16hex>"}`. This is on the prompt list, so the user approves it once.
5. Query with `query_loki_logs`.

## Query details

- Datasource UID: `FQTzEdlnz` (the only Loki datasource). If it fails, rediscover with `list_datasources`, type `loki`.
- You do not know the cluster. Do not set it. Select by namespace only, then read the `cluster` label off the result.
- Newest 100 lines in the last 6 hours:
  ```
  datasourceUid: FQTzEdlnz
  logql: {namespace="hosting-<16hex>"}
  limit: 100
  startRfc3339: now-6h
  ```
- Errors only: `{namespace="hosting-<16hex>"} |= "ERROR"`
- Match a phrase from the ticket: `{namespace="hosting-<16hex>"} |= "<exact error text>"`
- Hosted Metabase logs are plain lines. The raw line is in `message`.

## Limits and traps

- The server caps `limit` at 100 per call. To page back, set `endRfc3339` to the oldest timestamp you got and query again.
- Do not list values of the `namespace` label. There are thousands of instances and the result is huge. Match the namespace you built instead.
- Use a narrow time window that matches when the customer saw the problem.
- Logs can hold customer data. Quote only the lines you need. Never write log lines to a file in a repo. Replace emails, tokens, and customer names with placeholders.
