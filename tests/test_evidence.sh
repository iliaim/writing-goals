#!/usr/bin/env bash
# Protected G05 oracle: receipt predicates are deliberately fixture-driven so
# receipt currentness cannot be asserted by a maker-owned status field.
set -u
. "$(dirname "$0")/testlib.sh"

checker="$REPO_DIR/assets/record-check.sh"
policy="$REPO_DIR/shared/evidence.md"
fixtures="$REPO_DIR/tests/fixtures/evidence"

fail_missing_predicate() {
  printf '%s\n' 'FAIL: G05_EVIDENCE_PREDICATE_MISSING' >&2
  exit 1
}

# This guard is intentionally before all fixture parsing: the protected red is
# an absent receipt predicate, never a fixture or shell-harness failure.
[ -f "$checker" ] || fail_missing_predicate
[ -f "$policy" ] || fail_missing_predicate
[ -d "$fixtures" ] || fail_missing_predicate

run_receipt() {
  run_command bash "$checker" --receipt "$fixtures/$1/receipt.tsv" --expected "$fixtures/$1/expected.tsv"
}

# The documented closed classes keep research from being manufactured as a red
# and distinguish refactor characterization from behavior failure.
for task_class in behavioral_code docs_config refactor research_design; do
  assert_file_contains "$policy" "$task_class" \
    "G05_TASK_CLASSES: evidence policy defines $task_class"
done
assert_file_contains "$policy" 'protected oracle.*maker|maker.*protected oracle' \
  'G05_DUAL_SURFACES: protected oracle and maker-owned tests remain distinct'
assert_file_contains "$policy" 'fresh verifier.*reviewer|verifier.*fresh reviewer' \
  'G05_DUAL_SURFACES: verifier and reviewer are fresh contexts'
assert_file_contains "$policy" 'derive.*current|current.*derive' \
  'G05_EVIDENCE_BINDINGS: currentness is derived from exact bindings'
assert_file_contains "$policy" 'objective.*criterion.*oracle.*candidate' \
  'G05_EVIDENCE_BINDINGS: policy binds objective, criterion, oracle, and candidate'
assert_file_contains "$policy" 'argv|argument vector' \
  'G05_EVIDENCE_BINDINGS: checks retain an exact argument vector'
assert_file_contains "$policy" 'output.*hash|hash.*output' \
  'G05_EVIDENCE_BINDINGS: output is represented by a bounded hash'
assert_not_contains "$(cat "$checker")" '(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)' \
  'G05_EVIDENCE_BINDINGS: checker never evaluates a recorded command'

for case_name in valid-behavioral-red valid-docs-config-red valid-refactor-characterization valid-research-design valid-check valid-review; do
  run_receipt "$case_name"
  assert_success "G05_TASK_CLASSES: $case_name is accepted only with its exact completed evidence"
done

for case_name in wrong-red-reason changed-argv fake-research-red characterization-drift binding-mismatch same-context malformed-actor malformed-output-hash remediation-same-candidate pending-state stored-currentness digest-binding-mismatch duplicate-binding-key duplicate-red-predicate research-check-crossover; do
  run_receipt "$case_name"
  assert_nonzero "G05_EVIDENCE_BINDINGS: $case_name is rejected"
done

finish_tests
