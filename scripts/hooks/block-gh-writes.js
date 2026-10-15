#!/usr/bin/env node
// PreToolUse hook for the Bash tool. Blocks GitHub writes from Claude:
//   - any `gh` command that is not on the read-only allowlist below
//   - `gh api` calls that send data (-f/-F/--field/--raw-field/--input), use a
//     non-GET method, or hit graphql (mutations can't be inspected reliably)
//   - `git push`
// Fail-closed on unreadable input. Exit code 2 blocks the call and sends stderr
// to Claude. To allow another read-only gh command, add it to READ_ONLY.

const fs = require('fs');

const READ_ONLY = {
  issue: ['view', 'list', 'status'],
  pr: ['view', 'list', 'status', 'diff', 'checks'],
  repo: ['view', 'list'],
  release: ['view', 'list', 'download'],
  run: ['view', 'list', 'watch', 'download'],
  workflow: ['view', 'list'],
  label: ['list'],
  gist: ['view', 'list'],
  project: ['view', 'list', 'field-list', 'item-list'],
  ruleset: ['list', 'view', 'check'],
  cache: ['list'],
  variable: ['list', 'get'],
  secret: ['list'],
  auth: ['status'],
  extension: ['list', 'search', 'browse'],
};
const ANY_SUBCOMMAND = new Set(['search', 'browse', 'status', 'help', 'version']);
const TOP_FLAGS = new Set(['--version', '--help', '-h']);

function block(reason) {
  process.stderr.write(
    `Blocked by block-gh-writes hook: ${reason}\n` +
      'GitHub writes are not allowed. Save the draft as a local markdown file ' +
      'and let the user create it on github.com.\n'
  );
  process.exit(2);
}

let command;
try {
  const input = JSON.parse(fs.readFileSync(0, 'utf8'));
  command = (input.tool_input && input.tool_input.command) || '';
} catch (e) {
  block('could not read hook input');
}

const unquote = (t) => t.replace(/^['"]+|['"]+$/g, '');

// git push
if (/(^|[\s;&|(`])git\b[^;&|\n`]*\bpush\b/.test(command)) {
  block('`git push` writes to GitHub.');
}

// every gh invocation: gh at a word boundary, optional path prefix / .exe
const ghRe = /(?:^|[\s;&|()`"'])(?:[^\s;&|()`"']*[\\/])?gh(?:\.exe)?(?=\s|$)/g;
let m;
while ((m = ghRe.exec(command)) !== null) {
  const rest = command.slice(m.index + m[0].length);
  const segment = rest.split(/[;&|\n`]|\$\(|\)/)[0];
  const tokens = segment.trim().split(/\s+/).filter(Boolean).map(unquote);
  const [cmd, sub] = tokens;

  if (!cmd) continue;
  if (TOP_FLAGS.has(cmd) || ANY_SUBCOMMAND.has(cmd)) continue;

  if (cmd === 'api') {
    const args = tokens.slice(1);
    for (let i = 0; i < args.length; i++) {
      const a = args[i];
      if (/^(-f|-F|--field|--raw-field|--input)/.test(a)) {
        block('`gh api` with request fields or --input sends a write.');
      }
      const method = /^--method=(.+)$/.exec(a) || /^-X(.+)$/.exec(a) ||
        (/^(-X|--method)$/.test(a) ? [null, args[i + 1] || ''] : null);
      if (method && method[1].toUpperCase() !== 'GET') {
        block(`\`gh api\` with method ${method[1]}.`);
      }
    }
    const endpoint = args.find((a) => !a.startsWith('-'));
    if (endpoint === 'graphql') block('`gh api graphql` is not allowed.');
    continue;
  }

  if (READ_ONLY[cmd] && READ_ONLY[cmd].includes(sub)) continue;
  block(`\`gh ${cmd} ${sub || ''}\` is not on the read-only allowlist.`);
}

process.exit(0);
