# keypair-leak-guard

Blocks committed BasedAgents keypairs. One scanner (`hooks/keyguard.mjs`, Node >= 18, no dependencies), shipped three ways:

| Way | File | What it scans |
|---|---|---|
| Plain git hook | `hooks/pre-commit` | staged blobs: `git diff --cached --name-only --diff-filter=ACM`, content via `git show :path` (not the working tree) |
| pre-commit framework | `.pre-commit-config.yaml` (consumer) / `.pre-commit-hooks.yaml` (hook repo) | every staged file passed by the framework, no type/extension filter |
| GitHub Action (composite) | `action.yml` | `--all`: every tracked file in `git ls-files`, no cap, no extension allowlist |

Install the plain hook: `git config core.hooksPath hooks` (or `cp hooks/pre-commit hooks/keyguard.mjs .git/hooks/`; the hook calls `hooks/keyguard.mjs` from the repo root).
CI: `- uses: actions/checkout@<sha>` then `- uses: tshyshko/keypair-leak-guard@<sha>`.

## Rules

| ID | Matches | Why it is anchored this way |
|---|---|---|
| KG001-sdk-private-key-hex | `"private_key_hex": "<64 or 128 hex>"` | exact SDK keypair JSON field name + exact Ed25519 seed/secret length |
| KG002-cli-private-key | `"privateKey": "<64/128 hex or 43-88 char base64>"` | exact npm CLI keypair field + key-sized value only |
| KG003-raw-seed-near-agent-id | a standalone 64-hex token within 3 lines of an `ag_<base58>` agent id | bare 64-hex alone is too common (sha256 hashes, tx hashes); proximity to an agent id is what makes it a seed |
| KG004-basedagents-keys-path | any staged/tracked file whose **path** is under `.basedagents/keys/` | the CLI key directory; never legitimately committed |

Messages name the file, line number and rule ID, and never print the matched value.

## Escape hatch (one, consistent)

Put `KEYGUARD:ALLOW` on the **same line** as a synthetic fixture value. That line is not reported; nothing else is exempt.
There is no per-file or per-directory exemption, and KG004 (the path rule) cannot be escaped. Example: `fixtures/allowed-line.txt`.

## Nothing skipped silently

Every file is read and scanned as text (binary files included, decoded as latin1). A file that cannot be read is
printed as `ERROR could not read <path>` and the run exits 3. Every run ends with `scanned=N/M findings=F unreadable=U`.
Exit codes: 0 clean, 1 findings, 3 unreadable files.

## Fixtures

`fixtures/` holds obviously synthetic values (`deadbeef…`, `c0ffee00…`, `FAKEFAKE…`, agent id `ag_FAKExSyntheticxTestxAgentxNotRea`).
Each fixture line carries `KEYGUARD:ALLOW` so this repo's own CI stays green; `test/run-fixtures.sh` strips the marker,
stages the fixture in a throwaway repo and makes a **real `git commit`**, which the hook must block with the right rule.
