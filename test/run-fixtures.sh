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
# --- revision 3 cases ---
# rename (R): commit a placeholder example, git mv it to the real name, put a 64-hex value in private_key_hex -> must block
cp "$ROOT/fixtures/agent-keypair.example.json" agent-keypair.example.json; git add agent-keypair.example.json; expect "placeholder example keypair" pass
git mv agent-keypair.example.json agent-keypair.json
sed -i 's/<64 hex chars - never commit>/deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef/' agent-keypair.json; git add agent-keypair.json
echo "\$ git diff --cached --name-status -M"; git diff --cached --name-status -M
expect "rename example -> agent-keypair.json with a 64-hex private_key_hex" block KG001
# pure rename into .basedagents/keys/ (no content change) -> must block KG004
mkdir -p .basedagents/keys; git mv agent-keypair.example.json .basedagents/keys/agent.json
echo "\$ git diff --cached --name-status -M"; git diff --cached --name-status -M
expect "git mv into .basedagents/keys/" block KG004
# type change (T): a committed symlink replaced by a regular file holding a key -> must block
ln -s clean.txt linked.json; git add linked.json; expect "symlink (clean)" pass
rm linked.json; strip sdk-keypair.json.fixture > linked.json; git add linked.json
echo "\$ git diff --cached --name-status"; git diff --cached --name-status
expect "type change symlink -> file with key" block KG001
# public chain data: GET /v1/chain/latest (entry_hash, previous_hash, public_key next to agent_id) -> must pass
cp "$ROOT/fixtures/chain-latest.public.json" chain-latest.json; git add chain-latest.json; expect "public /v1/chain/latest response" pass
# gitlink (submodule, mode 160000): commit passes and --all skips + counts it instead of exiting 3
git update-index --add --cacheinfo "160000,$(git rev-parse HEAD),vendor/sub"; expect "add submodule gitlink" pass
echo '$ node hooks/keyguard.mjs --all'; out=$(node hooks/keyguard.mjs --all 2>&1); rc=$?; echo "$out"; echo "exit=$rc"
if [ $rc -eq 0 ] && grep -q 'gitlinks_skipped=1' <<<"$out"; then echo "TEST OK: --all with a gitlink -> exit 0, gitlinks_skipped=1"; else echo "TEST FAIL: --all with a gitlink"; fail=1; fi
echo
# README cp install: fresh repo WITHOUT hooks/, hook files copied into .git/hooks/
F=$(mktemp -d); cd "$F"; git init -q; git config user.email ci@example.invalid; git config user.name keyguard-test
echo '$ cp hooks/pre-commit hooks/keyguard.mjs .git/hooks/   # fresh repo, no hooks/ dir, no core.hooksPath'
cp "$ROOT/hooks/pre-commit" "$ROOT/hooks/keyguard.mjs" .git/hooks/; ls hooks 2>/dev/null || echo "(no hooks/ dir in this repo)"
cp "$ROOT/fixtures/clean.txt" clean.txt; git add clean.txt; expect "cp install: clean commit in a fresh repo" pass
strip sdk-keypair.json.fixture > agent-keypair.json; git add agent-keypair.json; expect "cp install: sdk keypair json" block KG001
echo "fixtures result: fail=$fail"
exit $fail
