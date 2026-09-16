# Agent reference: dataset (DWH) scaffold pattern

Read this only when adding, modifying, or debugging a dataset profile. Not needed for routine repo work — `CLAUDE.md` covers everything needed day-to-day.

A "dataset" is a data-warehouse profile a stack connects Metabase to. Three exist today: `sample-pg15`, `sample-mysql8`, `clickhouse-nyctaxi`. The scaffold is fully generic — `scripts/common.sh`, `scripts/new-stack.sh`, and `scripts/nuke.sh` need **zero** changes to add a new one. A dataset is exactly three files plus two optional script branches:

## The three required files

- **`env/dwh_source/<id>.env`** — `DATASET=<id>`, `DATASET_NAME="<human label>"`, `SAMPLE_DB_DISPLAY_NAME`, `SAMPLE_DB_TYPE`, an image reference var (`QA_SAMPLE_IMAGE` for `metabase/qa-databases:*` images; use a differently-named var like `SAMPLE_DB_IMAGE` for anything else — it's only ever read inside the dataset's own compose file, so there's no naming requirement across datasets), `SAMPLE_DB_NAME`/`SAMPLE_DB_USER`/`SAMPLE_DB_PASSWORD` (plus any engine-specific extra creds, e.g. MySQL's `SAMPLE_DB_ROOT_PASSWORD`), and `METABASE_CONFIG_FILE=config-<id>.yml`. `scripts/new-stack.sh` discovers datasets by globbing this directory (`find env/dwh_source -name "*.env"`) — dropping a new file here is the *only* thing that makes it show up in the `make new` picker.

- **`compose/datasets/<id>.yml`** — the warehouse container. Two hard requirements, both because other scripts hardcode them:
  - The service **must** be named `sample-dwh` — `compose/base.yml`'s `metabase` service has `depends_on: sample-dwh: condition: service_healthy`, and `scripts/start.sh` calls `wait_for_service_health sample-dwh 30 10`. It needs a real `healthcheck:` block for both of those to work.
  - The Compose-level volume key **must** be `sample_dwh_data`, bound via `name: ${SAMPLE_DB_VOLUME}` and `external: true` — `scripts/common.sh`'s `ensure_external_volumes()` pre-creates this volume by that exact env-var-derived name (`${COMPOSE_PROJECT_NAME}_${dataset_key}_data`) before `docker compose up`, and `scripts/nuke.sh` removes it by the same name. Nothing dataset-specific needed in either script.
  - Relative bind-mount paths in this file are resolved against **`compose/`** (the directory of `compose/base.yml`, always the first `-f` file in `scripts/common.sh`'s `compose()`), not against `compose/datasets/` where the file itself lives. `../seed/...` reaches `STACK_ROOT/seed/...`; `../data/...` reaches `STACK_ROOT/data/...`. Getting this wrong silently mounts nothing (or the wrong path) rather than erroring.

- **`seed/metabase/config-<id>.yml`** — a `METABASE_CONFIG_FILE`-driven bootstrap file, mounted read-only into the `metabase` container and pointed at via `MB_CONFIG_FILE_PATH`. All three existing files are identical boilerplate (site settings, 3 users, an admin API key) except the single `databases[0]` block — `engine`, `port`, and whatever `details` keys that engine's Metabase driver actually expects. **Don't guess the `details` schema** — check the real driver in the sibling `metabase` repo at `modules/drivers/<engine>/resources/metabase/<engine>/metabase-plugin.yaml` (`connection-properties`) before writing this file; ClickHouse's, for example, uses `enable-multiple-db`/`dbname` rather than Postgres/MySQL's plain `dbname`.

## The two optional script branches

- **`scripts/seed-sample-dwh.sh`** — loads data *into* the warehouse container itself (not Metabase content). Postgres applies a JSON seed file via `psql`; MySQL is a no-op (its QA image ships pre-seeded); ClickHouse creates a `file()`-backed view over a pre-downloaded, bind-mounted folder rather than loading anything (see the `clickhouse-nyctaxi` bullet in `CLAUDE.md`). Branch on `$DATASET_KEY` here only if your dataset needs warehouse-side setup beyond what its base image already provides.
- **`scripts/seed-metabase.sh`** — seeds demo Metabase *content* (collection, cards, dashboard) that assumes `orders`/`people`/`products` tables exist. If a new dataset doesn't have that shape of data (like `clickhouse-nyctaxi`), add an early-exit guard for it (after the cache-policy calls, which are generic and worth keeping) rather than trying to make the existing MySQL/Postgres branches cope with different tables.

## What's fully generic (no dataset-specific code exists or should be added)

`scripts/common.sh` (`compose()`, `load_stack_env()`, volume derivation, health-check waiting), `scripts/new-stack.sh` (dataset picker), `scripts/nuke.sh` (volume/marker cleanup), `compose/base.yml` (the `metabase` service itself). If a change to any of these starts looking dataset-conditional, that's a signal the new dataset's *files* aren't following the pattern above closely enough, not that these scripts need a special case.
