# Execution modes — how a chain of goals gets driven

Three ways to run a goal (or a decomposed chain of `.goals/*.md`). They differ only in **who
advances to the next goal**. All three need the same **hard bounds** (success + failure +
iteration/cost/time cap) and the same **Class-4 deny-list** — the mode changes who pulls the
trigger, never whether the safety exists.

**Key platform fact:** there is **no native goal-to-goal chaining** in Claude Code or Codex.
The evaluator judges *one* condition; it does not fire the next goal. So any auto-advance is
an **external wrapper**, not a built-in.

## The three modes

**1. Human-gated stepping (default).** The skill emits the ordered chain; the **human sets
each `/goal`** and only moves to the next after the current one's gate clears. Natural
checkpoints, a person in the loop at every hop. Best default — no wrapper, no bypass mode.

**2. Autonomous driver.** An **external wrapper loop** does the advancing, because nothing
native will:
- a script over headless `claude -p "/goal …"` (or `codex exec`), **or** a `/schedule` cloud
  routine, that
- reads the **ledger** (`.goals/` statuses) + the **gate output** for the current goal, and
- **fires the next ready goal** (`status:todo` ∧ all `depends_on` done) when the gate passes.
The wrapper is the chaining engine; the platform just runs one goal at a time.

**3. Full-auto.** Mode 2's driver operating **under the autonomy policy** (`autonomy.md`):
judgment calls at each fork are decided-and-logged (Class ≤ 2) or confirmed/denied
(Class 3/4) instead of pausing for a human. Runs in bypass mode → the `autonomy.md`
deterministic controls (PreToolUse deny-list, scoping, cost/iteration cap, kill-switch) are
**mandatory**, not optional.

## When to use

| Situation | Mode |
|---|---|
| Reviewing as you go; want a checkpoint every goal | **1 — human-gated** (default) |
| Trusted chain, want it to advance without you, but a human still eyeballs forks | **2 — autonomous driver** |
| Long unattended run (overnight, cloud routine); no human available for forks | **3 — full-auto** |
| Any irreversible / external / spend step in the path | **1**, or **3 with that step forced to CONFIRM** — never silent |
| No verifiable gate on a goal | **none** — fix the gate first; an ungated goal can't be driven |

## Non-negotiable for every mode

- **Bounds:** success stop + failure stop (fails N× / blocked / needs-human) + hard
  iteration + cost/time cap. An unbounded driver is a cost risk, not automation.
- **Deny-list:** the `PreToolUse` Class-4 hook + workspace scoping — required the moment a
  run is unattended (modes 2 and 3), since bypass mode turns platform prompts off.
- **Entry re-verify:** the driver re-checks the previous goal's gate at entry — it never
  trusts the ledger's "done".
