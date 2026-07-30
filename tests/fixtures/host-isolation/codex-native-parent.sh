#!/usr/bin/env bash
# Bounded behavioral model for the one supported native Codex goal. It is not
# a host emulator: it only records the invariant the adapter must preserve.
set -u

objective="${1:-}"
run="${2:-}"
native_binding="${3:-}"
child_state="${4:-}"
parent_rollup="${5:-}"
action="${6:-}"

[ -n "$objective" ] && [ -n "$run" ] || exit 64
[ "$native_binding" = "$objective/$run" ] || exit 64
[ "$child_state" = child_success ] || exit 64
[ "$parent_rollup" = incomplete ] || exit 64

case "$action" in
  attempt_native_parent_completion)
    printf '%s\n' 'REJECT: child success cannot complete an incomplete native parent goal'
    exit 73
    ;;
  explicit_resume)
    printf '%s\n' 'RESUME: retain the parent goal and dispatch the next frozen-order child'
    exit 0
    ;;
  *) exit 64 ;;
esac
