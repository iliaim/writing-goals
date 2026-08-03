#!/usr/bin/env bash
# Foreground, single-flight Codex continuation supervisor for a protected run.
# It deliberately has no daemon, cron, --last, shell-command, or fixture input.
set -u
set -o pipefail

die() { printf '%s\n' "codex-continuation: $*" >&2; exit 1; }

mode_of() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then stat -f '%Lp' "$1"; else stat -c '%a' "$1" 2>/dev/null; fi
}

validate_authority() {
  case "$1" in /*) ;; *) die 'authority must be an absolute path' ;; esac
  case "/$1/" in *'/../'*|*'/./'*) die 'authority traversal is not allowed' ;; esac
  [ -d "$1" ] && [ ! -L "$1" ] || die 'authority must be a real directory'
  mode=$(mode_of "$1") || die 'cannot inspect authority permissions'
  case "$mode" in ???) ;; *) die 'cannot inspect authority permissions' ;; esac
  case "${mode#?}" in *[1-7]*) die 'authority is not protected' ;; esac
}

require_protected_file() {
  file=$1 label=$2
  case "$file" in "$authority"/*) ;; *) die "$label must be inside authority" ;; esac
  [ -f "$file" ] && [ ! -L "$file" ] || die "$label must be a protected regular file"
  [ "$(mode_of "$file")" = 600 ] || die "$label must be mode 0600"
}

sha_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi
}

valid_hex() { [ "${#1}" = 64 ] && case "$1" in *[!0-9A-Fa-f]*) return 1 ;; *) return 0 ;; esac; }

authority='' identity='' plan='' run=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --authority|--identity|--plan|--run)
      [ "$#" -ge 2 ] || die "missing value for $1"
      case "$1" in --authority) authority=$2 ;; --identity) identity=$2 ;; --plan) plan=$2 ;; --run) run=$2 ;; esac
      shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$authority" ] && [ -n "$identity" ] && [ -n "$plan" ] && [ -n "$run" ] || die 'authority, identity, plan, and run are required'
case "$identity" in *[!A-Za-z0-9-]*|'') die 'invalid identity' ;; esac
case "$plan" in p[0-9][0-9]) ;; *) die 'invalid plan' ;; esac
case "$run" in *[!A-Za-z0-9._-]*|'') die 'invalid run' ;; esac
validate_authority "$authority"

config="$authority/continuation.env"
require_protected_file "$config" 'continuation configuration'
cfg_identity='' cfg_plan='' cfg_run='' session_id='' workspace='' codex_bin='' sandbox_profile='' trusted_root='' controller_sha256='' runtime_path='' runtime_sha256='' advance_path='' advance_sha256='' no_progress_cap=''
config_keys=''
while IFS='=' read -r key value || [ -n "${key:-}" ]; do
  case "$key" in identity|plan|run|session_id|workspace|codex_bin|sandbox_profile|trusted_root|controller_sha256|runtime_path|runtime_sha256|advance_path|advance_sha256|no_progress_cap) ;; *) die 'invalid continuation configuration field' ;; esac
  case "|$config_keys|" in *"|$key|"*) die 'duplicate continuation configuration field' ;; esac
  config_keys="${config_keys:+$config_keys|}$key"
  case "$key" in
    identity) cfg_identity=$value ;; plan) cfg_plan=$value ;; run) cfg_run=$value ;; session_id) session_id=$value ;;
    workspace) workspace=$value ;; codex_bin) codex_bin=$value ;; sandbox_profile) sandbox_profile=$value ;;
    trusted_root) trusted_root=$value ;; controller_sha256) controller_sha256=$value ;;
    runtime_path) runtime_path=$value ;; runtime_sha256) runtime_sha256=$value ;; advance_path) advance_path=$value ;; advance_sha256) advance_sha256=$value ;; no_progress_cap) no_progress_cap=$value ;;
  esac
done < "$config"
for key in identity plan run session_id workspace codex_bin sandbox_profile trusted_root controller_sha256 runtime_path runtime_sha256 advance_path advance_sha256 no_progress_cap; do
  case "|$config_keys|" in *"|$key|"*) ;; *) die 'incomplete continuation configuration' ;; esac
done
[ "$cfg_identity" = "$identity" ] && [ "$cfg_plan" = "$plan" ] && [ "$cfg_run" = "$run" ] || die 'continuation configuration binding mismatch'
case "$session_id" in ????????-????-????-????-????????????) ;; *) die 'session id must be an exact UUID' ;; esac
case "$workspace" in /*) ;; *) die 'workspace must be absolute' ;; esac
[ -d "$workspace" ] && [ ! -L "$workspace" ] || die 'workspace must be a real directory'
case "$codex_bin" in /*) ;; *) die 'codex binary must be absolute' ;; esac
[ -x "$codex_bin" ] && [ ! -L "$codex_bin" ] || die 'codex binary must be a real executable'
require_protected_file "$sandbox_profile" 'sandbox profile'
case "$trusted_root" in /*) ;; *) die 'trusted tool root must be absolute' ;; esac
[ -d "$trusted_root" ] && [ ! -L "$trusted_root" ] || die 'trusted tool root must be a real directory'
case "$0" in "$trusted_root"/*) ;; *) die 'controller must run from the trusted tool root' ;; esac
[ -f "$0" ] && [ ! -L "$0" ] || die 'controller must be a regular trusted file'
valid_hex "$controller_sha256" || die 'invalid controller SHA-256'
case "$runtime_path" in /*) ;; *) die 'runtime path must be absolute' ;; esac
[ "${runtime_path#"$trusted_root"/}" != "$runtime_path" ] || die 'runtime path must be inside trusted tool root'
[ -f "$runtime_path" ] && [ ! -L "$runtime_path" ] || die 'runtime path must be a regular file'
valid_hex "$runtime_sha256" || die 'invalid runtime SHA-256'
case "$advance_path" in /*) ;; *) die 'advance path must be absolute' ;; esac
[ "${advance_path#"$trusted_root"/}" != "$advance_path" ] || die 'advance path must be inside trusted tool root'
[ -f "$advance_path" ] && [ ! -L "$advance_path" ] || die 'advance path must be a regular file'
valid_hex "$advance_sha256" || die 'invalid advance SHA-256'
case "$no_progress_cap" in ''|0|*[!0-9]*) die 'no-progress cap must be a positive integer' ;; esac
[ "${#no_progress_cap}" -le 9 ] || die 'no-progress cap is too large'
[ -x /usr/bin/sandbox-exec ] || die 'sandbox-exec is required for protected continuation'

lock="$authority/.continuation-${run}.lock"
if ! mkdir "$lock" 2>/dev/null; then die 'controller-busy'; fi
cleanup() { rmdir "$lock" 2>/dev/null || true; }
trap cleanup EXIT HUP INT TERM

receipts="$authority/continuation-receipts"
[ -d "$receipts" ] && [ ! -L "$receipts" ] || die 'missing continuation receipt directory'
receipt_mode=$(mode_of "$receipts") || die 'cannot inspect continuation receipt directory'
case "$receipt_mode" in ???) ;; *) die 'cannot inspect continuation receipt directory' ;; esac
case "${receipt_mode#?}" in *[1-7]*) die 'continuation receipt directory is not protected' ;; esac

state="$authority/continuation-state.env"
state_phase=idle state_sequence=0 state_no_progress=0 state_core=bootstrap state_transition=0 state_receipt=bootstrap
read_state() {
  [ ! -e "$state" ] && [ ! -L "$state" ] && return 0
  require_protected_file "$state" 'continuation state'
  state_keys=''; state_identity='' state_plan='' state_run=''
  while IFS='=' read -r key value || [ -n "${key:-}" ]; do
    case "$key" in identity|plan|run|phase|wake_sequence|no_progress_count|last_core_sha256|last_transition_generation|last_receipt_sha256) ;; *) die 'invalid continuation state field' ;; esac
    case "|$state_keys|" in *"|$key|"*) die 'duplicate continuation state field' ;; esac
    state_keys="${state_keys:+$state_keys|}$key"
    case "$key" in
      identity) state_identity=$value ;; plan) state_plan=$value ;; run) state_run=$value ;; phase) state_phase=$value ;;
      wake_sequence) state_sequence=$value ;; no_progress_count) state_no_progress=$value ;;
      last_core_sha256) state_core=$value ;; last_transition_generation) state_transition=$value ;; last_receipt_sha256) state_receipt=$value ;;
    esac
  done < "$state"
  for key in identity plan run phase wake_sequence no_progress_count last_core_sha256 last_transition_generation last_receipt_sha256; do
    case "|$state_keys|" in *"|$key|"*) ;; *) die 'incomplete continuation state' ;; esac
  done
  [ "$state_identity" = "$identity" ] && [ "$state_plan" = "$plan" ] && [ "$state_run" = "$run" ] || die 'continuation state binding mismatch'
  case "$state_phase" in idle|inflight|blocked|terminal) ;; *) die 'invalid continuation state phase' ;; esac
  case "$state_sequence:$state_no_progress:$state_transition" in *[!0-9:]*|::*|'') die 'invalid continuation state counter' ;; esac
  for digest in "$state_core" "$state_receipt"; do [ "$digest" = bootstrap ] || valid_hex "$digest" || die 'invalid continuation state digest'; done
}

write_state() {
  new_phase=$1 new_sequence=$2 new_no_progress=$3 new_core=$4 new_transition=$5 new_receipt=$6
  tmp="$authority/.continuation-state.${run}.$$"
  umask 077
  { printf 'identity=%s\nplan=%s\nrun=%s\nphase=%s\nwake_sequence=%s\nno_progress_count=%s\nlast_core_sha256=%s\nlast_transition_generation=%s\nlast_receipt_sha256=%s\n' "$identity" "$plan" "$run" "$new_phase" "$new_sequence" "$new_no_progress" "$new_core" "$new_transition" "$new_receipt"; } > "$tmp" || die 'cannot write continuation state'
  chmod 600 "$tmp" || die 'cannot protect continuation state'
  mv -f "$tmp" "$state" || die 'cannot atomically write continuation state'
  state_phase=$new_phase state_sequence=$new_sequence state_no_progress=$new_no_progress state_core=$new_core state_transition=$new_transition state_receipt=$new_receipt
}

write_receipt() {
  receipt_name=$1
  shift
  receipt="$receipts/$receipt_name.env"
  [ ! -e "$receipt" ] && [ ! -L "$receipt" ] || die 'continuation receipt already exists'
  tmp="$receipts/.${receipt_name}.$$"
  umask 077
  { printf 'identity=%s\nplan=%s\nrun=%s\nprevious_receipt_sha256=%s\n' "$identity" "$plan" "$run" "$state_receipt"; printf '%s\n' "$@"; } > "$tmp" || die 'cannot write continuation receipt'
  chmod 600 "$tmp" || die 'cannot protect continuation receipt'
  mv "$tmp" "$receipt" || die 'cannot append continuation receipt'
  sha_file "$receipt"
}

# Command substitution runs in a subshell, so keep receipt-chain state in this
# process rather than relying on a side effect of write_receipt.
append_receipt() {
  last_receipt_hash=$(write_receipt "$@")
  state_receipt=$last_receipt_hash
}

verify_runtime() {
  [ "$(sha_file "$0")" = "$controller_sha256" ] || die 'trusted controller digest changed'
  [ "$(sha_file "$runtime_path")" = "$runtime_sha256" ] || die 'trusted runtime digest changed'
}

read_state
[ "$state_phase" != blocked ] && [ "$state_phase" != terminal ] || die "continuation is already $state_phase"
if [ "$state_phase" = inflight ]; then
  die 'inflight continuation requires explicit human reconciliation'
fi

run_state="$authority/run-state.env"
require_protected_file "$run_state" 'protected lifecycle state'
state_result="$(bash "$runtime_path" --authority "$authority" --identity "$identity" --plan "$plan" --run "$run" --status)" || die 'cannot read protected lifecycle state'
lifecycle_state="$(printf '%s\n' "$state_result" | sed -n 's/^state=//p')"
case "$lifecycle_state" in
  done|cancelled|blocked)
    append_receipt "$(printf '%06d' "$state_sequence")-terminal" "kind=terminal" "reason=lifecycle-$lifecycle_state"
    receipt_hash=$last_receipt_hash
    write_state terminal "$state_sequence" "$state_no_progress" "$state_core" "$state_transition" "$receipt_hash"
    printf '%s\n' "result=terminal reason=lifecycle-$lifecycle_state"
    exit 0 ;;
  pending|implementing|reviewing) ;;
  *) die 'invalid protected lifecycle state' ;;
esac

while :; do
  verify_runtime
  core="$authority/core-state.env"
  require_protected_file "$core" 'protected core state'
  runtime_result="$(bash "$runtime_path" --authority "$authority" --identity "$identity" --plan "$plan" --run "$run" --approval-record "$authority/approval.env" --preflight-record "$authority/preflight.env" --activation-record "$authority/activation.env" --core-record "$core" --resume)" || {
    append_receipt "$(printf '%06d' "$state_sequence")-blocked" 'kind=blocked' 'reason=runtime-rejected'
    receipt_hash=$last_receipt_hash
    write_state blocked "$state_sequence" "$state_no_progress" "$state_core" "$state_transition" "$receipt_hash"
    die 'runtime-rejected'
  }
  cursor="$(printf '%s\n' "$runtime_result" | sed -n 's/^current_or_next=//p')"
  role="$(printf '%s\n' "$runtime_result" | sed -n 's/^role=//p')"
  [ -n "$cursor" ] && [ -n "$role" ] || die 'runtime did not return a cursor'
  core_hash="$(sha_file "$core")"
  transition="$(sed -n 's/^transition_generation=//p' "$core")"
  predecessor="$(sed -n 's/^previous_core_sha256=//p' "$core")"
  case "$transition" in *[!0-9]*|'') die 'missing core transition generation' ;; esac
  [ "$(grep -c '^previous_core_sha256=' "$core")" = 1 ] || die 'missing core predecessor digest'
  [ "$predecessor" = bootstrap ] || valid_hex "$predecessor" || die 'invalid core predecessor digest'
  # A saved state normally names this same current snapshot.  Require the
  # predecessor link only when the authority has changed since that save.
  if [ "$state_core" != bootstrap ] && [ "$core_hash" != "$state_core" ]; then
    [ "$predecessor" = "$state_core" ] && [ "$transition" -gt "$state_transition" ] || {
      append_receipt "$(printf '%06d' "$state_sequence")-blocked" 'kind=blocked' 'reason=nonmonotonic-core-state'
      receipt_hash=$last_receipt_hash
      write_state blocked "$state_sequence" "$state_no_progress" "$state_core" "$state_transition" "$receipt_hash"
      die 'nonmonotonic-core-state'
    }
  fi
  sequence=$((state_sequence + 1))
  sequence_name=$(printf '%06d' "$sequence")
  prompt="Protected continuation for $identity/$plan/$run: resume $cursor as $role. The parent is non-terminal; do not select another node or declare the parent complete."
  prompt_sha256=$(printf '%s' "$prompt" | shasum -a 256 | awk '{print $1}')
  append_receipt "${sequence_name}-wake-intent" 'kind=wake-intent' "sequence=$sequence" "cursor=$cursor" "role=$role" "pre_core_sha256=$core_hash" "prompt_sha256=$prompt_sha256"
  intent_hash=$last_receipt_hash
  write_state inflight "$sequence" "$state_no_progress" "$core_hash" "$transition" "$intent_hash"
  (
    cd "$workspace" || exit 1
    /usr/bin/sandbox-exec -f "$sandbox_profile" "$codex_bin" exec resume "$session_id" "$prompt"
  )
  child_status=$?
  if [ "$child_status" -ne 0 ]; then
    append_receipt "${sequence_name}-wake-exit" 'kind=wake-exit' "sequence=$sequence" "exit_status=$child_status" "post_core_sha256=$core_hash"
    exit_hash=$last_receipt_hash
    append_receipt "${sequence_name}-blocked" 'kind=blocked' 'reason=codex-exit-failure'
    blocked_hash=$last_receipt_hash
    write_state blocked "$sequence" "$state_no_progress" "$core_hash" "$transition" "$blocked_hash"
    printf '%s\n' 'result=blocked reason=codex-exit-failure'
    exit 1
  fi
  verify_runtime
  require_protected_file "$core" 'protected core state'
  post_hash="$(sha_file "$core")"
  append_receipt "${sequence_name}-wake-exit" 'kind=wake-exit' "sequence=$sequence" 'exit_status=0' "post_core_sha256=$post_hash"
  exit_hash=$last_receipt_hash
  if [ "$post_hash" = "$core_hash" ]; then
    no_progress=$((state_no_progress + 1))
    if [ "$no_progress" -ge "$no_progress_cap" ]; then
      append_receipt "${sequence_name}-blocked" 'kind=blocked' 'reason=no-progress-cap'
      blocked_hash=$last_receipt_hash
      write_state blocked "$sequence" "$no_progress" "$core_hash" "$transition" "$blocked_hash"
      printf '%s\n' 'result=blocked reason=no-progress-cap'
      exit 1
    fi
    write_state idle "$sequence" "$no_progress" "$core_hash" "$transition" "$exit_hash"
    continue
  fi
  # A changed file is progress only when the new protected snapshot explicitly
  # names this exact prior digest and increases its transition generation.
  post_transition="$(sed -n 's/^transition_generation=//p' "$core")"
  post_predecessor="$(sed -n 's/^previous_core_sha256=//p' "$core")"
  case "$post_transition" in *[!0-9]*|'') die 'missing post-transition generation' ;; esac
  [ "$post_predecessor" = "$core_hash" ] && [ "$post_transition" -gt "$transition" ] || {
    append_receipt "${sequence_name}-blocked" 'kind=blocked' 'reason=nonmonotonic-core-state'
    blocked_hash=$last_receipt_hash
    write_state blocked "$sequence" "$state_no_progress" "$core_hash" "$transition" "$blocked_hash"
    die 'nonmonotonic-core-state'
  }
  append_receipt "${sequence_name}-advance" 'kind=advance' "pre_core_sha256=$core_hash" "post_core_sha256=$post_hash" "transition_generation=$post_transition"
  advance_hash=$last_receipt_hash
  write_state idle "$sequence" 0 "$post_hash" "$post_transition" "$advance_hash"
done
