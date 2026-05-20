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
- Future datasets should be added as dataset env files plus dataset compose overlays, not as one-off compose copies.