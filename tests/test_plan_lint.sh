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

run_variant() {
  local name expected plan manifest
  name="$1"
  expected="$2"
  plan="$TEST_TMP/plan-lint-$name.yml"
  manifest="$TEST_TMP/plan-lint-$name.json"
  shift 2
  "$@" > "$plan"
  printf '{"schema":"writing-goals-plan-manifest/v1","plan_digest":"sha256:%s"}\n' \
    "$(shasum -a 256 "$plan" | awk '{print $1}')" > "$manifest"
  run_command bash "$linter" --plan "$plan" --manifest "$manifest" --index "$fixtures/valid/index.md"
  assert_nonzero "G14_SCOPED_PARSER: $name is rejected"
  assert_contains "$(cat "$RUN_OUT" "$RUN_ERR")" "$expected" \
    "G14_SCOPED_PARSER: $name reports its exact structural failure"
}

assert_file_contains "$recipe" 'behavioral_code.*(red|characterization).*green|behavioral_code.*green' 'G14_TASK_CLASS_ROUTING: behavioral code has a red-to-green route'
assert_file_contains "$recipe" 'docs_config.*(red|characterization).*green|docs_config.*green' 'G14_TASK_CLASS_ROUTING: docs/config has a red-to-green route'
assert_file_contains "$recipe" 'refactor.*characterization.*green|refactor.*green' 'G14_TASK_CLASS_ROUTING: refactor has a characterization route'
assert_file_contains "$recipe" 'research_design.*(source|challenge)' 'G14_TASK_CLASS_ROUTING: research design has sourced challenge'
assert_file_contains "$recipe" 'research_design.*(does not|no).*red|no.*red.*research_design' 'G14_TASK_CLASS_ROUTING: research never invents red/green work'
assert_file_contains "$recipe" 'node.*task class|task class.*node|per-node' 'G14_NODE_SCOPED_TASK_CLASS: task class is declared per node'
assert_file_contains "$recipe" 'evidence_route' 'G14_TASK_CLASS_ROUTING: nodes declare a structural evidence route'
assert_file_contains "$recipe" 'alternatives.*rejection|rejection.*alternatives' 'G14_ALTERNATIVES_RECORDED: full plans record credible alternatives and rejected reasons'
assert_file_contains "$recipe" 'activatable successor revision.*complete, self-contained' 'G14_SUCCESSOR_AUTHORITY_COMPLETE: an activatable successor must bind the complete plan'
assert_file_contains "$recipe" 'narrow correction|untrusted evidence only' 'G14_PARTIAL_CORRECTION_NONAUTHORITATIVE: a partial correction cannot become execution authority'
assert_file_contains "$linter" '(not|never).*(semantic|prose)|(semantic|prose).*(not|never)' 'G14_NO_AUTOMATED_SEMANTIC_APPROVAL: linter is structural only'

run_lint valid
assert_success 'G14_RECIPE_FIELDS_REQUIRED: complete canonical recipe is accepted'

run_variant empty-alternatives 'empty alternatives need an explicit reason' \
  awk 'BEGIN { replacing=0 } /^alternatives:/ { print "alternatives: []"; replacing=1; next } replacing && /^dag:/ { replacing=0 } !replacing { print }' "$fixtures/valid/plan.yml"
run_variant missing-route 'invalid evidence route' \
  sed '/^    evidence_route: /d' "$fixtures/valid/plan.yml"
run_variant incomplete-evidence 'evidence command is incomplete' \
  sed 's/^          expected_exit:/        expected_exit:/' "$fixtures/valid/plan.yml"
run_variant evidence-cross-section 'evidence command is incomplete' \
  awk 'BEGIN { removed=0; injected=0 }
       /^          expected_exit: 0$/ && !removed { removed=1; next }
       /^      handoff:/ && removed && !injected {
         print "      handoff:"; print "        detail:"; print "          expected_exit: 0"; injected=1; next
       }
       { print }' "$fixtures/valid/plan.yml"
run_variant cyclic-dag 'dag is cyclic' \
  sed '1,/^    depends_on: \[\]$/s/^    depends_on: \[\]$/    depends_on: [verify]/' "$fixtures/valid/plan.yml"
run_variant invalid-node-id 'dag node id is missing or invalid' \
  sed 's/^  - id: author$/  - id: invalid.id/' "$fixtures/valid/plan.yml"
run_variant duplicate-node-id 'dag node ids must be unique' \
  sed 's/^  - id: verify$/  - id: author/' "$fixtures/valid/plan.yml"
run_variant unknown-dependency 'dag dependency is unknown' \
  sed 's/^    depends_on: \[author\]$/    depends_on: [unknown]/' "$fixtures/valid/plan.yml"
run_variant missing-execution-recipe 'missing execution recipe' \
  sed '/^    execution_recipe:/d' "$fixtures/valid/plan.yml"
run_variant missing-top-level-routes 'missing top-level acceptance routes' \
  sed '/^objective_acceptance:/d' "$fixtures/valid/plan.yml"
run_variant placeholder 'placeholders are not permitted' \
  awk '{ print } END { print "# TODO: remove" }' "$fixtures/valid/plan.yml"
run_variant workflow-order 'workflow must lint before challenge and freeze' \
  sed 's/^workflow:.*/workflow: [discover, author, challenge, lint, freeze]/' "$fixtures/valid/plan.yml"

run_command bash "$linter" --plan "$fixtures/valid/plan.yml" --manifest "$fixtures/valid/manifest.json" --index "$fixtures/duplicate-index/index.md"
assert_nonzero 'G14_INDEX_POLICY: duplicated plan policy in the navigation index is rejected'
assert_contains "$(cat "$RUN_OUT" "$RUN_ERR")" 'navigation index must not duplicate plan policy' \
  'G14_INDEX_POLICY: index policy diagnostic is exact'
run_lint digest-mismatch
assert_nonzero 'G14_DIGEST_BINDING: a manifest cannot bind a different plan'
assert_contains "$(cat "$RUN_OUT" "$RUN_ERR")" 'manifest digest does not bind the exact plan' \
  'G14_DIGEST_BINDING: digest binding diagnostic is exact'
for case_name in fake-task-class expanded-node-missing-depends write-collision; do
  run_lint "$case_name"
  case "$case_name" in
    fake-task-class) assertion_id=G14_TASK_CLASS_ROUTING ;;
    expanded-node-missing-depends) assertion_id=G14_DAG_AND_ORDER_VALID ;;
    write-collision) assertion_id=G14_WRITE_COLLISIONS_REJECTED ;;
  esac
  assert_nonzero "$assertion_id: $case_name structural fixture is rejected"
  case "$case_name" in
    fake-task-class) expected='unsupported task class' ;;
    expanded-node-missing-depends) expected='missing dependency declaration' ;;
    write-collision) expected='maker and oracle paths collide across the dag' ;;
  esac
  assert_contains "$(cat "$RUN_OUT" "$RUN_ERR")" "$expected" \
    "$assertion_id: $case_name rejects for its declared invariant"
done

finish_tests
