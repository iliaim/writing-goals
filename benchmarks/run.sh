#!/usr/bin/env bash
# Reproducible local benchmark runner. Profiles are data; adapters own CLI argv.
set -euo pipefail

usage() {
  printf '%s\n' "usage: $0 --ledger FILE --profile FILE --scenario DIRECTORY --run-id ID [--output-root DIRECTORY] (--dry-run|--execute)" >&2
  exit 2
}

root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
ledger=
profile=
scenario=
run_id=
output_root="$root/.archive/benchmarks"
mode=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ledger) [ "$#" -ge 2 ] || usage; ledger=$2; shift 2 ;;
    --profile) [ "$#" -ge 2 ] || usage; profile=$2; shift 2 ;;
    --scenario) [ "$#" -ge 2 ] || usage; scenario=$2; shift 2 ;;
    --run-id) [ "$#" -ge 2 ] || usage; run_id=$2; shift 2 ;;
    --output-root) [ "$#" -ge 2 ] || usage; output_root=$2; shift 2 ;;
    --dry-run|--execute) [ -z "$mode" ] || usage; mode=${1#--}; shift ;;
    *) usage ;;
  esac
done

[ -n "$ledger" ] && [ -f "$ledger" ] && [ ! -L "$ledger" ] || usage
[ -n "$profile" ] && [ -f "$profile" ] && [ ! -L "$profile" ] || usage
[ -n "$scenario" ] && [ -d "$scenario" ] && [ ! -L "$scenario" ] || usage
[ -n "$run_id" ] && printf '%s' "$run_id" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || usage
[ -n "$mode" ] || usage
[ -f "$scenario/prompt.txt" ] && [ -x "$scenario/evaluate.sh" ] || {
  printf '%s\n' 'scenario requires regular prompt.txt and executable evaluate.sh files' >&2
  exit 2
}

ledger_header=$'cohort_id\tbase_commit\tprofile_sha256\tprompt_sha256\tevaluator_sha256\tadapter_sha256\tscenario_id\tarm\trepeat\trun_id\tplanned_order\ttimeout_seconds\toperator_action'
validate_ledger() {
  awk -F '\t' -v expected="$ledger_header" '
    NR == 1 { if ($0 != expected) { print "invalid ledger header" > "/dev/stderr"; exit 1 }; next }
    NF != 13 { print "invalid ledger row field count at line " NR > "/dev/stderr"; exit 1 }
    $1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "" || $6 == "" || $7 == "" || $8 == "" || $9 == "" || $10 == "" || $11 == "" || $12 == "" || $13 == "" { print "blank ledger field at line " NR > "/dev/stderr"; exit 1 }
    $8 !~ /^(control|treatment)$/ { print "invalid ledger arm at line " NR > "/dev/stderr"; exit 1 }
    $9 !~ /^[1-9][0-9]*$/ || $11 !~ /^[1-9][0-9]*$/ || $11 > 12 || $12 !~ /^[1-9][0-9]*$/ || $12 > 3600 { print "invalid ledger numeric field at line " NR > "/dev/stderr"; exit 1 }
    $13 !~ /^(none|operator-aborted|environment-repaired)$/ { print "invalid ledger operator action at line " NR > "/dev/stderr"; exit 1 }
    seen_run[$10]++ { print "duplicate ledger run_id: " $10 > "/dev/stderr"; exit 1 }
    seen_order[$11]++ { print "duplicate ledger planned_order: " $11 > "/dev/stderr"; exit 1 }
    END {
      if (NR != 13) { print "ledger must contain exactly 12 run rows" > "/dev/stderr"; exit 1 }
      for (order = 1; order <= 12; order++) if (!seen_order[order]) { print "ledger planned_order must be contiguous 1..12" > "/dev/stderr"; exit 1 }
    }
  ' "$ledger"
}

validate_ledger
ledger_row="$(awk -F '\t' -v wanted="$run_id" '$10 == wanted { print; count++ } END { exit count == 1 ? 0 : 1 }' "$ledger")" || {
  printf 'ledger must contain exactly one row for run_id: %s\n' "$run_id" >&2
  exit 2
}
IFS=$'\t' read -r cohort_id ledger_base_commit ledger_profile_hash ledger_prompt_hash ledger_evaluator_hash ledger_adapter_hash scenario_id arm repeat ledger_run_id planned_order timeout_seconds operator_action <<EOF
$ledger_row
EOF

host=
model=
workflow=
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  key=${line%%=*}
  value=${line#*=}
  [ "$key" != "$line" ] || { printf 'invalid profile row: %s\n' "$line" >&2; exit 2; }
  case "$key" in
    host) [ -z "$host" ] || exit 2; host=$value ;;
    model) [ -z "$model" ] || exit 2; model=$value ;;
    workflow) [ -z "$workflow" ] || exit 2; workflow=$value ;;
    *) printf 'unknown profile key: %s\n' "$key" >&2; exit 2 ;;
  esac
done < "$profile"

case "$host" in codex) ;; *) printf 'unsupported host: %s\n' "$host" >&2; exit 2 ;; esac
case "$workflow" in control|writing-goals) ;; *) printf 'unsupported workflow: %s\n' "$workflow" >&2; exit 2 ;; esac
[ -n "$model" ] || { printf '%s\n' 'profile model is required' >&2; exit 2; }
case "$workflow" in
  control) expected_arm=control ;;
  writing-goals) expected_arm=treatment ;;
esac
[ "$arm" = "$expected_arm" ] || { printf 'ledger arm does not match profile workflow: %s\n' "$workflow" >&2; exit 2; }

# Benchmarks run without interactive approvals but never opt into a bypass or broader sandbox.
approval_policy=never
sandbox=workspace-write
prompt_hash="$(shasum -a 256 "$scenario/prompt.txt" | awk '{print $1}')"
profile_hash="$(shasum -a 256 "$profile" | awk '{print $1}')"
evaluator_hash="$(shasum -a 256 "$scenario/evaluate.sh" | awk '{print $1}')"
adapter_hash="$(shasum -a 256 "$root/benchmarks/adapters/codex.sh" | awk '{print $1}')"
base_commit="$(git -C "$root" rev-parse HEAD)"
actual_scenario_id="$(basename "$scenario")"

[ "$ledger_base_commit" = "$base_commit" ] || { printf '%s\n' 'ledger base_commit does not match source checkout' >&2; exit 2; }
[ "$ledger_profile_hash" = "$profile_hash" ] || { printf '%s\n' 'ledger profile hash does not match profile' >&2; exit 2; }
[ "$ledger_prompt_hash" = "$prompt_hash" ] || { printf '%s\n' 'ledger prompt hash does not match scenario' >&2; exit 2; }
[ "$ledger_evaluator_hash" = "$evaluator_hash" ] || { printf '%s\n' 'ledger evaluator hash does not match scenario' >&2; exit 2; }
[ "$ledger_adapter_hash" = "$adapter_hash" ] || { printf '%s\n' 'ledger adapter hash does not match runner adapter' >&2; exit 2; }
[ "$scenario_id" = "$actual_scenario_id" ] || { printf '%s\n' 'ledger scenario_id does not match scenario directory' >&2; exit 2; }
[ "$ledger_run_id" = "$run_id" ] || { printf '%s\n' 'ledger run_id does not match selected run' >&2; exit 2; }

mkdir -p "$output_root"
output_root="$(CDPATH= cd -- "$output_root" && pwd -P)"
run_dir="$output_root/$run_id"
[ ! -e "$run_dir" ] && [ ! -L "$run_dir" ] || { printf 'run directory exists: %s\n' "$run_dir" >&2; exit 2; }
mkdir -p "$run_dir/logs"
worktree="$run_dir/worktree"
manifest="$run_dir/manifest.tsv"
result="$run_dir/result.tsv"
cp "$scenario/evaluate.sh" "$run_dir/evaluator.sh"
chmod 700 "$run_dir/evaluator.sh"

now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000'; }
started_ms="$(now_ms)"
remaining_timeout_seconds() {
  elapsed_ms=$(( $(now_ms) - started_ms ))
  printf '%s\n' $((timeout_seconds - ((elapsed_ms + 999) / 1000)))
}

write_manifest() {
  {
    printf 'run_id\t%s\n' "$run_id"
    printf 'started_ms\t%s\n' "$started_ms"
    printf 'cohort_id\t%s\n' "$cohort_id"
    printf 'base_commit\t%s\n' "$base_commit"
    printf 'host\t%s\n' "$host"
    printf 'model\t%s\n' "$model"
    printf 'workflow\t%s\n' "$workflow"
    printf 'sandbox\t%s\n' "$sandbox"
    printf 'approval_policy\t%s\n' "$approval_policy"
    printf 'profile_sha256\t%s\n' "$profile_hash"
    printf 'prompt_sha256\t%s\n' "$prompt_hash"
    printf 'evaluator_artifact\t%s\n' 'evaluator.sh'
    printf 'evaluator_sha256\t%s\n' "$evaluator_hash"
    printf 'adapter_sha256\t%s\n' "$adapter_hash"
    printf 'scenario_id\t%s\n' "$scenario_id"
    printf 'arm\t%s\n' "$arm"
    printf 'repeat\t%s\n' "$repeat"
    printf 'planned_order\t%s\n' "$planned_order"
    printf 'timeout_seconds\t%s\n' "$timeout_seconds"
    printf 'operator_action\t%s\n' "$operator_action"
    printf 'runtime_home\t%s\n' 'ephemeral'
    printf 'scenario\t%s\n' "$scenario"
    printf 'worktree\t%s\n' "$worktree"
  } > "$manifest"
}

write_result() {
  disposition=$1
  exit_code=${2:-}
  stage=$3
  ended_ms="$(now_ms)"
  elapsed_ms=$((ended_ms - started_ms))
  acceptance=false
  if [ "$disposition" = passed ]; then
    acceptance=true
  fi
  {
    printf 'disposition\t%s\n' "$disposition"
    printf 'acceptance\t%s\n' "$acceptance"
    printf 'exit_code\t%s\n' "$exit_code"
    printf 'stage\t%s\n' "$stage"
    printf 'elapsed_ms\t%s\n' "$elapsed_ms"
  } > "$result"
}

write_manifest
write_result planned '' planning
printf 'Benchmark %s: %s/%s (%s, %s)\n' "$run_id" "$host" "$workflow" "$model" "$mode"
printf 'Evidence: %s\n' "$run_dir"
if [ "$mode" = dry-run ]; then
  printf '%s\n' 'Dry run only: no worktree or model process was created.'
  exit 0
fi

git -C "$root" diff --quiet --ignore-submodules -- && [ -z "$(git -C "$root" status --porcelain)" ] || {
  write_result setup-failed '' source-check
  printf '%s\n' 'source checkout must be clean before a benchmark run' >&2
  exit 1
}
set +e
git -C "$root" worktree add -b "benchmark/$run_id" "$worktree" "$base_commit"
worktree_status=$?
set -e
if [ "$worktree_status" -ne 0 ]; then
  write_result setup-failed "$worktree_status" worktree
  exit "$worktree_status"
fi

runtime_home="$(mktemp -d "${TMPDIR:-/tmp}/writing-goals-benchmark-home.XXXXXX")"
cleanup_runtime() { rm -rf -- "$runtime_home"; }
trap cleanup_runtime EXIT HUP INT TERM
credential_values="$runtime_home/credential-values"

setup_failed() {
  write_result setup-failed "${1:-}" "$2"
  exit "${1:-1}"
}

if [ "$workflow" = writing-goals ]; then
  setup_timeout_seconds="$(remaining_timeout_seconds)"
  [ "$setup_timeout_seconds" -gt 0 ] || {
    write_result timed-out '' setup
    exit 124
  }
  run_install_with_timeout() {
    set +e
    perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' -- \
      env HOME="$runtime_home" CODEX_HOME="$runtime_home/.codex" bash "$worktree/install.sh" codex \
      > "$run_dir/logs/setup.stdout" 2> "$run_dir/logs/setup.stderr" &
    install_pid=$!
    (
      sleep "$setup_timeout_seconds"
      if kill -0 "$install_pid" 2>/dev/null; then
        printf '%s\n' timed-out > "$run_dir/.setup-timeout"
        command -v pkill >/dev/null 2>&1 && pkill -TERM -P "$install_pid" 2>/dev/null || true
        kill -TERM "-$install_pid" 2>/dev/null || true
        sleep 1
        command -v pkill >/dev/null 2>&1 && pkill -KILL -P "$install_pid" 2>/dev/null || true
        kill -KILL "-$install_pid" 2>/dev/null || true
      fi
    ) &
    install_watchdog_pid=$!
    wait "$install_pid"
    install_status=$?
    if [ -f "$run_dir/.setup-timeout" ]; then
      wait "$install_watchdog_pid" 2>/dev/null || true
    else
      kill "$install_watchdog_pid" 2>/dev/null || true
      wait "$install_watchdog_pid" 2>/dev/null || true
    fi
    set -e
  }
  run_install_with_timeout
  if [ -f "$run_dir/.setup-timeout" ]; then
    rm -f "$run_dir/.setup-timeout"
    write_result timed-out "$install_status" setup
    exit 124
  fi
  [ "$install_status" -eq 0 ] || setup_failed "$install_status" install
fi
if [ -n "${WG_CODEX_AUTH_SOURCE:-}" ]; then
  [ -f "$WG_CODEX_AUTH_SOURCE" ] && [ ! -L "$WG_CODEX_AUTH_SOURCE" ] || {
    printf '%s\n' 'WG_CODEX_AUTH_SOURCE must be a regular authentication file' >&2
    setup_failed 2 authentication
  }
  jq -er . "$WG_CODEX_AUTH_SOURCE" >/dev/null || {
    printf '%s\n' 'WG_CODEX_AUTH_SOURCE must contain valid JSON' >&2
    setup_failed 2 authentication
  }
  jq -r 'paths(strings) as $path | ($path | map(tostring) | join(".") | ascii_downcase) as $key | select($key | test("token|secret|key|password|credential|auth|session")) | getpath($path) | select(length >= 8)' "$WG_CODEX_AUTH_SOURCE" > "$credential_values"
  mkdir -p "$runtime_home/.codex"
  cp "$WG_CODEX_AUTH_SOURCE" "$runtime_home/.codex/auth.json"
  chmod 600 "$runtime_home/.codex/auth.json"
fi
unset WG_CODEX_AUTH_SOURCE

discard_credential_leak() {
  leaked_path=$1
  printf 'credential value found in retained benchmark evidence (%s); discarded run\n' "$leaked_path" >&2
  rm -rf -- "$run_dir"
  exit 1
}

reject_credential_leaks() {
  [ -s "$credential_values" ] || return 0
  while IFS= read -r credential_value || [ -n "$credential_value" ]; do
    leaked_path="$(grep -a -r -F -l -- "$credential_value" "$run_dir/logs" "$worktree" || true)"
    [ -z "$leaked_path" ] || discard_credential_leak "$leaked_path"
  done < "$credential_values"
}

# Perl ships with macOS and common Linux distributions.  It gives the adapter a
# new session/process group, allowing the watchdog to terminate descendants too.
agent_timeout_seconds="$(remaining_timeout_seconds)"
[ "$agent_timeout_seconds" -gt 0 ] || {
  reject_credential_leaks
  write_result timed-out '' setup
  exit 124
}
run_agent_with_timeout() {
  set +e
  perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' -- \
env HOME="$runtime_home" CODEX_HOME="$runtime_home/.codex" \
  GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false GH_CONFIG_DIR="$runtime_home/.config/gh" \
  GIT_AUTHOR_NAME='Writing Goals Benchmark' GIT_AUTHOR_EMAIL='benchmark@writing-goals.invalid' \
  GIT_COMMITTER_NAME='Writing Goals Benchmark' GIT_COMMITTER_EMAIL='benchmark@writing-goals.invalid' \
    bash "$root/benchmarks/adapters/codex.sh" "$worktree" "$model" \
    "$scenario/prompt.txt" "$run_dir/logs/final.md" > "$run_dir/logs/events.jsonl" 2> "$run_dir/logs/stderr.log" &
  agent_pid=$!
  (
    sleep "$agent_timeout_seconds"
    if kill -0 "$agent_pid" 2>/dev/null; then
      printf '%s\n' timed-out > "$run_dir/.timeout"
      command -v pkill >/dev/null 2>&1 && pkill -TERM -P "$agent_pid" 2>/dev/null || true
      kill -TERM "-$agent_pid" 2>/dev/null || true
      sleep 1
      command -v pkill >/dev/null 2>&1 && pkill -KILL -P "$agent_pid" 2>/dev/null || true
      kill -KILL "-$agent_pid" 2>/dev/null || true
    fi
  ) &
  watchdog_pid=$!
  wait "$agent_pid"
  agent_status=$?
  if [ -f "$run_dir/.timeout" ]; then
    wait "$watchdog_pid" 2>/dev/null || true
  else
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
  fi
  set -e
}

run_agent_with_timeout
if [ -f "$run_dir/.timeout" ]; then
  rm -f "$run_dir/.timeout"
  reject_credential_leaks
  write_result timed-out "$agent_status" agent
  exit 124
fi
if [ "$agent_status" -ne 0 ]; then
  reject_credential_leaks
  if [ "$agent_status" -ge 128 ]; then
    write_result signaled "$agent_status" agent
  else
    write_result agent-failed "$agent_status" agent
  fi
  exit "$agent_status"
fi
reject_credential_leaks

set +e
evaluator_timeout_seconds="$(remaining_timeout_seconds)"
[ "$evaluator_timeout_seconds" -gt 0 ] || {
  reject_credential_leaks
  write_result timed-out '' evaluator
  exit 124
}
run_evaluator_with_timeout() {
  perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' -- \
    bash "$run_dir/evaluator.sh" "$worktree" > "$run_dir/logs/evaluator.stdout" 2> "$run_dir/logs/evaluator.stderr" &
  evaluator_pid=$!
  (
    sleep "$evaluator_timeout_seconds"
    if kill -0 "$evaluator_pid" 2>/dev/null; then
      printf '%s\n' timed-out > "$run_dir/.evaluator-timeout"
      command -v pkill >/dev/null 2>&1 && pkill -TERM -P "$evaluator_pid" 2>/dev/null || true
      kill -TERM "-$evaluator_pid" 2>/dev/null || true
      sleep 1
      command -v pkill >/dev/null 2>&1 && pkill -KILL -P "$evaluator_pid" 2>/dev/null || true
      kill -KILL "-$evaluator_pid" 2>/dev/null || true
    fi
  ) &
  evaluator_watchdog_pid=$!
  wait "$evaluator_pid"
  evaluator_status=$?
  if [ -f "$run_dir/.evaluator-timeout" ]; then
    wait "$evaluator_watchdog_pid" 2>/dev/null || true
  else
    kill "$evaluator_watchdog_pid" 2>/dev/null || true
    wait "$evaluator_watchdog_pid" 2>/dev/null || true
  fi
}
run_evaluator_with_timeout
set -e
if [ -f "$run_dir/.evaluator-timeout" ]; then
  rm -f "$run_dir/.evaluator-timeout"
  reject_credential_leaks
  write_result timed-out "$evaluator_status" evaluator
  exit 124
fi
if [ "$evaluator_status" -ne 0 ]; then
  reject_credential_leaks
  if [ "$evaluator_status" -ge 128 ]; then
    write_result signaled "$evaluator_status" evaluator
  else
    write_result evaluator-failed "$evaluator_status" evaluator
  fi
  exit "$evaluator_status"
fi
reject_credential_leaks
write_result passed 0 evaluator
printf '%s\n' 'Benchmark passed; retained worktree and evidence for independent review.'
