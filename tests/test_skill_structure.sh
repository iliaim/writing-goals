#!/usr/bin/env bash
# G10 protected oracle: package/reference surface for the quality-evaluation contract.
set -u
. "$(dirname "$0")/testlib.sh"

policy="$REPO_DIR/shared/skill-quality.md"
runner="$REPO_DIR/scripts/run-skill-behavioral-eval.sh"
fixtures="$REPO_DIR/tests/fixtures/skill-evals"

missing() { printf '%s\n' 'FAIL: G10_STRUCTURE_CONTRACT_MISSING' >&2; exit 1; }

# This guard intentionally happens before content parsing.  It is the exact,
# deterministic red tuple recorded in the plan.
[ -f "$policy" ] && [ -f "$runner" ] && [ -x "$runner" ] && [ -d "$fixtures" ] || missing

assert_file_contains "$policy" 'risk-based|affected-risk' \
  'G10_PACKAGE_STRUCTURE: policy selects evaluation by affected risk'
assert_file_contains "$policy" 'deterministic' \
  'G10_PACKAGE_STRUCTURE: policy separates deterministic checks'
assert_file_contains "$policy" 'held-out|without.skill|with.skill' \
  'G10_PACKAGE_STRUCTURE: policy defines a paired held-out comparison'
assert_file_contains "$policy" '(not|never).*(deterministic proof|prove).*model|model.*(not|never).*(deterministic proof|prove)' \
  'G10_PACKAGE_STRUCTURE: policy does not claim model behavior is deterministic proof'
assert_file_contains "$policy" 'release candidate|host/version|supported host' \
  'G10_PACKAGE_STRUCTURE: policy scopes live smoke to release or host change'
assert_file_contains "$runner" '--scorer-contract' \
  'G10_PACKAGE_STRUCTURE: runner exposes the deterministic scorer-contract mode'
assert_file_contains "$runner" '--protected-config' \
  'G10_PACKAGE_STRUCTURE: runner keeps live configuration protected'
assert_file_contains "$runner" '--output' \
  'G10_PACKAGE_STRUCTURE: runner requires an explicit evidence output path'

for file in rubric.tsv paired-smoke.tsv planning-positive.tsv planning-antipatterns.tsv plan-recipe-lint.tsv execution-invariants.tsv execution-order.tsv host-contract.tsv; do
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ -s "$fixtures/$file" ]; then
    pass "G10_REFERENCE_METADATA_PARITY: $file is a non-empty protected fixture"
  else
    fail "G10_REFERENCE_METADATA_PARITY: missing or empty $file"
  fi
done

assert_file_contains "$fixtures/paired-smoke.tsv" '^scenario_id\thost\tarm\tassertion_id$' \
  'G10_REFERENCE_METADATA_PARITY: paired smoke has an explicit arm schema'
assert_file_contains "$fixtures/host-contract.tsv" '^host\targv$' \
  'G10_REFERENCE_METADATA_PARITY: host command metadata has a stable schema'
assert_file_contains "$fixtures/rubric.tsv" '^assertion_id\tclass\trequired$' \
  'G10_REFERENCE_METADATA_PARITY: fixed rubric metadata has a stable schema'

finish_tests
