#!/usr/bin/env bash
# Protected G07 oracle: cross-contract parent execution and rejection surface.
set -u
. "$(dirname "$0")/testlib.sh"

runtime="$REPO_DIR/assets/runtime-check.sh"
workflow="$REPO_DIR/shared/workflow.md"
fixtures="$REPO_DIR/tests/fixtures/core-integration"

missing_contract() {
  printf '%s\n' 'FAIL: G07_CORE_INTEGRATION_MISSING' >&2
  exit 1
}

[ -f "$runtime" ] && [ -f "$workflow" ] && [ -f "$fixtures/six-slice-parent/core.env" ] || missing_contract
bash -n "$runtime" || missing_contract
grep -q -- '--core-fixture' "$runtime" || missing_contract
grep -q -- '--activation-record' "$runtime" || missing_contract
grep -q -- 'G07 protected sequential core' "$workflow" || missing_contract

authority="$TEST_TMP/protected-authority"
mkdir -p "$authority"
chmod 700 "$authority"

core_case() {
  case_name=$1 record_mode=${2:-complete}
  run_name=run-g07-fixture
  case "$case_name" in six-slice-parent|five-slices-parent-done|parent-missing-*) run_name=run-g07-six-slice ;; esac
  case_file="$fixtures/$case_name/core.env"
  activation_field() {
    value="$(sed -n "s/^activation_$1=//p" "$case_file")"
    [ -n "$value" ] || value="$(sed -n "s/^$1=//p" "$case_file")"
    printf '%s' "$value"
  }
  { printf 'identity=%s\n' "$(activation_field identity)"
    printf 'plan=%s\n' "$(activation_field plan)"
    printf 'run=%s\n' "$(activation_field run)"
    printf 'generation=%s\n' "$(activation_field generation)"
    printf 'objective_digest=%s\n' "$(activation_field objective_digest)"
    printf 'plan_digest=%s\n' "$(activation_field plan_digest)"
    printf 'execution_order=%s\n' "$(activation_field execution_order)"; } > "$authority/activation.env"
  chmod 600 "$authority/activation.env"
  { printf 'objective_digest=%s\n' "$(activation_field objective_digest)"
    printf 'plan_digest=%s\n' "$(activation_field plan_digest)"
    printf 'approver=fixture-human\n'
    printf 'approved_at=2026-08-02T00:00:00Z\n'
    printf 'revoked=false\n'; } > "$authority/approval.env"
  chmod 600 "$authority/approval.env"
  preflight_surface='sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
  [ "$record_mode" = invalid-preflight ] && preflight_surface='sha256:not-a-digest'
  { printf 'objective_digest=%s\n' "$(activation_field objective_digest)"
    printf 'plan_digest=%s\n' "$(activation_field plan_digest)"
    printf 'surface_digest=%s\n' "$preflight_surface"
    printf 'baseline=green\n'; } > "$authority/preflight.env"
  chmod 600 "$authority/preflight.env"
  if [ "$record_mode" = missing-preflight ]; then
    bash "$runtime" --authority "$authority" --identity 20260729-GV53BZ --plan p01 --run "$run_name" \
      --approval-record "$authority/approval.env" --activation-record "$authority/activation.env" \
      --core-fixture "$case_file" --resume
  else
    bash "$runtime" --authority "$authority" --identity 20260729-GV53BZ --plan p01 --run "$run_name" \
      --approval-record "$authority/approval.env" --preflight-record "$authority/preflight.env" \
      --activation-record "$authority/activation.env" --core-fixture "$case_file" --resume
  fi
}

assert_reject() {
  case_name=$1 reason=$2 label=$3
  run_command core_case "$case_name"
  assert_nonzero "$label"
  assert_contains "$(cat "$RUN_OUT" "$RUN_ERR")" "^reason=$reason$|$reason" "$label: rejects with the declared fail-closed reason"
}

run_command core_case resume-maker
assert_success 'G07_ROLE_HANDOFFS: maker handoff is accepted only with its protected predecessor'
assert_file_contains "$RUN_OUT" '^role=writing-goals-maker$' 'G07_ROLE_HANDOFFS: maker role is explicit'
run_command core_case resume-verifier
assert_success 'G07_ROLE_HANDOFFS: verifier handoff is accepted only at its recorded cursor'
assert_file_contains "$RUN_OUT" '^role=writing-goals-verifier$' 'G07_ROLE_HANDOFFS: verifier role is explicit'
run_command core_case resume-maker missing-preflight
assert_nonzero 'G07_PREFLIGHT_REQUIRED: full-tier resume rejects a missing protected preflight record'
assert_contains "$(cat "$RUN_OUT" "$RUN_ERR")" 'requires approval, preflight, activation records' 'G07_PREFLIGHT_REQUIRED: missing preflight fails before runtime continuation'
run_command core_case resume-maker invalid-preflight
assert_nonzero 'G07_PREFLIGHT_FORMAT: full-tier resume rejects a noncanonical preflight surface digest'
assert_contains "$(cat "$RUN_OUT" "$RUN_ERR")" 'invalid preflight surface digest' 'G07_PREFLIGHT_FORMAT: the strict preflight digest diagnostic is reported'
assert_file_contains "$workflow" 'oracle-author.*maker.*verifier.*reviewer|maker.*verifier.*reviewer' 'G07_PROTECTED_INTEGRATION: workflow records protected role handoffs'
assert_file_contains "$workflow" 'host.*(select|selects).*first.*ready|first.*ready.*host.*(select|selects)' 'G07_PROTECTED_INTEGRATION: host, not a helper, selects the ready node'
assert_file_contains "$workflow" 'frozen.*(order|digest).*(activation|bound)|(activation|bound).*(frozen.*(order|digest))' 'G07_FROZEN_ORDER_ACTIVATION_BOUND: activation binds the frozen order and digest'

assert_reject parallel-attempt parallel-dispatch-not-permitted 'G07_PARALLEL_REJECTED: parallel dispatch metadata fails closed'
assert_reject missing-order execution-order-missing-node 'G07_EXECUTION_ORDER_MISSING_REJECTED: missing DAG node in order fails activation'
assert_reject unknown-order execution-order-unknown-node 'G07_EXECUTION_ORDER_UNKNOWN_REJECTED: unknown DAG node in order fails activation'
assert_reject duplicate-order execution-order-duplicate-node 'G07_EXECUTION_ORDER_DUPLICATE_REJECTED: duplicate order node fails activation'
assert_reject stale-predecessor stale-predecessor 'G07_STALE_TOP_ACCEPTANCE_REJECTED: stale predecessor evidence fails before continuation'
assert_reject unknown-successor unknown-successor 'G07_UNKNOWN_SUCCESSOR_REJECTED: undeclared successor fails closed'
assert_reject untrusted-report untrusted-report-not-authority 'G07_PROTECTED_INTEGRATION: rNN report cannot become authority'
assert_reject activation-generation-drift activation-generation-drift 'G07_FROZEN_ORDER_ACTIVATION_BOUND: altered protected generation rejects resume'
assert_reject activation-objective-drift activation-objective-digest-drift 'G07_FROZEN_ORDER_ACTIVATION_BOUND: altered objective digest rejects resume'
assert_reject activation-plan-drift activation-plan-digest-drift 'G07_FROZEN_ORDER_ACTIVATION_BOUND: altered plan digest rejects resume'
assert_reject activation-order-drift activation-execution-order-drift 'G07_FROZEN_ORDER_ACTIVATION_BOUND: altered frozen execution order rejects resume'
assert_reject missing-predecessor missing-predecessor 'G07_STALE_TOP_ACCEPTANCE_REJECTED: missing dependency predecessor rejects continuation'
assert_reject nondependency-predecessor nondependency-predecessor 'G07_STALE_TOP_ACCEPTANCE_REJECTED: non-dependency predecessor rejects continuation'
assert_reject successor-checkpoint-mismatch successor-checkpoint-mismatch 'G07_CHECKPOINT_THEN_CONTINUE: successor must bind the exact predecessor checkpoint'
assert_reject reviewer-without-verifier reviewer-without-verifier-handoff 'G07_ROLE_HANDOFFS: reviewer cannot bypass verifier handoff'
assert_reject missing-role-cursor role-cursor-missing 'G07_ROLE_HANDOFFS: nonterminal work cannot resume without an exact role cursor'

run_command core_case tie-break
assert_success 'G07_READY_FRONTIER_FIRST_IN_FROZEN_ORDER: ready frontier tie-break is accepted'
assert_file_contains "$RUN_OUT" '^current_or_next=G02-INTEGRATION$' 'G07_READY_FRONTIER_FIRST_IN_FROZEN_ORDER: frozen-order first node wins'

run_command core_case six-slice-parent
assert_success 'G07_SIX_SLICE_ISSUE_REGRESSION: sixth-slice fixture remains resumable before final checkpoint'
assert_file_contains "$RUN_OUT" '^parent_state=in_progress$' 'G07_SIX_SLICE_ISSUE_REGRESSION: parent stays active until all six slices complete'
assert_file_contains "$RUN_OUT" '^completed_slices=G01,G02,G03,G04,G05$' 'G07_SIX_SLICE_ISSUE_REGRESSION: checkpoints one through five do not complete the parent'
assert_file_contains "$RUN_OUT" '^current_or_next=G06$' 'G07_CHECKPOINT_THEN_CONTINUE: parent resumes the sixth checkpoint exactly'
assert_file_contains "$RUN_OUT" '^role=writing-goals-reviewer$' 'G07_CHECKPOINT_THEN_CONTINUE: reviewer predicate remains a protected handoff'
assert_reject five-slices-parent-done parent-complete-before-sixth-slice 'G07_SIX_SLICE_ISSUE_REGRESSION: five slices cannot complete the parent'
assert_reject parent-missing-top-acceptance parent-missing-top-level-acceptance 'G07_SIX_SLICE_ISSUE_REGRESSION: parent completion requires current top-level acceptance'
assert_reject parent-missing-verifier parent-missing-verifier 'G07_SIX_SLICE_ISSUE_REGRESSION: parent completion requires fresh verifier evidence'
assert_reject parent-missing-reviewer parent-missing-reviewer 'G07_SIX_SLICE_ISSUE_REGRESSION: parent completion requires fresh reviewer evidence'

finish_tests
