#!/usr/bin/env bash
# Protected G01 oracle: validates the public OKF/profile contract without
# granting the validator permission to alter a workspace.
set -u
. "$(dirname "$0")/testlib.sh"

validator="$REPO_DIR/assets/validate-markdown.sh"
fixtures="$REPO_DIR/tests/fixtures/okf"

# This is deliberately the first assertion: G01's protected red must identify
# a missing validator entrypoint, rather than a fixture or test-harness error.
if [ ! -f "$validator" ]; then
  printf '%s\n' 'FAIL: G01_OKF_ENTRYPOINT_MISSING' >&2
  exit 1
fi

copy_fixture() {
  local name destination
  name="$1"
  destination="$TEST_TMP/$name/20260729-GV53BZ--writing-goals-v1"
  mkdir -p "${destination%/*}"
  cp -R "$fixtures/valid" "$destination"
  printf '%s\n' "$destination"
}

workspace_digest() {
  local root="$1"
  (
    cd "$root" || exit 1
    find . -type f -print | LC_ALL=C sort | while IFS= read -r path; do
      printf '%s\0' "$path"
      cat "$path"
    done
  ) | shasum -a 256 | awk '{print $1}'
}

run_validator() {
  run_command bash "$validator" "$1"
}

emit_u64() {
  local value="$1" divisor byte
  printf '\000\000\000\000'
  for divisor in 16777216 65536 256 1; do
    byte=$((value / divisor % 256))
    printf "\\$(printf '%03o' "$byte")"
  done
}

refresh_plan_payload_digest() {
  local plan_root="$1" payload_digest
  payload_digest="$({
    { printf '%s\n' objective.md index.md; find "$plan_root/goals" -type f -name '*.md' -print 2>/dev/null | sed "s#^$plan_root/##"; } | LC_ALL=C sort | while IFS= read -r relative; do
      content="$plan_root/$relative"
      path_bytes="$(LC_ALL=C printf '%s' "$relative" | wc -c | tr -d ' ')"
      content_bytes="$(wc -c < "$content" | tr -d ' ')"
      emit_u64 "$path_bytes"
      printf '%s' "$relative"
      emit_u64 "$content_bytes"
      cat "$content"
    done
  } | shasum -a 256 | awk '{print $1}')"
  jq --arg digest "$payload_digest" '.plan_payload.frozen_sha256 = $digest' \
    "$plan_root/revision.json" > "$plan_root/revision.json.tmp" &&
    mv "$plan_root/revision.json.tmp" "$plan_root/revision.json"
}

workspace="$(copy_fixture 'valid-workspace')"
before_digest="$(workspace_digest "$workspace")"
run_validator "$workspace"
assert_success 'G01_OKF_ROUTES: reserved index, ordinary profile, and owner-schema routes pass'
after_digest="$(workspace_digest "$workspace")"
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$before_digest" = "$after_digest" ]; then
  pass 'G01_OKF_NON_MUTATING: validation leaves the workspace byte-identical'
else
  fail 'G01_OKF_NON_MUTATING: validation rewrote fixture bytes'
fi

workspace="$(copy_fixture 'unknown-extensions')"
run_validator "$workspace"
assert_success 'G01_UNKNOWN_EXTENSIONS: unknown OKF key and type are accepted'

workspace="$(copy_fixture 'bad-identity')"
bad_identity_root="${workspace%/*}/20260729-GV53BI--writing-goals-v1"
mv "$workspace" "$bad_identity_root"
workspace="$bad_identity_root"
run_validator "$workspace"
assert_nonzero 'G01_IDENTITY_REVISION: invalid Crockford workspace identity is rejected'

workspace="$(copy_fixture 'bad-revision')"
mv "$workspace/plans/p01" "$workspace/plans/p1"
run_validator "$workspace"
assert_nonzero 'G01_IDENTITY_REVISION: non-pNN revision directory is rejected'

workspace="$(copy_fixture 'missing-revision-manifest')"
cp -R "$workspace/plans/p01" "$workspace/plans/p02"
rm "$workspace/plans/p01/revision.json"
run_validator "$workspace"
assert_nonzero 'G01_IDENTITY_REVISION: a pNN directory without revision.json is rejected'

workspace="$(copy_fixture 'implicit-latest')"
mkdir "$workspace/plans/latest"
cp "$workspace/plans/p01/objective.md" "$workspace/plans/latest/objective.md"
run_validator "$workspace"
assert_nonzero 'G01_IDENTITY_REVISION: implicit latest revision route is rejected'

workspace="$(copy_fixture 'index-policy')"
sed -i.bak '2a\
type: plan_index' "$workspace/plans/p01/index.md"
rm "$workspace/plans/p01/index.md.bak"
run_validator "$workspace"
assert_nonzero 'G01_INDEX_NAVIGATION_ONLY: reserved indexes reject non-navigation frontmatter'

workspace="$(copy_fixture 'index-normative-body')"
printf '%s\n' '' 'All goals MUST include independently verifiable completion evidence.' >> "$workspace/plans/p01/index.md"
run_validator "$workspace/plans/p01/index.md"
assert_nonzero 'G01_INDEX_NAVIGATION_ONLY: reserved indexes reject normative requirements in their body'

workspace="$(copy_fixture 'index-lifecycle-body')"
printf '%s\n' '' 'A goal moves from draft to stable only after review approval.' >> "$workspace/plans/p01/index.md"
run_validator "$workspace/plans/p01/index.md"
assert_nonzero 'G01_INDEX_NAVIGATION_ONLY: reserved indexes reject lifecycle policy in their body'

workspace="$(copy_fixture 'index-missing-frontmatter')"
sed -i.bak '1,3d' "$workspace/plans/p01/index.md"
rm "$workspace/plans/p01/index.md.bak"
refresh_plan_payload_digest "$workspace/plans/p01"
run_validator "$workspace/plans/p01/index.md"
assert_nonzero 'G01_INDEX_OKF_FRONTMATTER: direct validation rejects a plan index without frontmatter'
assert_contains "$(cat "$RUN_ERR")" 'missing or invalid OKF version' 'G01_INDEX_OKF_FRONTMATTER: direct validation identifies missing frontmatter'
run_validator "$workspace"
assert_nonzero 'G01_INDEX_OKF_FRONTMATTER: directory validation rejects a plan index without frontmatter'
assert_contains "$(cat "$RUN_ERR")" 'missing or invalid OKF version' 'G01_INDEX_OKF_FRONTMATTER: directory validation identifies missing frontmatter'

workspace="$(copy_fixture 'index-missing-okf-version')"
sed -i.bak '/^okf_version:/d' "$workspace/plans/p01/index.md"
rm "$workspace/plans/p01/index.md.bak"
refresh_plan_payload_digest "$workspace/plans/p01"
run_validator "$workspace/plans/p01/index.md"
assert_nonzero 'G01_INDEX_OKF_VERSION: direct validation rejects a plan index without okf_version'
assert_contains "$(cat "$RUN_ERR")" 'missing or invalid OKF version' 'G01_INDEX_OKF_VERSION: direct validation identifies missing okf_version'
run_validator "$workspace"
assert_nonzero 'G01_INDEX_OKF_VERSION: directory validation rejects a plan index without okf_version'
assert_contains "$(cat "$RUN_ERR")" 'missing or invalid OKF version' 'G01_INDEX_OKF_VERSION: directory validation identifies missing okf_version'

workspace="$(copy_fixture 'unowned-malformed')"
printf '%s\n' 'this unowned Markdown lacks OKF frontmatter' > "$workspace/docs/unowned.md"
run_validator "$workspace"
assert_nonzero 'G01_UNOWNED_MARKDOWN: malformed unowned Markdown is rejected'

workspace="$(copy_fixture 'owner-overreach')"
printf '%s\n' 'this is not an allowlisted Claude agent definition' > "$workspace/claude/agents/other.md"
run_validator "$workspace"
assert_nonzero 'G01_OWNER_SCHEMA_ALLOWLIST: non-namespaced owner route is rejected'

workspace="$(copy_fixture 'nested-claude-owner-route')"
mkdir -p "$workspace/claude/agents/writing-goals-maker"
printf '%s\n' 'a nested descendant is not a Claude agent definition' > "$workspace/claude/agents/writing-goals-maker/nested.md"
run_validator "$workspace"
assert_nonzero 'G01_OWNER_SCHEMA_ALLOWLIST: nested Claude-agent descendants are rejected'

workspace="$(copy_fixture 'nested-role-owner-route')"
mkdir -p "$workspace/assets/roles/writing-goals-maker"
printf '%s\n' 'a nested descendant is not a role definition' > "$workspace/assets/roles/writing-goals-maker/nested.md"
run_validator "$workspace"
assert_nonzero 'G01_OWNER_SCHEMA_ALLOWLIST: nested role descendants are rejected'

workspace="$(copy_fixture 'single-goal-file')"
run_validator "$workspace/plans/p01/goals/g01.md"
assert_success 'G01_SINGLE_FILE_ROUTE: a nested valid goal file validates on its own'

workspace="$(copy_fixture 'single-goal-missing-manifest')"
rm "$workspace/plans/p01/revision.json"
run_validator "$workspace/plans/p01/goals/g01.md"
assert_nonzero 'G01_SINGLE_FILE_MANIFEST_BINDING: a nested goal rejects a missing enclosing manifest'

workspace="$(copy_fixture 'single-goal-draft-manifest')"
sed -i.bak 's/"frozen_approved"/"draft_unfrozen"/' "$workspace/plans/p01/revision.json"
rm "$workspace/plans/p01/revision.json.bak"
run_validator "$workspace/plans/p01/goals/g01.md"
assert_nonzero 'G01_SINGLE_FILE_MANIFEST_BINDING: a nested goal rejects a draft enclosing manifest'

workspace="$(copy_fixture 'single-goal-tampered-manifest')"
sed -i.bak 's/"frozen_sha256": "98d754b0d1b705a01ec6e19a6655eff4ca555cd2671a1b40067699ed2ba93ae6"/"frozen_sha256": "0000000000000000000000000000000000000000000000000000000000000000"/' "$workspace/plans/p01/revision.json"
rm "$workspace/plans/p01/revision.json.bak"
run_validator "$workspace/plans/p01/goals/g01.md"
assert_nonzero 'G01_SINGLE_FILE_MANIFEST_BINDING: a nested goal rejects a tampered enclosing manifest'

workspace="$(copy_fixture 'single-objective-draft-manifest')"
sed -i.bak 's/"frozen_approved"/"draft_unfrozen"/' "$workspace/plans/p01/revision.json"
rm "$workspace/plans/p01/revision.json.bak"
run_validator "$workspace/plans/p01/objective.md"
assert_nonzero 'G01_SINGLE_FILE_MANIFEST_BINDING: a direct objective rejects a draft enclosing manifest'

workspace="$(copy_fixture 'single-objective-tampered-manifest')"
sed -i.bak 's/"frozen_sha256": "98d754b0d1b705a01ec6e19a6655eff4ca555cd2671a1b40067699ed2ba93ae6"/"frozen_sha256": "0000000000000000000000000000000000000000000000000000000000000000"/' "$workspace/plans/p01/revision.json"
rm "$workspace/plans/p01/revision.json.bak"
run_validator "$workspace/plans/p01/objective.md"
assert_nonzero 'G01_SINGLE_FILE_MANIFEST_BINDING: a direct objective rejects a tampered enclosing manifest'

workspace="$(copy_fixture 'single-index-draft-manifest')"
sed -i.bak 's/"frozen_approved"/"draft_unfrozen"/' "$workspace/plans/p01/revision.json"
rm "$workspace/plans/p01/revision.json.bak"
run_validator "$workspace/plans/p01/index.md"
assert_nonzero 'G01_SINGLE_FILE_MANIFEST_BINDING: a direct index rejects a draft enclosing manifest'

workspace="$(copy_fixture 'single-index-tampered-manifest')"
sed -i.bak 's/"frozen_sha256": "98d754b0d1b705a01ec6e19a6655eff4ca555cd2671a1b40067699ed2ba93ae6"/"frozen_sha256": "0000000000000000000000000000000000000000000000000000000000000000"/' "$workspace/plans/p01/revision.json"
rm "$workspace/plans/p01/revision.json.bak"
run_validator "$workspace/plans/p01/index.md"
assert_nonzero 'G01_SINGLE_FILE_MANIFEST_BINDING: a direct index rejects a tampered enclosing manifest'

workspace="$(copy_fixture 'missing-goal-id')"
sed -i.bak '/^id: G01-FIXTURE$/d' "$workspace/plans/p01/goals/g01.md"
rm "$workspace/plans/p01/goals/g01.md.bak"
run_validator "$workspace"
assert_nonzero 'G01_GOAL_ID: a goal without an id is rejected'

workspace="$(copy_fixture 'invalid-goal-id')"
sed -i.bak 's/^id: G01-FIXTURE$/id: invalid id/' "$workspace/plans/p01/goals/g01.md"
rm "$workspace/plans/p01/goals/g01.md.bak"
run_validator "$workspace"
assert_nonzero 'G01_GOAL_ID: a goal id with whitespace is rejected'

workspace="$(copy_fixture 'missing-goal-type')"
sed -i.bak '/^type: goal$/d' "$workspace/plans/p01/goals/g01.md"
rm "$workspace/plans/p01/goals/g01.md.bak"
run_validator "$workspace"
assert_nonzero 'G01_GOAL_TYPE: a goal without a type is rejected'

workspace="$(copy_fixture 'incomplete-goal-profile')"
sed -i.bak '/^    algorithm: sha256$/d' "$workspace/plans/p01/goals/g01.md"
rm "$workspace/plans/p01/goals/g01.md.bak"
run_validator "$workspace"
assert_nonzero 'G01_GOAL_PROFILE: an incomplete writing_goals profile is rejected'

workspace="$(copy_fixture 'plan-payload-tamper')"
sed -i.bak 's/"frozen_sha256": "6b34feac73a8ccb2bbd5ae67a526051e74bff162120199537127b8fb7d87c37f"/"frozen_sha256": "0000000000000000000000000000000000000000000000000000000000000000"/' "$workspace/plans/p01/revision.json"
rm "$workspace/plans/p01/revision.json.bak"
run_validator "$workspace"
assert_nonzero 'G01_PLAN_PAYLOAD_MANIFEST_BINDING: payload digest tampering is rejected'

workspace="$(copy_fixture 'goal-different-manifest')"
cp "$workspace/plans/p01/revision.json" "$workspace/plans/p01/different-revision.json"
sed -i.bak 's#manifest_ref: "../revision.json"#manifest_ref: "../different-revision.json"#' "$workspace/plans/p01/goals/g01.md"
rm "$workspace/plans/p01/goals/g01.md.bak"
run_validator "$workspace"
assert_nonzero 'G01_GOAL_MANIFEST_BINDING: a goal bound to another manifest is rejected'

workspace="$(copy_fixture 'manifest-tamper')"
sed -i.bak 's/"frozen_approved"/"draft_unfrozen"/' "$workspace/plans/p01/revision.json"
rm "$workspace/plans/p01/revision.json.bak"
run_validator "$workspace"
assert_nonzero 'G01_OBJECTIVE_SNAPSHOT_MANIFEST_BINDING: draft manifest cannot masquerade as approval'

workspace="$(copy_fixture 'snapshot-tamper')"
printf '\nTampered after freeze.\n' >> "$workspace/plans/p01/objective.md"
run_validator "$workspace"
assert_nonzero 'G01_OBJECTIVE_SNAPSHOT_MANIFEST_BINDING: objective digest must match frozen manifest'

finish_tests
