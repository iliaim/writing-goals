#!/usr/bin/env bash
set -u
. "$(dirname "$0")/testlib.sh"

deny_hook="$REPO_DIR/assets/deny-list.sh"

run_hook() {
  local root="$1" tool="$2" command="$3" cwd="${4:-$1}" payload
  payload="$(jq -cn --arg tool "$tool" --arg command "$command" --arg cwd "$cwd" '{tool_name:$tool,tool_input:{command:$command},cwd:$cwd}')"
  run_input "$payload" env HOME="$TEST_TMP/home" CLAUDE_PROJECT_DIR="$root" bash "$deny_hook"
}

assert_denied() {
  local label="$1"
  assert_success "$label exits with the hook allow/deny status"
  assert_deny_json "$RUN_OUT" "$label emits deny JSON"
}

assert_allowed() {
  local label="$1"
  assert_success "$label exits zero"
  assert_empty_file "$RUN_OUT" "$label emits no deny decision"
}

root="$TEST_TMP/repo"
outside="$TEST_TMP/outside"
mkdir -p "$root/subdir" "$outside"
printf 'one\n' > "$root/safe.txt"

# A valid payload cwd is authoritative over a bad environment root.
payload="$(jq -cn --arg command 'touch payload-root.txt' --arg cwd "$root" '{tool_name:"Bash",tool_input:{command:$command},cwd:$cwd}')"
run_input "$payload" env HOME="$TEST_TMP/home" CLAUDE_PROJECT_DIR="$TEST_TMP/not-a-repo" bash "$deny_hook"
assert_allowed 'payload cwd selects the repository root for supported mutations'

# Invalid payload roots fall back first to Claude's project directory, then to
# the hook process working directory.
payload="$(jq -cn --arg command 'touch claude-root.txt' '{tool_name:"Bash",tool_input:{command:$command},cwd:"/does-not-exist"}')"
run_input "$payload" env HOME="$TEST_TMP/home" CLAUDE_PROJECT_DIR="$root" bash "$deny_hook"
assert_allowed 'valid Claude project directory is the second root source'

payload="$(jq -cn --arg command 'touch process-root.txt' '{tool_name:"Bash",tool_input:{command:$command},cwd:"/does-not-exist"}')"
run_input "$payload" env TEST_HOOK="$deny_hook" TEST_ROOT="$root" TEST_PATH="$PATH" TEST_HOME="$TEST_TMP/home" \
  bash -c 'cd "$TEST_ROOT" || exit; exec env -i PATH="$TEST_PATH" HOME="$TEST_HOME" CLAUDE_PROJECT_DIR=/also-missing bash "$TEST_HOOK"'
assert_allowed 'process working directory is the final root source'

run_hook "$root" Bash "touch $outside/touched" "$root"
assert_denied 'touch outside the repository is denied'
run_hook "$root" Bash 'touch subdir/inside' "$root"
assert_allowed 'touch inside the repository is allowed'

run_hook "$root" Bash "mkdir $outside/new-dir" "$root"
assert_denied 'mkdir outside the repository is denied'
run_hook "$root" Bash 'mkdir subdir/new-dir' "$root"
assert_allowed 'mkdir inside the repository is allowed'

run_hook "$root" Bash "sed -Ei '' 's/one/two/' $outside/file" "$root"
assert_denied 'combined-option in-place sed outside the repository is denied'
run_hook "$root" Bash "sed -Ei '' 's/one/two/' safe.txt" "$root"
assert_allowed 'combined-option in-place sed inside the repository is allowed'

run_hook "$root" Bash 'gh pr create'
assert_denied 'gh is denied as an external mutator'
run_hook "$root" Bash 'glab mr create'
assert_denied 'glab is denied as an external mutator'

# Missing every root source is unsafe for a recognized mutator.
payload="$(jq -cn --arg command 'touch unknown-root.txt' '{tool_name:"Bash",tool_input:{command:$command},cwd:"/does-not-exist"}')"
deleted_cwd="$TEST_TMP/deleted-cwd"
mkdir "$deleted_cwd"
run_input "$payload" env TEST_HOOK="$deny_hook" TEST_CWD="$deleted_cwd" TEST_PATH="$PATH" TEST_HOME="$TEST_TMP/home" \
  bash -c 'cd "$TEST_CWD" || exit; rmdir "$TEST_CWD" || exit; env -i PATH="$TEST_PATH" HOME="$TEST_HOME" CLAUDE_PROJECT_DIR=/also-missing bash "$TEST_HOOK"'
assert_denied 'supported mutation with no valid repository root fails closed'

valid_patch='*** Begin Patch
*** Add File: safe-added.txt
+hello
*** Update File: safe.txt
@@
*** ordinary star-prefixed hunk content
*** Delete File: old.txt
*** End Patch'
run_hook "$root" apply_patch "$valid_patch" "$root"
assert_allowed 'structured in-repository Add Update Delete patch is allowed'

for bad_patch in \
  '*** Begin Patch
*** Add File: ../escape.txt
+no
*** End Patch' \
  "*** Begin Patch
*** Add File: $outside/escape.txt
+no
*** End Patch" \
  '*** Begin Patch
*** Update File: safe.txt
*** Move to: ../escape.txt
@@
-old
+new
*** End Patch' \
  "*** Begin Patch
*** Update File: safe.txt
*** Move to: $outside/escape.txt
@@
-old
+new
*** End Patch" \
  '*** Add File: safe.txt
+missing-boundary' \
  '*** Begin Patch
*** Add File: safe.txt
+missing-end-boundary' \
  '*** Begin Patch
*** End Patch' \
  '*** Begin Patch
*** Unknown File: safe.txt
*** End Patch' \
  '*** Begin Patch
*** Add Filename: confused.txt
*** Add File: safe.txt
+content
*** End Patch' \
  '*** Begin Patch
--- a/safe.txt
+++ b/safe.txt
*** End Patch'; do
  run_hook "$root" apply_patch "$bad_patch" "$root"
  assert_denied 'malformed or escaping apply_patch payload is denied'
done

# Older callers supplied a separate .patch field. The current contract is the
# command string; silently accepting a missing command would skip validation.
payload="$(jq -cn --arg patch "$valid_patch" --arg cwd "$root" '{tool_name:"apply_patch",tool_input:{patch:$patch},cwd:$cwd}')"
run_input "$payload" env HOME="$TEST_TMP/home" CLAUDE_PROJECT_DIR="$root" bash "$deny_hook"
assert_denied 'legacy patch-only apply_patch payload is denied'

finish_tests
