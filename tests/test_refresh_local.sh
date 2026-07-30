#!/usr/bin/env bash
# G09 regression: local refresh needs explicit authority before touching installs.
set -u
. "$(dirname "$0")/testlib.sh"

refresh="$REPO_DIR/scripts/refresh-local.sh"

TEST_COUNT=$((TEST_COUNT + 1))
if [ -f "$refresh" ] && [ -x "$refresh" ]; then
  pass 'G09_SAFE_REFRESH: refresh command is installed as an executable script'
else
  fail 'G09_SAFE_REFRESH: scripts/refresh-local.sh is missing or not executable'
fi

run_command bash "$refresh" --help
assert_success 'G09_SAFE_REFRESH: help is available without source or install changes'
assert_contains "$(cat "$RUN_ERR")" '^usage:.*--install' 'G09_SAFE_REFRESH: help requires an explicit install flag'

run_command bash "$refresh"
assert_nonzero 'G09_SAFE_REFRESH: default invocation refuses to change installed copies'
assert_contains "$(cat "$RUN_ERR")" 'explicit --install' 'G09_SAFE_REFRESH: refusal explains the required authority'

assert_file_contains "$refresh" 'bash tests/run\.sh' 'G09_SAFE_REFRESH: refresh verifies the source before installation'
assert_file_contains "$refresh" 'scripts/build-bundles\.sh' 'G09_SAFE_REFRESH: refresh installs a self-contained bundle'
assert_file_contains "$refresh" '\.archive/writing-goals' 'G09_SAFE_REFRESH: refresh preserves replaced targets in the repository archive'
assert_file_contains "$REPO_DIR/.gitignore" '^/dist/$' 'G09_SAFE_REFRESH: generated refresh bundles do not leave the source checkout dirty'
assert_file_contains "$REPO_DIR/.gitignore" '^/\.archive/$' 'G09_SAFE_REFRESH: local backup archives do not dirty the source checkout'

finish_tests
