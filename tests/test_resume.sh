#!/usr/bin/env bash
# Protected G07 oracle: exact sequential resume and interruption semantics.
set -u
. "$(dirname "$0")/testlib.sh"

runtime="$REPO_DIR/assets/runtime-check.sh"
workflow="$REPO_DIR/shared/workflow.md"
fixtures="$REPO_DIR/tests/fixtures/core-integration"

missing_contract() {
  printf '%s\n' 'FAIL: G07_RESUME_HANDOFF_MISSING' >&2
  exit 1
}

# Keep this red gate before fixture parsing.  The existing lifecycle reader is
# intentionally insufficient until the maker adds the frozen-core handoff.
[ -f "$runtime" ] && [ -f "$workflow" ] && [ -f "$fixtures/resume-maker/core.env" ] || missing_contract
bash -n "$runtime" || missing_contract
grep -q -- '--core-fixture' "$runtime" || missing_contract
grep -q -- '--activation-record' "$runtime" || missing_contract
grep -q -- 'G07 protected sequential core' "$workflow" || missing_contract

authority="$TEST_TMP/protected-authority"
mkdir -p "$authority"
chmod 700 "$authority"

core_case() {
  case_name=$1
  run_name=run-g07-fixture
  [ "$case_name" = six-slice-parent ] && run_name=run-g07-six-slice
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
  bash "$runtime" --authority "$authority" --identity 20260729-GV53BZ --plan p01 --run "$run_name" \
    --activation-record "$authority/activation.env" --core-fixture "$case_file" --resume
}

run_command core_case resume-maker
assert_success 'G07_EXACT_RESUME: resumes the recorded incomplete node'
assert_file_contains "$RUN_OUT" '^result=resume$' 'G07_EXACT_RESUME: reports a resume, never implicit latest work'
assert_file_contains "$RUN_OUT" '^current_or_next=G02-INTEGRATION$' 'G07_EXACT_RESUME: preserves the exact recorded node'
assert_file_contains "$RUN_OUT" '^role=writing-goals-maker$' 'G07_EXACT_RESUME: preserves the exact interrupted role'
assert_not_contains "$(cat "$RUN_OUT" "$RUN_ERR")" 'background|parallel|dispatched' 'G07_NO_BACKGROUND_CONTINUATION: no background continuation is claimed'

run_command core_case resume-verifier
assert_success 'G07_INTERRUPTED_ROLE_RECOVERY: resumes verifier rather than restarting maker'
assert_file_contains "$RUN_OUT" '^role=writing-goals-verifier$' 'G07_INTERRUPTED_ROLE_RECOVERY: recorded verifier cursor is exact'

run_command core_case checkpoint-then-continue
assert_success 'G07_EXACT_INTERRUPTION_CHECKPOINT: accepted predecessor checkpoint permits only its successor'
assert_file_contains "$RUN_OUT" '^reason=checkpoint-before-next-node$' 'G07_EXACT_INTERRUPTION_CHECKPOINT: reports the checkpoint handoff'

run_command core_case tie-break
assert_success 'G07_SEQUENTIAL_PATH: multiple ready nodes remain host-sequential'
assert_file_contains "$RUN_OUT" '^execution_order=G02-INTEGRATION,G01-DISCOVERY,G03-POST$' 'G07_RESUME_ORDER_PRESERVED: activation-bound frozen order is retained'
assert_file_contains "$RUN_OUT" '^current_or_next=G02-INTEGRATION$' 'G07_RESUME_ORDER_PRESERVED: first ready node follows frozen-order tie-break'

finish_tests
