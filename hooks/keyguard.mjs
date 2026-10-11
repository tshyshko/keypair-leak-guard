#!/usr/bin/env node
// keyguard: blocks committed BasedAgents keypairs.
// Modes:
//   (no args) | --staged   scan staged blobs (git diff --cached --name-only --diff-filter=ACMRT; content via `git show :path`)
//   --files <p...>         scan given paths, reading the STAGED blob when the path is staged (pre-commit framework)
//   --all                  scan every tracked file (git ls-files) at its index blob - used in CI
// Gitlinks (submodule entries, mode 160000) have no blob to read: they are skipped and counted (gitlinks_skipped=N).
// Escape hatch (the only one): a line containing KEYGUARD:ALLOW is not reported.
// The path rule (.basedagents/keys/*) has no escape: key directories must never be committed.
// Nothing is skipped silently: every file is scanned as text (binary included); any file that cannot be
// read is reported and makes the run fail (exit 3). Exit 0 = clean, 1 = findings, 3 = unreadable files.
import { execFileSync } from 'node:child_process';

const git = (args, opts = {}) => execFileSync('git', args, { maxBuffer: 1 << 30, ...opts });
const ALLOW = 'KEYGUARD:ALLOW';
const AGENT_ID = /\bag_[1-9A-HJ-NP-Za-km-z]{20,60}\b/;
const HEX64 = /(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])/;
// KG003 exemptions: known PUBLIC fields are removed from the line before looking for a raw seed:
// "public_key" / "publicKey" / "public_key_hex" values, any "*_hash" / "hash" value, and 0x-prefixed hex (EVM tx hashes, addresses).
const PUBLIC_FIELD = /"(?:public_?[kK]ey(?:_hex)?|[A-Za-z0-9_]*_hash|hash)"\s*:\s*"[^"]*"/g;
const OX_HEX = /\b0x[0-9a-fA-F]+/g;
export const stripPublic = (l) => l.replace(PUBLIC_FIELD, '"public":""').replace(OX_HEX, '0x');

export const RULES = [
  { id: 'KG001-sdk-private-key-hex',
    msg: 'BasedAgents SDK keypair JSON: "private_key_hex" holding a 64-hex Ed25519 seed',
    re: /"private_key_hex"\s*:\s*"[0-9a-fA-F]{64}(?:[0-9a-fA-F]{64})?"/ },
  { id: 'KG002-cli-private-key',
    msg: 'BasedAgents npm CLI keypair JSON: "privateKey" holding hex or base64 key material',
    re: /"privateKey"\s*:\s*"(?:[0-9a-fA-F]{64}(?:[0-9a-fA-F]{64})?|[A-Za-z0-9+/]{43,88}={0,2})"/ },
  { id: 'KG003-raw-seed-near-agent-id',
    msg: 'raw 64-hex seed within 3 lines of a BasedAgents agent id (ag_...)',
    near: true },
];
export const PATH_RULE = { id: 'KG004-basedagents-keys-path',
  msg: 'file lives under .basedagents/keys/ - key directories must never be committed',
  re: /(^|\/)\.basedagents\/keys\// };

export function scanText(path, text) {
  const out = [];
  if (PATH_RULE.re.test(path)) out.push({ path, line: 0, rule: PATH_RULE.id, msg: PATH_RULE.msg });
  const lines = text.split(/\r?\n/);
  lines.forEach((l, i) => {
    if (l.includes(ALLOW)) return;
    for (const r of RULES) {
      let hit = false;
      if (r.near) {
        if (HEX64.test(stripPublic(l)) && !/"private_key_hex"|"privateKey"/.test(l)) {
          const win = lines.slice(Math.max(0, i - 3), i + 4).join('\n');
          hit = AGENT_ID.test(win);
        }
      } else hit = r.re.test(l);
      if (hit) out.push({ path, line: i + 1, rule: r.id, msg: r.msg });
    }
  });
  return out;
}

function staged() {
  return git(['diff', '--cached', '--name-only', '--diff-filter=ACMRT', '-z']).toString().split('\0').filter(Boolean);
}
function tracked() { return git(['ls-files', '-z']).toString().split('\0').filter(Boolean); }
// path -> index mode, to recognise gitlinks (160000)
function indexModes() {
  const m = new Map();
  try {
    for (const e of git(['ls-files', '-s', '-z'], { stdio: ['ignore', 'pipe', 'ignore'] }).toString().split('\0').filter(Boolean)) {
      const tab = e.indexOf('\t'); m.set(e.slice(tab + 1), e.slice(0, 6));
    }
  } catch { /* not a git repo: --files on plain paths */ }
  return m;
}
function readIndex(p) { return git(['show', ':' + p], { stdio: ['ignore', 'pipe', 'pipe'] }).toString('latin1'); }

function main(argv) {
  let mode = 'staged', files = [];
  if (argv[0] === '--all') mode = 'all';
  else if (argv[0] === '--files') { mode = 'files'; files = argv.slice(1); }
  else if (argv[0] && argv[0] !== '--staged') { files = argv; mode = 'files'; }
  if (mode === 'staged') files = staged();
  if (mode === 'all') files = tracked();
  const findings = [], unreadable = [], modes = indexModes();
  const gitlinks = files.filter((f) => modes.get(f) === '160000');
  files = files.filter((f) => modes.get(f) !== '160000');
  for (const f of files) {
    let text;
    try { text = readIndex(f); }
    catch { try { text = (await_fs()).readFileSync(f, 'latin1'); } catch (e) { unreadable.push(f); continue; } }
    findings.push(...scanText(f, text));
  }
  for (const x of findings)
    console.error(`keyguard: BLOCKED ${x.path}${x.line ? ':' + x.line : ''} [${x.rule}] ${x.msg} (value not shown)`);
  for (const u of unreadable) console.error(`keyguard: ERROR could not read ${u} - refusing to skip it silently`);
  console.error(`keyguard: mode=${mode} scanned=${files.length - unreadable.length}/${files.length} findings=${findings.length} unreadable=${unreadable.length} gitlinks_skipped=${gitlinks.length}`);
  if (findings.length) {
    console.error('keyguard: remove the key (and rotate it if it was real). For a synthetic test fixture, add KEYGUARD:ALLOW on that same line.');
    return 1;
  }
  return unreadable.length ? 3 : 0;
}
import * as fs from 'node:fs';
function await_fs() { return fs; }
import { fileURLToPath } from 'node:url';
if (process.argv[1] && fileURLToPath(import.meta.url) === (await import('node:fs')).realpathSync(process.argv[1]))
  process.exit(main(process.argv.slice(2)));
