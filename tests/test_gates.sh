#!/usr/bin/env bash
set -u
. "$(dirname "$0")/testlib.sh"

# jq's `//` operator treats boolean false like a missing value, so the generic
# helper cannot inspect the required JSON boolean. Keep this focused override
# strict about both the type and the needs-human reason.
assert_terminal_json() {
  local file="$1" label="$2" is_false reason
  TEST_COUNT=$((TEST_COUNT + 1))
  is_false="$(jq -r '(.continue | type == "boolean") and (.continue == false)' "$file" 2>/dev/null)"
  reason="$(jq -r '.stopReason // empty' "$file" 2>/dev/null)"
  if [ "$is_false" = true ] && printf '%s' "$reason" | grep -Eqi 'needs human'; then
    pass "$label"
  else
    fail "$label (expected terminal needs-human JSON)"
  fi
}

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

gate_without_state_home() {
  local platform="$1" input="$2" command="$3" root="$4" script
  case "$platform" in
    claude) script="$REPO_DIR/assets/gate.claude.sh" ;;
    codex) script="$REPO_DIR/assets/gate.codex.sh" ;;
  esac
  run_input "$input" env -u HOME -u XDG_STATE_HOME \
    CLAUDE_PROJECT_DIR="$root" GATE_CMD="$command" GOAL_GATE_CAP=8 \
    GATE_SURFACE='surface.txt' bash "$script"
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
  script="$REPO_DIR/assets/gate.$platform.sh"
  assert_file_contains "$script" 'validate_stop_payload' "G08_STOP_GATE_MISSING: $platform validates its Stop payload before running a gate"
  root="$TEST_TMP/root-$platform"
  state="$TEST_TMP/state-$platform"
  mkdir -p "$root" "$state"
  printf 'surface\n' > "$root/surface.txt"
  input="$(input_for "$platform" "$root" "session-$platform")"

  malformed_marker="$TEST_TMP/$platform-malformed-command-ran"
  malformed_command="printf ran > '$malformed_marker'; true"
  if [ "$platform" = codex ]; then
    malformed_input='{"cwd":7,"session_id":false,"transcript_path":[],"stop_hook_active":"false"}'
  else
    malformed_input='{"session_id":false,"transcript_path":[],"stop_hook_active":"false"}'
  fi
  gate_once "$platform" "$malformed_input" "$state" "$malformed_command" 8 'surface.txt' "$root"
  assert_success "$platform malformed Stop payload returns a host-valid terminal response"
  assert_terminal_json "$RUN_OUT" "$platform malformed Stop payload fails closed"
  assert_path_absent "$malformed_marker" "$platform malformed Stop payload never executes GATE_CMD"

  if [ "$platform" = codex ]; then
    null_state="$TEST_TMP/null-transcript-state"
    null_marker="$TEST_TMP/codex-null-transcript-gate-ran"
    mkdir -p "$null_state"
    null_input="$(jq -cn --arg cwd "$root" --arg s 'codex-null-transcript' '{cwd:$cwd,session_id:$s,transcript_path:null,stop_hook_active:false}')"
    null_command="printf GATE_CMD > '$null_marker'"
    gate_once codex "$null_input" "$null_state" "$null_command" 8 'surface.txt' "$root"
    assert_success 'G08_STOP_BEHAVIOR: Codex accepts a documented null transcript_path'
    assert_empty_file "$RUN_OUT" 'G08_STOP_BEHAVIOR: null transcript_path green gate emits no model-visible stdout'
    assert_file_contains "$null_marker" '^GATE_CMD$' 'G08_STOP_BEHAVIOR: null transcript_path executes GATE_CMD'
  fi

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

  no_home_marker="$TEST_TMP/$platform-no-home-command-ran"
  no_home_command="printf ran > '$no_home_marker'; false"
  gate_without_state_home "$platform" "$input" "$no_home_command" "$root"
  assert_success "$platform missing HOME and XDG_STATE_HOME returns a hook-valid status"
  assert_terminal_json "$RUN_OUT" "$platform missing state-home configuration fails terminally"
  assert_path_absent "$no_home_marker" "$platform missing state-home configuration never executes GATE_CMD"

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
    assert_mode_600 "$count_file" "$platform counter is mode 0600"
    invalid_index=0
    for invalid_count in corrupt '' 1234567890123456789; do
      invalid_index=$((invalid_index + 1))
      printf '%s' "$invalid_count" > "$count_file"
      corrupt_marker="$TEST_TMP/$platform-corrupt-command-ran-$invalid_index"
      corrupt_command="printf ran > '$corrupt_marker'; false"
      gate_once "$platform" "$input" "$corrupt_state" "$corrupt_command" 8 'surface.txt' "$root"
      assert_success "$platform invalid counter '$invalid_count' returns a hook-valid status"
      assert_terminal_json "$RUN_OUT" "$platform invalid counter '$invalid_count' fails closed before gate execution"
      assert_path_absent "$corrupt_marker" "$platform invalid counter '$invalid_count' never executes GATE_CMD"
    done

    rm -f "$count_file"
    ln -s "$corrupt_state/missing-counter-target" "$count_file"
    dangling_marker="$TEST_TMP/$platform-dangling-counter-command-ran"
    dangling_command="printf ran > '$dangling_marker'; false"
    gate_once "$platform" "$input" "$corrupt_state" "$dangling_command" 8 'surface.txt' "$root"
    assert_success "$platform dangling counter returns a hook-valid status"
    assert_terminal_json "$RUN_OUT" "$platform dangling counter fails terminally"
    assert_path_absent "$dangling_marker" "$platform dangling counter never executes GATE_CMD"
  fi
done

finish_tests
