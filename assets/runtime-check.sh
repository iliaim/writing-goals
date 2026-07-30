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
authority='' identity='' plan='' run='' status=false reopen=false approval_revoked=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --authority|--identity|--plan|--run)
      [ "$#" -ge 2 ] || die "missing value for $1"
      case "$1" in --authority) authority=$2 ;; --identity) identity=$2 ;; --plan) plan=$2 ;; --run) run=$2 ;; esac
      shift 2 ;;
    --status) status=true; shift ;;
    --reopen) reopen=true; shift ;;
    --approval-revoked) approval_revoked=true; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$authority" ] && [ -n "$identity" ] && [ -n "$plan" ] && [ -n "$run" ] || die 'authority, identity, plan, and run are required'
validate_authority_path "$authority"
case "$identity" in *[!A-Za-z0-9-]*|'') die 'invalid identity' ;; esac
case "$plan" in p[0-9][0-9]) ;; *) die 'invalid plan' ;; esac
case "$run" in *[!A-Za-z0-9._-]*|'') die 'invalid run' ;; esac
if stat -f '%Lp' "$authority" >/dev/null 2>&1; then mode=$(stat -f '%Lp' "$authority"); else mode=$(stat -c '%a' "$authority" 2>/dev/null) || die 'cannot inspect authority permissions'; fi
case "$mode" in ???) ;; *) die 'cannot inspect authority permissions' ;; esac
case "${mode#?}" in *[1-7]*) die 'authority is not protected' ;; esac

record="$authority/run-state.env"
if [ "$reopen" = true ]; then
  [ "$approval_revoked" = true ] || die 'reopen requires revoked approval'
  [ ! -e "$record" ] && [ ! -L "$record" ] && [ ! -e "$authority/bootstrap.env" ] && [ ! -L "$authority/bootstrap.env" ] || die 'bound authority cannot be reopened in place'
  exit 0
fi
[ "$status" = true ] || die 'only --status is supported'
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
