#!/usr/bin/env bash
# Real git commits against the plain hook. Each fixture has its KEYGUARD:ALLOW marker stripped
# before staging, so the guard must block it; the allowed-line fixture keeps its marker and must pass.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); cd "$T"; git init -q; git config user.email ci@example.invalid; git config user.name keyguard-test
mkdir -p hooks && cp "$ROOT/hooks/pre-commit" "$ROOT/hooks/keyguard.mjs" hooks/ && git config core.hooksPath hooks
fail=0
expect() { # name expected(pass|block) rule
  if out=$(git commit -q -m "$1" 2>&1); then got=pass; else got=block; fi
  echo "\$ git commit -m '$1'"; echo "$out"
  if [ "$got" != "$2" ] || { [ -n "${3:-}" ] && ! grep -q "$3" <<<"$out"; }; then echo "TEST FAIL: $1 (wanted $2 ${3:-})"; fail=1; else echo "TEST OK: $1 -> $got"; fi
  git reset -q --hard 2>/dev/null; git clean -qfdx -e hooks >/dev/null; echo
}
strip() { sed -e 's/ *# *KEYGUARD:ALLOW//' -e 's/ *KEYGUARD:ALLOW//' "$ROOT/fixtures/$1"; }
cp "$ROOT/fixtures/clean.txt" clean.txt; git add clean.txt hooks; expect "clean commit" pass
strip sdk-keypair.json.fixture > agent-keypair.json; git add agent-keypair.json; expect "sdk keypair json" block KG001
strip cli-keypair.json.fixture > keys.txt; git add keys.txt; expect "cli keypair in .txt" block KG002
strip raw-seed.env.fixture > .env; git add -f .env; expect "raw seed in .env" block KG003
strip raw-seed.env.fixture > SEEDFILE; git add SEEDFILE; expect "raw seed in extensionless file" block KG003
mkdir -p .basedagents/keys; cp "$ROOT/fixtures/keys-path.fixture" .basedagents/keys/agent.json; git add -f .basedagents/keys/agent.json; expect "file under .basedagents/keys" block KG004
cp "$ROOT/fixtures/allowed-line.txt" allowed.txt; git add allowed.txt; expect "KEYGUARD:ALLOW escape" pass
# staged blob, not working tree: stage a key, then clean the working copy -> must still block
strip sdk-keypair.json.fixture > staged-only.json; git add staged-only.json; echo '{}' > staged-only.json; expect "staged blob scanned, not working tree" block KG001
exit $fail
