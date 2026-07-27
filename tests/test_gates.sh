#!/usr/bin/env bash
set -u
. "$(dirname "$0")/testlib.sh"

gate_once() {
  local platform="$1" input="$2" state="$3" command="$4" cap="$5" surface="$6" root="$7" script
  case "$platform" in
    claude) script="$REPO_DIR/assets/gate.claude.sh" ;;
    codex) script="$REPO_DIR/assets/gate.codex.sh" ;;
  esac
  run_input "$input" env HOME="$TEST_TMP/home-$platform" XDG_STATE_HOME="$state" \
    CLAUDE_PROJECT_DIR="$root" GATE_CMD="$command" GOAL_GATE_CAP="$cap" \
    GATE_SURFACE="$surface" bash "$script"
}

input_for() {
  local platform="$1" root="$2" session="$3"
  if [ "$platform" = codex ]; then
    jq -cn --arg cwd "$root" --arg s "$session" '{cwd:$cwd,session_id:$s,transcript_path:"/tmp/transcript",stop_hook_active:false}'
  else
    jq -cn --arg s "$session" '{session_id:$s,transcript_path:"/tmp/transcript",stop_hook_active:false}'
  fi
}

for platform in claude codex; do
  root="$TEST_TMP/root-$platform"
  state="$TEST_TMP/state-$platform"
  mkdir -p "$root" "$state"
  printf 'surface\n' > "$root/surface.txt"
  input="$(input_for "$platform" "$root" "session-$platform")"

  gate_once "$platform" "$input" "$state" '' 8 'surface.txt' "$root"
  assert_success "$platform rejects missing GATE_CMD without a hook crash"
  assert_terminal_json "$RUN_OUT" "$platform requires an explicit non-empty GATE_CMD"

  for bad_cap in '' 0 08 nope 1234567890123456789; do
    gate_once "$platform" "$input" "$state" true "$bad_cap" 'surface.txt' "$root"
    assert_success "$platform invalid cap '$bad_cap' fails closed"
    assert_terminal_json "$RUN_OUT" "$platform rejects cap '$bad_cap'"
  done

  gate_once "$platform" "$input" "$state" true 8 '' "$root"
  assert_success "$platform empty GATE_SURFACE fails closed"
  assert_terminal_json "$RUN_OUT" "$platform requires a non-empty GATE_SURFACE"
  gate_once "$platform" "$input" "$state" true 8 'missing-*' "$root"
  assert_success "$platform unresolved GATE_SURFACE fails closed"
  assert_terminal_json "$RUN_OUT" "$platform rejects an unresolved GATE_SURFACE"

  green_state="$TEST_TMP/green-$platform"
  mkdir -p "$green_state"
  gate_once "$platform" "$input" "$green_state" true 8 'surface.txt' "$root"
  assert_success "$platform green gate exits zero"
  assert_empty_file "$RUN_OUT" "$platform green gate emits no model-visible stdout"

  red_state="$TEST_TMP/red-$platform"
  mkdir -p "$red_state"
  i=1
  while [ "$i" -le 8 ]; do
    gate_once "$platform" "$input" "$red_state" 'printf gate-red >&2; false' 8 'surface.txt' "$root"
    assert_success "$platform failure $i has a hook-valid exit status"
    if [ "$i" -lt 8 ]; then
      assert_contains "$(cat "$RUN_OUT")" '"decision":"block"' "$platform failure $i blocks"
    else
      assert_terminal_json "$RUN_OUT" "$platform failure 8 terminates immediately for a human"
    fi
    i=$((i + 1))
  done
  log_file="$(grep -rl 'gate-red' "$red_state" 2>/dev/null | head -n 1)"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ -n "$log_file" ]; then pass "$platform persists failure output outside model JSON"; else fail "$platform persists failure output outside model JSON"; fi
  [ -n "$log_file" ] && assert_mode_600 "$log_file" "$platform failure log is mode 0600"
  assert_not_contains "$(cat "$RUN_OUT")" 'gate-red' "$platform does not expose failure output in terminal JSON"

  corrupt_state="$TEST_TMP/corrupt-$platform"
  mkdir -p "$corrupt_state"
  gate_once "$platform" "$input" "$corrupt_state" 'false' 8 'surface.txt' "$root"
  count_file="$(find "$corrupt_state" -type f -name 'gate-count-*' -print | head -n 1)"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ -n "$count_file" ]; then pass "$platform creates a session-keyed counter"; else fail "$platform creates a session-keyed counter"; fi
  if [ -n "$count_file" ]; then
    printf 'corrupt' > "$count_file"
    corrupt_marker="$TEST_TMP/$platform-corrupt-command-ran"
    corrupt_command="printf ran > '$corrupt_marker'; false"
    gate_once "$platform" "$input" "$corrupt_state" "$corrupt_command" 8 'surface.txt' "$root"
    assert_success "$platform corrupt counter returns a hook-valid status"
    assert_terminal_json "$RUN_OUT" "$platform corrupt counter fails closed before gate execution"
    assert_path_absent "$corrupt_marker" "$platform corrupt counter never executes GATE_CMD"
  fi
done

finish_tests
