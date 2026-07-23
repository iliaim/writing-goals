#!/usr/bin/env bash
# ============================================================================
# gate.claude.sh — a deterministic Claude Code *Stop-hook* gate.
#
# WHAT IT IS: the real maker != checker. Claude's native /goal evaluator only
# reads the transcript and runs no tools, so it can be talked into "done". This
# script actually RUNS the gate command in a fresh process and lets the exit
# code — not the model's prose — decide whether Claude is allowed to stop.
#
# CONTRACT (Claude Stop hook):
#   * stdin  = JSON with, among others, `stop_hook_active`.
#   * stdout `{"decision":"block","reason":"..."}` + exit 0  -> Claude KEEPS
#     working, `reason` fed back to it as guidance.
#   * clean exit 0 with NO block on stdout                   -> Claude may STOP.
#   * (exit 2 + stderr would also block; we use the JSON form.)
#
# WIRING: .claude/settings.json -> hooks.Stop[].hooks[] =
#   {"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/gate.claude.sh"}
# `chmod +x` this file. See shared/gates.md.
# ============================================================================

set -u

# ---- config (override via env) --------------------------------------------
GATE_CMD="${GATE_CMD:-pytest -q}"          # the check; its exit code is the verdict
CAP="${GOAL_GATE_CAP:-5}"                   # hard iteration cap N (bounds the loop)
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"     # Claude sets CLAUDE_PROJECT_DIR to repo root
COUNT_FILE="$REPO_ROOT/.goal-gate-count"    # persisted attempt counter

# ---- read the hook's JSON stdin -------------------------------------------
INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  stop_hook_active="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')"
else
  # jq-less fallback: crude but sufficient to read one boolean field.
  case "$INPUT" in
    *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) stop_hook_active=true ;;
    *) stop_hook_active=false ;;
  esac
fi

# ---- fail-safe: never loop unbounded --------------------------------------
# The persisted counter is our real bound. If we cannot even write it, we have
# no bound — so we must ALLOW the stop rather than risk an infinite loop. This
# is where we honor `stop_hook_active`: it tells us a hook-driven continuation
# is already in flight, so failing open here is the safe choice.
if ! touch "$COUNT_FILE" 2>/dev/null; then
  echo "goal-gate: cannot persist '$COUNT_FILE'; allowing stop to avoid an unbounded loop (stop_hook_active=$stop_hook_active)." >&2
  exit 0
fi

# current attempt count (missing/empty -> 0)
count="$(cat "$COUNT_FILE" 2>/dev/null)"
case "$count" in ''|*[!0-9]*) count=0 ;; esac

# ---- BRANCH 1: cap hit -> allow stop, needs human -------------------------
# The strongest gate must still be bounded. Once we've blocked N times we stop
# blocking REGARDLESS of pass/fail and hand off to a human. Reset the counter
# because this loop is over; a fresh manual re-run should start clean.
if [ "$count" -ge "$CAP" ]; then
  rm -f "$COUNT_FILE"
  echo "goal-gate: iteration cap hit ($CAP/$CAP) — needs human. '$GATE_CMD' was not verified green after $CAP attempts." >&2
  exit 0    # clean exit, no block on stdout -> Claude may stop
fi

# ---- run the gate (run -> compare -> block/allow; NO silent fixing) --------
# We only RUN the command and read its exit code. We never edit, reformat, or
# otherwise mutate the verification surface to make it pass.
GATE_OUT="$(cd "$REPO_ROOT" && eval "$GATE_CMD" 2>&1)"
rc=$?

# ---- BRANCH 2: pass -> allow stop -----------------------------------------
if [ "$rc" -eq 0 ]; then
  rm -f "$COUNT_FILE"                       # loop succeeded; clear the counter
  echo "goal-gate: '$GATE_CMD' passed (exit 0) — allowing stop." >&2
  exit 0                                    # no block on stdout -> Claude may stop
fi

# ---- BRANCH 3: fail & under cap -> block, keep working --------------------
# Increment and persist first, so the NEXT Stop-hook invocation sees the higher
# count and the cap eventually fires.
count=$((count + 1))
printf '%s' "$count" > "$COUNT_FILE"

REASON="$GATE_CMD failed (attempt $count/$CAP); fix the code — do NOT edit, skip, xfail, or delete tests to go green."
if command -v jq >/dev/null 2>&1; then
  # jq guarantees valid escaping of the reason string.
  jq -cn --arg r "$REASON" '{decision:"block",reason:$r}'
else
  # REASON contains no quotes/newlines, so a manual template is safe here.
  printf '{"decision":"block","reason":"%s"}\n' "$REASON"
fi
# Optional: the failing output is available in $GATE_OUT for logging/debug.
exit 0    # exit 0 + block-on-stdout -> Claude KEEPS working
