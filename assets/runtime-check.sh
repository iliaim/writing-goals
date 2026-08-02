#!/usr/bin/env bash
# Read-only view of the protected lifecycle authority. It never selects work.
set -u

die() { printf '%s\n' "runtime-check: $*" >&2; exit 1; }
validate_authority_path() {
  authority_input=$1
  case "$authority_input" in /*) ;; *) die 'authority must be an absolute path' ;; esac
  case "/$authority_input/" in *'/../'*|*'/./'*) die 'authority traversal is not allowed' ;; esac
  authority_walk=/
  authority_rest=${authority_input#/}
  old_ifs=$IFS; IFS='/'; set -- $authority_rest; IFS=$old_ifs
  for authority_part in "$@"; do
    [ -n "$authority_part" ] || continue
    authority_walk=${authority_walk%/}/$authority_part
    if [ -L "$authority_walk" ] && ! { [ "$authority_walk" = /var ] && [ "$(readlink /var 2>/dev/null)" = private/var ]; }; then
      die 'authority symlink is not allowed'
    fi
  done
  [ -d "$authority_input" ] && [ ! -L "$authority_input" ] || die 'authority must be a real directory'
}
authority='' identity='' plan='' run='' status=false reopen=false approval_revoked=false core_fixture='' activation_record='' activation_receipt='' approval_record='' preflight_record='' resume=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --authority|--identity|--plan|--run|--core-fixture|--activation-record|--activation-receipt|--approval-record|--preflight-record)
      [ "$#" -ge 2 ] || die "missing value for $1"
      case "$1" in --authority) authority=$2 ;; --identity) identity=$2 ;; --plan) plan=$2 ;; --run) run=$2 ;; --core-fixture) core_fixture=$2 ;; --activation-record) activation_record=$2 ;; --activation-receipt) activation_receipt=$2 ;; --approval-record) approval_record=$2 ;; --preflight-record) preflight_record=$2 ;; esac
      shift 2 ;;
    --status) status=true; shift ;;
    --resume) resume=true; shift ;;
    --reopen) reopen=true; shift ;;
    --approval-revoked) approval_revoked=true; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$authority" ] && [ -n "$identity" ] && [ -n "$plan" ] && [ -n "$run" ] || die 'authority, identity, plan, and run are required'
validate_authority_path "$authority"
case "$identity" in *[!A-Za-z0-9-]*|'') die 'invalid identity' ;; esac
case "$plan" in p[0-9][0-9]) ;; *) die 'invalid plan' ;; esac
# p03 is the recorded narrow correction to the completed p02 authority, not a
# complete successor plan.  It must never be selected as an activation target.
[ "$plan" != p03 ] || die 'partial correction plan is not activatable'
case "$run" in *[!A-Za-z0-9._-]*|'') die 'invalid run' ;; esac
if stat -f '%Lp' "$authority" >/dev/null 2>&1; then mode=$(stat -f '%Lp' "$authority"); else mode=$(stat -c '%a' "$authority" 2>/dev/null) || die 'cannot inspect authority permissions'; fi
case "$mode" in ???) ;; *) die 'cannot inspect authority permissions' ;; esac
case "${mode#?}" in *[1-7]*) die 'authority is not protected' ;; esac

validate_protected_record() {
  record_path=$1 record_label=$2 expected_keys=$3
  case "$record_path" in "$authority"/*) ;; *) die "$record_label must be inside authority" ;; esac
  [ -f "$record_path" ] && [ ! -L "$record_path" ] || die "missing protected $record_label"
  if stat -f '%Lp' "$record_path" >/dev/null 2>&1; then record_mode=$(stat -f '%Lp' "$record_path"); else record_mode=$(stat -c '%a' "$record_path" 2>/dev/null) || die "cannot inspect $record_label permissions"; fi
  [ "$record_mode" = 600 ] || die "$record_label is not protected"
  record_keys=''
  while IFS='=' read -r record_key record_value || [ -n "${record_key:-}" ]; do
    case "|$expected_keys|" in *"|$record_key|"*) ;; *) die "invalid protected $record_label field" ;; esac
    case "|$record_keys|" in *"|$record_key|"*) die "duplicate protected $record_label field" ;; esac
    record_keys="${record_keys:+$record_keys|}$record_key"
    case "$record_key" in
      objective_digest) record_objective_digest=$record_value ;;
      plan_digest) record_plan_digest=$record_value ;;
      approver) record_approver=$record_value ;;
      approved_at) record_approved_at=$record_value ;;
      revoked) record_revoked=$record_value ;;
      surface_digest) record_surface_digest=$record_value ;;
      baseline) record_baseline=$record_value ;;
    esac
  done < "$record_path"
  old_ifs=$IFS; IFS='|'; set -- $expected_keys; IFS=$old_ifs
  for required_key in "$@"; do
    case "|$record_keys|" in *"|$required_key|"*) ;; *) die "incomplete protected $record_label" ;; esac
  done
}

# P02 activation is allowed only after the immutable p01 predecessor receipt
# binds the frozen manifest, objective, commit, and tree.  These values are
# protected plan authority, not caller-provided defaults.
if [ "$plan" = p02 ]; then
  [ -n "$activation_receipt" ] || die 'p02 activation requires a protected p01 receipt'
  case "$activation_receipt" in "$authority"/*) ;; *) die 'activation receipt must be inside authority' ;; esac
  [ -f "$activation_receipt" ] && [ ! -L "$activation_receipt" ] || die 'missing protected p01 receipt'
  if stat -f '%Lp' "$activation_receipt" >/dev/null 2>&1; then activation_receipt_mode=$(stat -f '%Lp' "$activation_receipt"); else activation_receipt_mode=$(stat -c '%a' "$activation_receipt" 2>/dev/null) || die 'cannot inspect activation receipt permissions'; fi
  [ "$activation_receipt_mode" = 600 ] || die 'activation receipt is not protected'

  p01_revision_manifest_sha256='' p01_objective_sha256='' p01_commit='' p01_tree='' activation_receipt_keys=''
  while IFS='=' read -r key value || [ -n "${key:-}" ]; do
    case "$key" in p01_revision_manifest_sha256|p01_objective_sha256|p01_commit|p01_tree) ;; *) die 'invalid protected p01 receipt field' ;; esac
    case "|$activation_receipt_keys|" in *"|$key|"*) die 'duplicate protected p01 receipt field' ;; esac
    activation_receipt_keys="${activation_receipt_keys:+$activation_receipt_keys|}$key"
    case "$key" in
      p01_revision_manifest_sha256) p01_revision_manifest_sha256=$value ;;
      p01_objective_sha256) p01_objective_sha256=$value ;;
      p01_commit) p01_commit=$value ;;
      p01_tree) p01_tree=$value ;;
    esac
  done < "$activation_receipt"
  [ "$p01_revision_manifest_sha256" = 29d89429a80256000051d808dde8051b29400c75dee878677b2d3f0940c2e228 ] || die 'protected p01 manifest binding mismatch'
  [ "$p01_objective_sha256" = 9d92b36f759f1f5d1bf3fc621843d50e6f78cc4816bf04bcc0c910dd457fe83e ] || die 'protected p01 objective binding mismatch'
  [ "$p01_commit" = 0dbc8f4508a3a24b1eddc36ed85590cd5d853256 ] || die 'protected p01 commit binding mismatch'
  [ "$p01_tree" = 5082f46ac22677075ccbda3ae9dcaaaab730482d ] || die 'protected p01 tree binding mismatch'
fi

# This seam deliberately validates an already-selected, immutable core record.
# It is not a scheduler: the host supplies the fixture and performs any later
# dispatch after this command has returned.
if [ -n "$core_fixture" ] || [ "$resume" = true ]; then
  [ -n "$core_fixture" ] && [ -n "$activation_record" ] && [ -n "$approval_record" ] && [ -n "$preflight_record" ] && [ "$resume" = true ] || die 'core fixture requires approval, preflight, activation records, and --resume'
  [ "$status" = false ] && [ "$reopen" = false ] && [ "$approval_revoked" = false ] || die 'core fixture options are incompatible with lifecycle options'
  [ -f "$core_fixture" ] && [ ! -L "$core_fixture" ] || die 'core fixture must be a regular file'
  case "$activation_record" in "$authority"/*) ;; *) die 'activation record must be inside authority' ;; esac
  [ -f "$activation_record" ] && [ ! -L "$activation_record" ] || die 'activation record must be a regular file'
  if stat -f '%Lp' "$activation_record" >/dev/null 2>&1; then activation_mode=$(stat -f '%Lp' "$activation_record"); else activation_mode=$(stat -c '%a' "$activation_record" 2>/dev/null) || die 'cannot inspect activation record permissions'; fi
  [ "$activation_mode" = 600 ] || die 'activation record is not protected'

  core_identity='' core_plan='' core_run='' core_generation='' core_objective_digest='' core_plan_digest=''
  core_order='' core_states='' core_dependencies='' core_ready='' core_cursor='' core_predecessor=''
  core_checkpoint='' core_successor='' core_parallel='' core_untrusted='' core_parent='' core_result=''
  core_current='' core_role='' core_reason='' core_completed='' core_top='' core_verifier='' core_reviewer='' core_activation_generation='' core_activation_objective='' core_activation_plan='' core_activation_order='' core_verifier_handoff=''
  core_keys=''
  while IFS='=' read -r key value || [ -n "${key:-}" ]; do
    case "$key" in
      identity) target=core_identity ;; plan) target=core_plan ;; run) target=core_run ;;
      generation) target=core_generation ;; objective_digest) target=core_objective_digest ;; plan_digest) target=core_plan_digest ;;
      execution_order) target=core_order ;; node_states) target=core_states ;; dependencies) target=core_dependencies ;;
      ready_frontier) target=core_ready ;; role_cursor) target=core_cursor ;; accepted_predecessor) target=core_predecessor ;;
      checkpoint) target=core_checkpoint ;; requested_successor) target=core_successor ;; parallel_dispatch) target=core_parallel ;;
      untrusted_report) target=core_untrusted ;; parent_state) target=core_parent ;; result) target=core_result ;;
      current_or_next) target=core_current ;; role) target=core_role ;; reason) target=core_reason ;;
      completed_slices) target=core_completed ;; top_level_acceptance) target=core_top ;; verifier) target=core_verifier ;; reviewer) target=core_reviewer ;;
      activation_generation) target=core_activation_generation ;; activation_objective_digest) target=core_activation_objective ;; activation_plan_digest) target=core_activation_plan ;; activation_execution_order) target=core_activation_order ;;
      verifier_handoff) target=core_verifier_handoff ;;
      ''|'#'*) continue ;;
      *) die 'invalid core fixture field' ;;
    esac
    case "|$core_keys|" in *"|$key|"*) die 'duplicate core fixture field' ;; esac
    core_keys="${core_keys:+$core_keys|}$key"
    case "$target" in
      core_identity) core_identity=$value ;; core_plan) core_plan=$value ;; core_run) core_run=$value ;;
      core_generation) core_generation=$value ;; core_objective_digest) core_objective_digest=$value ;; core_plan_digest) core_plan_digest=$value ;;
      core_order) core_order=$value ;; core_states) core_states=$value ;; core_dependencies) core_dependencies=$value ;;
      core_ready) core_ready=$value ;; core_cursor) core_cursor=$value ;; core_predecessor) core_predecessor=$value ;;
      core_checkpoint) core_checkpoint=$value ;; core_successor) core_successor=$value ;; core_parallel) core_parallel=$value ;;
      core_untrusted) core_untrusted=$value ;; core_parent) core_parent=$value ;; core_result) core_result=$value ;;
      core_current) core_current=$value ;; core_role) core_role=$value ;; core_reason) core_reason=$value ;;
      core_completed) core_completed=$value ;; core_top) core_top=$value ;; core_verifier) core_verifier=$value ;; core_reviewer) core_reviewer=$value ;;
      core_activation_generation) core_activation_generation=$value ;; core_activation_objective) core_activation_objective=$value ;; core_activation_plan) core_activation_plan=$value ;; core_activation_order) core_activation_order=$value ;;
      core_verifier_handoff) core_verifier_handoff=$value ;;
    esac
  done < "$core_fixture"
  [ "$core_identity" = "$identity" ] && [ "$core_plan" = "$plan" ] && [ "$core_run" = "$run" ] || die 'core fixture binding mismatch'
  case "$core_generation" in *[!0-9]*|'') die 'invalid core generation' ;; esac
  case "$core_objective_digest" in sha256:?*) ;; *) die 'invalid core objective digest' ;; esac
  case "$core_plan_digest" in sha256:?*) ;; *) die 'invalid core plan digest' ;; esac
  [ -n "$core_order" ] && [ -n "$core_states" ] && [ -n "$core_parent" ] && [ -n "$core_result" ] || die 'incomplete core fixture'
  case "$core_parent" in in_progress|blocked|done|cancelled) ;; *) die 'invalid core parent state' ;; esac

  activation_identity='' activation_plan='' activation_run='' activation_generation='' activation_objective='' activation_plan_digest='' activation_order='' activation_keys=''
  while IFS='=' read -r key value || [ -n "${key:-}" ]; do
    case "$key" in
      identity|plan|run|generation|objective_digest|plan_digest|execution_order) ;;
      *) die 'invalid activation record field' ;;
    esac
    case "|$activation_keys|" in *"|$key|"*) die 'duplicate activation record field' ;; esac
    activation_keys="${activation_keys:+$activation_keys|}$key"
    case "$key" in
      identity) activation_identity=$value ;; plan) activation_plan=$value ;; run) activation_run=$value ;;
      generation) activation_generation=$value ;; objective_digest) activation_objective=$value ;; plan_digest) activation_plan_digest=$value ;; execution_order) activation_order=$value ;;
    esac
  done < "$activation_record"
  [ "$activation_identity" = "$identity" ] && [ "$activation_plan" = "$plan" ] && [ "$activation_run" = "$run" ] || die 'activation record binding mismatch'
  [ -n "$activation_generation" ] && [ -n "$activation_objective" ] && [ -n "$activation_plan_digest" ] && [ -n "$activation_order" ] || die 'incomplete activation record'

  contains_node() { case ",$1," in *,"$2",*) return 0 ;; *) return 1 ;; esac; }
  order_nodes=''
  old_ifs=$IFS; IFS=','; set -- $core_order; IFS=$old_ifs
  for node in "$@"; do
    case "$node" in *[!A-Za-z0-9._-]*|'') die 'invalid execution order node' ;; esac
    contains_node "$order_nodes" "$node" && { printf 'result=reject\nreason=execution-order-duplicate-node\n'; exit 1; }
    order_nodes="${order_nodes:+$order_nodes,}$node"
  done
  state_nodes=''
  old_ifs=$IFS; IFS=','; set -- $core_states; IFS=$old_ifs
  for pair in "$@"; do
    node=${pair%%:*}; node_state=${pair#*:}
    [ "$node" != "$pair" ] || die 'invalid node state'
    case "$node" in *[!A-Za-z0-9._-]*|'') die 'invalid node state node' ;; esac
    case "$node_state" in pending|implementing|reviewing|done|blocked|cancelled) ;; *) die 'invalid node state' ;; esac
    contains_node "$state_nodes" "$node" && die 'duplicate node state'
    state_nodes="${state_nodes:+$state_nodes,}$node"
  done
  old_ifs=$IFS; IFS=','; set -- $state_nodes; IFS=$old_ifs
  for node in "$@"; do contains_node "$order_nodes" "$node" || { printf 'result=reject\nreason=execution-order-missing-node\n'; exit 1; }; done
  old_ifs=$IFS; IFS=','; set -- $order_nodes; IFS=$old_ifs
  for node in "$@"; do contains_node "$state_nodes" "$node" || { printf 'result=reject\nreason=execution-order-unknown-node\n'; exit 1; }; done

  reject_core() { [ "$core_result" = reject ] && [ "$core_reason" = "$1" ] || die 'invalid rejected core fixture'; printf 'result=reject\nreason=%s\n' "$1"; exit 1; }
  [ "$core_generation" = "$activation_generation" ] || reject_core activation-generation-drift
  [ "$core_objective_digest" = "$activation_objective" ] || reject_core activation-objective-digest-drift
  [ "$core_plan_digest" = "$activation_plan_digest" ] || reject_core activation-plan-digest-drift
  [ "$core_order" = "$activation_order" ] || reject_core activation-execution-order-drift
  validate_protected_record "$approval_record" 'approval record' 'objective_digest|plan_digest|approver|approved_at|revoked'
  [ "$record_objective_digest" = "$core_objective_digest" ] || die 'approval objective digest drift'
  [ "$record_plan_digest" = "$core_plan_digest" ] || die 'approval plan digest drift'
  [ -n "$record_approver" ] && [ -n "$record_approved_at" ] || die 'incomplete protected approval record'
  [ "$record_revoked" = false ] || die 'approval is revoked'
  validate_protected_record "$preflight_record" 'preflight record' 'objective_digest|plan_digest|surface_digest|baseline'
  [ "$record_objective_digest" = "$core_objective_digest" ] || die 'preflight objective digest drift'
  [ "$record_plan_digest" = "$core_plan_digest" ] || die 'preflight plan digest drift'
  case "$record_surface_digest" in
    sha256:????????????????????????????????????????????????????????????????)
      case "${record_surface_digest#sha256:}" in *[!0-9A-Fa-f]*) die 'invalid preflight surface digest' ;; esac ;;
    *) die 'invalid preflight surface digest' ;;
  esac
  [ "$record_baseline" = green ] || die 'preflight baseline is not green'
  [ -z "$core_parallel" ] || reject_core parallel-dispatch-not-permitted
  if [ -n "$core_successor" ]; then contains_node "$order_nodes" "$core_successor" || reject_core unknown-successor; fi
  [ -z "$core_untrusted" ] || reject_core untrusted-report-not-authority
  case "$core_predecessor" in *-old*|*:tree-old:*|*:evidence-old*) reject_core stale-predecessor ;; esac
  if [ "$core_result" = reject ] && [ -z "$core_predecessor" ] && [ -n "$core_dependencies" ]; then
    old_ifs=$IFS; IFS=','; set -- $core_dependencies; IFS=$old_ifs
    for pair in "$@"; do
      [ -n "${pair#*:}" ] && reject_core missing-predecessor
    done
  fi
  if [ "$core_result" = reject ] && [ -n "$core_predecessor" ] && [ -n "$core_dependencies" ]; then
    predecessor_node=${core_predecessor%%:*}; dependency_match=false
    old_ifs=$IFS; IFS=','; set -- $core_dependencies; IFS=$old_ifs
    for pair in "$@"; do contains_node "${pair#*:}" "$predecessor_node" && dependency_match=true; done
    [ "$dependency_match" = true ] || reject_core nondependency-predecessor
  fi
  if [ "$core_result" = reject ] && [ -n "$core_checkpoint" ]; then
    checkpoint_node=${core_checkpoint%%:*}; checkpoint_generation=${core_checkpoint#*:}
    [ "$checkpoint_node" != "$core_checkpoint" ] && [ "$checkpoint_generation" = "generation-$core_generation" ] || reject_core successor-checkpoint-mismatch
  fi
  if [ "$core_parent" = done ]; then
    old_ifs=$IFS; IFS=','; set -- $core_states; IFS=$old_ifs
    for pair in "$@"; do [ "${pair#*:}" = done ] || reject_core parent-complete-before-sixth-slice; done
    [ "$core_top" = current ] || reject_core parent-missing-top-level-acceptance
    [ "$core_verifier" = current ] || reject_core parent-missing-verifier
    [ "$core_reviewer" = current ] || reject_core parent-missing-reviewer
  fi
  cursor_node=''; cursor_role=''; cursor_state=''; cursor_previous=''; previous_node=''
  if [ -n "$core_cursor" ]; then
    cursor_node=${core_cursor%%:*}; cursor_role=${core_cursor#*:}
    [ "$cursor_node" != "$core_cursor" ] && contains_node "$order_nodes" "$cursor_node" || die 'invalid role cursor'
    case "$cursor_role" in writing-goals-maker|writing-goals-verifier|writing-goals-reviewer) ;; *) die 'invalid role cursor' ;; esac
    if [ "$core_result" = resume ]; then
      [ "$core_current" = "$cursor_node" ] && [ "$core_role" = "$cursor_role" ] || die 'core cursor mismatch'
    fi
  fi
  [ -n "$cursor_node" ] || reject_core role-cursor-missing
  old_ifs=$IFS; IFS=','; set -- $core_order; IFS=$old_ifs
  for node in "$@"; do
    if [ "$node" = "$cursor_node" ]; then cursor_previous=$previous_node; break; fi
    previous_node=$node
  done
  old_ifs=$IFS; IFS=','; set -- $core_states; IFS=$old_ifs
  for pair in "$@"; do [ "${pair%%:*}" = "$cursor_node" ] && cursor_state=${pair#*:}; done
  case "$cursor_state:$cursor_role" in
    implementing:writing-goals-maker|pending:writing-goals-maker|reviewing:writing-goals-verifier|reviewing:writing-goals-reviewer) ;;
    *) die 'role cursor does not match node state' ;;
  esac
  if [ -n "$core_dependencies" ]; then
    cursor_dependencies='' cursor_dependency_declared=false
    old_ifs=$IFS; IFS=','; set -- $core_dependencies; IFS=$old_ifs
    for pair in "$@"; do
      dependency_node=${pair%%:*}; dependency_list=${pair#*:}
      [ "$dependency_node" != "$pair" ] || die 'invalid dependency declaration'
      if [ "$dependency_node" = "$cursor_node" ]; then cursor_dependencies=$dependency_list; cursor_dependency_declared=true; fi
    done
    [ "$cursor_dependency_declared" = true ] || die 'missing dependency declaration'
    if [ -n "$cursor_dependencies" ]; then
      [ -n "$core_predecessor" ] || reject_core missing-predecessor
      predecessor_node=${core_predecessor%%:*}
      contains_node "$cursor_dependencies" "$predecessor_node" || reject_core nondependency-predecessor
      old_ifs=$IFS; IFS=','; set -- $core_states; IFS=$old_ifs
      predecessor_state=''
      for pair in "$@"; do [ "${pair%%:*}" = "$predecessor_node" ] && predecessor_state=${pair#*:}; done
      [ "$predecessor_state" = done ] || reject_core stale-predecessor
    fi
  elif [ -n "$core_predecessor" ]; then
    [ -n "$cursor_previous" ] && case "$core_predecessor" in "$cursor_previous":?*:?*:?*) ;; *) die 'invalid accepted predecessor' ;; esac
  fi
  if [ -n "$core_checkpoint" ]; then
    checkpoint_node=${core_checkpoint%%:*}; checkpoint_generation=${core_checkpoint#*:}
    [ "$checkpoint_node" != "$core_checkpoint" ] && [ "$checkpoint_generation" = "generation-$core_generation" ] || reject_core successor-checkpoint-mismatch
    contains_node "$state_nodes" "$checkpoint_node" || die 'checkpoint node is unknown'
    [ -z "$core_successor" ] || [ "$core_successor" = "$cursor_node" ] || reject_core successor-checkpoint-mismatch
    [ -z "$core_predecessor" ] || [ "$checkpoint_node" = "${core_predecessor%%:*}" ] || reject_core successor-checkpoint-mismatch
  fi
  if [ "$cursor_role" = writing-goals-reviewer ] && [ "$core_verifier_handoff" != current ] && [ "$core_verifier" != current ]; then reject_core reviewer-without-verifier-handoff; fi
  if [ -n "$core_ready" ]; then
    selected=''
    old_ifs=$IFS; IFS=','; set -- $order_nodes; IFS=$old_ifs
    for node in "$@"; do if contains_node "$core_ready" "$node"; then selected=$node; break; fi; done
    [ "$selected" = "$cursor_node" ] || die 'core ready-frontier selection mismatch'
  fi
  [ "$core_result" = resume ] || die 'unsupported core result'
  printf 'result=resume\nparent_state=%s\ncurrent_or_next=%s\nrole=%s\nexecution_order=%s\n' "$core_parent" "$cursor_node" "$cursor_role" "$core_order"
  [ -z "$core_completed" ] || printf 'completed_slices=%s\n' "$core_completed"
  [ -z "$core_reason" ] || printf 'reason=%s\n' "$core_reason"
  exit 0
fi

record="$authority/run-state.env"
if [ "$reopen" = true ]; then
  [ "$approval_revoked" = true ] || die 'reopen requires revoked approval'
  [ ! -e "$record" ] && [ ! -L "$record" ] && [ ! -e "$authority/bootstrap.env" ] && [ ! -L "$authority/bootstrap.env" ] || die 'bound authority cannot be reopened in place'
  exit 0
fi
[ "$status" = true ] || die 'only --status is supported'
[ "$plan" != p02 ] || [ -e "$record" ] || { printf 'activation_receipt=p01-bound\n'; exit 0; }
[ -f "$record" ] && [ ! -L "$record" ] || die 'missing protected record'

found_identity='' found_plan='' found_run='' found_generation='' found_digest='' found_state='' found_candidate=''
while IFS='=' read -r key value || [ -n "${key:-}" ]; do
  case "$key" in
    identity) found_identity=$value ;; plan) found_plan=$value ;; run) found_run=$value ;;
    generation) found_generation=$value ;; digest) found_digest=$value ;; state) found_state=$value ;;
    candidate) found_candidate=$value ;; *) die 'invalid protected record field' ;;
  esac
done < "$record"
[ "$found_identity" = "$identity" ] && [ "$found_plan" = "$plan" ] && [ "$found_run" = "$run" ] || die 'protected record binding mismatch'
case "$found_generation" in *[!0-9]*|'') die 'invalid protected generation' ;; esac
case "$found_digest" in sha256:*) ;; *) die 'invalid protected digest' ;; esac
case "$found_state" in pending|implementing|reviewing|blocked|done|cancelled) ;; *) die 'invalid protected state' ;; esac
[ -n "$found_candidate" ] || die 'invalid protected candidate'
cat "$record"
