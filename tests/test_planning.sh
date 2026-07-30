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

assert_file_contains "$workflow" 'one question|single question' \
  'G03_DISCOVERY_DIALOGUE: discovery asks one question at a time'
assert_file_contains "$workflow" 'two.*alternative|four.*alternative|2.*alternative|4.*alternative' \
  'G03_ALTERNATIVE_REJECTION: planning records two-to-four alternatives and why rejected'
assert_file_contains "$workflow" 'approval barrier|approved.*before.*(dispatch|activation)|before.*(dispatch|activation).*approved' \
  'G03_APPROVAL_BARRIER: no maker dispatch or activation precedes plan approval'
assert_file_contains "$template" 'observable_outcome|observable outcome' \
  'G03_TEMPLATE_OUTCOME: template persists an observable outcome field'
assert_file_contains "$template" 'start_gates|start gates|genuine_start_gates' \
  'G03_TEMPLATE_START_GATES: template persists genuine start gates'
assert_file_contains "$template" 'capsule.*(bound|size)|capsule_bound' \
  'G03_TEMPLATE_CAPSULE: template persists a bounded capsule'
assert_file_contains "$template" 'integration' \
  'G03_TEMPLATE_INTEGRATION: template assigns integration responsibility'

while IFS= read -r artifact; do
  case "$artifact" in ''|'#'*) continue ;; esac
  assert_contains "$planning_surface" "(no|without|reject).*${artifact}" \
    "G03_REJECTED_PLANNING_ARTIFACTS: policy rejects new $artifact planning state"
done < "$rejected"

finish_tests
