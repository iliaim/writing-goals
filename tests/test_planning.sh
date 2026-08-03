#!/usr/bin/env bash
# Protected G03 oracle: validates planning discipline without introducing a
# separate planning artifact or lifecycle state machine.
set -u
. "$(dirname "$0")/testlib.sh"

workflow="$REPO_DIR/shared/workflow.md"
template="$REPO_DIR/assets/goal.md.tmpl"
fixture="$REPO_DIR/tests/fixtures/planning/planning-contracts.tsv"
rejected="$REPO_DIR/tests/fixtures/planning/rejected-artifacts.txt"

fail_missing_contract() {
  printf '%s\n' 'FAIL: G03_PLANNING_CONTRACT_MISSING' >&2
  exit 1
}

# Keep this initial check deterministic. A missing policy is the intended red;
# fixture, parser, or host-version failures are wrong-red failures.
[ -f "$workflow" ] || fail_missing_contract
[ -f "$template" ] || fail_missing_contract
[ -f "$fixture" ] || fail_missing_contract
[ -f "$rejected" ] || fail_missing_contract

planning_surface="$(cat "$workflow" "$template")"
while IFS=$'\t' read -r assertion_id pattern; do
  case "$assertion_id" in ''|'#'*) continue ;; esac
  assert_contains "$planning_surface" "$pattern" "$assertion_id: canonical workflow or goal template carries the planning rule"
done < "$fixture"

assert_file_contains "$workflow" 'credible alternatives.*rejection reasons|alternatives.*rejection reasons' \
  'G03_ALTERNATIVE_REJECTION: planning records credible alternatives and why rejected'
assert_file_contains "$workflow" 'A human approves the frozen plan before' \
  'G03_APPROVAL_BARRIER: no maker dispatch or activation precedes plan approval'
assert_file_contains "$workflow" 'user-visible review packet|review packet.*canonical plan' \
  'G03_PLAN_REVIEW_PACKET: full-tier planning presents phases and deliverables for user review'
assert_file_contains "$workflow" 'approve, request revision, change scope, pause, or cancel' \
  'G03_PLAN_REVIEW_OUTCOMES: full-tier planning records the available user review outcomes'
assert_file_contains "$template" 'Observable outcome|observable outcome' \
  'G03_TEMPLATE_OUTCOME: template persists an observable outcome field'
assert_file_contains "$template" 'Writable paths|Protected paths' \
  'G03_TEMPLATE_SCOPE: lightweight template persists scoped paths'
assert_file_contains "$template" 'Acceptance and regression checks' \
  'G03_TEMPLATE_CHECKS: lightweight template persists exact verification'
assert_file_contains "$template" 'Alternatives considered' \
  'G03_TEMPLATE_ALTERNATIVES: lightweight template persists alternatives'
assert_file_contains "$template" 'Read first / sources of truth' \
  'G03_TEMPLATE_READ_FIRST: lightweight template persists read-first sources'
assert_file_contains "$template" 'Non-goals / constraints' \
  'G03_TEMPLATE_CONSTRAINTS: lightweight template persists non-goals and constraints'
assert_file_contains "$template" 'Stop condition and checkpoints' \
  'G03_TEMPLATE_STOP_RULE: lightweight template persists stop and checkpoint rules'
assert_file_contains "$template" 'Documentation impact' \
  'G03_TEMPLATE_DOCUMENTATION: lightweight template persists documentation impact'

while IFS= read -r artifact; do
  case "$artifact" in ''|'#'*) continue ;; esac
  assert_contains "$planning_surface" "(no|without|reject).*${artifact}" \
    "G03_REJECTED_PLANNING_ARTIFACTS: policy rejects new $artifact planning state"
done < "$rejected"

finish_tests
