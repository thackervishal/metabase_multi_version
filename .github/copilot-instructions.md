If present, read `.agent-local/copilot-memory.md` before making changes in this repository.

Memory rules:
- Do not write repo knowledge or decisions to the user's `~/.claude/` directory or to `.agent-local/`. Those locations are machine-local and invisible to other contributors.
- All repo-level memory (design decisions, conventions, seed rules, naming choices) belongs in this file so it travels with the repo.
- The only exception is genuinely machine-specific state: absolute paths, local tool locations (e.g. `JQ_BIN`), or per-machine overrides. Those belong in `.agent-local/copilot-memory.md` or `env/common.env`, not in `~/.claude/`.

Respect these repo-specific rules:
- Do not start stacks, run `make start`, or launch other long-running services unless the user explicitly asks.
- It is fine to make file edits proactively when the requested change is clear.
- Preserve the dataset dimension in the scaffold even when only the `sample` dataset exists.
- Treat env files in `env/` as shell-sourced files. Quote values that contain spaces.
- On Windows Git Bash, keep Docker compose path handling compatible with native Docker on Windows.

Tracked repo notes:
- Version env files (`env/versions/*.env`) are gitignored and personal — each developer creates their own from `env/versions/template.env.example`. There is no shared canonical version list and no `versions.mk`. Floating `.x` filenames (e.g. `1.61.1.x.env`) track the latest patch; a full 4-part filename (e.g. `1.61.1.3.env`) pins to a specific build.
- The current dataset profile is `sample-pg15`, using `metabase/qa-databases:postgres-sample-15` from `env/datasets/sample-pg15.env`. The sample data warehouse service is named `sample-dwh` in Docker Compose (not `sample-db`). The Metabase connection display name is `sample_dwh_pg15`.
- The public workflow is `make start`, `make stop`, and `make nuke`.
- `make nuke` removes containers, the compose network, external volumes, and the seed marker under `.state/`.
- `scripts/common.sh` is the shared runtime layer for env loading, path normalization, stack naming, compose invocation, Metabase image refresh (pull if newer, prune old), and Metabase health waiting.
- Bootstrap uses `seed/metabase/config.yml` plus `scripts/seed-metabase.sh` to create admin, analyst, and sales users, two groups, a starter collection, and a connectivity-check card.
- Seed new Metabase cards with the simplest viable approach: build direct API payloads in `scripts/seed-metabase.sh` instead of adding a separate metadata or template layer unless there is a strong reason.
- For GUI-query seeds that depend on Metabase field IDs, derive table and field IDs from live database metadata inside `scripts/seed-metabase.sh` instead of hardcoding raw IDs from one local stack.
- When deciding whether seeded cards or dashboards already exist, use `/api/collection/<id>/items` for the seeded collection rather than Metabase search results; search can return stale entries for content that no longer exists in the real collection state.
- The Metabase content seed uses the version marker in `.state/*.metabase-seeded` to decide when to reconcile new baseline content into an existing stack. The sample DWH seed uses `.state/*.sample-dwh-seeded`.
- When adding seeded Metabase cards, ask whether the card should also be attached to a dashboard; default to collection-only unless the user explicitly wants dashboard changes.
- If the user wants dashboard changes based on a locally edited dashboard, prefer extracting or importing the dashboard as a seeded artifact rather than hand-rebuilding dashboard layout in shell.
- Future datasets should be added as dataset env files plus dataset compose overlays, not as one-off compose copies.