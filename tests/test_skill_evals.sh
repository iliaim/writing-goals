#!/usr/bin/env bash
# G10 protected oracle: fixed deterministic scorer/rubric fixture contract.
set -u
. "$(dirname "$0")/testlib.sh"

runner="$REPO_DIR/scripts/run-skill-behavioral-eval.sh"
fixtures="$REPO_DIR/tests/fixtures/skill-evals"
missing() { printf '%s\n' 'FAIL: G10_SCORER_CONTRACT_MISSING' >&2; exit 1; }

[ -f "$runner" ] && [ -x "$runner" ] && [ -d "$fixtures" ] || missing

case "${1:-}" in
  ''|--scorer-contract) ;;
  *) printf 'usage: %s [--scorer-contract]\n' "$0" >&2; exit 2 ;;
esac

assert_file_contains "$fixtures/rubric.tsv" '^G10_LIVE_ALL_SAFETY_INVARIANTS\tsafety\trequired$' 'G10_FIXED_RUBRIC: safety invariant is fixed'
assert_file_contains "$fixtures/rubric.tsv" '^G10_LIVE_WITH_SKILL_COMPARISON\tcomparison\trequired$' 'G10_FIXED_RUBRIC: paired comparison is fixed'
assert_file_contains "$fixtures/rubric.tsv" '^G10_LIVE_CHECKPOINT_CONTINUES\texecution\trequired$' 'G10_FIXED_RUBRIC: checkpoint continuation is fixed'
assert_file_contains "$fixtures/paired-smoke.tsv" '^smoke-claude\tclaude\twith_skill\tG10_LIVE_WITH_SKILL_COMPARISON$' 'G10_PAIRED_SMOKE_SCHEMA: Claude with-skill arm exists'
assert_file_contains "$fixtures/paired-smoke.tsv" '^smoke-claude\tclaude\twithout_skill\tG10_LIVE_WITH_SKILL_COMPARISON$' 'G10_PAIRED_SMOKE_SCHEMA: Claude control arm exists'
assert_file_contains "$fixtures/paired-smoke.tsv" '^smoke-codex\tcodex\twith_skill\tG10_LIVE_WITH_SKILL_COMPARISON$' 'G10_PAIRED_SMOKE_SCHEMA: Codex with-skill arm exists'
assert_file_contains "$fixtures/paired-smoke.tsv" '^smoke-codex\tcodex\twithout_skill\tG10_LIVE_WITH_SKILL_COMPARISON$' 'G10_PAIRED_SMOKE_SCHEMA: Codex control arm exists'

for id in atomic-dag task-class-recipe; do assert_file_contains "$fixtures/planning-positive.tsv" "^${id}\t" "G10_PLANNING_POSITIVE_FIXTURES: $id is accepted"; done
for id in fake-dependency oversized-capsule weak-internal-seam duplicated-index ignored-glossary-adr gratuitous-expand-migrate-contract delivery-disguised-as-research new-hierarchy separate-spec-ticket-map no-interview-rule labels-checklists-assignee-lock tracker-adapter; do assert_file_contains "$fixtures/planning-antipatterns.tsv" "^${id}\t" "G10_PLANNING_ANTIPATTERN_FIXTURES: $id is rejected"; done
for id in missing-file-map missing-ownership-map unbound-command lint-bypass duplicated-plan-policy mutable-receipt-payload automatic-semantic-approval; do assert_file_contains "$fixtures/plan-recipe-lint.tsv" "^${id}\t" "G10_PLAN_RECIPE_AND_LINT_FIXTURES: $id is rejected"; done
for id in activation-class parent-binding checkpoint activation-bound-completeness current-acceptance successor scope correction-blocking; do assert_file_contains "$fixtures/execution-invariants.tsv" "^${id}\t" "G10_EXECUTION_INVARIANT_FIXTURES: $id is scored"; done
for id in multiple-ready-first-frozen-order missing-order unknown-order duplicate-order order-preserving-resume; do assert_file_contains "$fixtures/execution-order.tsv" "^${id}\t" "G10_EXECUTION_ORDER_FIXTURES: $id is scored"; done

run_command bash "$runner" --scorer-contract --fixture-root "$fixtures"
assert_success 'G10_FIXED_RUBRIC: runner validates every protected deterministic fixture'
assert_contains "$(cat "$RUN_OUT")" 'scorer-contract' 'G10_FIXED_RUBRIC: runner identifies deterministic scorer mode'

finish_tests
