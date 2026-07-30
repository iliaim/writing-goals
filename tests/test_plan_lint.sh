#!/usr/bin/env bash
# Protected G14 oracle: structural plan-lint contract, frozen before maker work.
set -u
. "$(dirname "$0")/testlib.sh"

linter="$REPO_DIR/scripts/plan-lint.sh"
recipe="$REPO_DIR/shared/planning-recipe.md"
template="$REPO_DIR/assets/goal.md.tmpl"
fixtures="$REPO_DIR/tests/fixtures/plan-lint"

missing() { printf '%s\n' 'FAIL: G14_PLAN_LINT_CONTRACT_MISSING' >&2; exit 1; }

# This guard deliberately precedes parsing and execution: absence is the exact
# protected red, never a broken fixture or a host-tool failure.
[ -f "$linter" ] && [ -x "$linter" ] && [ -f "$recipe" ] && [ -f "$template" ] && [ -d "$fixtures" ] || missing

run_lint() {
  local case_name="$1"
  run_command bash "$linter" --plan "$fixtures/$case_name/plan.yml" --manifest "$fixtures/$case_name/manifest.json" --index "$fixtures/$case_name/index.md"
}

assert_file_contains "$recipe" 'behavioral_code.*(red|characterization).*green|behavioral_code.*green' 'G14_TASK_CLASS_ROUTING: behavioral code has a red-to-green route'
assert_file_contains "$recipe" 'docs_config.*(red|characterization).*green|docs_config.*green' 'G14_TASK_CLASS_ROUTING: docs/config has a red-to-green route'
assert_file_contains "$recipe" 'refactor.*characterization.*green|refactor.*green' 'G14_TASK_CLASS_ROUTING: refactor has a characterization route'
assert_file_contains "$recipe" 'research_design.*(source|challenge)' 'G14_TASK_CLASS_ROUTING: research design has sourced challenge'
assert_file_contains "$recipe" 'research_design.*(does not|no).*red|no.*red.*research_design' 'G14_TASK_CLASS_ROUTING: research never invents red/green work'
assert_file_contains "$linter" '(not|never).*(semantic|prose)|(semantic|prose).*(not|never)' 'G14_NO_AUTOMATED_SEMANTIC_APPROVAL: linter is structural only'

run_lint valid
assert_success 'G14_RECIPE_FIELDS_REQUIRED: complete canonical recipe is accepted'
for case_name in missing-recipe fake-task-class invalid-dag expanded-node-missing-depends hidden-duplicate-id empty-expanded-id unknown-dependency three-node-cycle missing-routes write-collision bad-command duplicate-index placeholder lint-order digest-mismatch; do
  run_lint "$case_name"
  case "$case_name" in
    missing-recipe) assertion_id=G14_RECIPE_FIELDS_REQUIRED ;;
    fake-task-class) assertion_id=G14_TASK_CLASS_ROUTING ;;
    invalid-dag) assertion_id=G14_DAG_AND_ORDER_VALID ;;
    expanded-node-missing-depends) assertion_id=G14_DAG_AND_ORDER_VALID ;;
    hidden-duplicate-id) assertion_id=G14_DAG_AND_ORDER_VALID ;;
    empty-expanded-id) assertion_id=G14_DAG_AND_ORDER_VALID ;;
    unknown-dependency) assertion_id=G14_DAG_AND_ORDER_VALID ;;
    three-node-cycle) assertion_id=G14_DAG_AND_ORDER_VALID ;;
    missing-routes) assertion_id=G14_REQUIREMENT_AND_ACCEPTANCE_ROUTES ;;
    write-collision) assertion_id=G14_WRITE_COLLISIONS_REJECTED ;;
    bad-command) assertion_id=G14_EXACT_COMMAND_BINDINGS ;;
    duplicate-index) assertion_id=G14_NAVIGATION_ONLY_INDEXES ;;
    placeholder) assertion_id=G14_NO_PLACEHOLDERS ;;
    lint-order) assertion_id=G14_LINT_BEFORE_CHALLENGE_AND_FREEZE ;;
    digest-mismatch) assertion_id=G14_PLAN_DIGEST_BOUND ;;
  esac
  assert_nonzero "$assertion_id: $case_name structural fixture is rejected"
done

finish_tests
