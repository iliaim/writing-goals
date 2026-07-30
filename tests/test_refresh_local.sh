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

status_root="$(cd "$TEST_TMP" && pwd -P)/status-root"
mkdir -p "$status_root/scripts" "$TEST_TMP/claude-home/.claude/skills" "$TEST_TMP/codex-home/skills"
cp "$refresh" "$status_root/scripts/refresh-local.sh"
mkdir -p "$TEST_TMP/claude-source" "$TEST_TMP/codex-home/skills/writing-goals"
ln -s "$TEST_TMP/claude-source" "$TEST_TMP/claude-home/.claude/skills/writing-goals"

run_command env HOME="$TEST_TMP/claude-home" CODEX_HOME="$TEST_TMP/codex-home" bash "$status_root/scripts/refresh-local.sh" --status
assert_success 'G09_SAFE_REFRESH: status exits successfully without an install'
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$(cat "$RUN_OUT"; printf __END__)" = "Claude: symlink
Codex: copy
Latest archive: none
__END__" ]; then
  pass 'G09_SAFE_REFRESH: status reports ordered target types and no archive exactly'
else
  fail "G09_SAFE_REFRESH: status reports ordered target types and no archive exactly (got $(tr '\n' '|' < "$RUN_OUT"))"
fi
assert_empty_file "$RUN_ERR" 'G09_SAFE_REFRESH: status has no diagnostic output'
assert_path_absent "$status_root/.archive/writing-goals" 'G09_SAFE_REFRESH: status does not create an archive directory'
assert_symlink "$TEST_TMP/claude-home/.claude/skills/writing-goals" 'G09_SAFE_REFRESH: status preserves the Claude target'
TEST_COUNT=$((TEST_COUNT + 1))
if [ -d "$TEST_TMP/codex-home/skills/writing-goals" ]; then
  pass 'G09_SAFE_REFRESH: status preserves the Codex target'
else
  fail 'G09_SAFE_REFRESH: status preserves the Codex target'
fi

mkdir -p "$status_root/.archive/writing-goals/20260730T120000Z" "$status_root/.archive/writing-goals/20260730T130000Z"
rm "$TEST_TMP/claude-home/.claude/skills/writing-goals"
rm -rf "$TEST_TMP/codex-home/skills/writing-goals"
status_before="$(find "$status_root" "$TEST_TMP/claude-home" "$TEST_TMP/codex-home" -print | LC_ALL=C sort)"

run_command env HOME="$TEST_TMP/claude-home" CODEX_HOME="$TEST_TMP/codex-home" bash "$status_root/scripts/refresh-local.sh" --status
assert_success 'G09_SAFE_REFRESH: status exits successfully for missing targets and archives'
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$(cat "$RUN_OUT"; printf __END__)" = "Claude: missing
Codex: missing
Latest archive: $status_root/.archive/writing-goals/20260730T130000Z
__END__" ]; then
  pass 'G09_SAFE_REFRESH: status reports missing targets and lexically newest absolute archive exactly'
else
  fail "G09_SAFE_REFRESH: status reports missing targets and lexically newest absolute archive exactly (got $(tr '\n' '|' < "$RUN_OUT"))"
fi
assert_empty_file "$RUN_ERR" 'G09_SAFE_REFRESH: missing status has no diagnostic output'
status_after="$(find "$status_root" "$TEST_TMP/claude-home" "$TEST_TMP/codex-home" -print | LC_ALL=C sort)"
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$status_after" = "$status_before" ]; then
  pass 'G09_SAFE_REFRESH: status does not change inspected paths'
else
  fail 'G09_SAFE_REFRESH: status changed inspected paths'
fi

run_command bash "$refresh"
assert_nonzero 'G09_SAFE_REFRESH: default invocation refuses to change installed copies'
assert_contains "$(cat "$RUN_ERR")" 'explicit --install' 'G09_SAFE_REFRESH: refusal explains the required authority'

assert_file_contains "$refresh" 'bash tests/run\.sh' 'G09_SAFE_REFRESH: refresh verifies the source before installation'
assert_file_contains "$refresh" 'scripts/build-bundles\.sh' 'G09_SAFE_REFRESH: refresh installs a self-contained bundle'
assert_file_contains "$refresh" '\.archive/writing-goals' 'G09_SAFE_REFRESH: refresh preserves replaced targets in the repository archive'
assert_file_contains "$REPO_DIR/.gitignore" '^/dist/$' 'G09_SAFE_REFRESH: generated refresh bundles do not leave the source checkout dirty'
assert_file_contains "$REPO_DIR/.gitignore" '^/\.archive/$' 'G09_SAFE_REFRESH: local backup archives do not dirty the source checkout'

finish_tests
