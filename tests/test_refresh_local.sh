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

status_checkout="$TEST_TMP/status-checkout"
status_home="$TEST_TMP/status-home"
status_codex="$TEST_TMP/status-codex"
mkdir -p "$status_checkout/scripts"
cp "$refresh" "$status_checkout/scripts/refresh-local.sh"

run_command env HOME="$status_home" CODEX_HOME="$status_codex" \
  bash "$status_checkout/scripts/refresh-local.sh" --status
assert_success 'G09_SAFE_REFRESH_STATUS: status succeeds when all items are missing'
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$(cat "$RUN_OUT")" = $'Claude: missing\nCodex: missing\nLatest archive: none' ]; then
  pass 'G09_SAFE_REFRESH_STATUS: missing status output is exact and ordered'
else
  fail "G09_SAFE_REFRESH_STATUS: unexpected missing status output ($(cat "$RUN_OUT"))"
fi
assert_empty_file "$RUN_ERR" 'G09_SAFE_REFRESH_STATUS: status writes no diagnostics'
assert_path_absent "$status_home" 'G09_SAFE_REFRESH_STATUS: status does not create HOME'
assert_path_absent "$status_codex" 'G09_SAFE_REFRESH_STATUS: status does not create CODEX_HOME'
assert_path_absent "$status_checkout/.archive" 'G09_SAFE_REFRESH_STATUS: status does not create an archive'

mkdir -p "$status_home/.claude/skills/writing-goals" "$status_codex/skills" \
  "$status_checkout/.archive/writing-goals/20260101" \
  "$status_checkout/.archive/writing-goals/20261231"
printf '%s\n' sentinel >"$status_home/.claude/skills/writing-goals/sentinel"
ln -s "$status_checkout" "$status_codex/skills/writing-goals"
before_status="$(find "$status_checkout" "$status_home" "$status_codex" -mindepth 1 -print | LC_ALL=C sort)"

run_command env HOME="$status_home" CODEX_HOME="$status_codex" \
  bash "$status_checkout/scripts/refresh-local.sh" --status
assert_success 'G09_SAFE_REFRESH_STATUS: status succeeds for present items'
status_checkout_physical="$(cd "$status_checkout" && pwd -P)"
expected_status="$(printf 'Claude: copy\nCodex: symlink\nLatest archive: %s' \
  "$status_checkout_physical/.archive/writing-goals/20261231")"
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$(cat "$RUN_OUT")" = "$expected_status" ]; then
  pass 'G09_SAFE_REFRESH_STATUS: present status output is exact and ordered'
else
  fail "G09_SAFE_REFRESH_STATUS: unexpected present status output ($(cat "$RUN_OUT"))"
fi
after_status="$(find "$status_checkout" "$status_home" "$status_codex" -mindepth 1 -print | LC_ALL=C sort)"
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$after_status" = "$before_status" ] &&
   [ "$(cat "$status_home/.claude/skills/writing-goals/sentinel")" = sentinel ] &&
   [ "$(readlink "$status_codex/skills/writing-goals")" = "$status_checkout" ]; then
  pass 'G09_SAFE_REFRESH_STATUS: status does not change inspected trees'
else
  fail 'G09_SAFE_REFRESH_STATUS: status changed an inspected tree'
fi

assert_file_contains "$refresh" 'bash tests/run\.sh' 'G09_SAFE_REFRESH: refresh verifies the source before installation'
assert_file_contains "$refresh" 'scripts/build-bundles\.sh' 'G09_SAFE_REFRESH: refresh installs a self-contained bundle'
assert_file_contains "$refresh" '\.archive/writing-goals' 'G09_SAFE_REFRESH: refresh preserves replaced targets in the repository archive'
assert_file_contains "$REPO_DIR/.gitignore" '^/dist/$' 'G09_SAFE_REFRESH: generated refresh bundles do not leave the source checkout dirty'
assert_file_contains "$REPO_DIR/.gitignore" '^/\.archive/$' 'G09_SAFE_REFRESH: local backup archives do not dirty the source checkout'

finish_tests
