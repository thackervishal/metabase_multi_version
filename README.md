# Metabase Local Stack

This repo stands up local Metabase stacks across multiple Metabase versions and explicit dataset profiles. Each stack has one app Postgres database, one sample warehouse, and a small bootstrap step that seeds Metabase after startup.

## Overall flow

The repo follows the same lifecycle every time:

1. Load shared settings from `env/common.env`, version-specific settings from `env/versions/<version>.env`, and dataset settings from `env/datasets/<dataset>.env`.
2. Start the app database and sample warehouse first.
3. Wait for both databases to report healthy.
4. Start Metabase.
5. Wait for the Metabase health endpoint to respond.
6. Run a seed step that uses the config-file API key to create groups, memberships, a starter collection, and a sample card.

The stack keeps its database state in external named Docker volumes. `make stop` leaves those volumes alone. `make nuke` removes them.

Because Metabase compatibility and sample warehouse compatibility can drift independently over time, the repo treats them as two separate axes:

- `MB_VERSION` selects the Metabase image tag and host ports.
- `DATASET` selects the sample warehouse image and dataset-specific credentials.

That lets you run combinations like an older Metabase version with an older sample DB profile, or a newer Metabase version with a newer sample DB profile, without changing the shared scripts.

## Startup and bootstrap details

When you run `make start`, the process is split across Docker Compose, Metabase's config-file bootstrap, and a small post-start seed script.

1. `scripts/start.sh` loads the selected env files through `scripts/common.sh`.
2. It creates the external Docker volumes for the app database and sample database if they do not already exist.
3. It starts `app-db` and `sample-db` first and waits until both are healthy.
4. It runs `scripts/seed-sample-db.sh`, which creates and populates a JSON sidecar table in the sample warehouse.
5. It starts the Metabase container.
6. Metabase reads `seed/metabase/config.yml` during startup because `compose/base.yml` mounts that file and sets `MB_CONFIG_FILE_PATH`.
7. The stack derives local defaults for site naming, application naming, embedding, caching, transforms, usage analytics retention, and update checks from `scripts/common.sh`, and passes them into the Metabase container as environment variables.
8. The config file creates the initial users, registers the sample database connection using the dataset key as its name, and installs a fixed automation API key from `MB_AUTOMATION_API_KEY`.
9. After Metabase is reachable, `scripts/seed-metabase.sh` waits until that API key works, reconciles cache policies through `/api/cache`, and then reconciles groups, memberships, a starter collection, several starter questions, including a SQL example with a field filter, and a dashboard.
10. When either seed step succeeds, it writes its own marker under `.state/`. The Metabase content marker stores a seed content version, so later starts can pick up new baseline additions when that version changes. Cache policy reconciliation still runs on every start.
11. The Metabase seed checks for existing seeded cards and dashboards from the actual seeded collection contents, not from search results, because the search index can lag behind real content state.

## Automation API key

You do not need to generate the seed script API key manually in the Metabase UI for this repo.

- `MB_AUTOMATION_API_KEY` is defined in `env/common.env`.
- `compose/base.yml` passes that value into the Metabase container as an environment variable.
- `seed/metabase/config.yml` tells Metabase to create an API key with that exact value during bootstrap.
- `scripts/seed-metabase.sh` then uses the same key in the `x-api-key` header for its follow-up API calls.

That means the key is predetermined by your env file, but it becomes valid only after Metabase applies the config-file bootstrap during startup. If you rotate the key value in `env/common.env`, you should rebuild from a clean app database state so the bootstrap can recreate it consistently.

## Requirements

- Docker Desktop
- bash
- curl
- jq
- a Metabase Pro or Enterprise token for config-file loading

## One-time setup

1. Copy `env/common.env.example` to `env/common.env`.
2. Set `MB_PREMIUM_EMBEDDING_TOKEN` in `env/common.env`.
3. On Windows, set `JQ_BIN` in `env/common.env` if `jq.exe` is not available on `PATH` inside Git Bash.
4. Adjust admin credentials or ports if needed.

## Built-in local defaults

Unless you override them in `env/common.env`, the stack now applies these defaults on startup:

- Site name: `Metabase <version> Local Stack`
- Conceal Metabase application name: `<version> Metabase`
- Built-in H2 sample database: disabled
- Sample database connection name: dataset key transformed to shell-safe form, for example `sample_pg15`
- Usage analytics PII retention: enabled
- Check for updates: disabled
- Embedding: interactive, modular, SDK, and static embedding enabled
- Static embedding secret and SDK validation key: seeded with local-only defaults for convenience
- Caching: persisted models enabled, query cache size set to `10240` KB, query cache TTL set to `3600` seconds, default cache policy set to `1 hour`, and the selected sample database explicitly set to `1 hour`
- Transforms: enabled
- AI features and Metabot: enabled, with the local default provider set to `anthropic/claude-sonnet-4-6`

The stack does not currently expose a documented Metabase environment variable for a separate “semantic search” admin toggle.

To back Metabot with Anthropic locally, set `MB_LLM_ANTHROPIC_API_KEY` in `env/common.env`. The stack now forwards `MB_AI_FEATURES_ENABLED`, `MB_METABOT_ENABLED`, `MB_LLM_METABOT_PROVIDER`, and `MB_LLM_ANTHROPIC_API_KEY` into the Metabase container on `make start`.

## Supported selections

Current Metabase version files:

- `1.59.4`
- `1.59.5`
- `1.60.0`
- `1.61.1`

Current dataset profiles:

- `sample-pg15`

Use explicit `MB_VERSION` and `DATASET` values when working with stacks. The defaults are there for convenience, but the repo is meant to be operated as a version-and-dataset matrix.

## Daily commands

Start a stack:

```bash
make start MB_VERSION=1.61.1 DATASET=sample-pg15
```

Stop the stack but keep all data volumes:

```bash
make stop MB_VERSION=1.61.1 DATASET=sample-pg15
```

Nuke the stack completely, including external volumes and the seed marker:

```bash
make nuke MB_VERSION=1.61.1 DATASET=sample-pg15
```

Examples for older versions against the current sample profile:

```bash
make start MB_VERSION=1.59.4 DATASET=sample-pg15
make start MB_VERSION=1.60.0 DATASET=sample-pg15
```

## What start, stop, and nuke do

- `make start` creates any missing external volumes, starts Postgres, waits for health, runs the sample warehouse JSON seed, starts Metabase, and then runs the Metabase seed step.
- `make stop` stops containers only.
- `make nuke` removes containers, the compose network, both external database volumes, and both seed markers under `.state/`.

## Seeded JSON table

The sample warehouse seed now creates `public.person_profiles_json` before Metabase starts. It is designed as a sidecar table for `public.people`, so you can join `person_profiles_json.person_id` to `people.id`.

Table shape:

- `person_id bigint primary key`: references `people.id`
- `profile_json jsonb not null`: nested profile payload used for JSON querying demos
- `profile_source text not null`: currently seeded as `person-profile-seed`
- `created_at timestamp`: seeded from the linked person record when available
- `updated_at timestamp`: refreshed on every idempotent reseed

The seed currently loads the first 25 people from the sample dataset and inserts one JSON document per person.

`profile_json` structure:

- `external_id`: string like `cust-1`
- `loyalty`: object with `tier`, `points_balance`, and `member_since`
- `preferences`: object with `preferred_language`, `marketing_opt_in`, `dark_mode`, `contact_channels`, and `timezone`
- `devices`: array with two objects by default
- `tags`: array of profile tags such as `vip`, `newsletter`, `repeat-buyer`, or `beta-program`
- `enrichment`: object with `acquisition_source`, `home_state`, `support`, and `household`

Nested sub-objects and arrays:

- `devices[0]`: mobile device details with `type`, `platform`, `app_version`, and `push_enabled`
- `devices[1]`: web device details with `type`, `browser`, and `last_login_days_ago`
- `enrichment.support`: object with `last_ticket_priority` and `open_ticket_count`
- `enrichment.household`: object with `has_children` and `estimated_income_band`

This table exists to make Postgres `jsonb` operators easy to test in Metabase. Example patterns include extracting scalar fields, filtering on nested booleans, and expanding arrays of devices or tags.

## Current images

- Metabase uses `metabase/metabase-enterprise:v${MB_IMAGE_TAG}` from `compose/base.yml`.
- The app database uses `postgres:18-alpine`.
- The `sample-pg15` dataset uses `metabase/qa-databases:postgres-sample-15` from `env/datasets/sample-pg15.env` and is registered in Metabase as `sample_pg15` by default. The seed script requires that exact configured connection name instead of falling back to legacy names.

If you still see older Metabase or sample database images in Docker Desktop, they are just cached local images from previous runs or manual pulls. This repo only uses the dataset overlay selected by `DATASET`, because `scripts/common.sh` calls Docker Compose with `compose/base.yml` plus exactly one file: `compose/datasets/${DATASET}.yml`.

Even if you add multiple dataset overlays under `compose/datasets/`, they can all define the same service name `sample-db`. That is safe because only one dataset overlay is included in any given `make start` invocation.

## Default credentials

These credentials are shared across stacks unless you change the env files. The usernames and passwords stay the same by default; only the exposed host ports vary by `MB_VERSION`.

Metabase users from `env/common.env`:

- Admin: `admin@example.com` / `metabot1`
- Analyst: `analyst@example.com` / `metabot1`
- Sales: `sales@example.com` / `metabot1`

Metabase app database from `env/common.env`:

- Host: `localhost`
- Port: `APP_DB_PORT` from the selected `env/versions/<version>.env`
- Database: `metabaseappdb`
- User: `metabase`
- Password: `metabase_app_password`

Sample warehouse from the selected dataset env file:

- Host: `localhost`
- Port: `SAMPLE_DB_PORT` from the selected `env/versions/<version>.env`
- Database: `sample`
- User: `metabase`
- Password: `metasample123`

Example ports for the checked-in versions:

- `1.59.4`: Metabase `3000`, app DB `15402`, sample DB `15403`
- `1.59.5`: Metabase `3100`, app DB `15412`, sample DB `15413`
- `1.60.0`: Metabase `3200`, app DB `15422`, sample DB `15423`
- `1.61.1`: Metabase `3300`, app DB `15432`, sample DB `15433`

## Add a new Metabase version

To add another version by hand:

1. Create `env/versions/<version>.env`.
2. Set `MB_IMAGE_TAG`, `METABASE_PORT`, `APP_DB_PORT`, and `SAMPLE_DB_PORT` in that file.
3. If you want that version to become the default, update `DEFAULT_VERSION` in `versions.mk`.
4. Append the version string to `MB_VERSIONS` in `versions.mk`.
5. Start it with `make start MB_VERSION=<version> DATASET=<dataset>`.

For a new Metabase version, no new compose files are needed if the dataset stays the same.

## Add a new dataset profile

If a future or older Metabase version needs a different sample warehouse generation, add a new dataset profile instead of mutating an existing one in place.

1. Create `env/datasets/<dataset>.env`.
2. Set `QA_SAMPLE_IMAGE`, `SAMPLE_DB_NAME`, `SAMPLE_DB_USER`, and `SAMPLE_DB_PASSWORD` in that file.
3. Create `compose/datasets/<dataset>.yml` if the container wiring differs from the existing sample profile.
4. Append the dataset name to `DATASETS` in `versions.mk`.
5. Start the stack with `make start MB_VERSION=<version> DATASET=<dataset>`.

The dataset file is chosen entirely by the `DATASET` value. For example, `DATASET=sample-pg15` causes the scripts to load `env/datasets/sample-pg15.env` and `compose/datasets/sample-pg15.yml`.

## Key files

- `env/common.env` holds local secrets and shared settings.
- `env/versions/<version>.env` defines the Metabase image tag and port bindings for one version.
- `env/datasets/<dataset>.env` defines the sample warehouse image and dataset-specific database settings.
- `compose/datasets/<dataset>.yml` defines the dataset overlay that contributes the `sample-db` service for that dataset profile.
- `seed/metabase/config.yml` sets up the config-file bootstrap for Metabase.
- `seed/sample-db/person_profiles_json.sql` defines the JSON sidecar table and dummy `jsonb` seed data for the sample warehouse.
- `scripts/seed-metabase.sh` adds starter groups, memberships, and sample content after Metabase is up.
- `scripts/seed-sample-db.sh` applies the sample warehouse JSON seed before Metabase starts.

## Helper scripts

- `scripts/common.sh` is the shared runtime layer: load env files, derive stack names, normalize Windows paths, wrap `docker compose`, and wait for Metabase health.
- `scripts/start.sh` is the full startup path: create volumes, start databases, wait for health, start Metabase, then seed.
- `scripts/stop.sh` stops containers without touching volumes.
- `scripts/nuke.sh` is the destructive reset path used by `make nuke`.
- `scripts/seed-metabase.sh` performs the idempotent post-start API seeding, including starter GUI questions, starter SQL questions, a native SQL field-filter example, and a dashboard for the selected dataset. It reconciles existence from the seeded collection contents rather than relying on Metabase search results.
- `scripts/seed-sample-db.sh` performs the idempotent sample warehouse seed and writes its own `.state` marker so the JSON table is not recreated on every restart.
- `scripts/optional/snapshot.sh` creates SQL dumps for the app DB and sample DB.
- `scripts/optional/restore.sh` restores those SQL dumps back into running database containers.

The core stack flow is concentrated in four top-level scripts now: `common.sh`, `start.sh`, `stop.sh`, and `nuke.sh`. The snapshot utilities are still available, but they are pushed into `scripts/optional/` so they do not distract from the main lifecycle.
