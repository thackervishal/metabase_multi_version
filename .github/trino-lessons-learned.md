# Trino + Metabase: lessons learned and best practices

Working notes from building and testing Metabase connection impersonation against Trino locally (see `.github/agent-trino-impersonation.md` for the repo-specific rig this came out of). Unlike that file, this one isn't about our local scaffold — it's general advice for anyone connecting Metabase to Trino, worth sharing with a customer or teammate regardless of whether they use our rig, Ranger, or anything else on the Trino side.

## Connecting Metabase to Trino

- **Password requires TLS, by driver design.** The Trino JDBC driver refuses to send a username *and* password together over a non-TLS connection — you'll get `TLS/SSL is required for authentication with username and password`, even if the Trino server itself has no authenticator configured and never validates the password at all. If your Trino coordinator doesn't terminate TLS, the fix is to **leave the password field blank** and only supply a username. This surprised us — it's a client-side driver rule, not a server response, so it fires regardless of what Trino actually enforces.
- Conversely, turning on Metabase's "secure connection (SSL)" toggle against a coordinator that has no TLS listener at all produces a different, equally-misleading error: `javax.net.ssl.SSLException: Unsupported or unrecognized SSL message`. Metabase's generic troubleshooting panel suggests enabling SSL on most connection failures — that instinct is wrong here. Diagnose which of these two you're hitting before reaching for SSL as the fix.

## The schema browser is not access control

Metabase's table/schema browser reflects **its own cached sync metadata** — gathered once by the base/sync connection account — not a live, per-viewer query against Trino's access control. It will show every table it knows about, including ones the current (possibly impersonated) user has no access to. **Enforcement happens at query execution time**, not at browse time: clicking into a disallowed table returns data-fetch time, not a filtered list. Don't expect, or promise a customer, that the browse list itself narrows per impersonated identity — it doesn't, in either the query builder or the native SQL editor's autocomplete.

## Writing `rules.json` (Trino's file-based access control)

- **Each top-level key is an independent rulebook** answering one specific question — `catalogs` ("can this user touch this catalog at all"), `impersonation` ("can user A become user B"), `tables` ("what can this session user do to this table"), etc. Nothing in one list affects another.
- **Defaults are asymmetric and easy to get backwards.** Omit `catalogs` or `tables` entirely and access defaults to *allowed*. Omit `impersonation` entirely and it defaults to *denied*. Forgetting this is the single most likely reason an impersonation attempt silently fails with no obvious cause.
- **First matching rule wins, per section, top to bottom.** In a `tables` list, put user-specific restrictions *before* any catch-all rule, and end with a catch-all that preserves full access for whatever account Metabase uses for sync/fingerprinting — that account is never the impersonated identity, and losing its access silently breaks schema sync rather than failing loudly.
- **Scope that final catch-all to the sync account by name — don't leave it as an unscoped "everyone else gets full access."** We initially wrote the catch-all with no `user` field (matching `.*`), intending it only to preserve the sync account's access. Then we renamed the impersonation targets (retiring one identity, adding two others) without updating this rule, and the retired identity — no longer matched by anything more specific — fell through into that unscoped catch-all and silently **gained full, unrestricted access** instead of losing access. An unscoped catch-all fails *open* for any identity you forget to account for; a catch-all scoped to `"user": "<sync-account-name>"`, followed by a final true deny-all (`{"privileges": []}`), fails *closed* instead. Given how often impersonation targets get added/renamed/removed over a project's life, the closed version is the only safe default.
- **Column mask expressions must match the column's exact declared type, including length.** `concat()`/`substr()` return unbounded `varchar`; a column declared `varchar(255)` will reject that with `Expected column mask ... to be of type varchar(255), but was varchar`. Wrap the mask expression in an explicit `CAST(... AS varchar(255))`.
- **Don't trust a remembered schema for this file — check the docs for your exact Trino version.** The field names and behavior here have shifted across Trino releases (e.g. the deprecated `principals` rules vs. the current `impersonation` rules). Pull the actual doc page for the pinned version before writing rules from memory.
- **Verify real column/schema names against live metadata before writing rules**, don't guess from convention. We wrote `birthdate` from memory when the actual column was `birth_date` — the rule would have silently done nothing, not errored, since an unmatched column name just means no restriction applies rather than a validation failure.
- **`new_user` in an `impersonation` rule is a regex, not a single value — you don't need one rule per impersonated person.** `{"original_user": "trino_super", "new_user": "leo|mikey"}` already covers both; adding a third person just extends the alternation (`leo|mikey|jane`), not a new rule entry. This opens a real design choice worth making deliberately rather than drifting into by accretion:
  - **Explicit allowlist** (keep extending the regex as people are added) — more maintenance, but if the service account's credentials ever leak, the blast radius is limited to names already on the list.
  - **Wildcard** (`"new_user": ".*"`) — zero maintenance as the user base grows, and arguably the more accurate model when one service account (like `trino_super`) is the sole thing Metabase ever authenticates as: the actual gatekeeping already happens on Metabase's side (who's in a group with View data = Impersonation, and what attribute value they carry), not in this file. The tradeoff is that a leaked service-account credential can now impersonate anyone, not just a pre-approved few.
  
  Neither is "more correct" — it's a real security-vs-maintenance tradeoff a team has to choose deliberately, and it's the same choice Ranger's own impersonation policies face for the identical reason.

## `SELECT *` and hidden columns

This is the one worth leading with in a customer conversation, because it reads like a bug and isn't:

- **A fully hidden column (`"allow": false`) breaks `SELECT *` outright** for that table, for everyone subject to that rule — not just omits the column, the *entire query* fails with `Access Denied: Cannot select from table ...`. This is because Trino's SQL analyzer expands `*` into every column *before* checking authorization, and if any one of those columns is denied, the whole check fails.
- **A masked column does not have this problem.** `SELECT *` against a table with a `mask` (but no `allow: false` columns) works fine and returns the masked value in place of the real one.
- **This is core Trino analyzer behavior, not a Metabase quirk and not specific to file-based vs. Ranger access control.** Star-expansion happens before the pluggable `SystemAccessControl` is even consulted, so Ranger's Trino plugin would exhibit identical behavior. If a customer's end users report broken/confusing failures that they attribute to "impersonation not working," this exact interaction is worth checking first — it usually presents as a hard, opaque failure on an otherwise-reasonable query.
- **Practical mitigations, in order of preference:**
  1. Prefer masking over fully hiding a column wherever the use case allows it (e.g. mask a birthdate down to just the year, rather than removing it) — keeps `SELECT *` usable.
  2. If a column must be fully hidden, restrict that group's "Create queries" permission to **query builder only** — Metabase's query builder never emits `SELECT *` (it always compiles an explicit column list from synced metadata), so this failure mode never reaches those users.
  3. Otherwise, it's real end-user education: native SQL users must select explicit columns, not `*`, on any table with a hidden column.

### Broken vs. working, concretely

Same table rule, same intent (don't let `sales` see real `birth_date` values) — only the column rule differs:

**Broken — `SELECT * FROM people` fails outright for `sales`, on every query, not just ones touching `birth_date`:**
```json
{
  "user": "sales",
  "schema": "public",
  "table": "people",
  "privileges": ["SELECT"],
  "columns": [
    { "name": "birth_date", "allow": false }
  ]
}
```

```text
Query failed: Access Denied: Cannot select from table postgresql.public.people
```

**Working — `SELECT *` succeeds, `birth_date` comes back `NULL` instead of a real value:**
```json
{
  "user": "sales",
  "schema": "public",
  "table": "people",
  "privileges": ["SELECT"],
  "columns": [
    { "name": "birth_date", "mask": "CAST(NULL AS date)" }
  ]
}
```

```text
id | ... | birth_date | ...
117| ... | null       | ...
```

The only difference is `"allow": false` vs. `"mask": "CAST(NULL AS date)"` — swapping a hard deny for a mask that redacts to `NULL` gets the same practical outcome (real value never visible) without breaking `SELECT *`. Note the mask still has to satisfy the type-matching rule above — `CAST(NULL AS date)` matches `birth_date`'s actual column type.
