#!/usr/bin/env bash
# G09 regression: local refresh needs explicit authority before touching installs.
set -u
. "$(dirname "$0")/testlib.sh"

refresh="$REPO_DIR/scripts/refresh-local.sh"

assert_equals() {
  local actual="$1" expected="$2" label="$3"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

tree_manifest() {
  local path item
  for path in "$@"; do
    find "$path" -print
  done | LC_ALL=C sort | while IFS= read -r item; do
    if [ -L "$item" ]; then
      printf 'L %s %s\n' "$(file_mode "$item")" "$item -> $(readlink "$item")"
    elif [ -f "$item" ]; then
      printf 'F %s %s ' "$(file_mode "$item")" "$item"
      shasum "$item"
    elif [ -d "$item" ]; then
      printf 'D %s %s\n' "$(file_mode "$item")" "$item"
    fi
  done
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

status_repo="$TEST_TMP/status-repo"
status_home="$TEST_TMP/status-home"
status_codex="$TEST_TMP/status-codex"
mkdir -p "$status_repo/scripts" "$status_home" "$status_codex"
cp "$refresh" "$status_repo/scripts/refresh-local.sh"
status_repo_abs="$(CDPATH= cd -- "$status_repo" && pwd -P)"

run_command env HOME="$status_home" CODEX_HOME="$status_codex" \
  bash "$status_repo/scripts/refresh-local.sh" --status
assert_success 'G09_SAFE_REFRESH_STATUS: missing-state status exits successfully'
assert_empty_file "$RUN_ERR" 'G09_SAFE_REFRESH_STATUS: missing-state status has no stderr'
assert_equals "$(cat "$RUN_OUT")" \
  $'Claude: missing\nCodex: missing\nLatest archive: none' \
  'G09_SAFE_REFRESH_STATUS: missing-state status prints exactly three ordered lines'

mkdir -p "$status_home/.claude/skills/writing-goals"
mkdir -p "$status_codex/skills" "$status_repo/.archive/writing-goals/20260101T000000Z"
ln -s "$status_repo" "$status_codex/skills/writing-goals"
mkdir -p "$status_repo/.archive/writing-goals/20261231T235959Z"
before_status="$(tree_manifest "$status_repo" "$status_home" "$status_codex")"

run_command env HOME="$status_home" CODEX_HOME="$status_codex" \
  bash "$status_repo/scripts/refresh-local.sh" --status
assert_success 'G09_SAFE_REFRESH_STATUS: populated status exits successfully'
assert_empty_file "$RUN_ERR" 'G09_SAFE_REFRESH_STATUS: populated status has no stderr'
assert_equals "$(cat "$RUN_OUT")" \
  "Claude: copy
Codex: symlink
Latest archive: $status_repo_abs/.archive/writing-goals/20261231T235959Z" \
  'G09_SAFE_REFRESH_STATUS: status classifies targets and selects the lexical newest archive'
after_status="$(tree_manifest "$status_repo" "$status_home" "$status_codex")"
assert_equals "$after_status" "$before_status" \
  'G09_SAFE_REFRESH_STATUS: status does not mutate the repository or target roots'

rm -rf "$status_home/.claude/skills/writing-goals"
ln -s "$status_repo" "$status_home/.claude/skills/writing-goals"
rm "$status_codex/skills/writing-goals"
mkdir -p "$status_codex/skills/writing-goals"
run_command env HOME="$status_home" CODEX_HOME="$status_codex" \
  bash "$status_repo/scripts/refresh-local.sh" --status
assert_success 'G09_SAFE_REFRESH_STATUS: inverse target types exit successfully'
assert_equals "$(cat "$RUN_OUT")" \
  "Claude: symlink
Codex: copy
Latest archive: $status_repo_abs/.archive/writing-goals/20261231T235959Z" \
  'G09_SAFE_REFRESH_STATUS: status distinguishes symlinks from copies for both targets'

assert_file_contains "$refresh" 'bash tests/run\.sh' 'G09_SAFE_REFRESH: refresh verifies the source before installation'
assert_file_contains "$refresh" 'scripts/build-bundles\.sh' 'G09_SAFE_REFRESH: refresh installs a self-contained bundle'
assert_file_contains "$refresh" '\.archive/writing-goals' 'G09_SAFE_REFRESH: refresh preserves replaced targets in the repository archive'
assert_file_contains "$REPO_DIR/.gitignore" '^/dist/$' 'G09_SAFE_REFRESH: generated refresh bundles do not leave the source checkout dirty'
assert_file_contains "$REPO_DIR/.gitignore" '^/\.archive/$' 'G09_SAFE_REFRESH: local backup archives do not dirty the source checkout'

finish_tests
