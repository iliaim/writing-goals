#!/usr/bin/env bash
# Read-only aggregation for one predeclared benchmark cohort.
set -euo pipefail

usage() {
  printf '%s\n' "usage: $0 --ledger FILE --run-root DIRECTORY" >&2
  exit 2
}

ledger=
run_root=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ledger) [ "$#" -ge 2 ] || usage; ledger=$2; shift 2 ;;
    --run-root) [ "$#" -ge 2 ] || usage; run_root=$2; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$ledger" ] && [ -f "$ledger" ] && [ ! -L "$ledger" ] || usage
[ -n "$run_root" ] && [ -d "$run_root" ] && [ ! -L "$run_root" ] || usage

ledger_header=$'cohort_id\tbase_commit\tprofile_sha256\tprompt_sha256\tevaluator_sha256\tadapter_sha256\tscenario_id\tarm\trepeat\trun_id\tplanned_order\ttimeout_seconds\toperator_action'
awk -F '\t' -v expected="$ledger_header" '
  function reject(reason) { print reason > "/dev/stderr"; aborted = 1; exit 1 }
  NR == 1 { if ($0 != expected) reject("invalid ledger header"); next }
  NF != 13 { reject("invalid ledger row field count at line " NR) }
  $1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "" || $6 == "" || $7 == "" || $8 == "" || $9 == "" || $10 == "" || $11 == "" || $12 == "" || $13 == "" { reject("blank ledger field at line " NR) }
  $8 !~ /^(control|treatment)$/ { reject("invalid ledger arm at line " NR) }
  $9 !~ /^[1-9][0-9]*$/ || $11 !~ /^[1-9][0-9]*$/ || $11 > 12 || $12 !~ /^[1-9][0-9]*$/ || $12 > 3600 { reject("invalid ledger numeric field at line " NR) }
  $13 !~ /^(none|operator-aborted|environment-repaired)$/ { reject("invalid ledger operator action at line " NR) }
  # A cohort compares one code state through one adapter, so the identities that
  # are cohort-scoped must agree across all twelve rows, and each scenario must
  # present the same prompt and evaluator to both arms.  Per-row checks cannot
  # see this: a ledger split across two commits satisfies every row on its own.
  cohort != "" && cohort != $1 { reject("ledger has multiple cohort_ids") }
  ledger_base != "" && ledger_base != $2 { reject("ledger must declare a single base_commit") }
  ledger_adapter != "" && ledger_adapter != $6 { reject("ledger must declare a single adapter_sha256") }
  scenario_prompt[$7] != "" && scenario_prompt[$7] != $4 { reject("ledger must declare a single prompt_sha256 per scenario_id") }
  scenario_evaluator[$7] != "" && scenario_evaluator[$7] != $5 { reject("ledger must declare a single evaluator_sha256 per scenario_id") }
  { cohort = $1; ledger_base = $2; ledger_adapter = $6; scenario_prompt[$7] = $4; scenario_evaluator[$7] = $5 }
  seen_run[$10]++ { reject("duplicate ledger run_id: " $10) }
  seen_order[$11]++ { reject("duplicate ledger planned_order: " $11) }
  END {
    if (aborted) exit 1
    if (NR != 13) reject("ledger must contain exactly 12 run rows")
    for (order = 1; order <= 12; order++) if (!seen_order[order]) reject("ledger planned_order must be contiguous 1..12")
  }
' "$ledger"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/writing-goals-aggregate.XXXXXX")"
cleanup() { rm -rf -- "$scratch"; }
trap cleanup EXIT HUP INT TERM
facts="$scratch/facts.tsv"
: > "$facts"

value_for() {
  value_file=$1
  value_key=$2
  awk -F '\t' -v key="$value_key" '
    $1 == key { value = $2; count++ }
    END { if (count != 1) exit 1; print value }
  ' "$value_file"
}

result_value() {
  result_file=$1
  result_key=$2
  value_for "$result_file" "$result_key"
}

while IFS=$'\t' read -r cohort_id base_commit profile_hash prompt_hash evaluator_hash adapter_hash scenario_id arm repeat run_id planned_order timeout_seconds operator_action; do
  [ "$cohort_id" = cohort_id ] && continue
  printf '%s' "$run_id" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || {
    printf 'rca trigger: invalid-pair (invalid run_id in ledger: %s)\n' "$run_id" >&2
    exit 1
  }
  run_dir="$run_root/$run_id"
  manifest="$run_dir/manifest.tsv"
  result="$run_dir/result.tsv"
  [ -d "$run_dir" ] && [ ! -L "$run_dir" ] && [ -f "$manifest" ] && [ ! -L "$manifest" ] && [ -f "$result" ] && [ ! -L "$result" ] || {
    printf 'rca trigger: invalid-pair (missing retained run evidence for %s)\n' "$run_id" >&2
    exit 1
  }

  for field_value in \
    "run_id:$run_id" "cohort_id:$cohort_id" "base_commit:$base_commit" \
    "profile_sha256:$profile_hash" "prompt_sha256:$prompt_hash" \
    "evaluator_sha256:$evaluator_hash" "adapter_sha256:$adapter_hash" \
    "scenario_id:$scenario_id" "arm:$arm" "repeat:$repeat" \
    "planned_order:$planned_order" "timeout_seconds:$timeout_seconds" \
    "operator_action:$operator_action"; do
    manifest_key=${field_value%%:*}
    expected_value=${field_value#*:}
    actual_value="$(value_for "$manifest" "$manifest_key")" || {
      printf 'rca trigger: invalid-pair (missing manifest %s for %s)\n' "$manifest_key" "$run_id" >&2
      exit 1
    }
    [ "$actual_value" = "$expected_value" ] || {
      printf 'rca trigger: invalid-pair (manifest %s mismatch for %s)\n' "$manifest_key" "$run_id" >&2
      exit 1
    }
  done

  workflow="$(value_for "$manifest" workflow)" || {
    printf 'rca trigger: invalid-pair (missing manifest workflow for %s)\n' "$run_id" >&2
    exit 1
  }
  case "$arm:$workflow" in
    control:control|treatment:writing-goals) ;;
    *) printf 'rca trigger: invalid-pair (workflow does not match arm for %s)\n' "$run_id" >&2; exit 1 ;;
  esac
  started_ms="$(value_for "$manifest" started_ms)" || { printf 'rca trigger: invalid-pair (missing started_ms for %s)\n' "$run_id" >&2; exit 1; }
  model="$(value_for "$manifest" model)" || { printf 'rca trigger: invalid-pair (missing manifest model for %s)\n' "$run_id" >&2; exit 1; }
  case "$started_ms" in ''|*[!0-9]*) printf 'rca trigger: invalid-pair (invalid started_ms for %s)\n' "$run_id" >&2; exit 1 ;; esac

  disposition="$(result_value "$result" disposition)" || { printf 'rca trigger: invalid-pair (missing disposition for %s)\n' "$run_id" >&2; exit 1; }
  acceptance="$(result_value "$result" acceptance)" || { printf 'rca trigger: invalid-pair (missing acceptance for %s)\n' "$run_id" >&2; exit 1; }
  elapsed_ms="$(result_value "$result" elapsed_ms)" || { printf 'rca trigger: invalid-pair (missing elapsed_ms for %s)\n' "$run_id" >&2; exit 1; }
  stage="$(result_value "$result" stage)" || { printf 'rca trigger: invalid-pair (missing stage for %s)\n' "$run_id" >&2; exit 1; }
  exit_code="$(result_value "$result" exit_code)" || { printf 'rca trigger: invalid-pair (missing exit_code for %s)\n' "$run_id" >&2; exit 1; }
  case "$disposition" in planned|setup-failed|timed-out|signaled|agent-failed|evaluator-failed|passed) ;; *) printf 'rca trigger: invalid-pair (invalid disposition for %s)\n' "$run_id" >&2; exit 1 ;; esac
  [ "$disposition" != planned ] || { printf 'rca trigger: invalid-pair (planned run is incomplete: %s)\n' "$run_id" >&2; exit 1; }
  case "$acceptance" in true|false) ;; *) printf 'rca trigger: invalid-pair (invalid acceptance for %s)\n' "$run_id" >&2; exit 1 ;; esac
  case "$elapsed_ms" in ''|*[!0-9]*) printf 'rca trigger: invalid-pair (invalid elapsed_ms for %s)\n' "$run_id" >&2; exit 1 ;; esac
  [ -n "$stage" ] || { printf 'rca trigger: invalid-pair (empty stage for %s)\n' "$run_id" >&2; exit 1; }
  case "$exit_code" in
    '') ;;
    *[!0-9]*) printf 'rca trigger: invalid-pair (invalid exit_code for %s)\n' "$run_id" >&2; exit 1 ;;
  esac
  case "$disposition:$stage:$exit_code" in
    setup-failed:source-check:|setup-failed:source-check:[0-9]*|setup-failed:worktree:[0-9]*|setup-failed:install:[0-9]*|setup-failed:authentication:[0-9]*|timed-out:setup:|timed-out:setup:[0-9]*|timed-out:agent:[0-9]*|timed-out:evaluator:|timed-out:evaluator:[0-9]*|signaled:runner:[0-9]*|signaled:setup:[0-9]*|signaled:agent:[0-9]*|signaled:evaluator:[0-9]*|agent-failed:agent:[0-9]*|evaluator-failed:evaluator:[0-9]*|passed:evaluator:0) ;;
    *) printf 'rca trigger: invalid-pair (disposition detail mismatch for %s)\n' "$run_id" >&2; exit 1 ;;
  esac
  if [ "$disposition" = passed ]; then [ "$acceptance" = true ] || { printf 'rca trigger: invalid-pair (passed run not accepted for %s)\n' "$run_id" >&2; exit 1; }; else [ "$acceptance" = false ] || { printf 'rca trigger: invalid-pair (non-pass accepted for %s)\n' "$run_id" >&2; exit 1; }; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$scenario_id" "$arm" "$repeat" "$run_id" "$disposition" "$acceptance" "$elapsed_ms" "$operator_action" "$started_ms" "$profile_hash" "$model" "$planned_order" >> "$facts"
done < "$ledger"

# A valid cohort contains the paired control/treatment comparison twice for
# every scenario.  Do not silently aggregate an incomplete or duplicated pair.
awk -F '\t' '
  function reject(reason) { print "rca trigger: invalid-pair (" reason ")" > "/dev/stderr"; aborted = 1; exit 1 }
  {
    pair[$1 SUBSEP $3 SUBSEP $2]++
    repeats[$1 SUBSEP $2]++
    pair_any[$1 SUBSEP $3]++
    if (seen_profile[$2] && profile[$2] != $10) reject("profile drift")
    profile[$2] = $10
    seen_profile[$2] = 1
    if (seen_model[$2] && model[$2] != $11) reject("model drift")
    model[$2] = $11
    seen_model[$2] = 1
    # Key the observed start time by the planned order the run was declared to
    # occupy.  Comparing those keys in sequence is what proves the cohort ran in
    # its declared interleaving instead of merely claiming to.
    starts[$12] = $9
  }
  END {
    if (aborted) exit 1
    for (key in pair) if (pair[key] != 1) reject("duplicate arm/repeat")
    for (key in pair_any) if (pair_any[key] != 2) reject("missing control/treatment pair")
    for (key in repeats) if (repeats[key] != 2) reject("expected exactly two repeats per scenario/arm")
    for (key in pair_any) { split(key, components, SUBSEP); scenarios[components[1]] = 1 }
    for (scenario in scenarios) scenario_count++
    if (scenario_count != 3) reject("expected exactly three scenarios")
    for (order = 1; order <= 12; order++) if (!(order in starts)) reject("missing observed start for planned order " order)
    for (order = 2; order <= 12; order++) if (starts[order] + 0 <= starts[order - 1] + 0) reject("execution order does not match ledger")
  }
' "$facts"

printf 'scenario_id\tarm\trepeat\tdisposition\tacceptance\telapsed_ms\toperator_action\tpaired_disposition\tpaired_acceptance\tpair_status\trca_trigger\ttwo_repeat_consistency\n'
tab=$(printf '\t')
LC_ALL=C sort -t "$tab" -k1,1 -k3,3n -k2,2 "$facts" | while IFS=$'\t' read -r scenario_id arm repeat run_id disposition acceptance elapsed_ms operator_action started_ms profile_hash model planned_order; do
  if [ "$arm" = control ]; then paired_arm=treatment; else paired_arm=control; fi
  paired_line="$(awk -F '\t' -v scenario="$scenario_id" -v repeat="$repeat" -v arm="$paired_arm" '$1 == scenario && $2 == arm && $3 == repeat { print }' "$facts")"
  IFS=$'\t' read -r _ paired_arm _ _ paired_disposition paired_acceptance _ _ _ _ _ _ <<EOF
$paired_line
EOF
  pair_status=comparable
  case "$disposition:$paired_disposition" in *planned*|*setup-failed*) pair_status=not-comparable ;; esac
  if [ "$acceptance" != "$paired_acceptance" ]; then rca_trigger=discordant-paired-acceptance
  elif [ "$acceptance" != true ]; then rca_trigger=non-pass
  else rca_trigger=none
  fi
  repeat_values="$(awk -F '\t' -v scenario="$scenario_id" -v arm="$arm" '$1 == scenario && $2 == arm { print $5 "\t" $6 }' "$facts")"
  if printf '%s\n' "$repeat_values" | grep -Eq '^(planned|setup-failed)\t'; then
    consistency=not-comparable
  elif [ "$(printf '%s\n' "$repeat_values" | awk -F '\t' 'NR == 1 { first = $2 } $2 != first { different = 1 } END { print different ? "discordant" : "consistent" }')" = discordant ]; then
    consistency=discordant
  else
    consistency=consistent
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$scenario_id" "$arm" "$repeat" "$disposition" "$acceptance" "$elapsed_ms" "$operator_action" \
    "$paired_disposition" "$paired_acceptance" "$pair_status" "$rca_trigger" "$consistency"
done
