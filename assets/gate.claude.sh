#!/usr/bin/env bash
# Deterministic Claude Code Stop-hook gate. This is a cooperative-agent
# backstop, not a security boundary; isolate the gate for adversarial use.

set -u
set -o pipefail

INPUT="$(cat)"
if ! command -v jq >/dev/null 2>&1; then
  echo "goal-gate: jq is required; blocking until a human intervenes." >&2
  exit 2
fi
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  echo "goal-gate: invalid hook JSON; blocking until a human intervenes." >&2
  exit 2
fi

# Validate the host contract before reading configuration or evaluating a gate.
# In particular, do not coerce false/null values through jq's `//` operator:
# they identify a malformed Stop event and must fail closed.
validate_stop_payload() {
  printf '%s' "$INPUT" | jq -e '
    type == "object" and
    (.session_id | type == "string") and
    (.transcript_path | type == "string") and
    (.stop_hook_active | type == "boolean")
  ' >/dev/null 2>&1
}

stop_hook_active="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')"
session_id="$(printf '%s' "$INPUT" | jq -r '.session_id // ""')"
transcript_path="$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""')"
REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"

block() {
  jq -cn --arg reason "$1" '{decision:"block",reason:$reason}'
  exit 0
}

terminal() {
  local reason="$1"
  echo "goal-gate: needs human — $reason" >&2
  jq -cn --arg reason "Goal gate needs human: $reason" \
    '{continue:false,stopReason:$reason}'
  exit 0
}

if ! validate_stop_payload; then
  terminal "Stop hook payload does not match Claude's supported contract."
fi

# Configuration is deliberately explicit. Defaults can silently run the wrong
# check, and non-canonical numbers are easy to interpret inconsistently.
if [ "${GATE_CMD+x}" != x ] || [ -z "$GATE_CMD" ]; then
  terminal "GATE_CMD must be set to a non-empty trusted command."
fi
if [ "${GOAL_GATE_CAP+x}" != x ]; then
  terminal "GOAL_GATE_CAP must be set explicitly."
fi
CAP="$GOAL_GATE_CAP"
case "$CAP" in
  ''|0|*[!0-9]*|0*) terminal "GOAL_GATE_CAP must be a canonical positive base-10 integer." ;;
esac
if [ "${#CAP}" -gt 18 ]; then
  terminal "GOAL_GATE_CAP is too large (maximum 18 digits)."
fi
CAP=$((10#$CAP))

if [ "${GATE_SURFACE+x}" != x ] || [ -z "$GATE_SURFACE" ]; then
  terminal "GATE_SURFACE must resolve to at least one regular file."
fi
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT" ]; then
  terminal "no usable repository root was supplied."
fi

SHA_TOOL=""
if command -v shasum >/dev/null 2>&1; then
  SHA_TOOL=shasum
elif command -v sha256sum >/dev/null 2>&1; then
  SHA_TOOL=sha256sum
else
  terminal "no SHA-256 tool is available."
fi

valid_digest() {
  [ "${#1}" -eq 64 ] || return 1
  case "$1" in *[!0-9A-Fa-f]*) return 1 ;; esac
}

valid_prefixed_digest() {
  case "$1" in sha256:*) valid_digest "${1#sha256:}" ;; *) return 1 ;; esac
}

protected_mode() {
  local path mode
  path=$1
  if stat -f '%Lp' "$path" >/dev/null 2>&1; then mode=$(stat -f '%Lp' "$path"); else mode=$(stat -c '%a' "$path" 2>/dev/null) || return 1; fi
  case "$mode" in ???) ;; *) return 1 ;; esac
  case "${mode#?}" in *[1-7]*) return 1 ;; esac
}

validate_preflight_record() {
  local record_key record_value record_keys record_mode
  case "${GATE_AUTHORITY:-}" in /*) ;; *) terminal "GATE_AUTHORITY must be an absolute protected directory." ;; esac
  if ! { [ -d "$GATE_AUTHORITY" ] && [ ! -L "$GATE_AUTHORITY" ] && protected_mode "$GATE_AUTHORITY"; }; then
    terminal "GATE_AUTHORITY must be a protected real directory."
  fi
  case "${GATE_PREFLIGHT_RECORD:-}" in "$GATE_AUTHORITY"/*) ;; *) terminal "GATE_PREFLIGHT_RECORD must be inside GATE_AUTHORITY." ;; esac
  [ -f "$GATE_PREFLIGHT_RECORD" ] && [ ! -L "$GATE_PREFLIGHT_RECORD" ] ||
    terminal "GATE_PREFLIGHT_RECORD must be a protected regular file."
  if stat -f '%Lp' "$GATE_PREFLIGHT_RECORD" >/dev/null 2>&1; then record_mode=$(stat -f '%Lp' "$GATE_PREFLIGHT_RECORD"); else record_mode=$(stat -c '%a' "$GATE_PREFLIGHT_RECORD" 2>/dev/null) || terminal "cannot inspect GATE_PREFLIGHT_RECORD permissions."; fi
  [ "$record_mode" = 600 ] || terminal "GATE_PREFLIGHT_RECORD must be mode 0600."
  record_keys=''; preflight_objective=''; preflight_plan=''; preflight_surface=''; preflight_baseline=''
  while IFS='=' read -r record_key record_value || [ -n "${record_key:-}" ]; do
    case "$record_key" in objective_digest|plan_digest|surface_digest|baseline) ;; *) terminal "GATE_PREFLIGHT_RECORD has an invalid field." ;; esac
    case "|$record_keys|" in *"|$record_key|"*) terminal "GATE_PREFLIGHT_RECORD has a duplicate field." ;; esac
    record_keys="${record_keys:+$record_keys|}$record_key"
    case "$record_key" in objective_digest) preflight_objective=$record_value ;; plan_digest) preflight_plan=$record_value ;; surface_digest) preflight_surface=$record_value ;; baseline) preflight_baseline=$record_value ;; esac
  done < "$GATE_PREFLIGHT_RECORD"
  for required_key in objective_digest plan_digest surface_digest baseline; do
    case "|$record_keys|" in *"|$required_key|"*) ;; *) terminal "GATE_PREFLIGHT_RECORD is incomplete." ;; esac
  done
  if ! { valid_prefixed_digest "$preflight_objective" && valid_prefixed_digest "$preflight_plan" && valid_prefixed_digest "$preflight_surface"; }; then
    terminal "GATE_PREFLIGHT_RECORD has an invalid digest."
  fi
  [ "$preflight_baseline" = green ] || terminal "GATE_PREFLIGHT_RECORD baseline is not green."
  GATE_PREFLIGHT_SURFACE_DIGEST=${preflight_surface#sha256:}
}

sha_stdin() {
  local output digest
  if [ "$SHA_TOOL" = shasum ]; then
    output="$(shasum -a 256)" || return 1
  else
    output="$(sha256sum)" || return 1
  fi
  digest="${output%% *}"
  valid_digest "$digest" || return 1
  printf '%s\n' "$digest"
}

sha_file() {
  local output digest
  if [ "$SHA_TOOL" = shasum ]; then
    output="$(shasum -a 256 "$1")" || return 1
  else
    output="$(sha256sum "$1")" || return 1
  fi
  digest="${output%% *}"
  valid_digest "$digest" || return 1
  printf '%s\n' "$digest"
}

key_digest="$(printf '%s' "${REPO_ROOT}|${session_id}|${transcript_path}" | sha_stdin)" ||
  terminal "the session key could not be hashed."
KEY="${key_digest:0:16}"

if [ -n "${XDG_STATE_HOME:-}" ]; then
  STATE_BASE="$XDG_STATE_HOME"
elif [ -n "${HOME:-}" ]; then
  STATE_BASE="$HOME/.local/state"
else
  terminal "neither XDG_STATE_HOME nor HOME supplies a state location."
fi
STATE_ROOT="$STATE_BASE/writing-goals"
COUNT_FILE="$STATE_ROOT/gate-count-$KEY"
SURFACE_FILE="$STATE_ROOT/gate-surface-$KEY"
OUTPUT_FILE="$STATE_ROOT/gate-output-$KEY.log"
umask 077
if ! mkdir -p "$STATE_ROOT" 2>/dev/null; then
  terminal "cannot create state directory '$STATE_ROOT' (stop_hook_active=$stop_hook_active)."
fi

TEMP_FILE=""
# Invoked indirectly through the traps below.
# shellcheck disable=SC2317,SC2329
cleanup_temp() {
  if [ -n "$TEMP_FILE" ]; then
    rm -f "$TEMP_FILE" 2>/dev/null || true
  fi
}
trap cleanup_temp EXIT
trap 'cleanup_temp; exit 1' HUP INT TERM

make_temp() {
  TEMP_FILE="$(mktemp "$STATE_ROOT/.gate-state-$KEY.XXXXXX" 2>/dev/null)" ||
    terminal "a secure state temporary file could not be created."
  if [ ! -f "$TEMP_FILE" ] || [ -L "$TEMP_FILE" ] || ! chmod 600 "$TEMP_FILE"; then
    terminal "the secure state temporary file is unusable."
  fi
}

surface_hash() {
  (
    cd "$REPO_ROOT" || exit 1
    found=0
    # GATE_SURFACE is intentionally a shell glob/list configured by the user.
    # shellcheck disable=SC2086
    for file in $GATE_SURFACE; do
      [ -f "$file" ] || exit 1
      digest="$(sha_file "$file")" || exit 1
      printf '%s:%s\n' "$file" "$digest"
      found=1
    done
    [ "$found" -eq 1 ]
  ) | LC_ALL=C sort | sha_stdin
}

validate_preflight_record
cur_surface="$(surface_hash)" ||
  terminal "GATE_SURFACE='$GATE_SURFACE' did not resolve completely or could not be hashed."
if [ "$cur_surface" != "$GATE_PREFLIGHT_SURFACE_DIGEST" ]; then
  terminal "the verification surface does not match the protected preflight digest."
fi
if [ -e "$SURFACE_FILE" ] || [ -L "$SURFACE_FILE" ]; then
  if [ -L "$SURFACE_FILE" ] || [ ! -f "$SURFACE_FILE" ] || [ ! -r "$SURFACE_FILE" ]; then
    terminal "verification-surface state is not a readable regular file."
  fi
  prev_surface="$(cat "$SURFACE_FILE")" ||
    terminal "verification-surface state could not be read."
  if [ "$cur_surface" != "$prev_surface" ]; then
    terminal "the verification surface changed during this session."
  fi
else
  make_temp
  surface_tmp="$TEMP_FILE"
  if ! printf '%s\n' "$GATE_PREFLIGHT_SURFACE_DIGEST" >"$surface_tmp" ||
     ! mv -f "$surface_tmp" "$SURFACE_FILE"; then
    terminal "verification-surface state could not be persisted."
  fi
  TEMP_FILE=""
fi

count=0
if [ -e "$COUNT_FILE" ] || [ -L "$COUNT_FILE" ]; then
  if [ -L "$COUNT_FILE" ] || [ ! -f "$COUNT_FILE" ] || [ ! -r "$COUNT_FILE" ]; then
    terminal "attempt state is not a readable regular file."
  fi
  count="$(cat "$COUNT_FILE")" || terminal "attempt state could not be read."
  case "$count" in
    ''|*[!0-9]*) terminal "attempt state is empty or non-decimal." ;;
  esac
  if [ "${#count}" -gt 18 ]; then
    terminal "attempt state is too large."
  fi
  count=$((10#$count))
fi
if [ "$count" -ge "$CAP" ]; then
  terminal "the attempt cap was already reached ($count/$CAP)."
fi

if [ -e "$OUTPUT_FILE" ] || [ -L "$OUTPUT_FILE" ]; then
  if [ -L "$OUTPUT_FILE" ] || [ ! -f "$OUTPUT_FILE" ]; then
    terminal "gate-output state is not a regular file."
  fi
fi
make_temp
output_tmp="$TEMP_FILE"
(cd "$REPO_ROOT" && eval "$GATE_CMD") >"$output_tmp" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  rm -f "$output_tmp" "$COUNT_FILE" "$OUTPUT_FILE" 2>/dev/null || true
  TEMP_FILE=""
  exit 0
fi
if ! mv -f "$output_tmp" "$OUTPUT_FILE"; then
  terminal "failing gate output could not be persisted."
fi
TEMP_FILE=""

count=$((count + 1))
make_temp
count_tmp="$TEMP_FILE"
if ! printf '%s\n' "$count" >"$count_tmp" ||
   ! mv -f "$count_tmp" "$COUNT_FILE"; then
  terminal "attempt state could not be persisted atomically."
fi
TEMP_FILE=""
written="$(cat "$COUNT_FILE")" || terminal "attempt state could not be verified."
if [ "$written" != "$count" ]; then
  terminal "attempt state did not persist correctly."
fi

if [ "$count" -ge "$CAP" ]; then
  terminal "the verification command remained red at the attempt cap ($count/$CAP)."
fi
block "$GATE_CMD failed (attempt $count/$CAP); fix the code without weakening the verification surface."
