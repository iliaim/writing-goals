# Execution modes — how a chain of goals gets driven

Three ways to run a goal (or a decomposed chain of `.goals/*.md`). They differ only in **who
advances to the next goal**. All three need the same complete `stop_rules` (success, failure,
iterations, cost, and wall-clock). Unattended modes also require the Class-4 deny-list and
sandbox — the mode changes who pulls the trigger, not the method.

The persisted DAG is advanced by a human or an external driver; platform completion for one node
does not update the next node's ledger state.

## The three modes

**1. Human-gated stepping (default).** The skill emits the ordered chain; the human activates
each goal through the platform invocation and moves on only after the current gate clears. Natural
checkpoints, a person in the loop at every hop. Best default — no wrapper, no bypass mode.

**2. Autonomous driver.** An **external wrapper loop** does the advancing, because nothing
native will:
- a script over the platform's non-interactive entrypoint or scheduler that
- reads the **ledger** (`.goals/` statuses) + the **gate output** for the current goal, and
- **fires the next ready goal** (`status:todo` ∧ all `depends_on` done) when the gate passes.
The wrapper is the chaining engine; the platform just runs one goal at a time.

**3. Full-auto.** Mode 2's driver operating **under the autonomy policy** (`autonomy.md`):
judgment calls at each fork are decided-and-logged (Class ≤ 2), explicitly authorized by a
human (Class 3), or denied during unattended execution (Class 4). Runs in bypass mode → the `autonomy.md`
deterministic controls (PreToolUse deny-list, scoping, cost/iteration cap, kill-switch) are
**mandatory**, not optional.

## When to use

| Situation | Mode |
|---|---|
| Reviewing as you go; want a checkpoint every goal | **1 — human-gated** (default) |
| Trusted chain, want it to advance without you, but a human still eyeballs forks | **2 — autonomous driver** |
| Long unattended run (overnight, cloud routine); no human available for forks | **3 — full-auto** |
| Any irreversible / external / spend step in the path | **1**, or pause mode 3 for explicit bounded human authorization |
| No verifiable gate on a goal | **none** — fix the gate first; an ungated goal can't be driven |

## Non-negotiable for every mode

- **Bounds:** concrete success, failure, maximum iterations, maximum cost, and maximum wall-clock.
  An unbounded driver is a cost risk, not automation.
- **Deny-list:** the `PreToolUse` Class-4 hook + workspace scoping — required the moment a
  run is unattended (modes 2 and 3), since bypass mode turns platform prompts off.
- **Entry re-verify:** the driver re-checks the previous goal's gate at entry — it never
  trusts the ledger's "done".
