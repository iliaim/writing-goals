#!/usr/bin/env bash
# G10 protected oracle: offline host argv and fresh-home hermeticity.
set -u
. "$(dirname "$0")/testlib.sh"

runner="$REPO_DIR/scripts/run-skill-behavioral-eval.sh"
fixtures="$REPO_DIR/tests/fixtures/skill-evals"
shim_dir="$REPO_DIR/tests/host-shims"
missing() { printf '%s\n' 'FAIL: G10_HOST_CONTRACT_MISSING' >&2; exit 1; }

[ -f "$runner" ] && [ -x "$runner" ] && [ -f "$fixtures/host-contract.tsv" ] && [ -x "$shim_dir/claude" ] && [ -x "$shim_dir/codex" ] || missing
# The runner resolves its protected shim directory physically.  Canonicalize
# this test's PATH and expected values too, because macOS exposes /var through
# the /private/var symlink in ordinary temporary-directory paths.
shim_dir="$(CDPATH= cd -- "$shim_dir" && pwd -P)" || missing

home="$TEST_TMP/fresh-home"
log="$TEST_TMP/host.log"
resolution_log="$TEST_TMP/host-resolution.log"
cwd="$TEST_TMP/host-cwd"
mkdir -p "$home" "$cwd"

# `--host-contract` is an offline fixture-only path.  It must never fall
# through to a real host merely because a similarly named executable happens
# to be on PATH.  The guard therefore runs before either host command.
run_command env -i PATH="$shim_dir:/usr/bin:/bin" HOME="$home" CODEX_HOME="$home/.codex" \
  WG_EVAL_SHIM_LOG="$log" WG_EVAL_SHIM_RESOLUTION_LOG="$resolution_log" \
  WG_EVAL_EXPECT_HOME="$home" WG_EVAL_FORBID_PATH="$REPO_DIR" \
  bash -c 'cd "$1" && exec bash "$2" --host-contract --fixture-root "$3"' sh "$cwd" "$runner" "$fixtures"
assert_nonzero 'G10_HERMETIC_HOST_ENV: unmarked host-contract fails closed before host invocation'
assert_path_absent "$log" 'G10_HERMETIC_HOST_ENV: unmarked host-contract invokes neither fixture host'
assert_path_absent "$resolution_log" 'G10_HERMETIC_HOST_ENV: unmarked host-contract resolves neither fixture host'

run_command env -i PATH="$shim_dir:/usr/bin:/bin" HOME="$home" CODEX_HOME="$home/.codex" \
  WG_EVAL_OFFLINE_HOST_SHIMS=1 WG_EVAL_SHIM_LOG="$log" WG_EVAL_SHIM_RESOLUTION_LOG="$resolution_log" \
  WG_EVAL_EXPECT_HOME="$home" WG_EVAL_FORBID_PATH="$REPO_DIR" \
  bash -c 'cd "$1" && exec bash "$2" --host-contract --fixture-root "$3"' sh "$cwd" "$runner" "$fixtures"
if [ "$RUN_STATUS" -ne 0 ]; then
  printf '%s\n' 'Offline host-contract stderr follows:' >&2
  cat "$RUN_ERR" >&2
fi
assert_success 'G10_HERMETIC_HOST_ENV: offline host contract succeeds in a fresh empty home'
assert_file_contains "$resolution_log" "^${shim_dir}/claude$" \
  'G10_CLAUDE_ARGV_CONTRACT: resolved Claude command is the protected fixture shim'
assert_file_contains "$resolution_log" "^${shim_dir}/codex$" \
  'G10_CODEX_ARGV_CONTRACT: resolved Codex command is the protected fixture shim'
assert_file_contains "$log" '^claude\t-p --model claude-fixture-model --max-turns 3 --sandbox read-only$' \
  'G10_CLAUDE_ARGV_CONTRACT: exact Claude argv is frozen and exercised'
assert_file_contains "$log" '^codex\texec --model codex-fixture-model --max-turns 3 --sandbox read-only$' \
  'G10_CODEX_ARGV_CONTRACT: exact Codex argv is frozen and exercised'
assert_path_absent "$home/source-leak" 'G10_HERMETIC_HOST_ENV: host fixture did not create source-backed home state'
run_command find "$home" -mindepth 1 -print
assert_empty_file "$RUN_OUT" 'G10_HERMETIC_HOST_ENV: host contract leaves fresh home empty'

finish_tests
