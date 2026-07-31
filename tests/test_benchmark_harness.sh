#!/usr/bin/env bash
# Benchmark runner contracts remain offline: no model, credential, or worktree launch.
set -u
. "$(dirname "$0")/testlib.sh"

runner="$REPO_DIR/benchmarks/run.sh"
aggregator="$REPO_DIR/benchmarks/aggregate.sh"
profile="$REPO_DIR/benchmarks/profiles/codex-control.conf"
scenario="$REPO_DIR/benchmarks/scenarios/refresh-status"
output="$TEST_TMP/results"

# A watchdog's SIGKILL can land fractionally after the runner exits, so poll for
# the descendant to disappear instead of sampling once.  A process still alive
# after the grace period is a genuine leak, not a scheduling artefact.
assert_descendant_terminated() {
  descendant_pid_file=$1
  descendant_label=$2
  descendant_waited=0
  TEST_COUNT=$((TEST_COUNT + 1))
  while [ "$descendant_waited" -lt 50 ]; do
    descendant_pid="$(cat "$descendant_pid_file" 2>/dev/null || true)"
    if [ -n "$descendant_pid" ] && { ! kill -0 "$descendant_pid" 2>/dev/null || ps -o stat= -p "$descendant_pid" 2>/dev/null | grep -Eq '^[[:space:]]*[Zz]'; }; then
      pass "$descendant_label"
      return 0
    fi
    sleep 0.1
    descendant_waited=$((descendant_waited + 1))
  done
  fail "$descendant_label"
}

# The runner and the aggregator keep separate copies of the ledger rules so that
# each stays runnable on its own.  Assert they accept exactly the same ledgers,
# so a rule added to one copy but not the other is a test failure rather than a
# silent split between "runner accepts" and "aggregator rejects".
assert_ledger_rejected_by_both() {
  agreement_ledger=$1
  agreement_pattern=$2
  agreement_label=$3
  run_command bash "$aggregator" --ledger "$agreement_ledger" --run-root "$aggregate_root"
  assert_nonzero "BENCHMARK_LEDGER_AGREEMENT: aggregator rejects $agreement_label"
  assert_contains "$(cat "$RUN_ERR")" "$agreement_pattern" "BENCHMARK_LEDGER_AGREEMENT: aggregator names $agreement_label"
  run_command bash "$runner" --ledger "$agreement_ledger" --profile "$profile" --scenario "$scenario" --run-id alpha-control-1 --output-root "$TEST_TMP/agreement-results" --dry-run
  assert_nonzero "BENCHMARK_LEDGER_AGREEMENT: runner rejects $agreement_label"
  assert_contains "$(cat "$RUN_ERR")" "$agreement_pattern" "BENCHMARK_LEDGER_AGREEMENT: runner names $agreement_label"
}

make_ledger() {
  ledger=$1
  source_root=$2
  ledger_profile=$3
  ledger_scenario=$4
  ledger_run_id=$5
  ledger_arm=${6:-control}
  ledger_repeat=${7:-1}
  ledger_order=${8:-1}
  # One declared timeout covers git setup, agent, and evaluator, so fixtures that
  # are not exercising a timeout need enough budget to absorb setup jitter on a
  # loaded machine.  Tests that do exercise timeouts pass an explicit short value.
  ledger_timeout=${9:-60}
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
make_ledger "$setup_timeout_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-writing-goals.conf" "$fixture_source/benchmarks/scenarios/fixture" setup-timeout-smoke treatment 1 1 8
run_command env PATH="$execute_bin:$PATH" FIXTURE_SETUP_CHILD_PID="$setup_timeout_pid_file" bash "$fixture_source/benchmarks/run.sh" --ledger "$setup_timeout_ledger" --profile "$fixture_source/benchmarks/profiles/codex-writing-goals.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id setup-timeout-smoke --output-root "$setup_timeout_output" --execute
assert_nonzero 'BENCHMARK_TIMEOUT: setup cannot consume an unbounded pre-agent interval'
assert_file_contains "$setup_timeout_output/setup-timeout-smoke/result.tsv" $'^disposition\ttimed-out$' 'BENCHMARK_TIMEOUT: setup timeout has an unambiguous terminal disposition'
assert_file_contains "$setup_timeout_output/setup-timeout-smoke/result.tsv" $'^stage\tsetup$' 'BENCHMARK_TIMEOUT: setup timeout is distinguished from agent failure'
assert_descendant_terminated "$setup_timeout_pid_file" 'BENCHMARK_TIMEOUT: setup watchdog terminates descendants'

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
make_ledger "$hang_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-control.conf" "$fixture_source/benchmarks/scenarios/fixture" hang-smoke control 1 1 8
hang_pid_file="$TEST_TMP/hang-child.pid"
run_command env PATH="$hang_bin:$PATH" HANG_CHILD_PID="$hang_pid_file" bash "$fixture_source/benchmarks/run.sh" --ledger "$hang_ledger" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id hang-smoke --output-root "$hang_output" --execute
assert_nonzero 'BENCHMARK_TIMEOUT: timed-out agent exits non-zero'
assert_file_contains "$hang_output/hang-smoke/result.tsv" $'^disposition\ttimed-out$' 'BENCHMARK_TIMEOUT: timeout has an unambiguous terminal disposition'
assert_descendant_terminated "$hang_pid_file" 'BENCHMARK_TIMEOUT: watchdog terminates agent descendants'

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
make_ledger "$evaluator_hang_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-control.conf" "$fixture_source/benchmarks/scenarios/fixture" evaluator-hang-smoke control 1 1 8
run_command env PATH="$execute_bin:$PATH" FIXTURE_EVALUATOR_HANG=1 FIXTURE_EVALUATOR_CHILD_PID="$evaluator_hang_pid_file" bash "$fixture_source/benchmarks/run.sh" --ledger "$evaluator_hang_ledger" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id evaluator-hang-smoke --output-root "$evaluator_hang_output" --execute
assert_nonzero 'BENCHMARK_TIMEOUT: timed-out evaluator exits non-zero'
assert_file_contains "$evaluator_hang_output/evaluator-hang-smoke/result.tsv" $'^disposition\ttimed-out$' 'BENCHMARK_TIMEOUT: evaluator timeout has an unambiguous terminal disposition'
assert_descendant_terminated "$evaluator_hang_pid_file" 'BENCHMARK_TIMEOUT: evaluator watchdog terminates descendants'

# An isolated agent has no ambient Git identity to fall back on, so a commit can
# only succeed if the runner exported a benchmark-scoped one.  The fixture
# deliberately omits `git -c user.*`.
identity_bin="$TEST_TMP/identity-bin"
mkdir -p "$identity_bin"
cat > "$identity_bin/codex" <<'EOF'
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
git -C "$worktree" commit --allow-empty -m 'fixture identity result' >/dev/null
git -C "$worktree" log -1 --pretty='%an <%ae>|%cn <%ce>' > "$WG_IDENTITY_CAPTURE"
EOF
chmod +x "$identity_bin/codex"
identity_capture="$TEST_TMP/identity-capture"
identity_output="$TEST_TMP/identity-results"
identity_ledger="$TEST_TMP/identity-ledger.tsv"
make_ledger "$identity_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-control.conf" "$fixture_source/benchmarks/scenarios/fixture" identity-smoke
run_command env PATH="$identity_bin:$PATH" WG_IDENTITY_CAPTURE="$identity_capture" bash "$fixture_source/benchmarks/run.sh" --ledger "$identity_ledger" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id identity-smoke --output-root "$identity_output" --execute
assert_success 'BENCHMARK_IDENTITY: isolated agent commits without ambient Git configuration'
assert_file_contains "$identity_capture" '^Writing Goals Benchmark <benchmark@writing-goals\.invalid>\|Writing Goals Benchmark <benchmark@writing-goals\.invalid>$' 'BENCHMARK_IDENTITY: commit author and committer are benchmark-scoped'

# One declared timeout covers setup, agent, and evaluator.  Setup deliberately
# consumes most of the budget; a stage that received a fresh full budget would
# push the total well past the ledger timeout.
cat > "$fixture_source/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 8
EOF
chmod +x "$fixture_source/install.sh"
git -C "$fixture_source" add install.sh
git -C "$fixture_source" -c user.name='Benchmark Test' -c user.email='benchmark@example.invalid' commit -m 'fixture slow but succeeding install' >/dev/null
budget_output="$TEST_TMP/budget-results"
budget_ledger="$TEST_TMP/budget-ledger.tsv"
budget_pid_file="$TEST_TMP/budget-child.pid"
make_ledger "$budget_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-writing-goals.conf" "$fixture_source/benchmarks/scenarios/fixture" budget-smoke treatment 1 1 14
run_command env PATH="$hang_bin:$PATH" HANG_CHILD_PID="$budget_pid_file" bash "$fixture_source/benchmarks/run.sh" --ledger "$budget_ledger" --profile "$fixture_source/benchmarks/profiles/codex-writing-goals.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id budget-smoke --output-root "$budget_output" --execute
assert_nonzero 'BENCHMARK_BUDGET: agent still times out after setup consumed most of the budget'
assert_file_contains "$budget_output/budget-smoke/result.tsv" $'^stage\tagent$' 'BENCHMARK_BUDGET: remaining budget is charged to the agent stage'
budget_elapsed="$(awk -F '\t' '$1 == "elapsed_ms" { print $2 }' "$budget_output/budget-smoke/result.tsv" 2>/dev/null)"
TEST_COUNT=$((TEST_COUNT + 1))

# Sharing one budget makes the total track the declared timeout rather than the
# sum of the stages: correct is ~14s (the 14s budget plus teardown),
# whereas handing the agent a fresh 14s after an 8s setup lands near 22s.
if [ -n "$budget_elapsed" ] && [ "$budget_elapsed" -lt 18000 ]; then
  pass 'BENCHMARK_BUDGET: no stage receives a fresh full timeout budget'
else
  fail "BENCHMARK_BUDGET: no stage receives a fresh full timeout budget (elapsed_ms=${budget_elapsed:-missing})"
fi

# An operator interrupt must not leave a model process running, and must still
# explain why the run produced no measurement.
interrupt_output="$TEST_TMP/interrupt-results"
interrupt_ledger="$TEST_TMP/interrupt-ledger.tsv"
interrupt_pid_file="$TEST_TMP/interrupt-child.pid"
make_ledger "$interrupt_ledger" "$fixture_source" "$fixture_source/benchmarks/profiles/codex-control.conf" "$fixture_source/benchmarks/scenarios/fixture" interrupt-smoke control 1 1 60
# A non-interactive shell starts background jobs with SIGINT ignored, and an
# ignored signal cannot be trapped.  Restore the default disposition before exec
# so this exercises the operator's Ctrl-C path rather than the harness's.
env PATH="$hang_bin:$PATH" HANG_CHILD_PID="$interrupt_pid_file" perl -e '$SIG{INT} = "DEFAULT"; $SIG{HUP} = "DEFAULT"; exec @ARGV or die "exec: $!"' -- bash "$fixture_source/benchmarks/run.sh" --ledger "$interrupt_ledger" --profile "$fixture_source/benchmarks/profiles/codex-control.conf" --scenario "$fixture_source/benchmarks/scenarios/fixture" --run-id interrupt-smoke --output-root "$interrupt_output" --execute >"$TEST_TMP/interrupt.stdout" 2>"$TEST_TMP/interrupt.stderr" &
interrupt_runner_pid=$!
interrupt_waited=0
while [ ! -s "$interrupt_pid_file" ] && [ "$interrupt_waited" -lt 200 ]; do
  sleep 0.1
  interrupt_waited=$((interrupt_waited + 1))
done
kill -INT "$interrupt_runner_pid" 2>/dev/null || true
wait "$interrupt_runner_pid"
interrupt_status=$?
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$interrupt_status" -ne 0 ]; then
  pass 'BENCHMARK_INTERRUPT: interrupted runner exits non-zero'
else
  fail 'BENCHMARK_INTERRUPT: interrupted runner exits non-zero'
fi
assert_file_contains "$interrupt_output/interrupt-smoke/result.tsv" $'^disposition\tsignaled$' 'BENCHMARK_INTERRUPT: interrupted run retains signalled terminal evidence'
assert_file_contains "$interrupt_output/interrupt-smoke/result.tsv" $'^acceptance\tfalse$' 'BENCHMARK_INTERRUPT: interrupted run is never accepted'
assert_descendant_terminated "$interrupt_pid_file" 'BENCHMARK_INTERRUPT: interrupt terminates the active agent descendants'

# Observed start times are wall-clock epoch milliseconds in real evidence.  The
# fixture must use the same scale, otherwise an order check that only works on
# small synthetic values would look correct here and reject every real cohort.
make_cohort() {
  cohort_ledger=$1
  cohort_root=$2
  cohort_order=1
  cohort_epoch_ms=1900000000000
  rm -rf "$cohort_root"
  printf '%s\n' $'cohort_id\tbase_commit\tprofile_sha256\tprompt_sha256\tevaluator_sha256\tadapter_sha256\tscenario_id\tarm\trepeat\trun_id\tplanned_order\ttimeout_seconds\toperator_action' > "$cohort_ledger"
  for cohort_scenario in alpha beta gamma; do
    for cohort_repeat in 1 2; do
      for cohort_arm in control treatment; do
        cohort_run="${cohort_scenario}-${cohort_arm}-${cohort_repeat}"
        printf 'aggregate-cohort\tbase\tprofile\tprompt\tevaluator\tadapter\t%s\t%s\t%s\t%s\t%s\t5\tnone\n' "$cohort_scenario" "$cohort_arm" "$cohort_repeat" "$cohort_run" "$cohort_order" >> "$cohort_ledger"
        cohort_dir="$cohort_root/$cohort_run"
        mkdir -p "$cohort_dir"
        {
          printf 'run_id\t%s\n' "$cohort_run"
          printf 'started_ms\t%s\n' "$((cohort_epoch_ms + cohort_order * 1000))"
          printf 'cohort_id\taggregate-cohort\nbase_commit\tbase\nprofile_sha256\tprofile\nprompt_sha256\tprompt\nevaluator_sha256\tevaluator\nadapter_sha256\tadapter\n'
          printf 'model\tfixture\n'
          if [ "$cohort_arm" = control ]; then printf 'workflow\tcontrol\n'; else printf 'workflow\twriting-goals\n'; fi
          printf 'scenario_id\t%s\narm\t%s\nrepeat\t%s\nplanned_order\t%s\ntimeout_seconds\t5\noperator_action\tnone\n' "$cohort_scenario" "$cohort_arm" "$cohort_repeat" "$cohort_order"
        } > "$cohort_dir/manifest.tsv"
        printf 'disposition\tpassed\nacceptance\ttrue\nexit_code\t0\nstage\tevaluator\nelapsed_ms\t10\n' > "$cohort_dir/result.tsv"
        cohort_order=$((cohort_order + 1))
      done
    done
  done
}

aggregate_ledger="$TEST_TMP/aggregate-ledger.tsv"
aggregate_root="$TEST_TMP/aggregate-results"
make_cohort "$aggregate_ledger" "$aggregate_root"
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

# Declared interleaving is an experiment-validity property, so the observed start
# times must actually match planned orders 1..12 rather than merely be recorded.
order_ledger="$TEST_TMP/order-ledger.tsv"
order_root="$TEST_TMP/order-results"
make_cohort "$order_ledger" "$order_root"
order_first_ms="$(awk -F '\t' '$1 == "started_ms" { print $2 }' "$order_root/alpha-control-1/manifest.tsv")"
order_last_ms="$(awk -F '\t' '$1 == "started_ms" { print $2 }' "$order_root/gamma-treatment-2/manifest.tsv")"
perl -0pi -e "s/^started_ms\t.*\$/started_ms\t$order_last_ms/m" "$order_root/alpha-control-1/manifest.tsv"
perl -0pi -e "s/^started_ms\t.*\$/started_ms\t$order_first_ms/m" "$order_root/gamma-treatment-2/manifest.tsv"
run_command bash "$aggregator" --ledger "$order_ledger" --run-root "$order_root"
assert_nonzero 'BENCHMARK_AGGREGATE: cohort executed out of its declared order is rejected'
assert_contains "$(cat "$RUN_ERR")" 'execution order does not match ledger' 'BENCHMARK_AGGREGATE: out-of-order execution is classified for RCA'

missing_start_ledger="$TEST_TMP/missing-start-ledger.tsv"
missing_start_root="$TEST_TMP/missing-start-results"
make_cohort "$missing_start_ledger" "$missing_start_root"
perl -0pi -e 's/^started_ms\t.*\n//m' "$missing_start_root/beta-control-1/manifest.tsv"
run_command bash "$aggregator" --ledger "$missing_start_ledger" --run-root "$missing_start_root"
assert_nonzero 'BENCHMARK_AGGREGATE: run without observed start evidence is rejected'
assert_contains "$(cat "$RUN_ERR")" 'started_ms' 'BENCHMARK_AGGREGATE: missing start evidence is classified for RCA'

# Comparing arms only means something if every run in an arm used the same
# profile and the same model.
profile_drift_ledger="$TEST_TMP/profile-drift-ledger.tsv"
profile_drift_root="$TEST_TMP/profile-drift-results"
make_cohort "$profile_drift_ledger" "$profile_drift_root"
awk -F '\t' 'BEGIN { OFS = "\t" } $10 == "alpha-treatment-1" { $3 = "drifted" } { print }' "$profile_drift_ledger" > "$profile_drift_ledger.next"
mv "$profile_drift_ledger.next" "$profile_drift_ledger"
perl -0pi -e 's/^profile_sha256\tprofile$/profile_sha256\tdrifted/m' "$profile_drift_root/alpha-treatment-1/manifest.tsv"
run_command bash "$aggregator" --ledger "$profile_drift_ledger" --run-root "$profile_drift_root"
assert_nonzero 'BENCHMARK_AGGREGATE: profile drift within an arm is rejected'
assert_contains "$(cat "$RUN_ERR")" 'profile drift' 'BENCHMARK_AGGREGATE: profile drift is classified for RCA'
assert_not_contains "$(cat "$RUN_ERR")" 'expected exactly three scenarios' 'BENCHMARK_AGGREGATE: drift rejection reports one unambiguous cause'

model_drift_ledger="$TEST_TMP/model-drift-ledger.tsv"
model_drift_root="$TEST_TMP/model-drift-results"
make_cohort "$model_drift_ledger" "$model_drift_root"
perl -0pi -e 's/^model\tfixture$/model\tdrifted/m' "$model_drift_root/beta-treatment-1/manifest.tsv"
run_command bash "$aggregator" --ledger "$model_drift_ledger" --run-root "$model_drift_root"
assert_nonzero 'BENCHMARK_AGGREGATE: model drift within an arm is rejected'
assert_contains "$(cat "$RUN_ERR")" 'model drift' 'BENCHMARK_AGGREGATE: model drift is classified for RCA'

# A dry-run row has no measurement, so it can never enter an aggregate.
planned_ledger="$TEST_TMP/planned-ledger.tsv"
planned_root="$TEST_TMP/planned-results"
make_cohort "$planned_ledger" "$planned_root"
printf 'disposition\tplanned\nacceptance\tfalse\nexit_code\t\nstage\tplanning\nelapsed_ms\t0\n' > "$planned_root/beta-control-2/result.tsv"
run_command bash "$aggregator" --ledger "$planned_ledger" --run-root "$planned_root"
assert_nonzero 'BENCHMARK_AGGREGATE: planned dry-run evidence cannot be aggregated'
assert_contains "$(cat "$RUN_ERR")" 'planned run is incomplete' 'BENCHMARK_AGGREGATE: incomplete evidence is classified for RCA'

# An interrupted run is a legitimate non-pass outcome, so its terminal evidence
# must remain aggregatable rather than read as corrupt.
signaled_ledger="$TEST_TMP/signaled-ledger.tsv"
signaled_root="$TEST_TMP/signaled-results"
make_cohort "$signaled_ledger" "$signaled_root"
printf 'disposition\tsignaled\nacceptance\tfalse\nexit_code\t130\nstage\tsetup\nelapsed_ms\t42\n' > "$signaled_root/gamma-control-1/result.tsv"
run_command bash "$aggregator" --ledger "$signaled_ledger" --run-root "$signaled_root"
assert_success 'BENCHMARK_AGGREGATE: interrupted-run evidence is valid terminal evidence'
assert_contains "$(cat "$RUN_OUT")" $'gamma\tcontrol\t1\tsignaled\tfalse\t42\tnone\tpassed\ttrue\tcomparable\tdiscordant-paired-acceptance\tdiscordant' 'BENCHMARK_AGGREGATE: interrupted run is reported as a discordant non-pass'

# The runner records an empty exit code when the shared budget is already spent
# at the evaluator boundary, so that exact shape must remain aggregatable; the
# alternative is one late run discarding eleven valid ones.
boundary_ledger="$TEST_TMP/boundary-ledger.tsv"
boundary_root="$TEST_TMP/boundary-results"
make_cohort "$boundary_ledger" "$boundary_root"
printf 'disposition\ttimed-out\nacceptance\tfalse\nexit_code\t\nstage\tevaluator\nelapsed_ms\t60000\n' > "$boundary_root/beta-treatment-2/result.tsv"
run_command bash "$aggregator" --ledger "$boundary_ledger" --run-root "$boundary_root"
assert_success 'BENCHMARK_AGGREGATE: evaluator-boundary timeout without an exit code is valid terminal evidence'
assert_contains "$(cat "$RUN_OUT")" $'beta\ttreatment\t2\ttimed-out\tfalse\t60000' 'BENCHMARK_AGGREGATE: evaluator-boundary timeout is reported as a non-pass'

# A cohort compares one code state: identities that are cohort-scoped must hold
# across all twelve rows.  Per-row checks cannot see a ledger split across two
# commits, because each row still agrees with its own evidence.
base_drift_ledger="$TEST_TMP/base-drift-ledger.tsv"
awk -F '\t' 'BEGIN { OFS = "\t" } NR > 1 && $8 == "treatment" { $2 = "othercommit" } { print }' "$aggregate_ledger" > "$base_drift_ledger"
assert_ledger_rejected_by_both "$base_drift_ledger" 'single base_commit' 'a cohort split across two base commits'

adapter_drift_ledger="$TEST_TMP/adapter-drift-ledger.tsv"
awk -F '\t' 'BEGIN { OFS = "\t" } $10 == "beta-control-1" { $6 = "otheradapter" } { print }' "$aggregate_ledger" > "$adapter_drift_ledger"
assert_ledger_rejected_by_both "$adapter_drift_ledger" 'single adapter_sha256' 'a cohort measured through two adapters'

prompt_drift_ledger="$TEST_TMP/prompt-drift-ledger.tsv"
awk -F '\t' 'BEGIN { OFS = "\t" } $10 == "alpha-treatment-1" { $4 = "otherprompt" } { print }' "$aggregate_ledger" > "$prompt_drift_ledger"
assert_ledger_rejected_by_both "$prompt_drift_ledger" 'single prompt_sha256 per scenario_id' 'a scenario presenting two prompts'

evaluator_drift_ledger="$TEST_TMP/evaluator-drift-ledger.tsv"
awk -F '\t' 'BEGIN { OFS = "\t" } $10 == "alpha-treatment-2" { $5 = "otherevaluator" } { print }' "$aggregate_ledger" > "$evaluator_drift_ledger"
assert_ledger_rejected_by_both "$evaluator_drift_ledger" 'single evaluator_sha256 per scenario_id' 'a scenario graded by two evaluators'

finish_tests
