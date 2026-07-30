#!/usr/bin/env bash
# Protected G14 oracle: ephemeral derived capsule and closed receipt contract.
set -u
. "$(dirname "$0")/testlib.sh"

capsule="$REPO_DIR/scripts/render-role-capsule.sh"
receipt="$REPO_DIR/scripts/render-planning-receipt.sh"
plan="$REPO_DIR/tests/fixtures/planning-receipts/valid/plan.yml"
manifest="$REPO_DIR/tests/fixtures/planning-receipts/valid/manifest.json"
fixtures="$REPO_DIR/tests/fixtures/planning-receipts"
roles="$REPO_DIR/assets/roles"

missing() { printf '%s\n' 'FAIL: G14_PLANNING_RECEIPT_CONTRACT_MISSING' >&2; exit 1; }
[ -f "$capsule" ] && [ -x "$capsule" ] && [ -f "$receipt" ] && [ -x "$receipt" ] && [ -f "$plan" ] && [ -f "$manifest" ] && [ -d "$roles" ] || missing

capsule_out="$TEST_TMP/capsule.json"
receipt_out="$TEST_TMP/receipt.json"
run_command bash "$capsule" --plan "$plan" --manifest "$manifest" --role writing-goals-challenger --output "$capsule_out"
assert_success 'G14_CAPSULE_IS_EPHEMERAL: capsule renders on demand from a canonical plan'
assert_file_contains "$capsule_out" '"schema"[[:space:]]*:[[:space:]]*"writing-goals-role-capsule/v1"' 'G14_CAPSULE_IS_EPHEMERAL: capsule uses the derived schema'
assert_file_contains "$capsule_out" '"plan_manifest_digest"[[:space:]]*:' 'G14_CAPSULE_PLAN_DIGEST_BOUND: capsule includes plan manifest digest'
assert_file_contains "$capsule_out" '"role"[[:space:]]*:[[:space:]]*"writing-goals-challenger"' 'G14_CAPSULE_IS_EPHEMERAL: capsule preserves selected role'
run_command jq -e '. | keys == ["plan_manifest_digest", "role", "schema"]' "$capsule_out"
assert_success 'G14_CLOSED_RECEIPT_SCHEMA: capsule is a closed derived envelope'

run_command bash "$receipt" --plan "$plan" --manifest "$manifest" --role writing-goals-reviewer --status needs_human --findings-ref findings.md --evidence-ref evidence.md --follow-up-ref follow-up.md --output "$receipt_out"
assert_success 'G14_CLOSED_RECEIPT_SCHEMA: receipt renders from explicit derived inputs'
assert_file_contains "$receipt_out" '"schema"[[:space:]]*:[[:space:]]*"writing-goals-planning-receipt/v1"' 'G14_CLOSED_RECEIPT_SCHEMA: receipt schema is explicit'
assert_file_contains "$receipt_out" '"plan_manifest_digest"[[:space:]]*:' 'G14_RECEIPT_PLAN_DIGEST_BOUND: receipt includes plan manifest digest'
for key in role status findings_ref evidence_ref follow_up_ref; do
  assert_file_contains "$receipt_out" "\"$key\"[[:space:]]*:" "G14_CLOSED_RECEIPT_SCHEMA: receipt includes $key"
done
assert_not_contains "$(cat "$receipt_out")" '"(plan|dispatch|approval|selected_task)"[[:space:]]*:' 'G14_CLOSED_RECEIPT_SCHEMA: receipt excludes mutable plan or dispatch state'
run_command jq -e '. | keys == ["evidence_ref", "findings_ref", "follow_up_ref", "plan_manifest_digest", "role", "schema", "status"]' "$receipt_out"
assert_success 'G14_CLOSED_RECEIPT_SCHEMA: receipt contains no undeclared fields'

bad_manifest="$fixtures/digest-mismatch/manifest.json"
run_command bash "$capsule" --plan "$plan" --manifest "$bad_manifest" --role writing-goals-challenger --output "$TEST_TMP/bad-capsule.json"
assert_nonzero 'G14_CAPSULE_PLAN_DIGEST_BOUND: capsule rejects a non-matching SHA-256 manifest digest'
run_command bash "$receipt" --plan "$plan" --manifest "$bad_manifest" --role writing-goals-reviewer --status needs_human --findings-ref findings.md --evidence-ref evidence.md --follow-up-ref follow-up.md --output "$TEST_TMP/bad-receipt.json"
assert_nonzero 'G14_RECEIPT_PLAN_DIGEST_BOUND: receipt rejects a non-matching SHA-256 manifest digest'

malicious_ref="$(cat "$fixtures/json-injection/findings-ref.txt")"
run_command bash "$receipt" --plan "$plan" --manifest "$manifest" --role writing-goals-reviewer --status needs_human --findings-ref "$malicious_ref" --evidence-ref evidence.md --follow-up-ref follow-up.md --output "$TEST_TMP/injected-approval.json"
assert_nonzero 'G14_CLOSED_RECEIPT_SCHEMA: quote/newline approval injection is rejected'
malicious_ref="$(cat "$fixtures/json-injection/evidence-ref.txt")"
run_command bash "$receipt" --plan "$plan" --manifest "$manifest" --role writing-goals-reviewer --status needs_human --findings-ref findings.md --evidence-ref "$malicious_ref" --follow-up-ref follow-up.md --output "$TEST_TMP/injected-dispatch.json"
assert_nonzero 'G14_CLOSED_RECEIPT_SCHEMA: quote/newline dispatch injection is rejected'

for role_file in "$roles"/writing-goals-{planner,challenger,reviewer}.md; do
  assert_file_contains "$role_file" '(canonical plan|shared/planning-recipe)' 'G14_ROLE_PROMPTS_REFERENCE_CANONICAL_POLICY: role prompt references canonical policy'
  assert_not_contains "$(cat "$role_file")" 'task_class:|execution_recipe:|stop_rules:' 'G14_ROLE_PROMPTS_REFERENCE_CANONICAL_POLICY: role prompt does not copy plan policy'
done
assert_not_contains "$(cat "$capsule" "$receipt")" '(approve|select|dispatch).*(automatically|automated)|(automatically|automated).*(approve|select|dispatch)' 'G14_NO_AUTOMATED_SEMANTIC_APPROVAL: renderers never automate approval or dispatch'

for case_name in duplicate-plan copied-policy automated-approval generated-dispatch; do
  run_command bash "$receipt" --validate-fixture "$fixtures/$case_name"
  assert_nonzero "G14_${case_name}: prohibited persistent or automated fixture is rejected"
done

finish_tests
