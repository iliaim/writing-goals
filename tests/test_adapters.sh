#!/usr/bin/env bash
# G08's host adapters are intentionally thin. These assertions test declared,
# fixture-supported wiring; static templates do not prove live host behavior.
set -u
. "$(dirname "$0")/testlib.sh"

claude_skill="$REPO_DIR/claude/SKILL.md"
codex_skill="$REPO_DIR/codex/SKILL.md"
claude_hooks="$REPO_DIR/claude/hooks.json.tmpl"
codex_hooks="$REPO_DIR/codex/hooks.json.tmpl"

for file in "$claude_hooks" "$codex_hooks"; do
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ -f "$file" ] && jq -e . "$file" >/dev/null 2>&1; then
    pass "G08_ADAPTER_CONTRACT_MISSING: $file is valid JSON"
  else
    fail "G08_ADAPTER_CONTRACT_MISSING: $file must exist as valid JSON"
  fi
done

assert_file_contains "$claude_hooks" '"Stop"' 'G08_NATIVE_ADAPTERS: Claude registers Stop'
assert_file_contains "$claude_hooks" '"PreToolUse"' 'G08_NATIVE_ADAPTERS: Claude registers PreToolUse'
assert_file_contains "$claude_hooks" '"Bash"' 'G08_NATIVE_ADAPTERS: Claude limits deny coverage to Bash'
assert_file_contains "$claude_hooks" 'gate\.claude\.sh' 'G08_NATIVE_ADAPTERS: Claude uses its Stop gate'
assert_file_contains "$claude_hooks" 'deny-list\.sh' 'G08_NATIVE_ADAPTERS: Claude uses the payload policy hook'
assert_file_contains "$codex_hooks" '"Stop"' 'G08_NATIVE_ADAPTERS: Codex registers Stop'
assert_file_contains "$codex_hooks" '"PreToolUse"' 'G08_NATIVE_ADAPTERS: Codex registers PreToolUse'
assert_file_contains "$codex_hooks" '"Bash"' 'G08_NATIVE_ADAPTERS: Codex supports Bash/unified execution only'
assert_file_contains "$codex_hooks" '"apply_patch"' 'G08_NATIVE_ADAPTERS: Codex supports apply_patch only when validated'
assert_file_contains "$codex_hooks" 'gate\.codex\.sh' 'G08_NATIVE_ADAPTERS: Codex uses its Stop gate'
assert_file_contains "$codex_hooks" 'deny-list\.sh' 'G08_NATIVE_ADAPTERS: Codex uses the payload policy hook'

assert_file_contains "$claude_skill" 'sandbox-exec|OS-level sandbox' 'G08_PROXY_LABELS: Claude requires an OS sandbox'
assert_file_contains "$codex_skill" 'sandbox-exec|OS-level sandbox' 'G08_PROXY_LABELS: Codex requires an OS sandbox'
assert_file_contains "$claude_skill" 'not a security boundary|not.*containment' 'G08_PROXY_LABELS: Claude labels hooks as a proxy'
assert_file_contains "$codex_skill" 'not a security boundary|not.*containment' 'G08_PROXY_LABELS: Codex labels hooks as a proxy'
assert_file_contains "$codex_skill" 'one native Codex goal|one native goal' 'G08_NATIVE_GOAL_BINDS_PARENT: Codex documents exactly one native goal'
assert_file_contains "$codex_skill" 'complete objective/run|complete objective and run' 'G08_NATIVE_GOAL_BINDS_PARENT: the native goal binds the parent'
assert_file_contains "$codex_skill" 'child.*never.*complete.*parent|never.*child.*complete.*parent' 'G08_NATIVE_GOAL_BINDS_PARENT: child completion cannot complete the parent'
assert_file_contains "$codex_skill" 'parent.*rollup.*incomplete|incomplete.*parent.*rollup' 'G08_NATIVE_GOAL_BINDS_PARENT: incomplete rollup rejects native completion'
assert_not_contains "$(cat "$codex_skill")" 'MCP tools.*PreToolUse|most other local function tools.*PreToolUse|Hosted tools.*excluded' 'G08_PROXY_LABELS: Codex makes no unvalidated broader coverage claim'

native_parent_fixture="$REPO_DIR/tests/fixtures/host-isolation/codex-native-parent.sh"
run_command bash "$native_parent_fixture" 'objective-20260729' 'run-42' 'objective-20260729/run-42' child_success incomplete attempt_native_parent_completion
assert_status 73 'G08_PREMATURE_NATIVE_COMPLETION_REJECTED: child success cannot complete an incomplete parent'
assert_contains "$(cat "$RUN_OUT")" '^REJECT: child success cannot complete an incomplete native parent goal$' 'G08_PREMATURE_NATIVE_COMPLETION_REJECTED: fixture records the native-completion rejection'

run_command bash "$native_parent_fixture" 'objective-20260729' 'run-42' 'objective-20260729/run-42' child_success incomplete explicit_resume
assert_success 'G08_EXPLICIT_RESUME: incomplete parent resumes instead of completing natively'
assert_contains "$(cat "$RUN_OUT")" '^RESUME: retain the parent goal and dispatch the next frozen-order child$' 'G08_EXPLICIT_RESUME: fixture preserves the bound parent and next child'

run_command bash "$native_parent_fixture" 'objective-20260729' 'run-42' 'child-goal/run-42' child_success incomplete explicit_resume
assert_status 64 'G08_NATIVE_GOAL_BINDS_PARENT: a child binding is rejected in place of the complete objective/run'

finish_tests
