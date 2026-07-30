#!/usr/bin/env bash
# Minimal Bash 3.2 test helpers. No test framework is required.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/writing-goals-test.XXXXXX")"
TEST_COUNT=0
TEST_FAILURES=0
RUN_STATUS=0
RUN_OUT=""
RUN_ERR=""

cleanup_test_tmp() {
  [ -n "${TEST_TMP:-}" ] && [ -d "$TEST_TMP" ] && rm -rf "$TEST_TMP"
}
trap cleanup_test_tmp EXIT HUP INT TERM

note() { printf '%s\n' "$*"; }

fail() {
  TEST_FAILURES=$((TEST_FAILURES + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

pass() { printf 'ok: %s\n' "$*"; }

assert_status() {
  local expected="$1" label="$2"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ "$RUN_STATUS" -eq "$expected" ]; then pass "$label"; else fail "$label (expected exit $expected, got $RUN_STATUS)"; fi
}

assert_success() { assert_status 0 "$1"; }

assert_nonzero() {
  local label="$1"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ "$RUN_STATUS" -ne 0 ]; then pass "$label"; else fail "$label (expected non-zero exit, got 0)"; fi
}

assert_contains() {
  local text="$1" pattern="$2" label="$3"
  TEST_COUNT=$((TEST_COUNT + 1))
  if grep -Eq -- "$pattern" <<< "$text"; then pass "$label"; else fail "$label (missing /$pattern/)"; fi
}

assert_not_contains() {
  local text="$1" pattern="$2" label="$3"
  TEST_COUNT=$((TEST_COUNT + 1))
  if grep -Eq -- "$pattern" <<< "$text"; then fail "$label (unexpected /$pattern/)"; else pass "$label"; fi
}

assert_empty_file() {
  local file="$1" label="$2"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ ! -s "$file" ]; then pass "$label"; else fail "$label (expected empty $file)"; fi
}

assert_file_contains() {
  local file="$1" pattern="$2" label="$3"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ -f "$file" ] && grep -Eq -- "$pattern" "$file"; then pass "$label"; else fail "$label (missing /$pattern/ in $file)"; fi
}

assert_path_absent() {
  local path="$1" label="$2"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then pass "$label"; else fail "$label (unexpected path $path)"; fi
}

assert_symlink() {
  local path="$1" label="$2"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ -L "$path" ]; then pass "$label"; else fail "$label (expected symlink at $path)"; fi
}

assert_link_target() {
  local path="$1" expected="$2" label="$3" actual
  TEST_COUNT=$((TEST_COUNT + 1))
  actual="$(readlink "$path" 2>/dev/null)"
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label (expected '$expected', got '${actual:-not a symlink}')"
  fi
}

run_command() {
  local id
  id=$((TEST_COUNT + TEST_FAILURES + 1))
  RUN_OUT="$TEST_TMP/run-$id.stdout"
  RUN_ERR="$TEST_TMP/run-$id.stderr"
  "$@" >"$RUN_OUT" 2>"$RUN_ERR"
  RUN_STATUS=$?
}

run_input() {
  local input="$1" id
  shift
  id=$((TEST_COUNT + TEST_FAILURES + 1))
  RUN_OUT="$TEST_TMP/run-$id.stdout"
  RUN_ERR="$TEST_TMP/run-$id.stderr"
  printf '%s' "$input" | "$@" >"$RUN_OUT" 2>"$RUN_ERR"
  RUN_STATUS=${PIPESTATUS[1]}
}

file_mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

assert_mode_600() {
  local path="$1" label="$2" mode
  TEST_COUNT=$((TEST_COUNT + 1))
  mode="$(file_mode "$path" 2>/dev/null)"
  if [ "$mode" = 600 ]; then pass "$label"; else fail "$label (expected mode 600, got ${mode:-missing})"; fi
}

assert_deny_json() {
  local file="$1" label="$2" decision
  TEST_COUNT=$((TEST_COUNT + 1))
  decision="$(jq -r '.hookSpecificOutput.permissionDecision // empty' "$file" 2>/dev/null)"
  if [ "$decision" = deny ]; then pass "$label"; else fail "$label (expected deny JSON)"; fi
}

assert_terminal_json() {
  local file="$1" label="$2" continue reason
  TEST_COUNT=$((TEST_COUNT + 1))
  continue="$(jq -r '.continue // empty' "$file" 2>/dev/null)"
  reason="$(jq -r '.stopReason // empty' "$file" 2>/dev/null)"
  if [ "$continue" = false ] && printf '%s' "$reason" | grep -Eqi 'needs human'; then
    pass "$label"
  else
    fail "$label (expected terminal needs-human JSON)"
  fi
}

finish_tests() {
  if [ "$TEST_FAILURES" -eq 0 ]; then
    printf 'PASS: %s assertions\n' "$TEST_COUNT"
    return 0
  fi
  printf 'FAIL: %s of %s assertions failed\n' "$TEST_FAILURES" "$TEST_COUNT" >&2
  return 1
}
