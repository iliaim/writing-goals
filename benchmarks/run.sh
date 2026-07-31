#!/usr/bin/env bash
# Reproducible local benchmark runner. Profiles are data; adapters own CLI argv.
set -euo pipefail

usage() {
  printf '%s\n' "usage: $0 --profile FILE --scenario DIRECTORY --run-id ID [--output-root DIRECTORY] (--dry-run|--execute)" >&2
  exit 2
}

root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
profile=
scenario=
run_id=
output_root="$root/.archive/benchmarks"
mode=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) [ "$#" -ge 2 ] || usage; profile=$2; shift 2 ;;
    --scenario) [ "$#" -ge 2 ] || usage; scenario=$2; shift 2 ;;
    --run-id) [ "$#" -ge 2 ] || usage; run_id=$2; shift 2 ;;
    --output-root) [ "$#" -ge 2 ] || usage; output_root=$2; shift 2 ;;
    --dry-run|--execute) [ -z "$mode" ] || usage; mode=${1#--}; shift ;;
    *) usage ;;
  esac
done

[ -n "$profile" ] && [ -f "$profile" ] && [ ! -L "$profile" ] || usage
[ -n "$scenario" ] && [ -d "$scenario" ] && [ ! -L "$scenario" ] || usage
[ -n "$run_id" ] && printf '%s' "$run_id" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || usage
[ -n "$mode" ] || usage
[ -f "$scenario/prompt.txt" ] && [ -x "$scenario/evaluate.sh" ] || {
  printf '%s\n' 'scenario requires regular prompt.txt and executable evaluate.sh files' >&2
  exit 2
}

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

# Benchmarks run without interactive approvals but never opt into a bypass or broader sandbox.
approval_policy=never
sandbox=workspace-write

mkdir -p "$output_root"
output_root="$(CDPATH= cd -- "$output_root" && pwd -P)"
run_dir="$output_root/$run_id"
[ ! -e "$run_dir" ] && [ ! -L "$run_dir" ] || { printf 'run directory exists: %s\n' "$run_dir" >&2; exit 2; }
mkdir -p "$run_dir/logs"
worktree="$run_dir/worktree"
manifest="$run_dir/manifest.tsv"
result="$run_dir/result.tsv"
prompt_hash="$(shasum -a 256 "$scenario/prompt.txt" | awk '{print $1}')"
profile_hash="$(shasum -a 256 "$profile" | awk '{print $1}')"
evaluator_hash="$(shasum -a 256 "$scenario/evaluate.sh" | awk '{print $1}')"
base_commit="$(git -C "$root" rev-parse HEAD)"
cp "$scenario/evaluate.sh" "$run_dir/evaluator.sh"
chmod 700 "$run_dir/evaluator.sh"

write_manifest() {
  {
    printf 'run_id\t%s\n' "$run_id"
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
    printf 'runtime_home\t%s\n' 'ephemeral'
    printf 'scenario\t%s\n' "$scenario"
    printf 'worktree\t%s\n' "$worktree"
  } > "$manifest"
}

write_result() {
  printf 'status\t%s\n' "$1" > "$result"
}

write_manifest
write_result planned
printf 'Benchmark %s: %s/%s (%s, %s)\n' "$run_id" "$host" "$workflow" "$model" "$mode"
printf 'Evidence: %s\n' "$run_dir"
if [ "$mode" = dry-run ]; then
  printf '%s\n' 'Dry run only: no worktree or model process was created.'
  exit 0
fi

git -C "$root" diff --quiet --ignore-submodules -- && [ -z "$(git -C "$root" status --porcelain)" ] || {
  printf '%s\n' 'source checkout must be clean before a benchmark run' >&2
  exit 1
}
git -C "$root" worktree add -b "benchmark/$run_id" "$worktree" "$base_commit"

runtime_home="$(mktemp -d "${TMPDIR:-/tmp}/writing-goals-benchmark-home.XXXXXX")"
cleanup_runtime() { rm -rf -- "$runtime_home"; }
trap cleanup_runtime EXIT HUP INT TERM
credential_values="$runtime_home/credential-values"

if [ "$workflow" = writing-goals ]; then
  HOME="$runtime_home" CODEX_HOME="$runtime_home/.codex" bash "$worktree/install.sh" codex
fi
if [ -n "${WG_CODEX_AUTH_SOURCE:-}" ]; then
  [ -f "$WG_CODEX_AUTH_SOURCE" ] && [ ! -L "$WG_CODEX_AUTH_SOURCE" ] || {
    printf '%s\n' 'WG_CODEX_AUTH_SOURCE must be a regular authentication file' >&2
    exit 2
  }
  jq -er . "$WG_CODEX_AUTH_SOURCE" >/dev/null || {
    printf '%s\n' 'WG_CODEX_AUTH_SOURCE must contain valid JSON' >&2
    exit 2
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

set +e
env HOME="$runtime_home" CODEX_HOME="$runtime_home/.codex" \
  GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false GH_CONFIG_DIR="$runtime_home/.config/gh" \
  bash "$root/benchmarks/adapters/codex.sh" "$worktree" "$model" \
  "$scenario/prompt.txt" "$run_dir/logs/final.md" > "$run_dir/logs/events.jsonl" 2> "$run_dir/logs/stderr.log"
agent_status=$?
set -e
if [ "$agent_status" -ne 0 ]; then
  reject_credential_leaks
  write_result "agent-failed:$agent_status"
  exit "$agent_status"
fi
reject_credential_leaks

set +e
bash "$run_dir/evaluator.sh" "$worktree" > "$run_dir/logs/evaluator.stdout" 2> "$run_dir/logs/evaluator.stderr"
evaluator_status=$?
set -e
if [ "$evaluator_status" -ne 0 ]; then
  reject_credential_leaks
  write_result "evaluator-failed:$evaluator_status"
  exit "$evaluator_status"
fi
reject_credential_leaks
write_result passed
printf '%s\n' 'Benchmark passed; retained worktree and evidence for independent review.'
