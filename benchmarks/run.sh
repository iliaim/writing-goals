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
sandbox=
permission=
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  key=${line%%=*}
  value=${line#*=}
  [ "$key" != "$line" ] || { printf 'invalid profile row: %s\n' "$line" >&2; exit 2; }
  case "$key" in
    host) [ -z "$host" ] || exit 2; host=$value ;;
    model) [ -z "$model" ] || exit 2; model=$value ;;
    workflow) [ -z "$workflow" ] || exit 2; workflow=$value ;;
    sandbox) [ -z "$sandbox" ] || exit 2; sandbox=$value ;;
    permission) [ -z "$permission" ] || exit 2; permission=$value ;;
    *) printf 'unknown profile key: %s\n' "$key" >&2; exit 2 ;;
  esac
done < "$profile"

case "$host" in codex) ;; *) printf 'unsupported host: %s\n' "$host" >&2; exit 2 ;; esac
case "$workflow" in control|writing-goals) ;; *) printf 'unsupported workflow: %s\n' "$workflow" >&2; exit 2 ;; esac
case "$sandbox" in read-only|workspace-write|danger-full-access) ;; *) printf 'invalid sandbox: %s\n' "$sandbox" >&2; exit 2 ;; esac
case "$permission" in standard|dangerous) ;; *) printf 'invalid permission: %s\n' "$permission" >&2; exit 2 ;; esac
[ -n "$model" ] || { printf '%s\n' 'profile model is required' >&2; exit 2; }
if [ "$permission" = dangerous ] && [ "${WG_EXTERNAL_SANDBOX:-}" != 1 ]; then
  printf '%s\n' 'dangerous permission requires WG_EXTERNAL_SANDBOX=1; a worktree is not a security boundary' >&2
  exit 2
fi

mkdir -p "$output_root"
output_root="$(CDPATH= cd -- "$output_root" && pwd -P)"
run_dir="$output_root/$run_id"
[ ! -e "$run_dir" ] && [ ! -L "$run_dir" ] || { printf 'run directory exists: %s\n' "$run_dir" >&2; exit 2; }
mkdir -p "$run_dir/home" "$run_dir/logs"
worktree="$run_dir/worktree"
manifest="$run_dir/manifest.tsv"
result="$run_dir/result.tsv"
prompt_hash="$(shasum -a 256 "$scenario/prompt.txt" | awk '{print $1}')"
profile_hash="$(shasum -a 256 "$profile" | awk '{print $1}')"
base_commit="$(git -C "$root" rev-parse HEAD)"

write_manifest() {
  {
    printf 'run_id\t%s\n' "$run_id"
    printf 'base_commit\t%s\n' "$base_commit"
    printf 'host\t%s\n' "$host"
    printf 'model\t%s\n' "$model"
    printf 'workflow\t%s\n' "$workflow"
    printf 'sandbox\t%s\n' "$sandbox"
    printf 'permission\t%s\n' "$permission"
    printf 'profile_sha256\t%s\n' "$profile_hash"
    printf 'prompt_sha256\t%s\n' "$prompt_hash"
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

if [ "$workflow" = writing-goals ]; then
  CODEX_HOME="$run_dir/home/.codex" bash "$worktree/install.sh" codex
fi
if [ -n "${WG_CODEX_AUTH_SOURCE:-}" ]; then
  [ -f "$WG_CODEX_AUTH_SOURCE" ] && [ ! -L "$WG_CODEX_AUTH_SOURCE" ] || {
    printf '%s\n' 'WG_CODEX_AUTH_SOURCE must be a regular authentication file' >&2
    exit 2
  }
  mkdir -p "$run_dir/home/.codex"
  cp "$WG_CODEX_AUTH_SOURCE" "$run_dir/home/.codex/auth.json"
  chmod 600 "$run_dir/home/.codex/auth.json"
fi

set +e
env HOME="$run_dir/home" CODEX_HOME="$run_dir/home/.codex" \
  GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false GH_CONFIG_DIR="$run_dir/home/.config/gh" \
  bash "$root/benchmarks/adapters/codex.sh" "$worktree" "$model" "$sandbox" "$permission" \
  "$scenario/prompt.txt" "$run_dir/logs/final.md" > "$run_dir/logs/events.jsonl" 2> "$run_dir/logs/stderr.log"
agent_status=$?
set -e
if [ "$agent_status" -ne 0 ]; then
  write_result "agent-failed:$agent_status"
  exit "$agent_status"
fi

set +e
bash "$scenario/evaluate.sh" "$worktree" > "$run_dir/logs/evaluator.stdout" 2> "$run_dir/logs/evaluator.stderr"
evaluator_status=$?
set -e
if [ "$evaluator_status" -ne 0 ]; then
  write_result "evaluator-failed:$evaluator_status"
  exit "$evaluator_status"
fi
write_result passed
printf '%s\n' 'Benchmark passed; retained worktree and evidence for independent review.'
