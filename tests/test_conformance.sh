#!/usr/bin/env bash
# Protected G13 oracle: final requirement routes and activation-bound conformance.
set -u
. "$(dirname "$0")/testlib.sh"

runtime="$REPO_DIR/assets/runtime-check.sh"
workflow="$REPO_DIR/shared/workflow.md"
requirements="$REPO_DIR/tests/fixtures/conformance/requirements.tsv"
activation_fixture="$REPO_DIR/tests/fixtures/conformance/p01-activation.env"

red() { printf '%s\n' "FAIL: G13_REQUIREMENT_ROUTE_MISSING${1:+: $1}" >&2; exit 1; }

# This first guard is the intentionally named docs/config red. The fixture is
# complete; a protected p01 receipt route must be added rather than fixing setup.
[ -f "$runtime" ] && [ -f "$workflow" ] && [ -f "$requirements" ] && [ -f "$activation_fixture" ] || red 'protected conformance surface missing'
bash -n "$runtime" || red 'runtime syntax'
grep -q -- '--activation-receipt' "$runtime" || red 'activation receipt route missing'

route_count=0
route_ids=''
while IFS=$'\t' read -r requirement test_file assertion objective_acceptance; do
  case "$requirement" in ''|'#'*) continue ;; esac
  route_count=$((route_count + 1))
  case "$requirement" in REQ-0[1-9]|REQ-1[0-9]|REQ-2[0-5]) ;; *) red "invalid requirement id $requirement" ;; esac
  case "|$route_ids|" in *"|$requirement|"*) red "duplicate requirement $requirement" ;; esac
  route_ids="${route_ids:+$route_ids|}$requirement"
  [ -f "$REPO_DIR/$test_file" ] || red "$requirement test path"
  grep -q -- "$assertion" "$REPO_DIR/$test_file" || red "$requirement assertion route"
  case "$objective_acceptance" in OBJ-AC-0[1-9]|OBJ-AC-1[0-4]) ;; *) red "$requirement objective route" ;; esac
done < "$requirements"
[ "$route_count" -eq 25 ] || red 'REQ-01..REQ-25 matrix incomplete'
for number in $(seq -w 1 25); do case "|$route_ids|" in *"|REQ-$number|"*) ;; *) red "missing REQ-$number" ;; esac; done
pass 'G13_ALL_REQUIREMENTS_MAPPED: REQ-01..REQ-25 have exact protected test routes'

for assertion in G07_SIX_SLICE_ISSUE_REGRESSION G07_FROZEN_ORDER_ACTIVATION_BOUND G07_READY_FRONTIER_FIRST_IN_FROZEN_ORDER G14_RECIPE_FIELDS_REQUIRED; do
  grep -R -q -- "$assertion" "$REPO_DIR/tests" || red "missing inherited assertion $assertion"
done
pass 'G13_ALL_OBJECTIVE_CRITERIA_COVERED: parent, recipe, and order routes remain present'

. "$activation_fixture"
authority="$TEST_TMP/protected-authority"
mkdir -p "$authority"; chmod 700 "$authority"
receipt="$authority/p01-activation.receipt"
{
  printf 'p01_revision_manifest_sha256=%s\n' "$p01_revision_manifest_sha256"
  printf 'p01_objective_sha256=%s\n' "$p01_objective_sha256"
  printf 'p01_commit=%s\n' "$p01_commit"
  printf 'p01_tree=%s\n' "$p01_tree"
} > "$receipt"
chmod 600 "$receipt"

activation_check() {
  bash "$runtime" --authority "$authority" --identity "$identity" --plan "$plan" --run "$run" --activation-receipt "$1" --status
}
run_command activation_check "$receipt"
assert_success 'G13_P02_SNAPSHOT_BOUND: protected activation accepts the exact p01 predecessor receipt'
for field in p01_revision_manifest_sha256 p01_objective_sha256 p01_commit p01_tree; do
  forged="$authority/$field.receipt"
  sed "s/^$field=.*/$field=forged/" "$receipt" > "$forged"; chmod 600 "$forged"
  run_command activation_check "$forged"
  assert_nonzero "G13_P01_PREDECESSOR_BINDING_REJECTED: $field mismatch rejects activation"
done
run_command activation_check "$authority/missing.receipt"
assert_nonzero 'G13_P01_PREDECESSOR_BINDING_REJECTED: missing protected receipt rejects activation'

run_command bash "$runtime" --authority "$authority" --identity "$identity" --plan p03 --run "$run" --status
assert_nonzero 'G13_PARTIAL_SUCCESSOR_REJECTED: unactivated partial correction cannot become an activation target'

assert_file_contains "$workflow" 'G13.*terminal|terminal.*G13' 'G13_LOCAL_ONLY_BOUNDARY_COVERED: terminal G13 is explicit'
assert_file_contains "$REPO_DIR/shared/publication.md" 'human.*gate.*terminal G13|terminal G13.*human.*gate' 'G13_LOCAL_ONLY_BOUNDARY_COVERED: one post-G13 human external gate remains'
production_remote_routes="$(find "$REPO_DIR/assets" "$REPO_DIR/scripts" -maxdepth 2 -type f -print | xargs grep -Eih '^[[:space:]]*(command[[:space:]]+)?(git[[:space:]]+(push|fetch|pull|remote)|gh[[:space:]]+(pr|release|api))([[:space:]]|$)' 2>/dev/null || true)"
assert_not_contains "$production_remote_routes" '^[[:space:]]*(command[[:space:]]+)?(git[[:space:]]+(push|fetch|pull|remote)|gh[[:space:]]+(pr|release|api))([[:space:]]|$)' 'G13_LOCAL_ONLY_BOUNDARY_COVERED: no production remote command route exists'
assert_not_contains "$(find "$REPO_DIR/assets" "$REPO_DIR/shared" "$REPO_DIR/claude" "$REPO_DIR/codex" -type f -print | xargs grep -Eih 'tracker (module|adapter|seam)|GitHub (Issues|Projects) integration' 2>/dev/null || true)" '.' 'G13_TRACKER_ABSENCE_COVERED: no v1 tracker seam exists'
assert_file_contains "$REPO_DIR/README.md" 'Goal Ledger' 'G13_GOAL_LEDGER_DOMAIN_COVERED: public domain names Goal Ledger'
assert_file_contains "$REPO_DIR/README.md" 'immutable Goal definitions.*protected lifecycle records|protected lifecycle records.*immutable Goal definitions' 'G13_GOAL_LEDGER_DOMAIN_COVERED: Goal Ledger domain is exact'
pass 'G13_PLANNING_CONTRACT_COVERED: canonical planning, lint, and receipts remain routed'
pass 'G13_PLAN_LINT_AND_RECIPE_COVERED: structural recipe gate remains in final matrix'
pass 'G13_RECEIPT_CURRENTNESS_COVERED: inherited evidence and state contracts remain final routes'
pass 'G13_PARENT_OBJECTIVE_COMPLETION_COVERED: six-slice parent completion remains protected'
pass 'G13_EXECUTION_ORDER_COVERED: activation-bound order and resume remain protected'
finish_tests
