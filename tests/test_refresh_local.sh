#!/usr/bin/env bash
# G09 regression: local refresh needs explicit authority before touching installs.
set -u
. "$(dirname "$0")/testlib.sh"

refresh="$REPO_DIR/scripts/refresh-local.sh"
roles='planner challenger oracle-author maker verifier reviewer publisher'

assert_copy_tree() {
  local path="$1" label="$2"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ -d "$path" ] && [ ! -L "$path" ] && ! find "$path" -type l -print -quit | grep -q .; then
    pass "$label"
  else
    fail "$label (expected a real symlink-free directory)"
  fi
}

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

# Exercise the public wrapper from a clean, committed clone. Its suite stub
# proves that the wrapper invokes tests/run.sh before first installation; the
# outer test run separately validates the actual portable suite.
refresh_source="$TEST_TMP/refresh-source"
run_command git clone --quiet --no-hardlinks "$REPO_DIR" "$refresh_source"
assert_success 'G09_SAFE_REFRESH: isolated refresh source clone is available'
refresh_suite_marker="$TEST_TMP/refresh-suite.marker"
printf '%s\n' '#!/usr/bin/env bash' 'set -eu' '[ -n "${WG_REFRESH_SUITE_MARKER:-}" ]' 'if [ "${WG_REFRESH_EXPECT_EMPTY_TARGETS:-}" = 1 ]; then' '  [ ! -e "$HOME/.claude/skills/writing-goals" ]' '  [ ! -e "${CODEX_HOME:-$HOME/.codex}/skills/writing-goals" ]' 'fi' ': > "$WG_REFRESH_SUITE_MARKER"' > "$refresh_source/tests/run.sh"
chmod +x "$refresh_source/tests/run.sh"
run_command git -C "$refresh_source" add tests/run.sh
assert_success 'G09_SAFE_REFRESH: clone stages its sequence-checking suite stub'
run_command git -C "$refresh_source" -c user.name='writing-goals test' -c user.email='test@example.invalid' commit -qm 'test: add refresh suite stub'
assert_success 'G09_SAFE_REFRESH: clone is clean before refresh'

refresh_script="$refresh_source/scripts/refresh-local.sh"
refresh_home="$TEST_TMP/refresh-home"
run_command env HOME="$refresh_home" CODEX_HOME="$refresh_home/.codex" bash "$refresh_script"
assert_nonzero 'G09_SAFE_REFRESH: clean temporary home still requires explicit install authority'
assert_path_absent "$refresh_home/.claude/skills/writing-goals" 'G09_SAFE_REFRESH: no-opt-in refresh leaves Claude untouched'
assert_path_absent "$refresh_home/.codex/skills/writing-goals" 'G09_SAFE_REFRESH: no-opt-in refresh leaves Codex untouched'

run_command env HOME="$refresh_home" CODEX_HOME="$refresh_home/.codex" WG_REFRESH_SUITE_MARKER="$refresh_suite_marker" WG_REFRESH_EXPECT_EMPTY_TARGETS=1 bash "$refresh_script" --install all
assert_success 'G09_SAFE_REFRESH: clean temporary-home refresh installs both platforms'
TEST_COUNT=$((TEST_COUNT + 1))
if [ -f "$refresh_suite_marker" ]; then
  pass 'G09_SAFE_REFRESH: refresh runs its suite before the first install'
else
  fail 'G09_SAFE_REFRESH: refresh runs its suite before the first install'
fi
assert_copy_tree "$refresh_home/.claude/skills/writing-goals" 'G09_SAFE_REFRESH: refreshed Claude target is a real copy'
assert_copy_tree "$refresh_home/.codex/skills/writing-goals" 'G09_SAFE_REFRESH: refreshed Codex target is a real copy'
for role in $roles; do
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ -f "$refresh_home/.codex/agents/writing-goals-$role.toml" ] && [ ! -L "$refresh_home/.codex/agents/writing-goals-$role.toml" ]; then
    pass "G09_SAFE_REFRESH: refreshed Codex $role agent is a real copy"
  else
    fail "G09_SAFE_REFRESH: refreshed Codex $role agent is missing or linked"
  fi
done

# A successful replacement retains the previous exact targets in its archive.
previous="$TEST_TMP/refresh-preimage"
mkdir -p "$previous"
cp -R "$refresh_home/.claude" "$previous/.claude"
cp -R "$refresh_home/.codex" "$previous/.codex"
sleep 1
run_command env HOME="$refresh_home" CODEX_HOME="$refresh_home/.codex" WG_REFRESH_SUITE_MARKER="$refresh_suite_marker" bash "$refresh_script" --install all
assert_success 'G09_SAFE_REFRESH: existing temporary targets refresh successfully'
success_backup_root="$(sed -n 's/^Backup: //p' "$RUN_OUT")"
TEST_COUNT=$((TEST_COUNT + 1))
if [ -n "$success_backup_root" ] && [ -d "$success_backup_root/claude-writing-goals" ] && [ -d "$success_backup_root/codex-writing-goals" ] && [ -d "$success_backup_root/codex-agents" ]; then
  pass 'G09_SAFE_REFRESH: successful refresh preserves exact targets in a timestamped backup'
else
  fail 'G09_SAFE_REFRESH: successful refresh preserves exact targets in a timestamped backup'
fi
run_command diff -ru "$previous/.claude/skills/writing-goals" "$success_backup_root/claude-writing-goals"
assert_success 'G09_SAFE_REFRESH: successful refresh backup preserves the Claude preimage'
run_command diff -ru "$previous/.codex/skills/writing-goals" "$success_backup_root/codex-writing-goals"
assert_success 'G09_SAFE_REFRESH: successful refresh backup preserves the Codex preimage'
for role in $roles; do
  run_command diff -u "$previous/.codex/agents/writing-goals-$role.toml" "$success_backup_root/codex-agents/writing-goals-$role.toml"
  assert_success "G09_SAFE_REFRESH: successful refresh backup preserves the Codex $role agent preimage"
done

# A failed replacement restores the exact preimage.
restore_before="$TEST_TMP/refresh-restore-before"
mkdir -p "$restore_before"
cp -R "$refresh_home/.claude" "$restore_before/.claude"
cp -R "$refresh_home/.codex" "$restore_before/.codex"
sleep 1
run_command env HOME="$refresh_home" CODEX_HOME="$refresh_home/.codex" WG_REFRESH_SUITE_MARKER="$refresh_suite_marker" WG_INSTALL_FAIL_AFTER_STAGE=codex bash "$refresh_script" --install all
assert_nonzero 'G09_SAFE_REFRESH: injected post-backup installation failure is reported'
run_command diff -ru "$restore_before/.claude" "$refresh_home/.claude"
assert_success 'G09_COLLISION_ROLLBACK: failed refresh restores the Claude preimage'
run_command diff -ru "$restore_before/.codex" "$refresh_home/.codex"
assert_success 'G09_COLLISION_ROLLBACK: failed refresh restores the Codex tree and agents'

finish_tests
