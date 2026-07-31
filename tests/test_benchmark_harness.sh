#!/usr/bin/env bash
# Benchmark runner contracts remain offline: no model, credential, or worktree launch.
set -u
. "$(dirname "$0")/testlib.sh"

runner="$REPO_DIR/benchmarks/run.sh"
aggregator="$REPO_DIR/benchmarks/aggregate.sh"
profile="$REPO_DIR/benchmarks/profiles/codex-control.conf"
scenario="$REPO_DIR/benchmarks/scenarios/refresh-status"
output="$TEST_TMP/results"

make_ledger() {
  ledger=$1
  source_root=$2
  ledger_profile=$3
  ledger_scenario=$4
  ledger_run_id=$5
  ledger_arm=${6:-control}
  ledger_repeat=${7:-1}
  ledger_order=${8:-1}
  ledger_timeout=${9:-5}
  printf '%s\n' $'cohort_id\tbase_commit\tprofile_sha256\tprompt_sha256\tevaluator_sha256\tadapter_sha256\tscenario_id\tarm\trepeat\trun_id\tplanned_order\ttimeout_seconds\toperator_action' > "$ledger"
  printf 'fixture-cohort\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tnone\n' \
    "$(git -C "$source_root" rev-parse HEAD)" \
    "$(shasum -a 256 "$ledger_profile" | awk '{print $1}')" \
    "$(shasum -a 256 "$ledger_scenario/prompt.txt" | awk '{print $1}')" \
    "$(shasum -a 256 "$ledger_scenario/evaluate.sh" | awk '{print $1}')" \
    "$(shasum -a 256 "$source_root/benchmarks/adapters/codex.sh" | awk '{print $1}')" \
    "$(basename "$ledger_scenario")" "$ledger_arm" "$ledger_repeat" "$ledger_run_id" "$ledger_order" "$ledger_timeout" >> "$ledger"
  ledger_line=2
  while [ "$ledger_line" -le 12 ]; do
    printf 'fixture-cohort\t%s\t%s\t%s\t%s\t%s\taux-%s\tcontrol\t1\tfixture-unused-%s\t%s\t%s\tnone\n' \
      "$(git -C "$source_root" rev-parse HEAD)" \
      "$(shasum -a 256 "$ledger_profile" | awk '{print $1}')" \
      "$(shasum -a 256 "$ledger_scenario/prompt.txt" | awk '{print $1}')" \
      "$(shasum -a 256 "$ledger_scenario/evaluate.sh" | awk '{print $1}')" \
      "$(shasum -a 256 "$source_root/benchmarks/adapters/codex.sh" | awk '{print $1}')" \
      "$ledger_line" "$ledger_line" "$ledger_line" "$ledger_timeout" >> "$ledger"
    ledger_line=$((ledger_line + 1))
  done
}

smoke_ledger="$TEST_TMP/smoke-ledger.tsv"
make_ledger "$smoke_ledger" "$REPO_DIR" "$profile" "$scenario" control-smoke

run_command bash "$runner" --ledger "$smoke_ledger" --profile "$profile" --scenario "$scenario" --run-id control-smoke --output-root "$output" --dry-run
assert_success 'BENCHMARK_DRY_RUN: valid Codex profile creates a reproducible plan without a model process'
assert_file_contains "$output/control-smoke/manifest.tsv" $'^host\tcodex$' 'BENCHMARK_DRY_RUN: manifest records host'
assert_file_contains "$output/control-smoke/manifest.tsv" $'^workflow\tcontrol$' 'BENCHMARK_DRY_RUN: manifest records workflow'
assert_file_contains "$output/control-smoke/manifest.tsv" $'^approval_policy\tnever$' 'BENCHMARK_DRY_RUN: manifest records unattended approval policy'
assert_file_contains "$output/control-smoke/manifest.tsv" $'^evaluator_sha256\t[0-9a-f]{64}$' 'BENCHMARK_DRY_RUN: manifest identifies the evaluator content'
assert_file_contains "$output/control-smoke/manifest.tsv" $'^runtime_home\tephemeral$' 'BENCHMARK_DRY_RUN: manifest records non-retention of runtime home'
assert_file_contains "$output/control-smoke/evaluator.sh" '^#!/usr/bin/env bash$' 'BENCHMARK_DRY_RUN: retained evaluator artifact is executable evidence'
assert_file_contains "$output/control-smoke/result.tsv" $'^disposition\tplanned$' 'BENCHMARK_DRY_RUN: result records planned disposition'
assert_file_contains "$output/control-smoke/result.tsv" $'^acceptance\tfalse$' 'BENCHMARK_DRY_RUN: planned run is not accepted'
assert_path_absent "$output/control-smoke/worktree" 'BENCHMARK_DRY_RUN: dry run does not create a worktree'

bad_profile="$TEST_TMP/unknown-host.conf"
printf '%s\n' 'host=unknown' 'model=fixture' 'workflow=control' > "$bad_profile"
bad_ledger="$TEST_TMP/bad-ledger.tsv"
make_ledger "$bad_ledger" "$REPO_DIR" "$bad_profile" "$scenario" unknown-host
run_command bash "$runner" --ledger "$bad_ledger" --profile "$bad_profile" --scenario "$scenario" --run-id unknown-host --output-root "$output" --dry-run
assert_nonzero 'BENCHMARK_PROFILE: unknown host is rejected before execution'
assert_contains "$(cat "$RUN_ERR")" 'unsupported host' 'BENCHMARK_PROFILE: host rejection explains the problem'

unsafe_profile="$TEST_TMP/unsafe.conf"
printf '%s\n' 'host=codex' 'model=fixture' 'workflow=control' 'sandbox=danger-full-access' > "$unsafe_profile"
unsafe_ledger="$TEST_TMP/unsafe-ledger.tsv"
make_ledger "$unsafe_ledger" "$REPO_DIR" "$unsafe_profile" "$scenario" unsafe
run_command bash "$runner" --ledger "$unsafe_ledger" --profile "$unsafe_profile" --scenario "$scenario" --run-id unsafe --output-root "$output" --dry-run
assert_nonzero 'BENCHMARK_SAFETY: profile cannot select unsandboxed execution'
assert_contains "$(cat "$RUN_ERR")" 'unknown profile key: sandbox' 'BENCHMARK_SAFETY: sandbox selection is not a profile capability'

workflow_mismatch_ledger="$TEST_TMP/workflow-mismatch-ledger.tsv"
make_ledger "$workflow_mismatch_ledger" "$REPO_DIR" "$profile" "$scenario" workflow-mismatch treatment
run_command bash "$runner" --ledger "$workflow_mismatch_ledger" --profile "$profile" --scenario "$scenario" --run-id workflow-mismatch --output-root "$output" --dry-run
assert_nonzero 'BENCHMARK_LEDGER: arm must bind the selected profile workflow'
assert_contains "$(cat "$RUN_ERR")" 'ledger arm does not match profile workflow' 'BENCHMARK_LEDGER: workflow mismatch explains the rejection'

over_limit_ledger="$TEST_TMP/over-limit-ledger.tsv"
make_ledger "$over_limit_ledger" "$REPO_DIR" "$profile" "$scenario" over-limit
awk -F '\t' 'BEGIN { OFS = "\t" } NR == 2 { $12 = 3601 } { print }' "$over_limit_ledger" > "$over_limit_ledger.next"
mv "$over_limit_ledger.next" "$over_limit_ledger"
run_command bash "$runner" --ledger "$over_limit_ledger" --profile "$profile" --scenario "$scenario" --run-id over-limit --output-root "$output" --dry-run
assert_nonzero 'BENCHMARK_LEDGER: over-limit timeout is rejected'

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
cp "$REPO_DIR/benchmarks/aggregate.sh" "$fixture_source/benchmarks/aggregate.sh"
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
if [ "${FIXTURE_EVALUATOR_HANG:-}" = 1 ]; then
  sleep 30 &
  printf '%s\n' "$!" > "$FIXTURE_EVALUATOR_CHILD_PID"
  wait
fi
[ -z "$(git -C "$1" status --porcelain)" ]
EOF
chmod +x "$fixture_source/benchmarks/scenarios/fixture/evaluate.sh"
git -C "$fixture_source" add benchmarks
git -C "$fixture_source" -c user.name='Benchmark Test' -c user.email='benchmark@example.invalid' commit -m 'fixture benchmark runner' >/dev/null
printf '%s\n' 'host=codex' 'model=fixture' 'workflow=writing-goals' > "$fixture_source/benchmarks/profiles/codex-writing-goals.conf"
cat > "$fixture_source/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 30 &
printf '%s\n' "$!" > "$FIXTURE_SETUP_CHILD_PID"
wait
EOF
chmod +x "$fixture_source/install.sh"
git -C "$fixture_source" add benchmarks/profiles/codex-writing-goals.conf install.sh
git -C "$fixture_source" -c user.name='Benchmark Test' -c user.email='benchmark@example.invalid' commit -m 'fixture slow install' >/dev/null

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
execute_ledger="$TEST_TMP/execute-ledger.tsv"
make_ledger "$execute_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-control.conf" "$fixture_source/benchmarks/scenarios/fixture" execute-smoke
run_command env PATH="$execute_bin:$PATH" WG_CODEX_AUTH_SOURCE="$TEST_TMP/auth.json" bash "$fixture_source/benchmarks/run.sh" --ledger "$execute_ledger" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id execute-smoke --output-root "$execute_output" --execute
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
leak_ledger="$TEST_TMP/leak-ledger.tsv"
make_ledger "$leak_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-control.conf" "$fixture_source/benchmarks/scenarios/fixture" leak-smoke
run_command env PATH="$leaky_bin:$PATH" WG_CODEX_AUTH_SOURCE="$TEST_TMP/auth.json" bash "$fixture_source/benchmarks/run.sh" --ledger "$leak_ledger" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id leak-smoke --output-root "$leak_output" --execute
assert_nonzero 'BENCHMARK_EXECUTE: retained credential output rejects the run'
assert_path_absent "$leak_output/leak-smoke" 'BENCHMARK_EXECUTE: rejected credential evidence is discarded in full'

agent_failure_bin="$TEST_TMP/agent-failure-bin"
mkdir -p "$agent_failure_bin"
cp "$leaky_bin/codex" "$agent_failure_bin/codex"
printf '%s\n' 'exit 7' >> "$agent_failure_bin/codex"
chmod +x "$agent_failure_bin/codex"
agent_failure_output="$TEST_TMP/agent-failure-results"
agent_failure_ledger="$TEST_TMP/agent-failure-ledger.tsv"
make_ledger "$agent_failure_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-control.conf" "$fixture_source/benchmarks/scenarios/fixture" agent-failure-smoke
run_command env PATH="$agent_failure_bin:$PATH" WG_CODEX_AUTH_SOURCE="$TEST_TMP/auth.json" bash "$fixture_source/benchmarks/run.sh" --ledger "$agent_failure_ledger" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id agent-failure-smoke --output-root "$agent_failure_output" --execute
assert_nonzero 'BENCHMARK_EXECUTE: failed agent output is scanned for credential leaks'
assert_path_absent "$agent_failure_output/agent-failure-smoke" 'BENCHMARK_EXECUTE: failed agent credential evidence is discarded in full'

evaluator_failure_output="$TEST_TMP/evaluator-failure-results"
evaluator_failure_ledger="$TEST_TMP/evaluator-failure-ledger.tsv"
make_ledger "$evaluator_failure_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-control.conf" "$fixture_source/benchmarks/scenarios/fixture" evaluator-failure-smoke
run_command env PATH="$execute_bin:$PATH" WG_CODEX_AUTH_SOURCE="$TEST_TMP/auth.json" FIXTURE_EVALUATOR_LEAK=1 FIXTURE_TOKEN="$test_token" bash "$fixture_source/benchmarks/run.sh" --ledger "$evaluator_failure_ledger" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id evaluator-failure-smoke --output-root "$evaluator_failure_output" --execute
assert_nonzero 'BENCHMARK_EXECUTE: failed evaluator output is scanned for credential leaks'
assert_path_absent "$evaluator_failure_output/evaluator-failure-smoke" 'BENCHMARK_EXECUTE: failed evaluator credential evidence is discarded in full'

setup_timeout_output="$TEST_TMP/setup-timeout-results"
setup_timeout_ledger="$TEST_TMP/setup-timeout-ledger.tsv"
setup_timeout_pid_file="$TEST_TMP/setup-timeout-child.pid"
make_ledger "$setup_timeout_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-writing-goals.conf" "$fixture_source/benchmarks/scenarios/fixture" setup-timeout-smoke treatment 1 1 3
run_command env PATH="$execute_bin:$PATH" FIXTURE_SETUP_CHILD_PID="$setup_timeout_pid_file" bash "$fixture_source/benchmarks/run.sh" --ledger "$setup_timeout_ledger" --profile "$fixture_source/benchmarks/profiles/codex-writing-goals.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id setup-timeout-smoke --output-root "$setup_timeout_output" --execute
assert_nonzero 'BENCHMARK_TIMEOUT: setup cannot consume an unbounded pre-agent interval'
assert_file_contains "$setup_timeout_output/setup-timeout-smoke/result.tsv" $'^disposition\ttimed-out$' 'BENCHMARK_TIMEOUT: setup timeout has an unambiguous terminal disposition'
assert_file_contains "$setup_timeout_output/setup-timeout-smoke/result.tsv" $'^stage\tsetup$' 'BENCHMARK_TIMEOUT: setup timeout is distinguished from agent failure'
if [ -f "$setup_timeout_pid_file" ] && { ! kill -0 "$(cat "$setup_timeout_pid_file")" 2>/dev/null || ps -o stat= -p "$(cat "$setup_timeout_pid_file")" | grep -Eq '^[[:space:]]*[Zz]'; }; then pass 'BENCHMARK_TIMEOUT: setup watchdog terminates descendants'; else fail 'BENCHMARK_TIMEOUT: setup watchdog terminates descendants'; fi

hang_bin="$TEST_TMP/hang-bin"
mkdir -p "$hang_bin"
cat > "$hang_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
sleep 30 &
printf '%s\n' "$!" > "$HANG_CHILD_PID"
wait
EOF
chmod +x "$hang_bin/codex"
hang_output="$TEST_TMP/hang-results"
hang_ledger="$TEST_TMP/hang-ledger.tsv"
make_ledger "$hang_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-control.conf" "$fixture_source/benchmarks/scenarios/fixture" hang-smoke control 1 1 3
hang_pid_file="$TEST_TMP/hang-child.pid"
run_command env PATH="$hang_bin:$PATH" HANG_CHILD_PID="$hang_pid_file" bash "$fixture_source/benchmarks/run.sh" --ledger "$hang_ledger" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id hang-smoke --output-root "$hang_output" --execute
assert_nonzero 'BENCHMARK_TIMEOUT: timed-out agent exits non-zero'
assert_file_contains "$hang_output/hang-smoke/result.tsv" $'^disposition\ttimed-out$' 'BENCHMARK_TIMEOUT: timeout has an unambiguous terminal disposition'
if [ -f "$hang_pid_file" ] && { ! kill -0 "$(cat "$hang_pid_file")" 2>/dev/null || ps -o stat= -p "$(cat "$hang_pid_file")" | grep -Eq '^[[:space:]]*[Zz]'; }; then pass 'BENCHMARK_TIMEOUT: watchdog terminates agent descendants'; else fail 'BENCHMARK_TIMEOUT: watchdog terminates agent descendants'; fi

signal_bin="$TEST_TMP/signal-bin"
mkdir -p "$signal_bin"
cat > "$signal_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
kill -TERM "$$"
EOF
chmod +x "$signal_bin/codex"
signal_output="$TEST_TMP/signal-results"
signal_ledger="$TEST_TMP/signal-ledger.tsv"
make_ledger "$signal_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-control.conf" "$fixture_source/benchmarks/scenarios/fixture" signal-smoke
run_command env PATH="$signal_bin:$PATH" bash "$fixture_source/benchmarks/run.sh" --ledger "$signal_ledger" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id signal-smoke --output-root "$signal_output" --execute
assert_nonzero 'BENCHMARK_SIGNAL: signalled agent exits non-zero'
assert_file_contains "$signal_output/signal-smoke/result.tsv" $'^disposition\tsignaled$' 'BENCHMARK_SIGNAL: signal has an unambiguous terminal disposition'

evaluator_hang_output="$TEST_TMP/evaluator-hang-results"
evaluator_hang_ledger="$TEST_TMP/evaluator-hang-ledger.tsv"
evaluator_hang_pid_file="$TEST_TMP/evaluator-hang-child.pid"
make_ledger "$evaluator_hang_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-control.conf" "$fixture_source/benchmarks/scenarios/fixture" evaluator-hang-smoke control 1 1 3
run_command env PATH="$execute_bin:$PATH" FIXTURE_EVALUATOR_HANG=1 FIXTURE_EVALUATOR_CHILD_PID="$evaluator_hang_pid_file" bash "$fixture_source/benchmarks/run.sh" --ledger "$evaluator_hang_ledger" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id evaluator-hang-smoke --output-root "$evaluator_hang_output" --execute
assert_nonzero 'BENCHMARK_TIMEOUT: timed-out evaluator exits non-zero'
assert_file_contains "$evaluator_hang_output/evaluator-hang-smoke/result.tsv" $'^disposition\ttimed-out$' 'BENCHMARK_TIMEOUT: evaluator timeout has an unambiguous terminal disposition'
if [ -f "$evaluator_hang_pid_file" ] && { ! kill -0 "$(cat "$evaluator_hang_pid_file")" 2>/dev/null || ps -o stat= -p "$(cat "$evaluator_hang_pid_file")" | grep -Eq '^[[:space:]]*[Zz]'; }; then pass 'BENCHMARK_TIMEOUT: evaluator watchdog terminates descendants'; else fail 'BENCHMARK_TIMEOUT: evaluator watchdog terminates descendants'; fi

aggregate_ledger="$TEST_TMP/aggregate-ledger.tsv"
aggregate_root="$TEST_TMP/aggregate-results"
printf '%s\n' $'cohort_id\tbase_commit\tprofile_sha256\tprompt_sha256\tevaluator_sha256\tadapter_sha256\tscenario_id\tarm\trepeat\trun_id\tplanned_order\ttimeout_seconds\toperator_action' > "$aggregate_ledger"
aggregate_order=1
for aggregate_scenario in alpha beta gamma; do
  for aggregate_repeat in 1 2; do
    for aggregate_arm in control treatment; do
      aggregate_run="${aggregate_scenario}-${aggregate_arm}-${aggregate_repeat}"
      printf 'aggregate-cohort\tbase\tprofile\tprompt\tevaluator\tadapter\t%s\t%s\t%s\t%s\t%s\t5\tnone\n' "$aggregate_scenario" "$aggregate_arm" "$aggregate_repeat" "$aggregate_run" "$aggregate_order" >> "$aggregate_ledger"
      aggregate_dir="$aggregate_root/$aggregate_run"
      mkdir -p "$aggregate_dir"
      {
        printf 'run_id\t%s\n' "$aggregate_run"
        printf 'started_ms\t%s\n' "$aggregate_order"
        printf 'cohort_id\taggregate-cohort\nbase_commit\tbase\nprofile_sha256\tprofile\nprompt_sha256\tprompt\nevaluator_sha256\tevaluator\nadapter_sha256\tadapter\n'
        printf 'model\tfixture\n'
        if [ "$aggregate_arm" = control ]; then printf 'workflow\tcontrol\n'; else printf 'workflow\twriting-goals\n'; fi
        printf 'scenario_id\t%s\narm\t%s\nrepeat\t%s\nplanned_order\t%s\ntimeout_seconds\t5\noperator_action\tnone\n' "$aggregate_scenario" "$aggregate_arm" "$aggregate_repeat" "$aggregate_order"
      } > "$aggregate_dir/manifest.tsv"
      printf 'disposition\tpassed\nacceptance\ttrue\nexit_code\t0\nstage\tevaluator\nelapsed_ms\t10\n' > "$aggregate_dir/result.tsv"
      aggregate_order=$((aggregate_order + 1))
    done
  done
done
run_command bash "$aggregator" --ledger "$aggregate_ledger" --run-root "$aggregate_root"
assert_success 'BENCHMARK_AGGREGATE: declared 12-run cohort aggregates deterministically'
assert_file_contains "$RUN_OUT" $'^scenario_id\tarm\trepeat\tdisposition' 'BENCHMARK_AGGREGATE: output has a stable TSV header'
assert_contains "$(cat "$RUN_OUT")" $'alpha\tcontrol\t1\tpassed\ttrue\t10\tnone\tpassed\ttrue\tcomparable\tnone\tconsistent' 'BENCHMARK_AGGREGATE: output includes paired acceptance and repeat consistency'
perl -0pi -e 's/stage\tevaluator\n/stage\tagent\n/' "$aggregate_root/alpha-control-1/result.tsv"
run_command bash "$aggregator" --ledger "$aggregate_ledger" --run-root "$aggregate_root"
assert_nonzero 'BENCHMARK_AGGREGATE: passed evidence requires evaluator stage and exit zero'
assert_contains "$(cat "$RUN_ERR")" 'disposition detail mismatch' 'BENCHMARK_AGGREGATE: terminal evidence mismatch is classified for RCA'
perl -0pi -e 's/stage\tagent\n/stage\tevaluator\n/' "$aggregate_root/alpha-control-1/result.tsv"
traversal_ledger="$TEST_TMP/traversal-ledger.tsv"
awk -F '\t' 'BEGIN { OFS = "\t" } NR == 2 { $10 = "../outside" } { print }' "$aggregate_ledger" > "$traversal_ledger"
run_command bash "$aggregator" --ledger "$traversal_ledger" --run-root "$aggregate_root"
assert_nonzero 'BENCHMARK_AGGREGATE: traversal run ID is rejected before reading evidence'
assert_contains "$(cat "$RUN_ERR")" 'invalid run_id' 'BENCHMARK_AGGREGATE: traversal rejection is classified for RCA'
aggregate_over_limit_ledger="$TEST_TMP/aggregate-over-limit-ledger.tsv"
awk -F '\t' 'BEGIN { OFS = "\t" } NR == 2 { $12 = 3601 } { print }' "$aggregate_ledger" > "$aggregate_over_limit_ledger"
run_command bash "$aggregator" --ledger "$aggregate_over_limit_ledger" --run-root "$aggregate_root"
assert_nonzero 'BENCHMARK_AGGREGATE: over-limit timeout is rejected consistently'
printf 'base_commit\tmismatch\n' >> "$aggregate_root/alpha-control-1/manifest.tsv"
run_command bash "$aggregator" --ledger "$aggregate_ledger" --run-root "$aggregate_root"
assert_nonzero 'BENCHMARK_AGGREGATE: duplicate or mismatched manifest identity is rejected'
assert_contains "$(cat "$RUN_ERR")" 'invalid-pair' 'BENCHMARK_AGGREGATE: identity rejection is classified for RCA'

finish_tests
