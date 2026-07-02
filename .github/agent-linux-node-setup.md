# Agent playbook: Node/npm/`mb` CLI on Debian/Ubuntu

Read this only when bootstrapping the Metabase CLI (`mb`) on a fresh Debian/Ubuntu-family machine, or debugging why `mb`/`node`/`npm` can't be found from a non-interactive shell. Not needed for routine repo work — `.github/copilot-instructions.md` covers everything needed day-to-day.

## Replacing apt's Node with nvm

If Node came from apt (`nodejs`/`npm`/`libnode*`), the default global npm prefix (`/usr/local`) is root-owned, so `npm install -g @metabase/cli` fails with `EACCES`. Don't work around it — replace it:

1. Check reverse dependencies first: `apt-cache rdepends --installed libnode<N>` — should list only other `node-*`/`nodejs`/`npm` packages. If something unrelated depends on it, stop and ask the user before removing anything.
2. Remove: `sudo apt remove --purge nodejs npm nodejs-doc libnode-dev libnode<N> && sudo apt autoremove --purge`
3. Install Node via `nvm`. **Verify the current release tag live — do not trust a memorized or web-searched version number.** A fetched docs page and a web search summary have both been observed inventing plausible-but-wrong specifics for exactly this class of fact. Confirm via the GitHub API directly, no summarization layer involved:
   ```bash
   curl -fsS https://api.github.com/repos/nvm-sh/nvm/releases/latest
   ```
4. Install with the verified tag, then install Node and the CLI:
   ```bash
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/<verified-tag>/install.sh | bash
   nvm install --lts && nvm alias default lts/*
   npm install -g @metabase/cli
   ```

## Making `mb`/`node`/`npm` visible to a non-interactive agent shell

Non-interactive shells — including every agent Bash-tool call — do not source `~/.bashrc`, where nvm's init lines live; `.bashrc` no-ops immediately for non-interactive shells regardless of how it's invoked. Without a fix, every `mb`/`node`/`npm` call from an agent needs `source ~/.nvm/nvm.sh` first, every single time.

Fix once, permanently: symlink `node`, `npm`, `npx`, and `mb` into `~/.local/bin`, which is on `PATH` by default in every shell on Ubuntu/Kubuntu (confirm with `echo $PATH` before relying on this — don't assume).

Do **not** reach for `/usr/local/bin` instead — it's root-owned, needs `sudo`, and an agent should ask the user before taking a `sudo` action rather than defaulting to it as a workaround.

Exact paths and the currently-installed Node version are machine-specific — see (and keep current) `.agent-local/copilot-memory.md`, and re-derive them fresh on any new machine rather than copying values from there.
