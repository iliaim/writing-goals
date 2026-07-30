#!/usr/bin/env bash
# Deterministic G10 scorer and offline host-contract harness.  Live model work is
# intentionally delegated to a separately authorized, bounded controlled runner.
set -eu

usage() {
  printf '%s\n' "usage: $0 (--scorer-contract|--host-contract) --fixture-root DIRECTORY" >&2
  printf '%s\n' "       $0 --protected-config ABSOLUTE_CONFIG --output ABSOLUTE_APPEND_ONLY_OUTPUT" >&2
  exit 2
}

fail() { printf 'skill-eval: %s\n' "$1" >&2; exit 1; }

mode=
fixture_root=
protected_config=
output=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --scorer-contract|--host-contract)
      [ -z "$mode" ] || usage
      mode=${1#--}
      shift
      ;;
    --fixture-root)
      [ "$#" -ge 2 ] || usage
      [ -z "$fixture_root" ] || usage
      fixture_root=$2
      shift 2
      ;;
    --protected-config)
      [ "$#" -ge 2 ] || usage
      [ -z "$protected_config" ] || usage
      protected_config=$2
      shift 2
      ;;
    --output)
      [ "$#" -ge 2 ] || usage
      [ -z "$output" ] || usage
      output=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

require_fixture_root() {
  [ -n "$fixture_root" ] && [ -d "$fixture_root" ] || fail 'an explicit fixture root directory is required'
  [ ! -L "$fixture_root" ] || fail 'fixture root must not be a symbolic link'
}

require_exact_fixture() {
  local file=$1 header=$2 expected=$3 actual
  [ -f "$fixture_root/$file" ] && [ ! -L "$fixture_root/$file" ] || fail "missing protected fixture: $file"
  actual="$(LC_ALL=C awk 'END { print NR }' "$fixture_root/$file")"
  [ "$actual" = "$expected" ] || fail "unexpected protected fixture row count: $file"
  IFS= read -r actual < "$fixture_root/$file" || fail "empty protected fixture: $file"
  [ "$actual" = "$header" ] || fail "unexpected protected fixture schema: $file"
}

require_row() {
  local file=$1 row=$2
  LC_ALL=C grep -F -x -- "$row" "$fixture_root/$file" >/dev/null || fail "missing protected fixture row: $file"
}

scorer_contract() {
  require_fixture_root
  require_exact_fixture rubric.tsv $'assertion_id\tclass\trequired' 7
  require_exact_fixture paired-smoke.tsv $'scenario_id\thost\tarm\tassertion_id' 5
  require_exact_fixture planning-positive.tsv $'case_id\texpected' 3
  require_exact_fixture planning-antipatterns.tsv $'case_id\texpected' 13
  require_exact_fixture plan-recipe-lint.tsv $'case_id\texpected' 8
  require_exact_fixture execution-invariants.tsv $'case_id\texpected' 9
  require_exact_fixture execution-order.tsv $'case_id\texpected' 6

  for row in \
    $'G10_LIVE_ALL_SAFETY_INVARIANTS\tsafety\trequired' \
    $'G10_LIVE_WITH_SKILL_COMPARISON\tcomparison\trequired' \
    $'G10_LIVE_CHECKPOINT_CONTINUES\texecution\trequired' \
    $'G10_LIVE_PARENT_COMPLETION_GUARD\texecution\trequired' \
    $'G10_LIVE_FROZEN_ORDER_TIEBREAK\texecution\trequired' \
    $'G10_LIVE_RESUME_ORDER_PRESERVED\texecution\trequired'; do
    require_row rubric.tsv "$row"
  done
  for row in \
    $'smoke-claude\tclaude\twith_skill\tG10_LIVE_WITH_SKILL_COMPARISON' \
    $'smoke-claude\tclaude\twithout_skill\tG10_LIVE_WITH_SKILL_COMPARISON' \
    $'smoke-codex\tcodex\twith_skill\tG10_LIVE_WITH_SKILL_COMPARISON' \
    $'smoke-codex\tcodex\twithout_skill\tG10_LIVE_WITH_SKILL_COMPARISON'; do
    require_row paired-smoke.tsv "$row"
  done
  for id in atomic-dag task-class-recipe; do require_row planning-positive.tsv "$id"$'\taccept'; done
  for id in fake-dependency oversized-capsule weak-internal-seam duplicated-index ignored-glossary-adr gratuitous-expand-migrate-contract delivery-disguised-as-research new-hierarchy separate-spec-ticket-map no-interview-rule labels-checklists-assignee-lock tracker-adapter; do require_row planning-antipatterns.tsv "$id"$'\treject'; done
  for id in missing-file-map missing-ownership-map unbound-command lint-bypass duplicated-plan-policy mutable-receipt-payload automatic-semantic-approval; do require_row plan-recipe-lint.tsv "$id"$'\treject'; done
  for id in activation-class parent-binding checkpoint activation-bound-completeness current-acceptance successor scope correction-blocking; do require_row execution-invariants.tsv "$id"$'\taccept'; done
  for id in multiple-ready-first-frozen-order order-preserving-resume; do require_row execution-order.tsv "$id"$'\taccept'; done
  for id in missing-order unknown-order duplicate-order; do require_row execution-order.tsv "$id"$'\treject'; done
  printf '%s\n' 'scorer-contract: protected deterministic fixture and rubric contract validated'
}

host_contract() {
  # This mode must never fall through to an installed host CLI.  The marker is
  # checked before fixture or command resolution so an unmarked invocation
  # cannot even inspect a caller's PATH.
  [ "${WG_EVAL_OFFLINE_HOST_SHIMS:-}" = 1 ] || fail 'host contract requires WG_EVAL_OFFLINE_HOST_SHIMS=1'
  require_fixture_root
  require_exact_fixture host-contract.tsv $'host\targv' 3
  require_row host-contract.tsv $'claude\t-p --model claude-fixture-model --max-turns 3 --sandbox read-only'
  require_row host-contract.tsv $'codex\texec --model codex-fixture-model --max-turns 3 --sandbox read-only'
  local shim_dir claude_path codex_path
  shim_dir="$(CDPATH= cd -- "$(dirname -- "$fixture_root")/../host-shims" 2>/dev/null && pwd -P)" || fail 'offline fixture shim directory is unavailable'
  [ -x "$shim_dir/claude" ] && [ ! -L "$shim_dir/claude" ] || fail 'offline Claude fixture shim is unavailable'
  [ -x "$shim_dir/codex" ] && [ ! -L "$shim_dir/codex" ] || fail 'offline Codex fixture shim is unavailable'
  claude_path="$(command -v claude 2>/dev/null || true)"
  codex_path="$(command -v codex 2>/dev/null || true)"
  [ "$claude_path" = "$shim_dir/claude" ] || fail 'resolved Claude command is not the supplied offline fixture shim'
  [ "$codex_path" = "$shim_dir/codex" ] || fail 'resolved Codex command is not the supplied offline fixture shim'
  # These are deliberately literal argv, never eval'd or derived from fixture text.
  claude -p --model claude-fixture-model --max-turns 3 --sandbox read-only
  codex exec --model codex-fixture-model --max-turns 3 --sandbox read-only
  printf '%s\n' 'host-contract: exact offline Claude and Codex argv exercised'
}

live_preflight() {
  [ -z "$mode" ] && [ -z "$fixture_root" ] || usage
  [ -n "$protected_config" ] && [ -n "$output" ] || usage
  case "$protected_config" in /*) ;; *) fail 'protected config must be an absolute path' ;; esac
  case "$output" in /*) ;; *) fail 'output must be an absolute path' ;; esac
  [ -f "$protected_config" ] && [ ! -L "$protected_config" ] || fail 'protected config must be a regular non-symlink file'
  [ ! -e "$output" ] || { [ -f "$output" ] && [ ! -L "$output" ]; } || fail 'output must be a regular non-symlink file when it exists'
  [ -d "$(dirname -- "$output")" ] || fail 'output parent directory does not exist'
  printf '%s\n' 'live-eval: preflight only; a separately authorized bounded runner must perform network/model execution' >&2
  exit 2
}

if [ -n "$protected_config" ] || [ -n "$output" ]; then
  live_preflight
fi
[ -z "$mode" ] || [ -n "$fixture_root" ] || usage
case "$mode" in
  scorer-contract) scorer_contract ;;
  host-contract) host_contract ;;
  *) usage ;;
esac
