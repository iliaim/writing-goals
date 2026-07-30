#!/usr/bin/env bash
# Protected G04 oracle.  It owns the external-authority harness and exercises
# the narrow state writer as a CLI; neither helper may select work.
set -u
. "$(dirname "$0")/testlib.sh"

writer="$REPO_DIR/assets/run-state-cas.sh"
status_reader="$REPO_DIR/assets/runtime-check.sh"
fixture="$REPO_DIR/tests/fixtures/state/initial.env"
current_receipts="$REPO_DIR/tests/fixtures/state/receipt-current.env"
stale_receipts="$REPO_DIR/tests/fixtures/state/receipt-stale.env"
forged_receipts="$REPO_DIR/tests/fixtures/state/receipts/forged"
valid_receipts="$REPO_DIR/tests/fixtures/state/receipts/valid"

missing_contract() {
  printf '%s\n' 'FAIL: G04_STATE_CAS_MISSING' >&2
  exit 1
}

# This deliberately precedes every fixture or platform assertion: absent
# maker surfaces are the intended protected red, not an incidental failure.
[ -f "$writer" ] && [ -f "$status_reader" ] || missing_contract
bash -n "$writer" && bash -n "$status_reader" || missing_contract
[ -f "$fixture" ] && [ -f "$current_receipts" ] && [ -f "$stale_receipts" ] && [ -f "$forged_receipts/check.env" ] && [ -f "$forged_receipts/verifier.env" ] && [ -f "$forged_receipts/reviewer.env" ] && [ -f "$valid_receipts/check.env" ] && [ -f "$valid_receipts/verifier.env" ] && [ -f "$valid_receipts/reviewer.env" ] || missing_contract

# Contract for the maker-owned helpers:
#   run-state-cas.sh --authority DIR --identity ID --plan pNN --run ID
#     --expected-generation N --expected-digest DIGEST --next-state STATE
#     --candidate ID [--check-receipt ID --verifier-receipt ID
#     --reviewer-receipt ID] [--abandonment-authority ID]
#   runtime-check.sh --authority DIR --identity ID --plan pNN --run ID --status
# The writer emits exactly one current record on stdout with state=, generation=
# and digest= fields.  The reader is non-mutating and exposes derived status.
# Receipt identifiers are only locators.  Before a done transition the writer
# must resolve receipt artifacts below AUTHORITY/receipts, reject symlinks, and
# validate the immutable identity/plan/candidate/actor/result/binding digest.
# For deterministic interruption testing, when both variables are set the
# writer creates WG_TEST_HOLD_AFTER_LOCK_FILE after acquiring its lock and
# waits for WG_TEST_RELEASE_LOCK_FILE.  A TERM must fail closed: it
# must not resume that writer or make its stale preimage newly acceptable.

authority="$TEST_TMP/protected-authority"
mkdir -p "$authority"
chmod 700 "$authority"
cp "$fixture" "$authority/bootstrap.env"

read_status() {
  run_command bash "$status_reader" --authority "$authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture --status
  assert_success "G04_STATUS_READABLE: derived status reads protected authority"
}

state_of() {
  sed -n 's/^state=//p' "$RUN_OUT" | head -n 1
}

generation_of() {
  sed -n 's/^generation=//p' "$RUN_OUT" | head -n 1
}

digest_of() {
  sed -n 's/^digest=//p' "$RUN_OUT" | head -n 1
}

cas() {
  bash "$writer" --authority "$authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture "$@"
}

# Bootstrap establishes the sole active run.  A second activation is a
# rejection, rather than a selector or replacement operation.
run_command cas --expected-generation 0 --expected-digest sha256:pending-fixture --next-state pending --candidate candidate-initial
assert_success 'G04_ACTIVATION_LOCK: first explicit run activation succeeds'
read_status
initial_state="$(state_of)"
initial_digest="$(digest_of)"
assert_contains "$initial_state" '^pending$' 'G04_ACTIVATION_LOCK: initial run remains pending'
run_command bash "$writer" --authority "$authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-second --expected-generation 0 --expected-digest sha256:pending-fixture --next-state pending --candidate candidate-initial
assert_nonzero 'G04_ACTIVATION_LOCK: second activation cannot replace the active run'

run_command cas --expected-generation 1 --expected-digest "$initial_digest" --next-state implementing --candidate candidate-green
assert_success 'G04_SIX_STATE_LIFECYCLE: pending transitions to implementing'
read_status
assert_contains "$(state_of)" '^implementing$' 'G04_SIX_STATE_LIFECYCLE: status reports implementing'

# Illegal vocabulary and edge must fail without changing the protected record.
before_generation="$(generation_of)"
before_digest="$(digest_of)"
run_command cas --expected-generation "$before_generation" --expected-digest "$before_digest" --next-state selecting --candidate candidate-green
assert_nonzero 'G04_SIX_STATE_LIFECYCLE: rejects non-vocabulary state'
run_command cas --expected-generation "$before_generation" --expected-digest "$before_digest" --next-state done --candidate candidate-green
assert_nonzero 'G04_SIX_STATE_LIFECYCLE: rejects implementing directly to done'
read_status
assert_contains "$(state_of)" '^implementing$' 'G04_RUN_CAS_LOCK: rejected transition leaves record unchanged'

before_generation="$(generation_of)"
before_digest="$(digest_of)"

run_command cas --expected-generation "$before_generation" --expected-digest "$before_digest" --next-state reviewing --candidate candidate-green
assert_success 'G04_SIX_STATE_LIFECYCLE: implementing transitions to reviewing'

# Successful receipts must bind the exact candidate; stale receipts cannot
# manually close a node.
read_status
review_generation="$(generation_of)"
review_digest="$(digest_of)"
. "$stale_receipts"
run_command cas --expected-generation "$review_generation" --expected-digest "$review_digest" --next-state done --candidate candidate-green --check-receipt "$check_receipt" --verifier-receipt "$verifier_receipt" --reviewer-receipt "$reviewer_receipt"
assert_nonzero 'G04_DONE_REQUIRES_FRESH_RECEIPTS: stale candidate receipts reject done'
. "$current_receipts"
mkdir -p "$authority/receipts"
cp "$valid_receipts"/*.env "$authority/receipts/"
run_command cas --expected-generation "$review_generation" --expected-digest "$review_digest" --next-state done --candidate candidate-green --check-receipt "$check_receipt" --verifier-receipt "$verifier_receipt" --reviewer-receipt "$reviewer_receipt"
assert_success 'G04_DONE_REQUIRES_FRESH_RECEIPTS: exact current protected receipt artifacts permit done'
read_status
assert_contains "$(state_of)" '^done$' 'G04_SIX_STATE_LIFECYCLE: status reports done'

# A receipt locator alone is not enough: an authority with no receipt store
# must reject done even when the three CLI values look exact and current.
missing_receipt_authority="$TEST_TMP/protected-missing-receipts"
mkdir -p "$missing_receipt_authority"
chmod 700 "$missing_receipt_authority"
cp "$fixture" "$missing_receipt_authority/bootstrap.env"
missing_receipt_cas() { bash "$writer" --authority "$missing_receipt_authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture "$@"; }
run_command missing_receipt_cas --expected-generation 0 --expected-digest sha256:pending-fixture --next-state implementing --candidate candidate-green
assert_success 'G04_DONE_RECEIPT_ARTIFACT_BINDING: receiptless fixture reaches implementing'
missing_receipt_digest="$(sed -n 's/^digest=//p' "$RUN_OUT" | head -n 1)"
run_command missing_receipt_cas --expected-generation 1 --expected-digest "$missing_receipt_digest" --next-state reviewing --candidate candidate-green
assert_success 'G04_DONE_RECEIPT_ARTIFACT_BINDING: receiptless fixture reaches reviewing'
missing_receipt_digest="$(sed -n 's/^digest=//p' "$RUN_OUT" | head -n 1)"
run_command missing_receipt_cas --expected-generation 2 --expected-digest "$missing_receipt_digest" --next-state done --candidate candidate-green --check-receipt check:20260729-GV53BZ:p01:candidate-green:success --verifier-receipt verifier:20260729-GV53BZ:p01:candidate-green:success --reviewer-receipt reviewer:20260729-GV53BZ:p01:candidate-green:success
assert_nonzero 'G04_DONE_RECEIPT_ARTIFACT_BINDING: absent receipt store rejects done'

# A new isolated record makes stale-preimage and race semantics observable.
race_authority="$TEST_TMP/protected-race"
mkdir -p "$race_authority"
chmod 700 "$race_authority"
cp "$fixture" "$race_authority/bootstrap.env"
race_call() {
  bash "$writer" --authority "$race_authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture --expected-generation 0 --expected-digest sha256:pending-fixture --next-state implementing --candidate candidate-race
}
race_call >"$TEST_TMP/race-one.out" 2>"$TEST_TMP/race-one.err" & race_one=$!
race_call >"$TEST_TMP/race-two.out" 2>"$TEST_TMP/race-two.err" & race_two=$!
wait "$race_one"; race_one_status=$?
wait "$race_two"; race_two_status=$?
race_wins=0
[ "$race_one_status" -eq 0 ] && race_wins=$((race_wins + 1))
[ "$race_two_status" -eq 0 ] && race_wins=$((race_wins + 1))
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$race_wins" -eq 1 ]; then pass 'G04_RACE_ONE_WINNER: exactly one stale-preimage writer wins'; else fail "G04_RACE_ONE_WINNER: expected one winner, got $race_wins"; fi

# Failures in review may only re-enter implementation with a materially new
# candidate.  The unchanged candidate blocks rather than creating a loop.
rem_authority="$TEST_TMP/protected-remediation"
mkdir -p "$rem_authority"
chmod 700 "$rem_authority"
cp "$fixture" "$rem_authority/bootstrap.env"
rem_cas() { bash "$writer" --authority "$rem_authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture "$@"; }
run_command rem_cas --expected-generation 0 --expected-digest sha256:pending-fixture --next-state implementing --candidate candidate-one
run_command rem_cas --expected-generation 1 --expected-digest "$(sed -n 's/^digest=//p' "$RUN_OUT" | head -n 1)" --next-state reviewing --candidate candidate-one
rem_digest="$(sed -n 's/^digest=//p' "$RUN_OUT" | head -n 1)"
run_command rem_cas --expected-generation 2 --expected-digest "$rem_digest" --next-state implementing --candidate candidate-one --reviewer-receipt reviewer:20260729-GV53BZ:p01:candidate-one:failed
assert_nonzero 'G04_FAILED_REVIEW_REMEDIATION_OR_BLOCK: unchanged failed review rejects remediation'
run_command bash "$status_reader" --authority "$rem_authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture --status
assert_success 'G04_FAILED_REVIEW_REMEDIATION_OR_BLOCK: blocked remediation record remains readable'
assert_file_contains "$RUN_OUT" '^state=blocked$' 'G04_FAILED_REVIEW_REMEDIATION_OR_BLOCK: unchanged candidate becomes blocked'

# Receipt-shaped caller strings are never authority.  These files have the
# expected vocabulary and fields, but intentionally carry a forged binding;
# the writer must resolve and validate them, not trust CLI text.
forged_authority="$TEST_TMP/protected-forged-receipts"
mkdir -p "$forged_authority/receipts"
chmod 700 "$forged_authority"
cp "$fixture" "$forged_authority/bootstrap.env"
cp "$forged_receipts"/*.env "$forged_authority/receipts/"
forged_cas() { bash "$writer" --authority "$forged_authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture "$@"; }
run_command forged_cas --expected-generation 0 --expected-digest sha256:pending-fixture --next-state implementing --candidate candidate-forged
assert_success 'G04_DONE_RECEIPT_ARTIFACT_BINDING: forged fixture reaches implementing'
forged_digest="$(sed -n 's/^digest=//p' "$RUN_OUT" | head -n 1)"
run_command forged_cas --expected-generation 1 --expected-digest "$forged_digest" --next-state reviewing --candidate candidate-forged
assert_success 'G04_DONE_RECEIPT_ARTIFACT_BINDING: forged fixture reaches reviewing'
forged_digest="$(sed -n 's/^digest=//p' "$RUN_OUT" | head -n 1)"
run_command forged_cas --expected-generation 2 --expected-digest "$forged_digest" --next-state done --candidate candidate-forged --check-receipt check:20260729-GV53BZ:p01:candidate-forged:success --verifier-receipt verifier:20260729-GV53BZ:p01:candidate-forged:success --reviewer-receipt reviewer:20260729-GV53BZ:p01:candidate-forged:success
assert_nonzero 'G04_DONE_RECEIPT_ARTIFACT_BINDING: format-correct forged receipt artifacts reject done'

# A symlink anywhere in the authority path is unsafe, even when the final
# component itself is a real protected directory.
ancestor_real="$TEST_TMP/authority-ancestor-real"
ancestor_link="$TEST_TMP/authority-ancestor-link"
mkdir -p "$ancestor_real/protected"
chmod 700 "$ancestor_real/protected"
cp "$fixture" "$ancestor_real/protected/bootstrap.env"
ln -s "$ancestor_real" "$ancestor_link"
ancestor_authority="$ancestor_link/protected"
run_command bash "$writer" --authority "$ancestor_authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture --expected-generation 0 --expected-digest sha256:pending-fixture --next-state implementing --candidate candidate-ancestor
assert_nonzero 'G04_RUN_CAS_LOCK: writer rejects symlinked authority ancestor'
run_command bash "$status_reader" --authority "$ancestor_authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture --status
assert_nonzero 'G04_RUN_CAS_LOCK: reader rejects symlinked authority ancestor'

# A deterministic after-lock harness proves that interruption cannot turn an
# uncommitted preimage into a fresh writer opportunity.  The maker hook exists
# solely under explicit WG_TEST_* variables and is never used in production.
interrupt_authority="$TEST_TMP/protected-interrupt"
interrupt_hold="$TEST_TMP/interrupt-lock-held"
interrupt_release="$TEST_TMP/interrupt-release"
mkdir -p "$interrupt_authority"
chmod 700 "$interrupt_authority"
cp "$fixture" "$interrupt_authority/bootstrap.env"
env WG_TEST_HOLD_AFTER_LOCK_FILE="$interrupt_hold" WG_TEST_RELEASE_LOCK_FILE="$interrupt_release" \
  bash "$writer" --authority "$interrupt_authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture --expected-generation 0 --expected-digest sha256:pending-fixture --next-state implementing --candidate candidate-interrupted >"$TEST_TMP/interrupted.out" 2>"$TEST_TMP/interrupted.err" &
interrupted_pid=$!
hold_seen=false
hold_attempt=0
while [ "$hold_attempt" -lt 40 ]; do
  if [ -f "$interrupt_hold" ]; then hold_seen=true; break; fi
  sleep 0.05
  hold_attempt=$((hold_attempt + 1))
done
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$hold_seen" = true ]; then pass 'G04_INTERRUPT_STALE_WRITER: writer reached the held locked section'; else fail 'G04_INTERRUPT_STALE_WRITER: writer did not expose deterministic locked section'; fi
if [ "$hold_seen" = true ]; then kill -TERM "$interrupted_pid"; fi
wait "$interrupted_pid"; interrupted_status=$?
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$hold_seen" = true ] && [ "$interrupted_status" -ne 0 ]; then pass 'G04_INTERRUPT_STALE_WRITER: interrupted writer fails closed'; else fail "G04_INTERRUPT_STALE_WRITER: interrupted writer unexpectedly exited $interrupted_status"; fi
run_command bash "$writer" --authority "$interrupt_authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture --expected-generation 0 --expected-digest sha256:pending-fixture --next-state implementing --candidate candidate-stale-after-interrupt
assert_nonzero 'G04_INTERRUPT_STALE_WRITER: signal cannot release lock for a stale writer'

# Traversal and symlink inputs never become authority paths.
final_generation="$(generation_of)"
final_digest="$(digest_of)"
run_command bash "$writer" --authority "$authority/../escape" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture --expected-generation "$final_generation" --expected-digest "$final_digest" --next-state cancelled --candidate candidate-green --abandonment-authority human:abandon
assert_nonzero 'G04_RUN_CAS_LOCK: traversal authority is rejected'
ln -s "$authority" "$TEST_TMP/authority-link"
run_command bash "$status_reader" --authority "$TEST_TMP/authority-link" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture --status
assert_nonzero 'G04_RUN_CAS_LOCK: symlink authority is rejected'

status_output="$(cat "$RUN_OUT" 2>/dev/null || true)"
assert_not_contains "$status_output" 'percent|%|selected|next-node' 'G04_EMPTY_FRONTIER_BLOCKED: status is derived and never selects work or exposes subjective percentage'

# Reopen is valid only before any protected binding.  This authority already
# contains an active, completed run, so the validator must fail closed.
run_command bash "$status_reader" --authority "$authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture --reopen --approval-revoked
assert_nonzero 'G04_PREACTIVATION_REOPEN_ONLY: bound run authority rejects in-place reopen'

# Bootstrap is itself protected run binding.  A missing run-state.env cannot
# make that binding disappear and permit an in-place plan reopen.
bootstrap_only_authority="$TEST_TMP/protected-bootstrap-only"
mkdir -p "$bootstrap_only_authority"
chmod 700 "$bootstrap_only_authority"
cp "$fixture" "$bootstrap_only_authority/bootstrap.env"
run_command bash "$status_reader" --authority "$bootstrap_only_authority" --identity 20260729-GV53BZ --plan p01 --run run-g04-fixture --reopen --approval-revoked
assert_nonzero 'G04_PREACTIVATION_REOPEN_ONLY: bootstrap-only authority rejects in-place reopen'

finish_tests
