#!/usr/bin/env bash
# Benchmark runner contracts remain offline: no model, credential, or worktree launch.
set -u
. "$(dirname "$0")/testlib.sh"

runner="$REPO_DIR/benchmarks/run.sh"
profile="$REPO_DIR/benchmarks/profiles/codex-control.conf"
scenario="$REPO_DIR/benchmarks/scenarios/refresh-status"
output="$TEST_TMP/results"

run_command bash "$runner" --profile "$profile" --scenario "$scenario" --run-id control-smoke --output-root "$output" --dry-run
assert_success 'BENCHMARK_DRY_RUN: valid Codex profile creates a reproducible plan without a model process'
assert_file_contains "$output/control-smoke/manifest.tsv" $'^host\tcodex$' 'BENCHMARK_DRY_RUN: manifest records host'
assert_file_contains "$output/control-smoke/manifest.tsv" $'^workflow\tcontrol$' 'BENCHMARK_DRY_RUN: manifest records workflow'
assert_file_contains "$output/control-smoke/manifest.tsv" $'^approval_policy\tnever$' 'BENCHMARK_DRY_RUN: manifest records unattended approval policy'
assert_file_contains "$output/control-smoke/manifest.tsv" $'^evaluator_sha256\t[0-9a-f]{64}$' 'BENCHMARK_DRY_RUN: manifest identifies the evaluator content'
assert_file_contains "$output/control-smoke/manifest.tsv" $'^runtime_home\tephemeral$' 'BENCHMARK_DRY_RUN: manifest records non-retention of runtime home'
assert_file_contains "$output/control-smoke/evaluator.sh" '^#!/usr/bin/env bash$' 'BENCHMARK_DRY_RUN: retained evaluator artifact is executable evidence'
assert_file_contains "$output/control-smoke/result.tsv" $'^status\tplanned$' 'BENCHMARK_DRY_RUN: result records planned status'
assert_path_absent "$output/control-smoke/worktree" 'BENCHMARK_DRY_RUN: dry run does not create a worktree'

bad_profile="$TEST_TMP/unknown-host.conf"
printf '%s\n' 'host=unknown' 'model=fixture' 'workflow=control' > "$bad_profile"
run_command bash "$runner" --profile "$bad_profile" --scenario "$scenario" --run-id unknown-host --output-root "$output" --dry-run
assert_nonzero 'BENCHMARK_PROFILE: unknown host is rejected before execution'
assert_contains "$(cat "$RUN_ERR")" 'unsupported host' 'BENCHMARK_PROFILE: host rejection explains the problem'

unsafe_profile="$TEST_TMP/unsafe.conf"
printf '%s\n' 'host=codex' 'model=fixture' 'workflow=control' 'sandbox=danger-full-access' > "$unsafe_profile"
run_command bash "$runner" --profile "$unsafe_profile" --scenario "$scenario" --run-id unsafe --output-root "$output" --dry-run
assert_nonzero 'BENCHMARK_SAFETY: profile cannot select unsandboxed execution'
assert_contains "$(cat "$RUN_ERR")" 'unknown profile key: sandbox' 'BENCHMARK_SAFETY: sandbox selection is not a profile capability'

fake_bin="$TEST_TMP/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$WG_CAPTURE"
cat >/dev/null
EOF
chmod +x "$fake_bin/codex"
prompt="$TEST_TMP/prompt"
printf '%s\n' 'fixture prompt' > "$prompt"
WG_CAPTURE="$TEST_TMP/codex-argv" PATH="$fake_bin:$PATH" bash "$REPO_DIR/benchmarks/adapters/codex.sh" "$TEST_TMP/worktree" fixture "$prompt" "$TEST_TMP/final"
assert_file_contains "$TEST_TMP/codex-argv" '^--sandbox$' 'BENCHMARK_CODEX_ADAPTER: standard mode passes an explicit sandbox'
assert_file_contains "$TEST_TMP/codex-argv" '^workspace-write$' 'BENCHMARK_CODEX_ADAPTER: configured sandbox is forwarded'
assert_file_contains "$TEST_TMP/codex-argv" '^-c$' 'BENCHMARK_CODEX_ADAPTER: unattended approval policy is passed explicitly'
assert_file_contains "$TEST_TMP/codex-argv" '^approval_policy="never"$' 'BENCHMARK_CODEX_ADAPTER: commands never pause for approval'
assert_file_contains "$TEST_TMP/codex-argv" '^--ignore-user-config$' 'BENCHMARK_CODEX_ADAPTER: temporary home does not inherit ambient config'
assert_file_contains "$TEST_TMP/codex-argv" '^--json$' 'BENCHMARK_CODEX_ADAPTER: event evidence is requested'

fixture_source="$TEST_TMP/execute-source"
git clone --quiet --no-local "$REPO_DIR" "$fixture_source"
cp "$REPO_DIR/benchmarks/run.sh" "$fixture_source/benchmarks/run.sh"
cp "$REPO_DIR/benchmarks/adapters/codex.sh" "$fixture_source/benchmarks/adapters/codex.sh"
cp "$REPO_DIR/benchmarks/profiles/codex-control.conf" "$fixture_source/benchmarks/profiles/codex-control.conf"
mkdir -p "$fixture_source/benchmarks/scenarios/fixture"
printf '%s\n' 'fixture prompt' > "$fixture_source/benchmarks/scenarios/fixture/prompt.txt"
cat > "$fixture_source/benchmarks/scenarios/fixture/evaluate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${FIXTURE_EVALUATOR_LEAK:-}" = 1 ]; then
  printf '%s\n' "$FIXTURE_TOKEN"
  exit 1
fi
[ -z "$(git -C "$1" status --porcelain)" ]
EOF
chmod +x "$fixture_source/benchmarks/scenarios/fixture/evaluate.sh"
git -C "$fixture_source" add benchmarks
git -C "$fixture_source" -c user.name='Benchmark Test' -c user.email='benchmark@example.invalid' commit -m 'fixture benchmark runner' >/dev/null

execute_bin="$TEST_TMP/execute-bin"
mkdir -p "$execute_bin"
cat > "$execute_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
worktree=
while [ "$#" -gt 0 ]; do
  if [ "$1" = --cd ]; then
    worktree=$2
    shift 2
  else
    shift
  fi
done
cat >/dev/null
git -C "$worktree" -c user.name='Benchmark Agent' -c user.email='agent@example.invalid' commit --allow-empty -m 'fixture agent result' >/dev/null
EOF
chmod +x "$execute_bin/codex"
test_token="fixture-secret-token-$RANDOM"
printf '{"token":"%s"}\n' "$test_token" > "$TEST_TMP/auth.json"
execute_output="$TEST_TMP/execute-results"
run_command env PATH="$execute_bin:$PATH" WG_CODEX_AUTH_SOURCE="$TEST_TMP/auth.json" bash "$fixture_source/benchmarks/run.sh" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id execute-smoke --output-root "$execute_output" --execute
assert_success 'BENCHMARK_EXECUTE: fixed sandbox runner completes an unattended fixture run'
assert_path_absent "$execute_output/execute-smoke/home" 'BENCHMARK_EXECUTE: retained evidence never includes a runtime home'
assert_path_absent "$execute_output/execute-smoke/auth.json" 'BENCHMARK_EXECUTE: supplied credentials are not retained as run evidence'
assert_file_contains "$execute_output/execute-smoke/manifest.tsv" $'^runtime_home\tephemeral$' 'BENCHMARK_EXECUTE: manifest distinguishes retained evidence from ephemeral credentials'

leaky_bin="$TEST_TMP/leaky-bin"
mkdir -p "$leaky_bin"
cat > "$leaky_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
worktree=
while [ "$#" -gt 0 ]; do
  if [ "$1" = --cd ]; then
    worktree=$2
    shift 2
  else
    shift
  fi
done
cat >/dev/null
cp "$CODEX_HOME/auth.json" "$worktree/leaked-auth.json"
git -C "$worktree" -c user.name='Benchmark Agent' -c user.email='agent@example.invalid' add leaked-auth.json
git -C "$worktree" -c user.name='Benchmark Agent' -c user.email='agent@example.invalid' commit -m 'fixture leaked credential' >/dev/null
EOF
chmod +x "$leaky_bin/codex"
leak_output="$TEST_TMP/leak-results"
run_command env PATH="$leaky_bin:$PATH" WG_CODEX_AUTH_SOURCE="$TEST_TMP/auth.json" bash "$fixture_source/benchmarks/run.sh" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id leak-smoke --output-root "$leak_output" --execute
assert_nonzero 'BENCHMARK_EXECUTE: retained credential output rejects the run'
assert_path_absent "$leak_output/leak-smoke" 'BENCHMARK_EXECUTE: rejected credential evidence is discarded in full'

agent_failure_bin="$TEST_TMP/agent-failure-bin"
mkdir -p "$agent_failure_bin"
cp "$leaky_bin/codex" "$agent_failure_bin/codex"
printf '%s\n' 'exit 7' >> "$agent_failure_bin/codex"
chmod +x "$agent_failure_bin/codex"
agent_failure_output="$TEST_TMP/agent-failure-results"
run_command env PATH="$agent_failure_bin:$PATH" WG_CODEX_AUTH_SOURCE="$TEST_TMP/auth.json" bash "$fixture_source/benchmarks/run.sh" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id agent-failure-smoke --output-root "$agent_failure_output" --execute
assert_nonzero 'BENCHMARK_EXECUTE: failed agent output is scanned for credential leaks'
assert_path_absent "$agent_failure_output/agent-failure-smoke" 'BENCHMARK_EXECUTE: failed agent credential evidence is discarded in full'

evaluator_failure_output="$TEST_TMP/evaluator-failure-results"
run_command env PATH="$execute_bin:$PATH" WG_CODEX_AUTH_SOURCE="$TEST_TMP/auth.json" FIXTURE_EVALUATOR_LEAK=1 FIXTURE_TOKEN="$test_token" bash "$fixture_source/benchmarks/run.sh" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id evaluator-failure-smoke --output-root "$evaluator_failure_output" --execute
assert_nonzero 'BENCHMARK_EXECUTE: failed evaluator output is scanned for credential leaks'
assert_path_absent "$evaluator_failure_output/evaluator-failure-smoke" 'BENCHMARK_EXECUTE: failed evaluator credential evidence is discarded in full'

finish_tests
