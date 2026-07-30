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
assert_file_contains "$output/control-smoke/result.tsv" $'^status\tplanned$' 'BENCHMARK_DRY_RUN: result records planned status'
assert_path_absent "$output/control-smoke/worktree" 'BENCHMARK_DRY_RUN: dry run does not create a worktree'

bad_profile="$TEST_TMP/unknown-host.conf"
printf '%s\n' 'host=unknown' 'model=fixture' 'workflow=control' 'sandbox=workspace-write' 'permission=standard' > "$bad_profile"
run_command bash "$runner" --profile "$bad_profile" --scenario "$scenario" --run-id unknown-host --output-root "$output" --dry-run
assert_nonzero 'BENCHMARK_PROFILE: unknown host is rejected before execution'
assert_contains "$(cat "$RUN_ERR")" 'unsupported host' 'BENCHMARK_PROFILE: host rejection explains the problem'

dangerous_profile="$TEST_TMP/dangerous.conf"
printf '%s\n' 'host=codex' 'model=fixture' 'workflow=control' 'sandbox=workspace-write' 'permission=dangerous' > "$dangerous_profile"
run_command bash "$runner" --profile "$dangerous_profile" --scenario "$scenario" --run-id dangerous --output-root "$output" --dry-run
assert_nonzero 'BENCHMARK_SAFETY: dangerous mode needs an external-sandbox attestation'
assert_contains "$(cat "$RUN_ERR")" 'WG_EXTERNAL_SANDBOX=1' 'BENCHMARK_SAFETY: dangerous rejection names the required attestation'

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
WG_CAPTURE="$TEST_TMP/codex-argv" PATH="$fake_bin:$PATH" bash "$REPO_DIR/benchmarks/adapters/codex.sh" "$TEST_TMP/worktree" fixture workspace-write standard "$prompt" "$TEST_TMP/final"
assert_file_contains "$TEST_TMP/codex-argv" '^--sandbox$' 'BENCHMARK_CODEX_ADAPTER: standard mode passes an explicit sandbox'
assert_file_contains "$TEST_TMP/codex-argv" '^workspace-write$' 'BENCHMARK_CODEX_ADAPTER: configured sandbox is forwarded'
assert_file_contains "$TEST_TMP/codex-argv" '^--ignore-user-config$' 'BENCHMARK_CODEX_ADAPTER: temporary home does not inherit ambient config'
assert_file_contains "$TEST_TMP/codex-argv" '^--json$' 'BENCHMARK_CODEX_ADAPTER: event evidence is requested'

finish_tests
