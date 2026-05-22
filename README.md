# Metabase Local Stack

Spin up isolated, fully-seeded Metabase stacks for different versions — each with its own app_db, sample data warehouse, users, and starter content — independently, without touching each other's data. Not a migration or upgrade tool.

> **Under active development.** Structure may change. Fork before making significant local modifications.

---

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

## Make Commands

Run `make start`, `make stop`, or `make nuke` with no arguments for an interactive picker — reads your local env files, shows which stacks are running, and hands off once you choose.

| Command | What it does |
|---|---|
| `make start` | Interactive — pick a stack to start |
| `make stop` | Interactive — pick a running stack to stop |
| `make nuke` | Interactive — pick a stack to destroy |

**Prefer typing the command directly?**

```bash
# Single stack lifecycle:
make start MB_VERSION=1.61.1.x DATASET=sample-pg15
make stop  MB_VERSION=1.61.1.x DATASET=sample-pg15
make nuke  MB_VERSION=1.61.1.x DATASET=sample-pg15

# Multiple stacks simultaneously 
# (each binds to its own port set which is set in the stacks env/mb_versions/<version>.env .. see next section)
make start MB_VERSION=1.59.4.x DATASET=sample-pg15   # → localhost:3000
make start MB_VERSION=1.60.0.x DATASET=sample-pg15   # → localhost:3200 
make start MB_VERSION=1.61.1.x DATASET=sample-pg15   # → localhost:3300 
```

> **Tips for direct commands:** Use `Ctrl+R` in bash/zsh to reverse-search history and re-run a previous command instantly. Or set `export MB_VERSION=1.61.1.x` and `export DATASET=sample-pg15` in `~/.bashrc` so `make start` picks them up with no arguments.
>
> **Running multiple stacks:** Firefox [Multi-Account Containers](https://addons.mozilla.org/en-US/firefox/addon/multi-account-containers/) keeps each stack's session isolated — no session bleed across tabs. Pair with tab groups to stay organised.

---

## Setting Up Your Local Stacks

Stack env files are personal and gitignored. Create your own in `env/mb_versions/`:

1. Copy `env/mb_versions/template.env.example` → `env/mb_versions/<version>.env` (e.g. `1.61.1.x.env`).
2. Fill in `MB_IMAGE_TAG`, `METABASE_PORT`, `APP_DB_PORT`, `SAMPLE_DB_PORT` — values must not conflict with other local services.

**Naming:** `1.61.1.x.env` floats on the latest patch (auto-pulled on start). `1.61.1.3.env` pins to a specific build.

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

## What Is and Isn't Git-Ignored

| Path | Status | Why |
|---|---|---|
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
|---|---|
| `env/common.env` | Local secrets and shared settings (gitignored) |
| `env/mb_versions/<version>.env` | Image tag and port bindings for one stack (gitignored, personal) |
| `env/dwh_source/<dataset>.env` | DWH image and dataset-specific settings |
| `compose/datasets/<dataset>.yml` | Compose overlay wiring up the `sample-dwh` service |
| `seed/metabase/config.yml` | Bootstrap: users, API key, database connection |
| `seed/sample-dwh/person_profiles_json.sql` | JSON sidecar table for the sample DWH |
| `scripts/common.sh` | Shared runtime: env loading, stack naming, path normalization, image refresh, health waiting |
| `scripts/pick.sh` | Interactive picker: reads env files, detects running stacks, hands off to start/stop/nuke |
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
