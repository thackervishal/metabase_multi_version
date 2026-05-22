If present, read `.agent-local/copilot-memory.md` before making changes in this repository.

Respect these repo-specific rules:
- Do not start stacks, run `make start`, or launch other long-running services unless the user explicitly asks.
- It is fine to make file edits proactively when the requested change is clear.
- Preserve the dataset dimension in the scaffold even when only the `sample` dataset exists.
- Treat env files in `env/` as shell-sourced files. Quote values that contain spaces.
- On Windows Git Bash, keep Docker compose path handling compatible with native Docker on Windows.

Tracked repo notes:
- The repo supports multiple Metabase versions through `env/versions/*.env`; the current checked-in set is `1.59.4`, `1.59.5`, `1.60.0`, and `1.61.1`.
- The current dataset profile is `sample-pg15`, using `metabase/qa-databases:postgres-sample-15` from `env/datasets/sample-pg15.env`.
- The public workflow is `make start`, `make stop`, and `make nuke`.
- `make nuke` removes containers, the compose network, external volumes, and the seed marker under `.state/`.
- `scripts/common.sh` is the shared runtime layer for env loading, path normalization, stack naming, compose invocation, and Metabase health waiting.
- Bootstrap uses `seed/metabase/config.yml` plus `scripts/seed-metabase.sh` to create admin, analyst, and sales users, two groups, a starter collection, and a connectivity-check card.
- Seed new Metabase cards with the simplest viable approach: build direct API payloads in `scripts/seed-metabase.sh` instead of adding a separate metadata or template layer unless there is a strong reason.
- For GUI-query seeds that depend on Metabase field IDs, derive table and field IDs from live database metadata inside `scripts/seed-metabase.sh` instead of hardcoding raw IDs from one local stack.
- When deciding whether seeded cards or dashboards already exist, use `/api/collection/<id>/items` for the seeded collection rather than Metabase search results; search can return stale entries for content that no longer exists in the real collection state.
- The Metabase content seed uses the version marker in `.state/*.seeded` to decide when to reconcile new baseline content into an existing stack.
- When adding seeded Metabase cards, ask whether the card should also be attached to a dashboard; default to collection-only unless the user explicitly wants dashboard changes.
- If the user wants dashboard changes based on a locally edited dashboard, prefer extracting or importing the dashboard as a seeded artifact rather than hand-rebuilding dashboard layout in shell.
- Future datasets should be added as dataset env files plus dataset compose overlays, not as one-off compose copies.