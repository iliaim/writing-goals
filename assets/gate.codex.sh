#!/usr/bin/env bash
# ============================================================================
# gate.codex.sh — a deterministic Codex CLI *Stop-hook* gate.
#
# HONEST SCOPE — READ THIS FIRST
# ------------------------------------------------------------------------
# This hook is a BEST-EFFORT, DEFENSE-IN-DEPTH BACKSTOP that enforces
# maker != checker for a *cooperative* agent — it is NOT a security boundary
# against an *adversarial* agent. It runs a verification command in a fresh
# process and lets the exit code (not the model's prose) decide whether the
# agent may stop. A determined agent with shell access can still subvert a
# same-host check (edit the runner, poison the environment, etc.). The real
# boundary is OS-level sandboxing: run the gate where the agent cannot reach
# its state, on read-only mounts, as a non-root user, with no ambient egress.
#
# WHAT IT IS: Codex's native /goal completion is *model-declared* (the agent
# calls update_goal("complete")); the harness does not independently run your
# tests. So it can be talked into "done". This script actually RUNS the gate
# command and blocks the stop until the command exits 0.
#
# VERIFIED on codex-cli 0.144.1 (live smoke-test, 2026-07-23):
#   * The `Stop` hook genuinely BLOCKS (re-invokes the turn) — it is NOT
#     notify-only. Fire log showed 2 fires; Codex logged "Stop Blocked" then,
#     after the agent did one step, "Stop Completed".
#   * Block contract: **{"decision":"block","reason":"..."} on stdout + exit 0
#     BLOCKS** and feeds `reason` back. This matches the Claude contract.
#     A clean exit 0 with no block on stdout ALLOWS the stop.
#   * Stop-hook stdin carries: cwd, session_id, transcript_path,
#     stop_hook_active, last_assistant_message, permission_mode.
#   * REPO ROOT comes from the stdin **`cwd`** field — Codex sets no
#     CLAUDE_PROJECT_DIR-style env var. (This is the ONLY substantive
#     difference from gate.claude.sh.)
#
# HARDENING (same as gate.claude.sh):
#   * The attempt counter lives OUTSIDE the repo, under
#     $XDG_STATE_HOME (default ~/.local/state)/writing-goals, keyed by a hash
#     of the project cwd + session id + transcript path. The graded agent can
#     no longer seed a repo-local file to force an allow-stop.
#   * FAIL CLOSED: if state can't be persisted (unwritable dir, or a directory
#     sits where the file should) we BLOCK and escalate to a human — we do NOT
#     allow the stop. Every state write's exit status is checked.
#   * JSON is emitted via jq (fail closed if jq is missing). GATE_CMD is NEVER
#     interpolated into a printf JSON template.
#   * Optional verification-surface pinning: set GATE_SURFACE to a glob of the
#     test files; their hash is recorded on first run and any later change
#     BLOCKS+escalates (defends against editing tests to go green).
#
# CONTRACT (Codex Stop hook, verified 0.144.1):
#   * stdin = JSON with `cwd`, `session_id`, `transcript_path`,
#     `stop_hook_active`, ...
#   * stdout {"decision":"block","reason":"..."} + exit 0 -> Codex KEEPS
#     working, `reason` fed back as guidance.
#   * clean exit 0 with NO block  -> Codex may STOP.
#   * exit 2 + stderr             -> also blocks (used as the jq-less fallback).
#
# NOTE on "escalate to a human": a Stop hook can only block or allow. There is
# no human side-channel, so we escalate by BLOCKING with a loud reason that
# tells the agent to halt and get a human, plus a stderr banner. We prefer this
# (fail closed) over allow-stop. Codex's own loop detection (stop_hook_active)
# and the session budget remain the ultimate guard against an unbounded loop.
#
# WIRING: .codex/hooks.json (PascalCase events; on by default; must be TRUSTED
# via the /hooks flow or run with --dangerously-bypass-hook-trust):
#   { "hooks": { "Stop": [ { "hooks": [
#       { "type": "command", "command": "/abs/path/to/gate.codex.sh" } ] } ] } }
# `chmod +x` this file. See shared/gates.md for the neutral gate concepts.
# ============================================================================

set -u

# ---- config (override via env) --------------------------------------------
GATE_CMD="${GATE_CMD:-pytest -q}"           # the check; its exit code is the verdict
CAP="${GOAL_GATE_CAP:-5}"                    # hard iteration cap N (bounds the loop)
GATE_SURFACE="${GATE_SURFACE:-}"             # optional glob of the test files to pin

# ---- pick a sha tool -------------------------------------------------------
if command -v shasum >/dev/null 2>&1; then
  sha() { shasum -a 256 | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
  sha() { sha256sum | awk '{print $1}'; }
else
  echo "goal-gate: no sha256 tool (shasum/sha256sum) — cannot key or pin state. Blocking; a human must intervene." >&2
  exit 2   # fail closed
fi

# ---- read the hook's JSON stdin (jq REQUIRED) ------------------------------
INPUT="$(cat)"
if ! command -v jq >/dev/null 2>&1; then
  echo "goal-gate: jq is required to emit a valid Stop decision; refusing to fail open. A human must intervene." >&2
  exit 2   # exit 2 + stderr blocks -> fail closed
fi
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  echo "goal-gate: hook stdin is not valid JSON; failing closed (block). A human must intervene." >&2
  exit 2
fi
stop_hook_active="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')"
session_id="$(printf '%s' "$INPUT" | jq -r '.session_id // ""')"
transcript_path="$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""')"
# Codex sets no CLAUDE_PROJECT_DIR-style env var: the repo root is the stdin
# `cwd` field (verified present on 0.144.1). We do NOT silently fall back to the
# hook's own PWD — a missing/renamed `cwd` (e.g. a future Codex build) with a
# PWD fallback could run the gate in the wrong directory and ALLOW an unverified
# stop (fail-open). Instead an unusable repo root fails CLOSED (see below).
REPO_ROOT="$(printf '%s' "$INPUT" | jq -r '.cwd // ""')"

# ---- emit a block decision (JSON via jq) + exit 0 --------------------------
block() {
  local reason="$1"
  jq -cn --arg r "$reason" '{decision:"block",reason:$r}'
  exit 0
}
# escalate = block, but shout on stderr too. Used for every fail-closed path.
escalate() {
  local reason="$1"
  echo "goal-gate: ESCALATE (human needed) — $reason" >&2
  block "HALT and get a human: $reason"
}

# ---- FAIL CLOSED on an unusable repo root ----------------------------------
# Empty (Codex didn't send `cwd`) or not an existing directory -> we cannot
# trust where the gate command would run. BLOCK + escalate rather than run it in
# an unknown dir and risk allowing an unverified stop.
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT" ]; then
  escalate "no usable repo root from hook stdin (.cwd='$REPO_ROOT'); refusing to run the gate in an unknown directory."
fi

# ---- derive the out-of-repo state location ---------------------------------
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/writing-goals"
KEY="$(printf '%s' "${REPO_ROOT}|${session_id}|${transcript_path}" | sha | cut -c1-16)"
COUNT_FILE="$STATE_ROOT/gate-count-$KEY"
SURFACE_FILE="$STATE_ROOT/gate-surface-$KEY"

# Create the state dir; if we can't, we have no reliable bound -> fail closed.
if ! mkdir -p "$STATE_ROOT" 2>/dev/null; then
  escalate "cannot create state dir '$STATE_ROOT' (stop_hook_active=$stop_hook_active)."
fi
# A directory where the counter file should be is a tamper/EXDEV hazard.
if [ -e "$COUNT_FILE" ] && [ ! -f "$COUNT_FILE" ]; then
  escalate "'$COUNT_FILE' exists but is not a regular file (a directory/seed?) — cannot persist the counter."
fi

# ---- verification-surface pinning (best-effort) ----------------------------
# Hash the test files on first run; block if they change on a later run. This
# defends against the agent editing the tests to make the gate go green.
surface_hash() {
  # Expand GATE_SURFACE relative to the repo root; hash sorted per-file digests.
  # Use the sha() helper (picks shasum OR sha256sum) — NOT a hardcoded shasum,
  # so pinning still works on a sha256sum-only host.
  ( cd "$REPO_ROOT" 2>/dev/null || exit 1
    # shellcheck disable=SC2086
    for f in $GATE_SURFACE; do
      [ -f "$f" ] && printf '%s:%s\n' "$f" "$(sha < "$f")"
    done | sort | sha
  )
}
if [ -n "$GATE_SURFACE" ]; then
  cur_surface="$(surface_hash)"
  if [ -f "$SURFACE_FILE" ]; then
    prev_surface="$(cat "$SURFACE_FILE" 2>/dev/null || true)"
    if [ "$cur_surface" != "$prev_surface" ]; then
      escalate "verification surface (GATE_SURFACE='$GATE_SURFACE') changed since the run started — the tests may have been edited to pass."
    fi
  else
    if ! printf '%s' "$cur_surface" > "$SURFACE_FILE" 2>/dev/null; then
      escalate "cannot record the verification-surface hash to '$SURFACE_FILE'."
    fi
  fi
else
  echo "goal-gate: WARNING — surface pinning is OFF (set GATE_SURFACE to a glob of your test files to detect test-editing)." >&2
fi

# ---- current attempt count (missing/empty -> 0; anything odd -> 0) ---------
count="$(cat "$COUNT_FILE" 2>/dev/null || true)"
case "$count" in ''|*[!0-9]*) count=0 ;; esac
count=$((10#$count))   # force base-10 so a value like 08/09 can't break arithmetic

# ---- BRANCH 1: cap hit -> allow stop, needs human --------------------------
# The strongest gate must still be bounded. Once we've blocked N times we stop
# blocking REGARDLESS of pass/fail and hand off to a human.
if [ "$count" -ge "$CAP" ]; then
  rm -f "$COUNT_FILE" 2>/dev/null || true
  echo "goal-gate: iteration cap hit ($CAP/$CAP) — needs human. '$GATE_CMD' was not verified green after $CAP attempts." >&2
  exit 0    # clean exit, no block on stdout -> Codex may stop
fi

# ---- run the gate (run -> compare -> block/allow; NO silent fixing) --------
# We only RUN the command and read its exit code. We never edit, reformat, or
# otherwise mutate the verification surface to make it pass.
GATE_OUT="$(cd "$REPO_ROOT" && eval "$GATE_CMD" 2>&1)"
rc=$?

# ---- BRANCH 2: pass -> allow stop -----------------------------------------
if [ "$rc" -eq 0 ]; then
  rm -f "$COUNT_FILE" 2>/dev/null || true   # loop succeeded; clear the counter
  echo "goal-gate: '$GATE_CMD' passed (exit 0) — allowing stop." >&2
  exit 0                                     # no block on stdout -> Codex may stop
fi

# ---- BRANCH 3: fail & under cap -> block, keep working ---------------------
# Increment and PERSIST first so the NEXT Stop sees the higher count and the cap
# eventually fires. If we cannot persist, we have lost our bound -> fail closed.
count=$((count + 1))
if ! printf '%s' "$count" > "$COUNT_FILE" 2>/dev/null; then
  escalate "cannot persist the attempt counter to '$COUNT_FILE'; refusing to allow a possibly-red stop."
fi
# Confirm the value actually landed (guards a silently-truncated/odd write).
written="$(cat "$COUNT_FILE" 2>/dev/null || true)"
if [ "$written" != "$count" ]; then
  escalate "attempt counter did not persist correctly to '$COUNT_FILE' (wanted '$count', read '$written')."
fi

REASON="$GATE_CMD failed (attempt $count/$CAP); fix the code — do NOT edit, skip, xfail, or delete tests to go green."
block "$REASON"
# (unreached) — the failing output is available in $GATE_OUT for logging/debug.
