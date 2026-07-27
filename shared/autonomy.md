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
| **1** reversible + repo-local | undoable, in-workspace, ~free (edit a file; commit only with user or repository-policy authority) | **AUTO** — log if it resolved an ambiguity |
| **2** reversible but wide | big blast radius / effortful undo (mass rename, dependency bump, schema migration on a scratch DB) | **AUTO + checkpoint** |
| **3** irreversible / external / costs money / crosses trust boundary | prod deploy or DB write, any external send, payment, delete **outside** the repo, **changing the top objective / acceptance criteria** | **EXPLICIT BOUNDED HUMAN AUTHORIZATION** |
| **4** prohibited unattended | on the deny-list below | **DENY DURING UNATTENDED EXECUTION** |

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

If the fork is **Class 3** → stop until explicit, bounded human authorization names the action,
target, limit, and validity window. If **Class 4** → deny during unattended execution and hand the
controlled workflow to a human. A `MUST-ASK` fact (an absolute threshold, the definition of done, a decomposition
spec) is never auto-resolved this way — decide-and-log is for reversible judgment calls,
not for inventing facts.

## Unattended deny-list (Class 4 — evaluated FIRST)

Deny is checked **before** any allowlist and **applies to unattended execution even in bypass
mode** — as a
*classification rule the agent obeys*, not a guarantee the string-matching hook can enforce
against an adversary (see "the sandbox is the boundary" below). The unattended agent cannot
confirm these actions into permission; a human must use a separately controlled workflow.

- **Spend money** — purchases, paid API calls beyond budget, provisioning billable resources.
- **Delete or modify outside the workspace** — anything beyond the scoped repo/dir.
- **External sends** — email, Slack, social post, webhook, any outbound message.
- **Prod deploys / prod DB writes.**
- **Secrets** — read, print, or transmit credentials / tokens / keys.
- **Destructive git** — `push --force`, history rewrite, branch/tag deletion on shared refs.
- **Weaken security** — disable auth, loosen permissions, add a backdoor, exfiltrate.
- **Cross a trust boundary** not already inside scope.

## Unattended permission modes — the sandbox is the boundary

When an unattended permission mode turns interactive approvals off, a model promise ("I won't do
X") is not a control — but neither is a string-matching lifecycle policy. Be honest about what
each layer actually buys.

**The hooks are a best-effort, defense-in-depth backstop against footguns — NOT a security
boundary.** The `PreToolUse` deny-list and the Stop-hook gate catch a **cooperative** agent's
naive or accidental mistakes (a stray `rm -rf`, an unthinking force-push). They do **not**
contain an **adversarial or prompt-injected** agent. Regex-over-shell is structurally
unsound: interpreters (`python -c`, `node -e`), quoting and `$IFS` tricks, newlines, writes
under `$HOME`, and exfiltration through an allowlisted host all slip past string-matching. A
determined agent **will** defeat the deny-list. Treat it as a seatbelt, not a vault.

**The real boundary for unattended / bypass-mode autonomy is an OS-level sandbox** — run the
whole agent inside one:

- a **container or VM**, disposable, so a breakout damages nothing that matters;
- **read-only mounts** for everything outside the working repo;
- a **non-root user** with **dropped capabilities**;
- **no ambient network egress** — deny by default; allow only through an **allowlisting
  egress proxy** you control.

The deny-list and gate sit *inside* that sandbox as **extra layers** that cut noise and catch
honest mistakes — **not instead of it**. If the only thing between an unattended agent and
your production network is a bash regex, you have no boundary.

**The hardened scripts fail closed on uncertain tool input and invalid gate state.** The gate
counter should live outside the repository, but it is tamper-resistant only when sandbox
permissions prevent the worker from writing that state directory. Location alone is not a
control. This raises the bar against accidental bypass; it does not make string matching sound
against an adversary.

Inside the sandbox, the deterministic layers still earn their place:

- **`PreToolUse` deny-list hook** (`assets/deny-list.sh`) — fail-closed block of the tool inputs it
  recognizes. Coverage and exceptions are platform facts documented in each adapter.
- **Workspace / dir scoping** — belt-and-braces with the sandbox's read-only mounts.
- **Session cost budget** + **iteration cap** — hard stops so an unattended loop can't burn
  the night away.
- **Sandbox-protected gate counter + kill-switch** — keep state outside the repository and deny
  worker writes to its state directory; apply the same bounds and policy to subagents.

**Bottom line:** unattended autonomy is safe only **inside an OS-level sandbox**. Within it,
every Class-≤2 judgment call is recorded + reversible + surfaced, the run sits inside a
cost/iteration/kill bound, and the deny-list + gate add a best-effort footgun-catching layer.
The hooks are the backstop; the sandbox is the boundary. Anything less is a silent guess with
the safety off.
