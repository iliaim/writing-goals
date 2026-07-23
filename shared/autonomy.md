# Autonomy policy — act unattended without silently guessing or doing damage

This is the policy that lets an agent run a goal (or a chain) unattended. It reconciles
"act autonomously" with the skill's zero-guess rule, and it hardens the run for
**bypass / full-permission mode** where the platform's approval prompts are OFF.

## Reconciliation: autonomy ≠ guessing

A decision made without a human in the loop is **accountable autonomy** — not a guess —
**iff it is all three of:**

- **Recorded** — written to the goal's `assumptions` ledger, not held in the model's head.
- **Reversible** — an undo path exists and stays inside the workspace.
- **Surfaced** — raised at the next checkpoint so a human can veto it.

Drop **any one** of the three, or touch anything **irreversible / external / costly**, and
it is a **forbidden silent guess** — the exact failure this skill exists to prevent.

**Confidence NEVER upgrades a dangerous action to auto.** "I'm 99% sure" does not move a
Class 3/4 action down a tier. Class is set by the action's blast radius, not by how sure
the doer feels.

## 5-class action model (worst dimension wins)

Score the action on every dimension; the **worst** one sets the class. Confidence cannot
lower it.

| Class | Trigger | Decision |
|---|---|---|
| **0** read / inert | no state change (read, list, typecheck, dry-run) | **AUTO** |
| **1** reversible + repo-local | undoable, in-workspace, ~free (edit a file, local commit) | **AUTO** — log if it resolved an ambiguity |
| **2** reversible but wide | big blast radius / effortful undo (mass rename, dependency bump, schema migration on a scratch DB) | **AUTO + checkpoint** |
| **3** irreversible / external / costs money / crosses trust boundary | prod deploy or DB write, any external send, payment, delete **outside** the repo, **changing the top objective / acceptance criteria** | **CONFIRM ALWAYS** |
| **4** prohibited | on the deny-list below | **DENY** (hard block) |

Note **Class 3 includes editing the goal itself** — changing the top objective or the
acceptance gate is a trust-boundary crossing, never an auto decision.

## Decide-and-log protocol (replaces silent guessing)

On a fork where the choice is **Class ≤ 2**, do not stop and do not guess silently —
**decide and log:**

1. Pick the **best-practice default**: least-disruptive option, **prefer the reversible
   one**, **stay in the workspace**, **don't spend money**.
2. Record the decision in the goal's `assumptions` ledger:

   ```
   { fork, options, chosen, rationale, undo-path, confidence }
   ```

3. Keep the action reversible and **surface it at the next checkpoint** for veto.

If the fork is **Class 3** → CONFIRM (stop and ask / propose-and-checkpoint). If **Class 4**
→ DENY. A `MUST-ASK` fact (an absolute threshold, the definition of done, a decomposition
spec) is never auto-resolved this way — decide-and-log is for reversible judgment calls,
not for inventing facts.

## Hard deny-list (Class 4 — evaluated FIRST)

Deny is checked **before** any allowlist and **beats bypass mode**. These are hard blocks,
never auto, never confirmable-into-yes by the doer:

- **Spend money** — purchases, paid API calls beyond budget, provisioning billable resources.
- **Delete or modify outside the workspace** — anything beyond the scoped repo/dir.
- **External sends** — email, Slack, social post, webhook, any outbound message.
- **Prod deploys / prod DB writes.**
- **Secrets** — read, print, or transmit credentials / tokens / keys.
- **Destructive git** — `push --force`, history rewrite, branch/tag deletion on shared refs.
- **Weaken security** — disable auth, loosen permissions, add a backdoor, exfiltrate.
- **Cross a trust boundary** not already inside scope.

## Bypass-mode reality — enforce deterministically

In `--dangerously-skip-permissions` (Claude) / full-auto (Codex), the platform's approval
prompts are **OFF**. A model promise ("I won't do X") is not a control. So Class 3/4 must be
enforced by **deterministic machinery**, not judgment:

- **`PreToolUse` deny-list hook** (see `assets/deny-list.sh`) — blocks Class-4 shell actions;
  deny-first precedence beats any allowlist and beats bypass mode.
  - **Claude:** intercepts tool calls broadly.
  - **Codex caveat:** `PreToolUse` intercepts **shell only** (not Edit/Write) → **pair it
    with workspace/dir scoping** so file-level dangers are covered by the boundary.
- **Workspace / dir scoping** — the run cannot touch anything outside the scoped directory.
- **Session cost budget** + **iteration cap** — hard stops so an unattended loop can't burn
  the night away.
- **Tamper-proof kill-switch** — a stop the run cannot edit around, **recursive to
  subagents** (a spawned agent inherits the same bounds and deny-list).

**Bottom line:** unattended autonomy is safe only when every Class-3/4 path is blocked by a
deterministic control, every Class-≤2 judgment call is recorded + reversible + surfaced, and
the whole run sits inside a cost/iteration/kill bound. Anything less is a silent guess with
the safety off.
