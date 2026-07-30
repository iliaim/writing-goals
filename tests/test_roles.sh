#!/usr/bin/env bash
# Protected G03 oracle: validates the role contract and host-native wrappers.
set -u
. "$(dirname "$0")/testlib.sh"

role_fixture="$REPO_DIR/tests/fixtures/roles/role-contracts.tsv"
host_fixture="$REPO_DIR/tests/fixtures/roles/host-facts.tsv"
roles_doc="$REPO_DIR/shared/roles.md"

roles='planner challenger oracle-author maker verifier reviewer publisher'

fail_missing_contracts() {
  printf '%s\n' 'FAIL: G03_ROLE_CONTRACTS_MISSING' >&2
  exit 1
}

# This must remain first: the frozen red receipt identifies an absent G03
# contract, never a malformed fixture or an unavailable host executable.
[ -f "$roles_doc" ] || fail_missing_contracts
[ -f "$role_fixture" ] || fail_missing_contracts
[ -f "$host_fixture" ] || fail_missing_contracts
for role in $roles; do
  [ -f "$REPO_DIR/assets/roles/writing-goals-$role.md" ] || fail_missing_contracts
  [ -f "$REPO_DIR/claude/agents/writing-goals-$role.md" ] || fail_missing_contracts
  [ -f "$REPO_DIR/codex/agents/writing-goals-$role.toml" ] || fail_missing_contracts
done

while IFS=$'\t' read -r fact_id url checked_utc implication; do
  case "$fact_id" in ''|'#'*) continue ;; esac
  assert_file_contains "$roles_doc" "$url" "$fact_id: canonical role policy retains the primary-source URL"
  assert_file_contains "$roles_doc" "$checked_utc" "$fact_id: canonical role policy records its verification date"
done < "$host_fixture"

assert_file_contains "$roles_doc" 'advisory.*(not|rather than).*enforce|not.*enforce.*advisory' \
  'G03_ROLE_ISOLATION: path and prompt restrictions are labelled advisory unless host-enforced'
assert_file_contains "$roles_doc" 'same.model.*correlat|correlat.*same.model' \
  'G03_SAME_MODEL_CORRELATION: same-model review is explicitly correlated evidence'
assert_file_contains "$roles_doc" 'static definitions.*proxy|proxy.*static definitions' \
  'G03_STATIC_PROXY_LIMIT: static host definitions are proxy evidence, not prose-compliance proof'

while IFS=$'\t' read -r role assertion_id contract_pattern; do
  case "$role" in ''|'#'*) continue ;; esac
  asset="$REPO_DIR/assets/roles/writing-goals-$role.md"
  claude="$REPO_DIR/claude/agents/writing-goals-$role.md"
  codex="$REPO_DIR/codex/agents/writing-goals-$role.toml"

  assert_file_contains "$asset" "$contract_pattern" "$assertion_id: canonical $role capsule states its contract"
  assert_file_contains "$claude" "^name:[[:space:]]*writing-goals-$role$" "$assertion_id: Claude $role identity is exact"
  assert_file_contains "$claude" '^description:' "$assertion_id: Claude $role has host-required routing description"
  assert_file_contains "$claude" "$contract_pattern" "$assertion_id: Claude $role wrapper preserves the contract"
  assert_file_contains "$codex" '^developer_instructions[[:space:]]*=' "$assertion_id: Codex $role has a role-specific instruction layer"
  assert_file_contains "$codex" "^name[[:space:]]*=[[:space:]]*\"writing-goals-$role\"$" "$assertion_id: Codex $role identity is exact"
  assert_file_contains "$codex" '^description[[:space:]]*=' "$assertion_id: Codex $role has host-required routing description"
  assert_file_contains "$codex" "$contract_pattern" "$assertion_id: Codex $role wrapper preserves the contract"
done < "$role_fixture"

assert_file_contains "$roles_doc" 'planner.*challenger.*(one|single).*preapproval.*DAG|preapproval.*DAG.*planner.*challenger' \
  'G03_PREAPPROVAL_DAG_REVIEW: planner and challenger jointly review one decomposition/DAG before approval'
assert_file_contains "$roles_doc" 'standalone_slice.*parent_objective|parent_objective.*standalone_slice' \
  'G03_ACTIVATION_CLASS_EXACT: activation classification names exactly standalone_slice or parent_objective'
assert_file_contains "$roles_doc" 'parent_objective.*(approved objective|frozen plan|complete approved DAG|protected run authority)' \
  'G03_PARENT_PREREQUISITES_COMPLETE: parent activation has complete approved prerequisites'

finish_tests
