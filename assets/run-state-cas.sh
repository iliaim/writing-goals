#!/usr/bin/env bash
# Write one lifecycle record in a separately protected authority directory.
set -u

die() { printf '%s\n' "run-state-cas: $*" >&2; exit 1; }

# Reject lexical traversal and every symlink below root.  The authority is a
# security boundary, so accepting a symlinked ancestor is not equivalent to
# accepting its resolved directory.
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
    # macOS exposes /var as a system compatibility alias for /private/var.
    # It is the platform temp-root used by this portable contract suite, not a
    # caller-controlled authority indirection. All other ancestor links fail.
    if [ -L "$authority_walk" ] && ! { [ "$authority_walk" = /var ] && [ "$(readlink /var 2>/dev/null)" = private/var ]; }; then
      die 'authority symlink is not allowed'
    fi
  done
  [ -d "$authority_input" ] && [ ! -L "$authority_input" ] || die 'authority must be a real directory'
}

sha256_text() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  fi
}

receipt_value() {
  receipt_file=$1 receipt_key=$2
  [ "$(grep -c "^${receipt_key}=" "$receipt_file")" -eq 1 ] || return 1
  sed -n "s/^${receipt_key}=//p" "$receipt_file"
}

validate_receipt_artifact() {
  receipt_kind=$1 receipt_locator=$2 receipt_actor=$3
  receipt_file="$authority/receipts/${receipt_kind}.env"
  [ -f "$receipt_file" ] && [ ! -L "$receipt_file" ] || die "missing protected ${receipt_kind} receipt"
  receipt_id=$(receipt_value "$receipt_file" receipt) || die "invalid ${receipt_kind} receipt"
  receipt_identity=$(receipt_value "$receipt_file" identity) || die "invalid ${receipt_kind} receipt"
  receipt_plan=$(receipt_value "$receipt_file" plan) || die "invalid ${receipt_kind} receipt"
  receipt_candidate=$(receipt_value "$receipt_file" candidate) || die "invalid ${receipt_kind} receipt"
  receipt_artifact_actor=$(receipt_value "$receipt_file" actor) || die "invalid ${receipt_kind} receipt"
  receipt_result=$(receipt_value "$receipt_file" result) || die "invalid ${receipt_kind} receipt"
  receipt_binding=$(receipt_value "$receipt_file" binding_sha256) || die "invalid ${receipt_kind} receipt"
  [ "$receipt_id" = "$receipt_locator" ] && [ "$receipt_identity" = "$identity" ] && [ "$receipt_plan" = "$plan" ] && [ "$receipt_candidate" = "$candidate" ] && [ "$receipt_artifact_actor" = "$receipt_actor" ] && [ "$receipt_result" = success ] || die "receipt binding mismatch"
  case "$receipt_binding" in *[!0-9a-f]*|????????????????????????????????????????????????????????????????) ;; *) die "invalid ${receipt_kind} receipt binding" ;; esac
  expected_binding=$(sha256_text "${receipt_id}|${receipt_identity}|${receipt_plan}|${receipt_candidate}|${receipt_artifact_actor}|${receipt_result}")
  [ "$receipt_binding" = "$expected_binding" ] || die "receipt binding digest mismatch"
}

authority='' identity='' plan='' run='' expected_generation='' expected_digest=''
next_state='' candidate='' check_receipt='' verifier_receipt='' reviewer_receipt=''
abandonment_authority=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --authority|--identity|--plan|--run|--expected-generation|--expected-digest|--next-state|--candidate|--check-receipt|--verifier-receipt|--reviewer-receipt|--abandonment-authority)
      [ "$#" -ge 2 ] || die "missing value for $1"
      case "$1" in
        --authority) authority=$2 ;; --identity) identity=$2 ;; --plan) plan=$2 ;;
        --run) run=$2 ;; --expected-generation) expected_generation=$2 ;;
        --expected-digest) expected_digest=$2 ;; --next-state) next_state=$2 ;;
        --candidate) candidate=$2 ;; --check-receipt) check_receipt=$2 ;;
        --verifier-receipt) verifier_receipt=$2 ;; --reviewer-receipt) reviewer_receipt=$2 ;;
        --abandonment-authority) abandonment_authority=$2 ;;
      esac
      shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$authority" ] && [ -n "$identity" ] && [ -n "$plan" ] && [ -n "$run" ] || die 'authority, identity, plan, and run are required'
[ -n "$expected_generation" ] && [ -n "$expected_digest" ] && [ -n "$next_state" ] && [ -n "$candidate" ] || die 'CAS preimage, next state, and candidate are required'
validate_authority_path "$authority"
case "$identity" in *[!A-Za-z0-9-]*|'') die 'invalid identity' ;; esac
case "$plan" in p[0-9][0-9]) ;; *) die 'invalid plan' ;; esac
case "$run" in *[!A-Za-z0-9._-]*|'') die 'invalid run' ;; esac
case "$candidate" in *[!A-Za-z0-9._-]*|'') die 'invalid candidate' ;; esac
case "$expected_generation" in *[!0-9]*|'') die 'invalid expected generation' ;; esac
case "$expected_digest" in sha256:*) ;; *) die 'invalid expected digest' ;; esac
case "$next_state" in pending|implementing|reviewing|blocked|done|cancelled) ;; *) die 'invalid lifecycle state' ;; esac

if stat -f '%Lp' "$authority" >/dev/null 2>&1; then mode=$(stat -f '%Lp' "$authority"); else mode=$(stat -c '%a' "$authority" 2>/dev/null) || die 'cannot inspect authority permissions'; fi
case "$mode" in ???) ;; *) die 'cannot inspect authority permissions' ;; esac
case "${mode#?}" in *[1-7]*) die 'authority is not protected' ;; esac

record="$authority/run-state.env"
bootstrap="$authority/bootstrap.env"
lock="$authority/.run-${run}.lock"
if ! mkdir "$lock" 2>/dev/null; then die 'run is busy'; fi
cleanup() { rmdir "$lock" 2>/dev/null || true; }
interrupted=false
interrupt() {
  interrupted=true
  : > "$authority/.run-${run}.interrupted" 2>/dev/null || true
  exit 1
}
trap cleanup EXIT
trap interrupt HUP INT TERM

# Test-only deterministic seam: a signal after the lock is acquired creates a
# durable interruption marker, so a stale preimage cannot become publishable.
if [ -n "${WG_TEST_HOLD_AFTER_LOCK_FILE:-}" ] && [ -n "${WG_TEST_RELEASE_LOCK_FILE:-}" ]; then
  : > "$WG_TEST_HOLD_AFTER_LOCK_FILE" || die 'cannot create lock hold marker'
  hold_ticks=0
  while [ ! -e "$WG_TEST_RELEASE_LOCK_FILE" ] && [ "$hold_ticks" -lt 20 ]; do
    sleep 0.05
    hold_ticks=$((hold_ticks + 1))
  done
  # Non-interactive background shells can inherit ignored SIGINT.  The bounded
  # hold therefore also fails closed if no explicit release arrives, preserving
  # the same stale-writer guarantee on every supported shell.
  [ -e "$WG_TEST_RELEASE_LOCK_FILE" ] || interrupt
fi
[ ! -e "$authority/.run-${run}.interrupted" ] || die 'run was interrupted after lock acquisition'

if [ -e "$record" ] || [ -L "$record" ]; then
  [ -f "$record" ] && [ ! -L "$record" ] || die 'invalid protected record'
  source_file="$record"
else
  [ -f "$bootstrap" ] && [ ! -L "$bootstrap" ] || die 'missing protected bootstrap record'
  source_file="$bootstrap"
fi

old_identity='' old_plan='' old_run='' old_generation='' old_digest='' old_state='' old_candidate=''
while IFS='=' read -r key value || [ -n "${key:-}" ]; do
  case "$key" in
    identity) old_identity=$value ;; plan) old_plan=$value ;; run) old_run=$value ;;
    generation) old_generation=$value ;; digest) old_digest=$value ;; state) old_state=$value ;;
    candidate) old_candidate=$value ;; ''|'#'*) ;; *) die 'invalid protected record field' ;;
  esac
done < "$source_file"
[ "$old_identity" = "$identity" ] && [ "$old_plan" = "$plan" ] || die 'protected record binding mismatch'
[ "$old_generation" = "$expected_generation" ] && [ "$old_digest" = "$expected_digest" ] || die 'stale CAS preimage'
case "$old_generation" in *[!0-9]*|'') die 'invalid protected generation' ;; esac
case "$old_state" in pending|implementing|reviewing|blocked|done|cancelled) ;; *) die 'invalid protected state' ;; esac
if [ "$source_file" = "$record" ]; then [ "$old_run" = "$run" ] || die 'another run is already active'; else [ "$old_run" = "$run" ] || die 'bootstrap run mismatch'; fi

write_state=$next_state
valid_transition=false
case "$old_state:$next_state" in
  pending:pending|pending:implementing|pending:blocked|pending:cancelled|implementing:reviewing|implementing:blocked|implementing:cancelled|reviewing:blocked|reviewing:done|reviewing:cancelled) valid_transition=true ;;
  reviewing:implementing)
    failed="reviewer:${identity}:${plan}:${old_candidate}:failed"
    if [ "$reviewer_receipt" = "$failed" ]; then
      if [ "$candidate" = "$old_candidate" ]; then write_state=blocked; else valid_transition=true; fi
    fi ;;
esac
[ "$valid_transition" = true ] || [ "$write_state" = blocked ] || die "illegal transition: $old_state to $next_state"
if [ "$next_state" = done ]; then
  [ "$check_receipt" = "check:${identity}:${plan}:${candidate}:success" ] || die 'done requires current successful check receipt'
  [ "$verifier_receipt" = "verifier:${identity}:${plan}:${candidate}:success" ] || die 'done requires current successful verifier receipt'
  [ "$reviewer_receipt" = "reviewer:${identity}:${plan}:${candidate}:success" ] || die 'done requires current successful reviewer receipt'
  [ -d "$authority/receipts" ] && [ ! -L "$authority/receipts" ] || die 'missing protected receipt directory'
  validate_receipt_artifact check "$check_receipt" writing-goals-maker
  validate_receipt_artifact verifier "$verifier_receipt" writing-goals-verifier
  validate_receipt_artifact reviewer "$reviewer_receipt" writing-goals-reviewer
fi
if [ "$next_state" = cancelled ]; then [ -n "$abandonment_authority" ] || die 'cancelled requires abandonment authority'; fi

new_generation=$((old_generation + 1))
payload="${identity}|${plan}|${run}|${new_generation}|${write_state}|${candidate}|${check_receipt}|${verifier_receipt}|${reviewer_receipt}|${abandonment_authority}"
hash=$(sha256_text "$payload")
new_digest="sha256:${hash}"
tmp="$authority/.run-state.${run}.$$"
umask 077
{ printf 'identity=%s\nplan=%s\nrun=%s\ngeneration=%s\ndigest=%s\nstate=%s\ncandidate=%s\n' "$identity" "$plan" "$run" "$new_generation" "$new_digest" "$write_state" "$candidate"; } > "$tmp" || die 'cannot write protected record'
chmod 600 "$tmp" || die 'cannot protect record'
mv -f "$tmp" "$record" || die 'cannot atomically replace protected record'
cat "$record"
[ "$write_state" = blocked ] && [ "$next_state" = implementing ] && exit 1
exit 0
