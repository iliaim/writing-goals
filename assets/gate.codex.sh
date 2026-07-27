#!/usr/bin/env bash
# Deterministic Codex Stop-hook gate. This is a cooperative-agent backstop,
# not a security boundary; isolate the gate for adversarial use.

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

stop_hook_active="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')"
session_id="$(printf '%s' "$INPUT" | jq -r '.session_id // ""')"
transcript_path="$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""')"
REPO_ROOT="$(printf '%s' "$INPUT" | jq -r '.cwd // ""')"

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

STATE_ROOT="${XDG_STATE_HOME:-${HOME:?HOME is required}/.local/state}/writing-goals"
COUNT_FILE="$STATE_ROOT/gate-count-$KEY"
SURFACE_FILE="$STATE_ROOT/gate-surface-$KEY"
OUTPUT_FILE="$STATE_ROOT/gate-output-$KEY.log"
umask 077
if ! mkdir -p "$STATE_ROOT" 2>/dev/null; then
  terminal "cannot create state directory '$STATE_ROOT' (stop_hook_active=$stop_hook_active)."
fi

surface_hash() {
  (
    cd "$REPO_ROOT" || exit 1
    found=0
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

cur_surface="$(surface_hash)" ||
  terminal "GATE_SURFACE='$GATE_SURFACE' did not resolve completely or could not be hashed."
if [ -e "$SURFACE_FILE" ]; then
  if [ ! -f "$SURFACE_FILE" ] || [ ! -r "$SURFACE_FILE" ]; then
    terminal "verification-surface state is not a readable regular file."
  fi
  prev_surface="$(cat "$SURFACE_FILE")" ||
    terminal "verification-surface state could not be read."
  if [ "$cur_surface" != "$prev_surface" ]; then
    terminal "the verification surface changed during this session."
  fi
else
  surface_tmp="$STATE_ROOT/.gate-surface-$KEY.$$"
  if ! printf '%s\n' "$cur_surface" >"$surface_tmp" ||
     ! chmod 600 "$surface_tmp" ||
     ! mv -f "$surface_tmp" "$SURFACE_FILE"; then
    rm -f "$surface_tmp" 2>/dev/null || true
    terminal "verification-surface state could not be persisted."
  fi
fi

count=0
if [ -e "$COUNT_FILE" ]; then
  if [ ! -f "$COUNT_FILE" ] || [ ! -r "$COUNT_FILE" ]; then
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

output_tmp="$STATE_ROOT/.gate-output-$KEY.$$"
(cd "$REPO_ROOT" && eval "$GATE_CMD") >"$output_tmp" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  rm -f "$output_tmp" "$COUNT_FILE" "$OUTPUT_FILE" 2>/dev/null || true
  exit 0
fi
if ! chmod 600 "$output_tmp" || ! mv -f "$output_tmp" "$OUTPUT_FILE"; then
  rm -f "$output_tmp" 2>/dev/null || true
  terminal "failing gate output could not be persisted."
fi

count=$((count + 1))
count_tmp="$STATE_ROOT/.gate-count-$KEY.$$"
if ! printf '%s\n' "$count" >"$count_tmp" ||
   ! chmod 600 "$count_tmp" ||
   ! mv -f "$count_tmp" "$COUNT_FILE"; then
  rm -f "$count_tmp" 2>/dev/null || true
  terminal "attempt state could not be persisted atomically."
fi
written="$(cat "$COUNT_FILE")" || terminal "attempt state could not be verified."
if [ "$written" != "$count" ]; then
  terminal "attempt state did not persist correctly."
fi

if [ "$count" -ge "$CAP" ]; then
  terminal "the verification command remained red at the attempt cap ($count/$CAP)."
fi
block "$GATE_CMD failed (attempt $count/$CAP); fix the code without weakening the verification surface."
