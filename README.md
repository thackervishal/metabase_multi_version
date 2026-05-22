# Metabase Local Stack

Spin up isolated, fully-seeded Metabase stacks for different Metabase versions — each with its own app_db, sample data warehouse, users, and starter content — so you can test or explore behaviour across versions without touching each other's data.

This is not a tool for testing Metabase upgrades or migrations. Each version runs independently with its own persistent state. Cross-version upgrade comparison may be added in a future iteration.

> **This repo is under active development.** Behaviour and structure may change. If you want to make significant changes for your own use, fork it rather than building directly on top of this one.

## Before First Start

**Requirements:**

- **Windows:** Docker Desktop, Git Bash
- **macOS:** Docker Desktop, bash
- **Linux:** Docker Engine + Docker Compose plugin, bash
- curl, jq (on Windows, `jq.exe` may need to be set explicitly — see below)
- A Metabase Pro or Enterprise token
- An Anthropic API key (required to use Metabot with the default provider)

**Setup steps:**

1. Copy `env/common.env.example` to `env/common.env`.
2. Set `MB_PREMIUM_EMBEDDING_TOKEN` — required for Metabase config-file loading.
3. Set `MB_LLM_ANTHROPIC_API_KEY` — required to back Metabot locally with Anthropic.
4. On Windows, set `JQ_BIN` if `jq.exe` is not on `PATH` inside Git Bash (e.g. `JQ_BIN=/c/tools/jq/jq.exe`).
5. Adjust admin credentials or ports if needed.

`env/common.env` is gitignored — each user maintains their own copy with their own tokens.

## Make Commands

`MB_VERSION` and `DATASET` are always required.

| Command | What it does |
|---|---|
| `make start MB_VERSION=<version> DATASET=<dataset>` | Pull latest image for given version, create volumes, start databases, start Metabase, run seed |
| `make stop MB_VERSION=<version> DATASET=<dataset>` | Stop containers, leave all data volumes intact |
| `make nuke MB_VERSION=<version> DATASET=<dataset>` | Remove containers, network, volumes, and seed markers |

Single stack lifecycle:

```bash
make start MB_VERSION=1.61.1.x DATASET=sample-pg15
make stop  MB_VERSION=1.61.1.x DATASET=sample-pg15
make nuke  MB_VERSION=1.61.1.x DATASET=sample-pg15
```

> Example — Running three stacks at the same time (each binds to its own port set defined in your version env file):
> 
> ```bash
> make start MB_VERSION=1.59.4.x DATASET=sample-pg15   # → localhost:3000
> make start MB_VERSION=1.60.0.x DATASET=sample-pg15   # → localhost:3200
> make start MB_VERSION=1.61.1.x DATASET=sample-pg15   # → localhost:3300
> ```

> **Tip — avoiding repetitive typing:** Two good options — developer's choice:
>
> - **`Ctrl+R` (reverse search):** In bash or zsh, press `Ctrl+R` and start typing part of a previous command (e.g. `1.61`). The shell searches backwards through your history and shows the most recent match. Press `Ctrl+R` again to cycle to older matches, then `Enter` to run it. Fast once you've run the command a few times.
> - **Shell profile vars:** Add `export MB_VERSION=1.61.1.x` and `export DATASET=sample-pg15` to your `~/.bashrc` (or `~/.bash_profile` on macOS) so `make start` picks them up with no arguments.

> **Tip — running multiple versions simultaneously:** Firefox with the [Multi-Account Containers](https://addons.mozilla.org/en-US/firefox/addon/multi-account-containers/) extension is very effective here. Each container maintains its own isolated session, so you can be logged into `localhost:3000` as one user and `localhost:3300` as a different user at the same time without sessions bleeding across tabs. Pairing containers with Firefox tab groups makes it easy to keep each version's tabs organised together.

## Setting Up Your Local Stacks

Stacks (metabase version + datawarehouse source data) are defined using env files -- these are yours and maintained locally .. and gitignored. Each developer creates their own stacks in `env/mb_versions/`:

1. Copy `env/mb_versions/template.env.example` to `env/mb_versions/<version>.env` (e.g. `1.61.1.x.env`).
2. Fill in `MB_IMAGE_TAG`, `METABASE_PORT`, `APP_DB_PORT`, and `SAMPLE_DB_PORT` with values that don't conflict with other services running on your machine.
3. Run `make start MB_VERSION=<version> DATASET=sample-pg15`.

**Naming convention:**
- `<major>.<minor>.<patch>.x.env` (e.g. `1.61.1.x.env`) — floating patch tag, `make start` pulls a newer patch automatically if one exists on Docker Hub.
- `<major>.<minor>.<patch>.<build>.env` (e.g. `1.61.1.3.env`) — pins to an exact build. Useful when you need to reproduce behaviour from a specific release.

No new compose files are needed when the dataset stays the same.

## Sample Data Warehouse

The built-in Metabase H2 sample database is disabled. Instead, each stack connects Metabase to a dedicated Postgres sample data warehouse container (`metabase/qa-databases:postgres-sample-15`), registered in Metabase as `sample_dwh_pg15`.

This gives you a real Postgres connection for testing SQL, field filters, JSON operators, and other features that H2 does not support.

## Seeded Content

On first start (or when the seed content version changes), the seed step creates:

- **Users:** admin, analyst, and sales users
- **Groups:** Analytics Team and Sales Team, with users assigned as members
- **Collection:** a starter collection for the connected sample warehouse
- **Questions:** GUI questions (orders by month, customers by state, products by category, JSON unfolding example), SQL questions (monthly revenue, top categories by revenue), and a native SQL question with a field filter on `People.State`
- **Dashboard:** a seeded overview dashboard pre-populated with the starter questions
- **Sample DWH data:** a JSON sidecar table (`person_profiles_json`) seeded into the warehouse before Metabase starts, used for JSON querying demos

If new content is added to the seed script in a future commit, the next `make start` picks up only the additions — existing content is left untouched. The seed tracks a content version in `.state/<stack>.metabase-seeded` and re-runs the content block whenever that version advances.

## What Is and Isn't Git-Ignored

| Path | Status | Why |
| --- | --- | --- |
| `env/common.env` | git-ignored | Per-user secrets and tokens |
| `env/mb_versions/*.env` | git-ignored | Per-user: stack choice and port assignments vary per machine |
| `env/mb_versions/template.env.example` | committed | Reference template for creating your own version files |
| `env/dwh_source/*.env` | committed | Canonical: describes what a dataset *is*, no port assignments |

## Default Credentials

Shared across all stacks unless overridden in `env/common.env`. Ports vary by stack.

Metabase users:

- Admin: `admin@example.com` / `metabot1`
- Analyst: `analyst@example.com` / `metabot1`
- Sales: `sales@example.com` / `metabot1`

Example ports for the checked-in stacks:

| Version | Metabase | app_db | Sample DWH |
|---|---|---|---|
| `1.59.4.x` | 3000 | 15402 | 15403 |
| `1.59.5.x` | 3100 | 15412 | 15413 |
| `1.60.0.x` | 3200 | 15422 | 15423 |
| `1.61.1.x` | 3300 | 15432 | 15433 |

Credentials — app_db: host `localhost`, database `metabaseappdb`, user `metabase`, password `metabase_app_password`.

Credentials — Sample DWH: host `localhost`, database `sample`, user `metabase`, password `metasample123`.

## Built-In Local Defaults

Unless overridden in `env/common.env`:

- Site name: `Metabase <version> Local Stack`
- Application name: `<version> Metabase`
- Built-in H2 sample database: disabled
- Usage analytics PII retention: enabled
- Check for updates: disabled
- Embedding: interactive, modular, SDK, and static all enabled
- Static embedding secret and SDK validation key: local-only defaults
- Caching: persisted models enabled, query cache size `10240` KB, TTL `3600` seconds, default cache policy `1 hour`, sample DWH cache policy `1 hour`
- Transforms: enabled
- AI features and Metabot: enabled, default provider `anthropic/claude-sonnet-4-6`

## Automation API Key

`MB_AUTOMATION_API_KEY` is defined in `env/common.env`. The compose file passes it into the Metabase container, and `seed/metabase/config.yml` tells Metabase to create an API key with that exact value during bootstrap. The seed script then uses the same key for all post-start API calls — no manual key creation needed.

If you rotate the key in `env/common.env`, rebuild from a clean app_db so the bootstrap can recreate it consistently.

## Key Files

- `env/common.env` — local secrets and shared settings (gitignored)
- `env/mb_versions/<version>.env` — Metabase image tag and port bindings for one version
- `env/dwh_source/<dataset>.env` — sample DWH image and dataset-specific settings
- `compose/datasets/<dataset>.yml` — dataset overlay wiring up the `sample-dwh` service
- `seed/metabase/config.yml` — config-file bootstrap for users, API key, and database connection
- `seed/sample-dwh/person_profiles_json.sql` — JSON sidecar table and seed data for the sample DWH
- `scripts/seed-metabase.sh` — post-start API seeding for groups, users, collection, questions, and dashboard
- `scripts/seed-sample-dwh.sh` — sample DWH JSON seed, runs before Metabase starts

## Helper Scripts

- `scripts/common.sh` — shared runtime: load env files, derive stack names, normalize Windows paths, wrap `docker compose`, check for image updates, wait for health
- `scripts/start.sh` — full startup: pull image if newer, create volumes, start databases, wait for health, start Metabase, seed
- `scripts/stop.sh` — stop containers, leave volumes
- `scripts/nuke.sh` — destructive reset: remove containers, network, volumes, and seed markers
- `scripts/optional/snapshot.sh` — SQL dumps for the app_db and sample DWH
- `scripts/optional/restore.sh` — restore those dumps into running containers

## Adding a New Dataset Profile

The app_db is always Postgres. The sample data warehouse is currently Postgres-only (`sample-pg15`), but the repo is designed to support other database types in future dataset profiles.

To add a new dataset:

1. Create `env/dwh_source/<dataset>.env` with `QA_SAMPLE_IMAGE`, `SAMPLE_DB_NAME`, `SAMPLE_DB_USER`, `SAMPLE_DB_PASSWORD`, `DATASET_NAME`, and `SAMPLE_DB_DISPLAY_NAME`.
2. Create `compose/datasets/<dataset>.yml` wiring up the `sample-dwh` service for that image.
3. Run `make start MB_VERSION=<version> DATASET=<dataset>`.

Currently supported datasets: `sample-pg15`
