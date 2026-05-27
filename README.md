# Metabase Local Stack

Spin up isolated, fully-seeded Metabase stacks for different versions — each with its own app_db, sample data warehouse, users, and starter content — independently, without touching each other's data. Not a migration or upgrade tool.

> **Under active development.** Structure may change. Fork before making significant local modifications.



## Before First Start

**Requirements:** Docker Desktop (Windows/macOS) or Docker Engine + Compose plugin (Linux), Git Bash (Windows), curl, jq, a Metabase Pro/Enterprise token, an Anthropic API key.

> On Windows: `jq.exe` may need `JQ_BIN=/c/path/to/jq.exe` in `env/common.env` if it is not on PATH inside Git Bash.

**Setup:**

1. Copy `env/common.env.example` → `env/common.env`.
2. Edit `env/common.env`.
   - Set `MB_PREMIUM_EMBEDDING_TOKEN` — required for config-file bootstrap.
   - Set `MB_LLM_ANTHROPIC_API_KEY` — required for Metabot.
3. Adjust credentials or ports if needed.

`env/common.env` is gitignored — each user maintains their own copy.

---

## TL;DR
```sh
make new
```

That's it. It'll ask you a few questions, set everything up, and offer to start the stack right away. One command, then you're in. Read the rest when you feel like it.

---

## Setting Up Your Local Stacks

Before running any make command, create a stack env file for each Metabase version you want to run. These are personal and gitignored.

> **Tip:** `make new` walks you through this interactively and optionally starts the stack when done.

To set one up manually:

1. Copy `env/mb_versions/template.env.example` → `env/mb_versions/<version>.env` (e.g. `1.61.1.x.env`).
2. Fill in `MB_IMAGE_TAG`, `METABASE_PORT`, `APP_DB_PORT`, `SAMPLE_DB_PORT` — values must not conflict with other local services.

**Naming:** `1.61.1.x.env` floats on the latest patch (auto-pulled on start). `1.61.1.3.env` pins to a specific build.

---

## Make Commands

Once your stack env files are in place, run `make start`, `make stop`, or `make nuke` with no arguments for an interactive picker — reads your local env files, shows which stacks exist, which are running, and lets you choose which one to start.

| Command | What it does |
| --- | --- |
| `make start` | Interactive — pick a stack to start |
| `make stop` | Interactive — pick a running stack to stop |
| `make nuke` | Interactive — pick a stack to destroy |
| `make list` | Show all configured stacks with ports and running status |
| `make new` | Create a new version env file — drill down major → minor → hotfix or float, suggests ports, optionally starts |
| `make remove` | Remove a stack entirely — nukes runtime state then deletes the version env file |
| `make services-up` | Start shared services (Mailpit + webhook tester) manually |
| `make services-down` | Stop shared services |

**Prefer typing the command directly?**

```bash
# Single stack lifecycle:
make start MB_VERSION=1.61.1.x DATASET=sample-pg15
make stop  MB_VERSION=1.61.1.x DATASET=sample-pg15
make nuke  MB_VERSION=1.61.1.x DATASET=sample-pg15

# Multiple stacks simultaneously
# (each binds to its own port set defined in its env/mb_versions/<version>.env file)
make start MB_VERSION=1.59.4.x DATASET=sample-pg15   # → localhost:3000
make start MB_VERSION=1.60.0.x DATASET=sample-pg15   # → localhost:3200 
make start MB_VERSION=1.61.1.x DATASET=sample-pg15   # → localhost:3300 
```

> **Tips for direct commands:** Use `Ctrl+R` in bash/zsh to reverse-search history and re-run a previous command instantly. Or set `export MB_VERSION=1.61.1.x` and `export DATASET=sample-pg15` in `~/.bashrc` so `make start` picks them up with no arguments.

---

## Firefox Multi-Account Containers

Each `make start` automatically creates a named Firefox container for the stack (e.g. `mb-1.61.2.x-sample-pg15-3310-admin`). This keeps each Metabase version in its own isolated browser session — separate cookies, localStorage, and login state, no bleed between tabs.

**How to use it:** After `make start`, open Firefox, right-click any link or new-tab button, and choose **Open in Container → `mb-<version>-<dataset>-<port>-admin`**, then navigate to `localhost:<port>`. With the [Multi-Account Containers](https://addons.mozilla.org/en-US/firefox/addon/multi-account-containers/) extension you can also assign URLs to containers so they open automatically.

**Key behaviours to know:**

- **Firefox is never stopped.** The container is written directly to `containers.json` in your Firefox profile. If Firefox is already running when you start a new stack for the first time, **restart Firefox** to make the new container appear — it will not show up in a live session.
- **Live-session conflict (rare).** If you create or edit containers inside a running Firefox session *and* a new stack is started at the same time, Firefox may overwrite `containers.json` with its in-memory state on exit, losing the entry that was just written. If a container goes missing, re-run `make start` to recreate it (it's a no-op if the stack is already up).
- **No Firefox? No problem.** If Firefox is not installed the feature is silently skipped and a tip is printed. Everything else works normally.
- **No extension? Still works.** Containers are a built-in Firefox feature; the extension just adds UI shortcuts. Without it you can still open tabs in a specific container via the right-click tab menu.

---

## Sample Data Warehouse

H2 is disabled. Each stack connects to a dedicated Postgres container (`metabase/qa-databases:postgres-sample-15`), registered in Metabase as `sample_dwh_pg15` — enabling real Postgres features: SQL, field filters, JSON operators, and more.

---

## Seeded Content

On first start (or when the seed version advances), the seed step creates:

- **Users:** admin, analyst, sales
- **Groups:** Analytics Team, Sales Team
- **Collection:** starter collection for the sample DWH
- **Questions:** GUI (orders by month, customers by state, products by category, JSON unfolding), SQL (monthly revenue, top categories by revenue), native SQL with a field filter on `People.State`
- **Dashboard:** overview pre-loaded with the starter questions
- **Sample DWH data:** `person_profiles_json` table seeded before Metabase starts

Subsequent `make start` runs pick up only new content — existing items are untouched. Tracked via `.state/<stack>.metabase-seeded`.

---

## Shared Services (Email + Webhooks)

Each stack has two optional feature flags in its version env file (`env/mb_versions/<version>.env`):

```env
ENABLE_EMAIL=true    # starts Mailpit — catches all outbound email
ENABLE_WEBHOOKS=true # starts webhook-tester — receives webhook alerts
```

`make new` prompts for both when creating a new stack. To enable them on an existing stack, edit the env file directly and run `make start` again.

When either flag is `true`, `make start` automatically starts the shared services container (one instance shared across all stacks — Mailpit on port `8025`, webhook-tester on port `9000`).

### Webhooks

**How it works:**

When `ENABLE_WEBHOOKS=true`, `make start` auto-creates a webhook channel in Metabase pointing to the local webhook-tester container. The channel is ready immediately — no manual setup needed. At the end of `make start`, the monitoring URL is printed:

```text
Webhook tester:   http://localhost:9000/s/<session-id>
```

The session ID is stable across restarts for the same stack — bookmark it.

**Testing webhooks:**

1. **Quick test:** Go to **Admin → Notifications → Webhook channels** → click **Send a test** on the auto-created channel. The payload appears in the webhook tester immediately.

2. **Alert-based test:** Open any question → click the **bell icon** → **New alert** → set the condition to "Every time" or "When results change" → under **Where to send it**, select the webhook channel → **Save**. Trigger it by clicking **Send now** on the alert. The payload appears in the webhook tester.

**Adding more webhook channels — use the API, not the UI:**

There is a known Metabase bug ([GIT-10174](https://linear.app/metabase/issue/GIT-10174/webhook-destination-cannot-be-saved-from-the-ui)) where the webhook URL field rejects bare hostnames (e.g. `webhook-tester:8080`) with a validation error, even though the backend accepts them fine. This affects all Docker-internal URLs.

The auto-created channel is set up via the API in `scripts/start.sh`, bypassing the UI entirely. If you need to add more channels, do the same:

```bash
SESSION_ID=$(uuidgen)   # pick once, reuse forever
curl -X POST "http://localhost:${METABASE_PORT}/api/channel" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${MB_AUTOMATION_API_KEY}" \
  -d "{
    \"name\": \"My Webhook\",
    \"type\": \"channel/http\",
    \"details\": {
      \"url\": \"http://webhook-tester:8080/${SESSION_ID}\",
      \"auth-method\": \"none\",
      \"fe-form-type\": \"none\"
    }
  }"
```

Then watch it at `http://localhost:9000/s/${SESSION_ID}`.

**Session ID notes:**

- Generate any UUID once (`uuidgen`, an online generator, etc.) and reuse it — the webhook-tester auto-creates the session on the first incoming POST.
- The UUID is stable across Metabase and stack restarts (it's stored in Metabase's app_db as part of the channel).
- If the webhook-tester container itself restarts (`make services-down` / `make services-up`), past payloads are lost but the session recreates automatically the next time Metabase fires a webhook to that URL.

`MB_AUTOMATION_API_KEY` and `METABASE_PORT` are in `env/common.env` and your stack's version env file respectively. See `scripts/start.sh` for the full working example.

### Email

When `ENABLE_EMAIL=true`, all email sent by Metabase (alerts, invites, password resets) is captured by [Mailpit](http://localhost:8025) — nothing reaches real addresses.

---

## What Is and Isn't Git-Ignored

| Path | Status | Why |
| --- | --- | --- |
| `env/common.env` | git-ignored | Per-user secrets and tokens |
| `env/mb_versions/*.env` | git-ignored | Per-user: stack choice and ports vary per machine |
| `env/mb_versions/template.env.example` | committed | Reference template |
| `env/dwh_source/*.env` | committed | Canonical dataset definitions, no port assignments |

---

## Default Credentials

Shared across all stacks unless overridden in `env/common.env`.

- Admin: `admin@example.com` / `metabot1`
- Analyst: `analyst@example.com` / `metabot1`
- Sales: `sales@example.com` / `metabot1`

Ports are defined per-developer in `env/mb_versions/<version>.env` — see `env/mb_versions/template.env.example`.

- **app_db**
  - host: `localhost`
  - db: `metabaseappdb`
  - user: `metabase`
  - password: `metabase_app_password`
- **Sample DWH**
  - host: `localhost`
  - db: `sample`
  - user: `metabase`
  - password: `metasample123`

---

## Built-In Local Defaults

Unless overridden in `env/common.env`:

- Site name: `Metabase <version> Local Stack` · Application name: `<version> Metabase` (easy to see in browser tab title!)
- H2 sample database: disabled · Check for updates: disabled · Usage analytics PII retention: enabled
- Embedding: interactive, modular, SDK, static — all enabled (local-only secret/validation keys)
- Caching: persisted models enabled, cache size `10240` KB, TTL `3600` s, default and DWH policies `1 hour`
- Transforms, AI features, Metabot: enabled — default provider `anthropic/claude-sonnet-4-6`

---

## Technical Weeds

### Automation API Key

`MB_AUTOMATION_API_KEY` in `env/common.env` is injected into the container. `seed/metabase/config.yml` tells Metabase to create an API key with that exact value at bootstrap, so the seed script can call the API immediately — no manual key creation needed. If you rotate it, rebuild from a clean app_db.

### Files and Scripts

| Path | Purpose |
| --- | --- |
| `env/common.env` | Local secrets and shared settings (gitignored) |
| `env/mb_versions/<version>.env` | Image tag and port bindings for one stack (gitignored, personal) |
| `env/dwh_source/<dataset>.env` | DWH image and dataset-specific settings |
| `compose/datasets/<dataset>.yml` | Compose overlay wiring up the `sample-dwh` service |
| `seed/metabase/config.yml` | Bootstrap: users, API key, database connection |
| `seed/sample-dwh/person_profiles_json.sql` | JSON sidecar table for the sample DWH |
| `scripts/common.sh` | Shared runtime: env loading, stack naming, path normalization, image refresh, health waiting |
| `scripts/list-stacks.sh` | Show all configured stacks with ports and running status |
| `scripts/pick.sh` | Interactive picker: reads env files, detects running stacks, hands off to start/stop/nuke |
| `scripts/new-stack.sh` | Create a new version env file: queries Docker Hub, suggests ports, optionally starts |
| `scripts/remove-stack.sh` | Remove a stack: nukes runtime state for all dataset combos, deletes the version env file |
| `scripts/start.sh` | Pull image if newer, create volumes, start services, seed |
| `scripts/stop.sh` | Stop containers, leave volumes intact |
| `scripts/nuke.sh` | Remove containers, network, volumes, seed markers |
| `scripts/seed-metabase.sh` | Post-start API seeding: groups, users, collection, questions, dashboard |
| `scripts/seed-sample-dwh.sh` | DWH seed — runs before Metabase starts |
| `scripts/optional/snapshot.sh` | SQL dumps for app_db and sample DWH |
| `scripts/optional/restore.sh` | Restore dumps into running containers |

### Adding a New Dataset Profile

The app_db is always Postgres. The sample DWH is currently Postgres-only (`sample-pg15`) but designed to support additional database types.

1. Create `env/dwh_source/<dataset>.env` with `QA_SAMPLE_IMAGE`, `SAMPLE_DB_NAME`, `SAMPLE_DB_USER`, `SAMPLE_DB_PASSWORD`, `DATASET_NAME`, `SAMPLE_DB_DISPLAY_NAME`.
2. Create `compose/datasets/<dataset>.yml` wiring up the `sample-dwh` service.
3. `make start MB_VERSION=<version> DATASET=<dataset>`
