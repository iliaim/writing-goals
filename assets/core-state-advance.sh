#!/usr/bin/env bash
# Trusted host-only transition writer for a protected Codex core cursor.
set -u
set -o pipefail

die() { printf '%s\n' "core-state-advance: $*" >&2; exit 1; }
mode_of() { if stat -f '%Lp' "$1" >/dev/null 2>&1; then stat -f '%Lp' "$1"; else stat -c '%a' "$1" 2>/dev/null; fi; }
sha_file() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
valid_hex() { [ "${#1}" = 64 ] && case "$1" in *[!0-9A-Fa-f]*) return 1 ;; *) return 0 ;; esac; }
require_protected() {
  target=$1 label=$2
  case "$target" in "$authority"/*) ;; *) die "$label must be inside authority" ;; esac
  [ -f "$target" ] && [ ! -L "$target" ] || die "$label must be a protected regular file"
  [ "$(mode_of "$target")" = 600 ] || die "$label must be mode 0600"
}

authority='' identity='' plan='' run='' expected_core=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --authority|--identity|--plan|--run|--expected-core-sha256)
      [ "$#" -ge 2 ] || die "missing value for $1"
      case "$1" in --authority) authority=$2 ;; --identity) identity=$2 ;; --plan) plan=$2 ;; --run) run=$2 ;; --expected-core-sha256) expected_core=$2 ;; esac
      shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$authority" ] && [ -n "$identity" ] && [ -n "$plan" ] && [ -n "$run" ] && valid_hex "$expected_core" || die 'authority, identity, plan, run, and expected core SHA-256 are required'
case "$authority" in /*) ;; *) die 'authority must be absolute' ;; esac
[ -d "$authority" ] && [ ! -L "$authority" ] || die 'authority must be a real directory'
authority_mode=$(mode_of "$authority") || die 'cannot inspect authority permissions'
case "${authority_mode#?}" in *[1-7]*) die 'authority is not protected' ;; esac

config="$authority/continuation.env"
require_protected "$config" 'continuation configuration'
cfg_identity='' cfg_plan='' cfg_run='' trusted_root='' runtime_path='' runtime_sha256='' advance_path='' advance_sha256='' config_keys=''
while IFS='=' read -r key value || [ -n "${key:-}" ]; do
  case "$key" in identity|plan|run|session_id|workspace|codex_bin|sandbox_profile|trusted_root|controller_sha256|runtime_path|runtime_sha256|advance_path|advance_sha256|no_progress_cap) ;; *) die 'invalid continuation configuration field' ;; esac
  case "|$config_keys|" in *"|$key|"*) die 'duplicate continuation configuration field' ;; esac
  config_keys="${config_keys:+$config_keys|}$key"
  case "$key" in
    identity) cfg_identity=$value ;; plan) cfg_plan=$value ;; run) cfg_run=$value ;;
    trusted_root) trusted_root=$value ;; runtime_path) runtime_path=$value ;; runtime_sha256) runtime_sha256=$value ;;
    advance_path) advance_path=$value ;; advance_sha256) advance_sha256=$value ;;
    session_id|workspace|codex_bin|sandbox_profile|controller_sha256|no_progress_cap) ;;
  esac
done < "$config"
for key in identity plan run session_id workspace codex_bin sandbox_profile trusted_root controller_sha256 runtime_path runtime_sha256 advance_path advance_sha256 no_progress_cap; do
  case "|$config_keys|" in *"|$key|"*) ;; *) die 'incomplete continuation configuration' ;; esac
done
[ "$cfg_identity" = "$identity" ] && [ "$cfg_plan" = "$plan" ] && [ "$cfg_run" = "$run" ] || die 'continuation configuration binding mismatch'
case "$0" in "$trusted_root"/*) ;; *) die 'advance helper must run from trusted tool root' ;; esac
[ "$advance_path" = "$0" ] && [ "$(sha_file "$0")" = "$advance_sha256" ] || die 'trusted advance helper digest changed'
case "$runtime_path" in "$trusted_root"/*) ;; *) die 'runtime path must be inside trusted tool root' ;; esac
[ -f "$runtime_path" ] && [ ! -L "$runtime_path" ] || die 'runtime path must be a regular trusted file'
valid_hex "$runtime_sha256" && [ "$(sha_file "$runtime_path")" = "$runtime_sha256" ] || die 'trusted runtime digest changed'

core="$authority/core-state.env"; next="$authority/core-next.env"
require_protected "$core" 'protected core state'
require_protected "$next" 'protected next core state'
lock="$authority/.core-${run}.lock"
mkdir "$lock" 2>/dev/null || die 'core-advance-busy'
validation="$authority/.core-validate.${run}.$$"
cleanup() { rm -rf "$validation" 2>/dev/null || true; rmdir "$lock" 2>/dev/null || true; }
trap cleanup EXIT HUP INT TERM
current_hash=$(sha_file "$core")
[ "$current_hash" = "$expected_core" ] || die 'stale core preimage'
current_transition=$(sed -n 's/^transition_generation=//p' "$core")
next_transition=$(sed -n 's/^transition_generation=//p' "$next")
next_predecessor=$(sed -n 's/^previous_core_sha256=//p' "$next")
case "$current_transition" in *[!0-9]*|'') die 'invalid current core transition generation' ;; esac
case "$next_transition" in *[!0-9]*|'') die 'invalid next core transition generation' ;; esac
[ "$next_predecessor" = "$current_hash" ] && [ "$next_transition" -gt "$current_transition" ] || die 'nonmonotonic core transition'
mkdir "$validation" || die 'cannot create private validation authority'
chmod 700 "$validation" || die 'cannot protect validation authority'
for record in activation.env approval.env preflight.env; do
  require_protected "$authority/$record" "protected $record"
  cp -p "$authority/$record" "$validation/$record" || die 'cannot stage protected validation record'
done
cp -p "$next" "$validation/core-state.env" || die 'cannot stage next core state for validation'
if ! bash "$runtime_path" --authority "$validation" --identity "$identity" --plan "$plan" --run "$run" --approval-record "$validation/approval.env" --preflight-record "$validation/preflight.env" --activation-record "$validation/activation.env" --core-record "$validation/core-state.env" --resume >/dev/null; then
  die 'invalid next core state'
fi
# Validation has not touched the live cursor. Recheck immediately before the
# one atomic replacement so a stale preparation can never overwrite a newer one.
[ "$(sha_file "$core")" = "$expected_core" ] || die 'stale core preimage after validation'
mv "$next" "$core" || die 'cannot atomically install next core state'
printf 'result=advanced\ncore_sha256=%s\n' "$(sha_file "$core")"
