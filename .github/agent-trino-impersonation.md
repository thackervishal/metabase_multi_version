# Agent reference: Trino + Metabase connection impersonation (v1, no Ranger yet)

Read this only when working on `ENABLE_TRINO` or walking through the impersonation exercise yourself. Not needed for routine repo work — `CLAUDE.md` covers everything needed day-to-day.

For general Trino/Metabase advice that isn't specific to this repo's rig (connection gotchas, `rules.json` authoring pitfalls, the `SELECT *` + hidden-column trap) — worth sharing with a customer or teammate regardless of setup — see `.github/trino-lessons-learned.md`.

## Background: what Trino and Ranger actually are

**Trino** is a distributed SQL query *engine*, not a database — it stores nothing itself. A coordinator + worker cluster takes in SQL, and executes it against one or more real backends via "connectors" (each backend configured as a **catalog** — e.g. a `postgresql` catalog, an `iceberg` catalog). This is exactly the "SQL engine that queries multiple databases and can combine the results" mental model — Trino calls that federation, and it's the main reason people adopt it: one SQL surface over Postgres, Iceberg/S3, Kafka, etc., instead of one per system. Trino also draws a distinction that matters a lot here: the **authenticated principal** (who actually opened the connection) versus the **session user** (the identity the query is attributed to and authorized against). Normally these match, but Trino explicitly supports **user impersonation** — a trusted principal can open one connection and then run queries *as* someone else, subject to an authorization check.

**Apache Ranger** is a centralized authorization and audit *plane* for the Hadoop-adjacent ecosystem (Trino, Hive, HDFS, Kafka, ...) — also correct as remembered. It's not a database and it doesn't execute anything; a **Ranger Admin** service holds policies (per catalog/schema/table/column grants, row-filters, column masks, tag-based rules), a **plugin** embedded inside each service (e.g. Trino) intercepts every request and asks "is this allowed?", and everything gets audit-logged centrally. The Trino plugin implements Trino's `SystemAccessControl` SPI — which includes that same impersonation check above.

### Why pair them, and where Metabase fits

The appeal for a customer: point many BI/analytics tools at Trino, and let Ranger be the single place that defines "who can see what" — instead of replicating row-level security separately inside every source database. Metabase's job in that picture is narrow: connect to Trino as one service account, and when a person with **connection impersonation** configured runs a query, tell Trino "run this as *them*" via `setSessionUser` before executing it. Trino asks its access-control layer (Ranger, in production) whether that impersonation is allowed, and if so, every subsequent table/row/column check for that query is evaluated as *that* person — all without Metabase implementing any row/column security itself. That's the whole value proposition, and also exactly the plumbing this local rig exists to exercise (see below), just with Trino's own built-in access control standing in for Ranger.

## Why this exists

A customer runs Metabase connection impersonation against Apache Ranger + Trino, and wants to validate that flow with us. Ranger's Trino plugin is the fiddly, version-sensitive part to stand up from scratch; Metabase's own impersonation mechanics (`setSessionUser` on the Trino JDBC connection — see `modules/drivers/starburst/src/metabase/driver/starburst.clj` in the `metabase` repo, around line 1039) don't care whether the check on the other end is enforced by Ranger or by Trino's own built-in file-based access control. So v1 proves out the Metabase-side mechanics against Trino's built-in provider, with no Ranger involved at all. Ranger can be layered on later as a separate step, without touching anything on the Metabase side.

## What's already built for you (infra)

- `compose/trino-overlay.yml` — a `trino` service (official `trinodb/trino` image), added to a stack when `ENABLE_TRINO=true`.
- `scripts/common.sh`'s `ensure_trino_config()` (called from `scripts/start.sh`) — regenerates `data/trino-config/<stack>/catalog/postgresql.properties` on every start (a Trino catalog pointing at that same stack's `sample-dwh` Postgres container — host `sample-dwh`, port `5432`, using the dataset's own `SAMPLE_DB_*` credentials), and seeds (once, never overwrites) `data/trino-config/<stack>/access-control/rules.json` from `seed/trino/access-control/rules.example.json`.
- `seed/trino/etc/access-control.properties` — fixed, tracked, not meant to be edited. Turns on Trino's file-based access control (`access-control.name=file`) pointed at that `rules.json`, with `security.refresh-period=5s` — **edit `rules.json` and Trino picks it up within ~5 seconds, no container restart needed.**
- Currently wired up for the **sample-pg15 dataset only** — the generated catalog assumes Postgres is at `sample-dwh:5432`.
- `data/trino-config/` is gitignored (under the repo's blanket `data/` rule) and removed by `make nuke`, same as `data/remote-sync/`.

None of this touches Metabase's own config — no database connection, no permission group, no user attribute gets created automatically. That part is deliberately left for you.

## What you configure yourself

### 1. Add the Trino connection in Metabase

Admin > Databases > Add a database > **Starburst (Trino)**. Inside the Docker network the host is the service name, not `localhost`:

- Host: `trino`
- Port: `8080` (Trino's internal port — not the host-mapped `TRINO_PORT`)
- Catalog: `postgresql`
- **Username: type anything non-empty** (e.g. `a`) — Trino requires *some* username to attribute the query to, and has no authenticator configured in this v1 setup, so it trusts whatever string is sent as-is. That string becomes both the authenticated principal *and* the initial session user.
- **Password: leave completely blank.** This is the counterintuitive part — the Trino JDBC driver has a client-side rule that if *both* username and password are set, it refuses to send them without TLS, even though our Trino server never validates the password at all (no authenticator configured). Filling in a password gets you `TLS/SSL is required for authentication with username and password` even with SSL off; leaving it blank sidesteps that check entirely.
- **Leave "Use a secure connection (SSL)" OFF.** The Trino container only serves plain HTTP on 8080 — no TLS listener at all in this v1 setup. Turning SSL on (with a password set) instead gets you `javax.net.ssl.SSLException: Unsupported or unrecognized SSL message` (a TLS client talking to a non-TLS port). Metabase's generic troubleshooting panel suggests enabling SSL on any connection failure — that's a red herring for this setup; the real fix for both errors is username-only, no password, no SSL.

Confirm you can browse/query the sample tables (e.g. `orders`, `people`, `products`) through Trino before touching impersonation at all.

### 2. Set up Metabase's impersonation permission

Follow `docs/permissions/impersonation.md` in the `metabase` repo exactly as written for any other database — group, user attribute, "View data = Impersonation" on this Trino connection. The user attribute's value should be the Trino username you want Metabase to switch to per-person.

### 3. Grant that impersonation in Trino's rules.json

`data/trino-config/<stack>/access-control/rules.json` starts as a bare allow-everything file so Trino boots cleanly:

```json
{
  "catalogs": [
    { "allow": "all" }
  ]
}
```

You need to add an `impersonation` rule authorizing the user string your Metabase connection sends (from step 1) to impersonate the target session user (from step 2's attribute value) — this is the exact same authorization check Ranger's Trino plugin would otherwise answer. **Look up the current schema in Trino's own docs for the pinned version** (this stack runs `trinodb/trino:483` — check `https://trino.io/docs/current/security/file-system-access-control.html`, "Impersonation rules" section) rather than trusting a remembered shape here — this file's exact keys have shifted across Trino releases, and it's worth reading the source of truth once anyway.

Once added, save the file — Trino re-reads it within 5 seconds — and re-run a query as the impersonated Metabase user to confirm the session-user switch is actually permitted.

### 4. (Optional) Prove row/column-level restriction

Add `schemas`/`tables` rules (same docs page) keyed by username so two different impersonated identities see different data — this is what actually demonstrates the "governance lives centrally, Metabase just asks to be someone" story to the customer, beyond just proving the plumbing connects.

### 5. Layer on Ranger later

When ready: swap `access-control.name=file` (and the `security.config-file`/`security.refresh-period` lines) in `seed/trino/etc/access-control.properties` for Ranger's Trino plugin config, and re-express whatever rules you built in step 3/4 as Ranger policies via Ranger Admin. Nothing on the Metabase side changes — same database connection, same group, same user attribute, same `setSessionUser` call underneath.

## What to expect when testing

Log in as the actual impersonated user (not an admin — admins bypass impersonation entirely) in a separate browser/incognito window.

**The table browser will show every table, including ones the impersonated user has no access to.** This is expected, not a bug: Metabase's schema browser reflects its own cached metadata, populated once by the base sync account — it does not re-check Trino's access control per viewer before rendering the list. Enforcement only happens at **query execution time**: clicking into an allowed table returns data, clicking into a disallowed one returns a Trino `Access Denied: Cannot select from table ...` error surfaced through Metabase's generic query-error UI. Same in the SQL editor — the query runs and Trino denies it at execution, not before. Don't expect (or promise a customer) that the browse list itself gets filtered per impersonated identity.

## Troubleshooting

- `docker logs <project>-trino` for Trino's own startup/query errors.
- `wait_for_trino` in `scripts/common.sh` polls `http://127.0.0.1:${TRINO_PORT}/v1/info` for `"starting": false` — if `make start` hangs there, Trino itself is the thing not coming up (check the catalog file it generated, or a `rules.json` syntax error — file-based access control fails closed/hard on invalid JSON).
- A `setSessionUser` denial surfaces to Metabase as a JDBC exception from the impersonated query, not a clean Metabase-side permission error — expect to read the raw driver error the first few times.
- `javax.net.ssl.SSLException: Unsupported or unrecognized SSL message` when adding the connection means the "Use a secure connection (SSL)" toggle got turned on — turn it back off, this v1 Trino container has no TLS listener.
## Troubleshooting

- `docker logs <project>-trino` for Trino's own startup/query errors.
- `wait_for_trino` in `scripts/common.sh` polls `http://127.0.0.1:${TRINO_PORT}/v1/info` for `"starting": false` — if `make start` hangs there, Trino itself is the thing not coming up (check the catalog file it generated, or a `rules.json` syntax error — file-based access control fails closed/hard on invalid JSON).
- A `setSessionUser` denial surfaces to Metabase as a JDBC exception from the impersonated query, not a clean Metabase-side permission error — expect to read the raw driver error the first few times.
- `javax.net.ssl.SSLException: Unsupported or unrecognized SSL message` when adding the connection means the "Use a secure connection (SSL)" toggle got turned on — turn it back off, this v1 Trino container has no TLS listener.
