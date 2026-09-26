# Metabase Local Stack

Spin up isolated, fully-seeded Metabase stacks for different versions — each with its own app_db, sample data warehouse, users, and starter content — independently, without touching each other's data. Not a migration or upgrade tool.

> **Under active development.** Structure may change. Fork before making significant local modifications.



## Before First Start

**Requirements:** Docker Desktop (Windows/macOS) or Docker Engine + Compose plugin (Linux), Git Bash (Windows), curl, jq, a Metabase Pro/Enterprise token, an Anthropic API key. Node.js is optional — it enables the [Metabase CLI](#metabase-cli-mb); `make start` falls back to `npx` automatically if Node isn't installed.

> On Windows: `jq.exe` may need `JQ_BIN=/c/path/to/jq.exe` in `env/common.env` if it is not on PATH inside Git Bash.

**Setup:**

1. Copy `env/common.env.example` → `env/common.env`.
2. Edit `env/common.env`.
   - Set `MB_PREMIUM_EMBEDDING_TOKEN` — required for config-file bootstrap.
   - Set `MB_LLM_ANTHROPIC_API_KEY` — optional, only needed for stacks where you answer "yes" to the Metabot prompt in `make new`.
3. Adjust credentials or ports if needed.
4. *(Optional, recommended)* Install the [Metabase CLI](#metabase-cli-mb) globally: `npm install -g @metabase/cli`. Skip this and `make start` falls back to `npx` automatically — slower per call, but nothing else to set up.

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

**Optional friendly name:** `make new` ends by asking for a `STACK_LABEL` (e.g. `testing keycloak`) — purely cosmetic, shown by `make list` and the `make start`/`stop`/`nuke` picker so you can tell stacks apart at a glance. Skip the prompt to leave it unset, or hand-edit `STACK_LABEL="<value>"` into any existing version env file at any time.

---

## Make Commands

Once your stack env files are in place, run `make start`, `make stop`, or `make nuke` with no arguments for an interactive picker — reads your local env files, shows which stacks exist, which are running, and lets you choose which one to start.

| Command | What it does |
| --- | --- |
| `make start` | Interactive — pick a stack to start |
| `make stop` | Interactive — pick a running stack to stop |
| `make nuke` | Interactive — pick a stack to destroy (removes containers, volumes, seed markers; prompts to also delete the env file) |
| `make list` | Show all configured stacks with ports and running status |
| `make new` | Create a new version env file — drill down major → minor → hotfix or float, suggests ports, optionally starts |
| `make services-up` | Start all shared services (Mailpit, webhook tester, Keycloak) manually |
| `make services-down` | Stop shared services |
| `make prune` | Remove all unused Docker images (tagged and untagged) and orphaned volumes |
| `make done` | Stop all running stacks and shared services (end of day) |
| `make watch-remote-sync` | Interactive — pick a remote-sync-enabled stack and auto-pull its browsable checkout on every push (see [Remote Sync](#remote-sync)) |

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

## Claude Code MCP Integration

Each `make start` automatically registers the running Metabase stack as an MCP server in Claude Code, scoped to this project (written to `.mcp.json` in the repo root, which is gitignored). This gives Claude Code live access to Metabase tools — querying data, inspecting databases, running cards, etc. — directly from the chat.

**The order matters:**

1. Run `make start` in the terminal and wait for the "Stack ready" summary.
2. Check the summary line — if it says `MCP server  <name>  (start new Claude session)`, registration succeeded.
3. Open Claude Code and **start a new conversation**. Tools are not available in sessions that were already open when `make start` ran.

**If tools don't appear in the new session:**

- **Wait a moment and retry.** The Metabase MCP endpoint (`/api/metabase-mcp`) can lag slightly behind the health check. Close the conversation, wait 10–15 seconds, open a new one.
- **Check the startup summary.** If it said `MCP server  registration failed`, the `claude` CLI was not found on PATH in the terminal where you ran `make start`. Registration is silently skipped in that case — run `make start` again from a terminal where `claude` is available.
- **Multiple stacks** each get their own named MCP entry (e.g. `mb_1_62_3_x_sample_mysql8`), so you can have several registered simultaneously. Each new Claude session sees all of them.
- **`make nuke`** removes the MCP entry for that stack automatically.

---

## Metabase CLI (`mb`)

Each `make start` also authenticates the official [Metabase CLI](https://www.npmjs.com/package/@metabase/cli) (`mb`) against the running stack, using the same automation key as MCP. It gives you (or an AI agent) terminal access to the same content CRUD as MCP, plus things MCP doesn't expose — transforms, git-sync, documents, and more.

**Install (optional but recommended):**

```bash
npm install -g @metabase/cli
```

- **Windows:** usually works immediately — npm's default global install location is already user-owned.
- **Linux, with Node from a system package manager (e.g. `apt install nodejs npm`):** often fails with `EACCES`, because npm's default global prefix (`/usr/local`) is root-owned. Fix with a user-owned npm prefix, or reinstall Node via [nvm](https://github.com/nvm-sh/nvm) instead — recommended, since every future global install then works with no extra config.

No install? No problem — `make start` falls back to `npx @metabase/cli@latest` automatically (slower per call, since npx re-resolves the package each time, but functionally identical).

**Multiple stacks:** each gets its own CLI profile, named after the stack (the same name as its MCP server entry), so running several stacks concurrently doesn't overwrite each other's saved credentials. `--profile <name>` is required on every `mb` command you run yourself — check the "Metabase CLI" line in the summary `make start` prints for the exact profile name, or list them all:

```bash
mb auth list --json
```

**Learning the CLI:** it ships its own docs, and they're more reliable than anything external — the CLI's actual flags have been observed to differ from what the public docs page and web search describe:

```bash
mb --help
mb skills list    # bundled skill docs — read `core` first
mb __manifest     # full machine-readable command/flag inventory
```

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

Each stack has optional feature flags in its version env file (`env/mb_versions/<version>.env`):

```env
ENABLE_EMAIL=true    # starts Mailpit — catches all outbound email
ENABLE_WEBHOOKS=true # starts webhook-tester — receives webhook alerts
ENABLE_SAML=true     # starts Keycloak — local identity provider (SAML and OIDC)
```

`make new` prompts for email and webhooks when creating a new stack. To enable any flag on an existing stack, edit the env file directly and run `make start` again.

When any flag is `true`, `make start` automatically starts the relevant shared service. Services are isolated by Docker Compose profile — only the ones you enable are started. All share a single `mb_shared` Docker network and project, so enabling a second flag on a later stack just adds that service alongside whatever is already running.

Ports default to `8025` (Mailpit UI), `9000` (webhook-tester), `8180` (Keycloak). Override any of these in `env/common.env`.

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

### Keycloak (SAML / OIDC)

When `ENABLE_SAML=true`, a local [Keycloak](http://keycloak:8180) instance starts (admin / metabot1). It handles both SAML and OIDC flows.

**Hosts file requirement:**

Keycloak advertises all its endpoints (issuer, token endpoint, etc.) using the hostname `keycloak`, not `localhost`. Both the Metabase container (server-to-server token exchange) and your browser (redirect flow) must reach it at that hostname. Add this line to `C:\Windows\System32\drivers\etc\hosts` (requires an elevated editor):

```text
127.0.0.1 keycloak
```

Without this, browser-driven OIDC and SAML redirect flows will fail.

**OIDC setup (quick reference):**

| Field | Value |
| --- | --- |
| Keycloak admin UI | `http://keycloak:8180` |
| Issuer URI (in Metabase) | `http://keycloak:8180/realms/<your-realm>` |
| Valid redirect URI (in Keycloak client) | `http://localhost:<METABASE_PORT>/auth/sso/<key>/callback` |

The **Key** field in Metabase's OIDC form is a short slug you choose (e.g. `keycloak`). It forms the callback URL — use that exact URL in Keycloak's "Valid redirect URIs".

`MB_ENCRYPTION_SECRET_KEY` is required for Metabase to save OIDC settings. It is pre-configured in `env/common.env` and wired into `compose/base.yml` — no action needed for new stacks.

### Email

When `ENABLE_EMAIL=true`, all email sent by Metabase (alerts, invites, password resets) is captured by [Mailpit](http://localhost:8025) — nothing reaches real addresses.

---

## Remote Sync

Remote Sync is Metabase's git-backed collection/library sync feature (Enterprise-only). Enable it per-stack in the version env file:

```env
ENABLE_REMOTE_SYNC=true
```

`make new` prompts for it when creating a new stack. To enable it on an existing stack, edit the env file and run `make start` again.

**What gets set up automatically:**

- A local bare git repo at `data/remote-sync/<stack>/`, seeded with one empty commit on `main`. (A plain empty bare repo isn't enough on its own — Metabase's own connection check rejects a repo with zero branches, even in read-write mode.) It's bind-mounted read-write into the container, with `MB_REMOTE_SYNC_URL=file:///remote-sync/repo.git` and `MB_REMOTE_SYNC_TYPE=read-write` already set — open **Admin → Remote Sync** and the repo is already connected, nothing to configure.
- A normal, browsable working-tree checkout of that same repo at `data/remote-sync-checkout/<stack>/`. The bare repo itself has no visible files — that's what "bare" means — so this checkout is what to actually open in an editor.

Both paths are gitignored and removed automatically by `make nuke`.

**Deliberately left for you to turn on in Admin → Remote Sync:**

- **"Sync transforms"** and which collections sync. These have no env-var equivalent in Metabase itself (admin UI/API only), and transforms sync is an all-or-nothing toggle, so the scaffolding never flips it on for you — do it by hand once the stack is up.
- Every push. Nothing here auto-commits on content changes — you (or an automated caller) have to click **Push changes** in Admin → Remote Sync (or `POST /api/ee/remote-sync/export`) each time. This runs as a single background task: triggering a second export while one is still running fails with a generic "Something went wrong" toast rather than a clear "already in progress" message — just wait for the first one to finish and retry.

**Browsing the synced content:**

Open the checkout folder in VSCode like any other repo:

```bash
code data/remote-sync-checkout/<stack>
```

Refresh it manually after a push:

```bash
git -C data/remote-sync-checkout/<stack> pull
```

...or auto-refresh it continuously — polls the bare repo every 2s and pulls the instant it sees a new commit. Run this in a spare terminal and leave it while you work:

```bash
make watch-remote-sync                                          # interactive picker (lists remote-sync-enabled stacks only)
make watch-remote-sync MB_VERSION=<version> DATASET=<dataset>    # direct
```

**Inspecting the bare repo directly** (no checkout needed — useful for one-off scripting):

```bash
export GIT_DIR="data/remote-sync/<stack>"
git log --oneline --all --graph
git ls-tree -r main --name-only
git show main:<path-inside-repo>.yaml
unset GIT_DIR
```

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
  - password: `metabot1`
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

`make new` generates a random `MB_AUTOMATION_API_KEY` and writes it into that stack's `env/mb_versions/<version>.env` (gitignored, per-stack). The dataset's config file (`seed/metabase/config-pg15.yml` or `seed/metabase/config-mysql8.yml`) tells Metabase to create an API key with that exact value at bootstrap, so the seed script, MCP, and the `mb` CLI can all authenticate immediately — no manual key creation needed. `env/common.env.example` also carries a placeholder value as a fallback for stacks whose version env file doesn't set one (e.g. if you created it by hand from an older template) — replace it with your own generated value, same as `MB_ENCRYPTION_SECRET_KEY`.

If you rotate a stack's key, rebuild from a clean app_db (`make nuke` then `make start`) — it's baked in at bootstrap, not read live.

> **Security note:** Compose publishes `${METABASE_PORT}:3000` without a `127.0.0.1:` bind prefix, so the port is reachable from other machines whenever the host itself is reachable (LAN, cloud VM, etc.), not just from `localhost`. That's fine for a laptop behind a home router or corporate NAT. If you ever run a stack on a host with a public/routable IP, treat its automation key as sensitive like any other admin credential — it's no longer just a shared local-dev convenience once the port is reachable from outside.

### Files and Scripts

| Path | Purpose |
| --- | --- |
| `env/common.env` | Local secrets and shared settings (gitignored) |
| `env/mb_versions/<version>.env` | Image tag and port bindings for one stack (gitignored, personal) |
| `env/dwh_source/<dataset>.env` | DWH image and dataset-specific settings |
| `compose/datasets/<dataset>.yml` | Compose overlay wiring up the `sample-dwh` service |
| `compose/remote-sync-overlay.yml` | Compose overlay wiring up Remote Sync when `ENABLE_REMOTE_SYNC=true` |
| `seed/metabase/config-pg15.yml` / `config-mysql8.yml` | Bootstrap: users, API key, database connection (selected via `METABASE_CONFIG_FILE`) |
| `seed/sample-dwh/person_profiles_json.sql` | JSON sidecar table for the sample DWH |
| `scripts/common.sh` | Shared runtime: env loading, stack naming, path normalization, image refresh, health waiting |
| `scripts/shared-services.sh` | Manage the `mb_shared` Compose project: up, stop, down, ensure (profile-aware), ensure-network |
| `scripts/firefox-container.sh` | Create or remove a Firefox Multi-Account Container entry for a stack |
| `scripts/list-stacks.sh` | Show all configured stacks with ports and running status |
| `scripts/pick.sh` | Interactive picker: reads env files, detects running stacks, hands off to start/stop/nuke |
| `scripts/new-stack.sh` | Create a new version env file: queries Docker Hub, suggests ports, optionally starts |
| `scripts/start.sh` | Pull image if newer, create volumes, start services, seed |
| `scripts/stop.sh` | Stop containers, leave volumes intact |
| `scripts/done.sh` | Stop all running stacks and shared services (end-of-day shortcut) |
| `scripts/nuke.sh` | Remove containers, network, volumes, seed markers; optionally delete env file |
| `scripts/watch-remote-sync.sh` | Poll a stack's remote-sync bare repo and auto-pull its browsable checkout on every push |
| `scripts/seed-metabase.sh` | Post-start API seeding: groups, users, collection, questions, dashboard |
| `scripts/seed-sample-dwh.sh` | DWH seed — runs before Metabase starts |
| `scripts/optional/snapshot.sh` | SQL dumps for app_db and sample DWH |
| `scripts/optional/restore.sh` | Restore dumps into running containers |

### Adding a New Dataset Profile

The app_db is always Postgres. The sample DWH is currently Postgres-only (`sample-pg15`) but designed to support additional database types.

1. Create `env/dwh_source/<dataset>.env` with `QA_SAMPLE_IMAGE`, `SAMPLE_DB_NAME`, `SAMPLE_DB_USER`, `SAMPLE_DB_PASSWORD`, `DATASET_NAME`, `SAMPLE_DB_DISPLAY_NAME`.
2. Create `compose/datasets/<dataset>.yml` wiring up the `sample-dwh` service.
3. `make start MB_VERSION=<version> DATASET=<dataset>`
