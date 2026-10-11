# keypair-leak-guard

Blocks committed BasedAgents keypairs. One scanner (`hooks/keyguard.mjs`, Node >= 18, no dependencies), shipped three ways:

| Way | File | What it scans |
|---|---|---|
| Plain git hook | `hooks/pre-commit` | staged blobs: `git diff --cached --name-only --diff-filter=ACMRT` (added, copied, modified, **renamed**, **type-changed**), content via `git show :path` (not the working tree) |
| pre-commit framework | `.pre-commit-config.yaml` (this repo, `repo: local`) / `.pre-commit-hooks.yaml` (other repos, `language: script`) | every staged file passed by the framework, no type/extension filter |
| GitHub Action (composite) | `action.yml` | `--all`: every tracked file in `git ls-files`, no cap, no extension allowlist; submodule gitlinks (mode 160000) have no blob and are skipped and counted as `gitlinks_skipped=N` |

Install the plain hook, either way:

- `git config core.hooksPath hooks` (inside a clone of this repo), or
- in any repo: `cp hooks/pre-commit hooks/keyguard.mjs .git/hooks/`. The hook loads `keyguard.mjs` from its own directory (`$(dirname "$0")`), so the target repo does not need a `hooks/` folder.

pre-commit framework, in another repo's `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/tshyshko/keypair-leak-guard
    rev: <commit sha>
    hooks:
      - id: keypair-leak-guard
```

The hook is `language: script` (`entry: hooks/keyguard.mjs --files`, run from the cloned hook repo); it needs `node` >= 18 on PATH.
CI: `- uses: actions/checkout@<sha>` then `- uses: tshyshko/keypair-leak-guard@<sha>`.

## Rules

| ID | Matches | Why it is anchored this way |
|---|---|---|
| KG001-sdk-private-key-hex | `"private_key_hex": "<64 or 128 hex>"` | exact SDK keypair JSON field name + exact Ed25519 seed/secret length |
| KG002-cli-private-key | `"privateKey": "<64/128 hex or 43-88 char base64>"` | exact npm CLI keypair field + key-sized value only |
| KG003-raw-seed-near-agent-id | a standalone 64-hex token within 3 lines of an `ag_<base58>` agent id, after known public fields are removed | bare 64-hex alone is too common (sha256 hashes, tx hashes); proximity to an agent id is what makes it a seed. Public values are exempt: JSON `public_key` / `publicKey` / `public_key_hex`, any `*_hash` / `hash` field, and `0x`-prefixed hex. So the public `GET /v1/chain/latest` response (`entry_hash`, `previous_hash`, `public_key` next to `agent_id`) passes (`fixtures/chain-latest.public.json`). |
| KG004-basedagents-keys-path | any staged/tracked file whose **path** is under `.basedagents/keys/` | the CLI key directory; never legitimately committed |

Messages name the file, line number and rule ID, and never print the matched value.

## Escape hatch (one, consistent)

Put `KEYGUARD:ALLOW` on the **same line** as a synthetic fixture value. That line is not reported; nothing else is exempt.
There is no per-file or per-directory exemption, and KG004 (the path rule) cannot be escaped. Example: `fixtures/allowed-line.txt`.

## Nothing skipped silently

Every file is read and scanned as text (binary files included, decoded as latin1). A file that cannot be read is
printed as `ERROR could not read <path>` and the run exits 3. Every run ends with `scanned=N/M findings=F unreadable=U`.
Exit codes: 0 clean, 1 findings, 3 unreadable files. Submodule gitlinks are not files; they are skipped and counted (`gitlinks_skipped=N`).

## Fixtures

`fixtures/` holds obviously synthetic values (`deadbeef…`, `c0ffee00…`, `FAKEFAKE…`, agent id `ag_FAKExSyntheticxTestxAgentxNotRea`).
Each fixture line carries `KEYGUARD:ALLOW` so this repo's own CI stays green; `test/run-fixtures.sh` strips the marker,
stages the fixture in a throwaway repo and makes a **real `git commit`**, which the hook must block with the right rule.
It also covers: a `git mv` of a placeholder `agent-keypair.example.json` to `agent-keypair.json` with a 64-hex `private_key_hex` (rename, must block KG001);
a pure `git mv` into `.basedagents/keys/` (must block KG004); a symlink replaced by a key file (type change, must block KG001);
the public `/v1/chain/latest` response (must pass); a submodule gitlink (commit passes, `--all` exits 0 with `gitlinks_skipped=1`);
and the README `cp` install in a fresh repo with no `hooks/` folder (clean commit passes, keypair blocked).

`fixtures/chain-latest.public.json` is an unmodified public API response (no secrets; every 64-hex value in it is a public key or a hash).
