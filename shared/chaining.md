# Chaining — turn a big objective into a gated chain

Loaded by the method when one `/goal` can't hold the work. A chain is a **DAG of atomic
`.goals/*.md` files** run by a **resumable ledger loop**, where every node ends at a
machine-checkable gate a fresh checker verifies. Same spine as one goal: *the maker never
certifies its own completion; every node is bounded; nothing unverifiable is guessed.*

## 0. Chain, or don't

- **Chain** when the objective needs multiple gated slices, or parallel branches, or spans
  more than one session (must be resumable).
- **One goal** when a single vertical slice + gate covers it. Don't shard a small task into
  a `.goals/` tree — over-decomposition is a failure too.

## 1. Decompose from a REAL spec — the #1 discipline failure

**A one-line request is NOT a spec.** "Build the platformer / the CRUD app / the dashboard"
tells you nothing verifiable. The scope/spec of a decomposition is **MUST-ASK**: you may not
invent features, screens, endpoints, or acceptance criteria to fill the gap.

- **No spec → STOP.** Either get one, or **propose-and-checkpoint**: write a proposed spec
  (objectives, in/out of scope, acceptance) and get a cheap human OK *before* building.
- **Never build unattended on an invented spec.** Progress on a guessed spec is negative
  progress — you'll have to tear it out. A note ("assuming a jump mechanic") is not consent.

## 2. Stop-splitting rule — "is this leaf machine-verifiable?"

Split until every leaf has an `acceptance[]` a fresh agent could confirm from output alone —
**not** until leaves are merely "small". A tiny-but-unverifiable leaf is still malformed.

- **Shallow-stable, capped depth.** Prefer a wide shallow tree; cap recursion depth (~3) so
  the plan stays legible and re-plannable.
- **Walking-skeleton first.** Goal 1 = the thinnest **end-to-end runnable** slice (it builds,
  starts, and passes one trivial real check) — never a horizontal layer (all the models, or
  all the CSS) that runs nothing.
- Then **vertical slices**, **one feature per goal**. Each goal ends with a short progress note
  (what shipped, gate output, decisions) and, only when user or repository policy authorizes it,
  a commit.

## 3. `.goals/` layout — objective separate from plan

```
.goals/
  _objective.md     # IMMUTABLE: top objective + acceptance + global stop rules + autonomy policy
  <id>.md           # one file per sub-goal (schema below)
  ...
```

- **`_objective.md` is immutable** and stored **separately** from the mutable plan. The plan
  (the set of sub-goal files) churns as you replan; the objective does not.
- **Recursion is the filesystem** — a sub-goal that needs breaking down becomes its own set of
  sub-goal files linked by `depends_on`, **never** a nested array inside one file. One node =
  one file.

### `_objective.md` skeleton

The anti-drift check (§7) traces every sub-goal back to this file, so it must exist before any
sub-goal runs:

```
---
objective: <one sentence — the observable end-state the whole chain delivers>
acceptance:                       # chain is DONE only when EVERY line verifies fresh-context
  - "<top-level check + pass signal>"
  - "<...>"
stop_rules:                       # global bounds every sub-goal inherits
  max_iterations: <N>             # hard cap across the whole chain
  max_cost: <$ / tokens>          # budget kill
  max_wallclock: <duration>       # time kill
  on_block: escalate-to-human     # retry → replan → single-owner → human (§8)
autonomy_policy: shared/autonomy.md   # 5-class model + deny-list the run obeys
---

# <objective title>

<Why this matters + the hard constraints that must not regress. IMMUTABLE — changing it is a
Class-3 human checkpoint (§7), never an unattended rewrite to make the plan "fit".>
```

### Sub-goal frontmatter schema

| Field | Req? | Meaning |
|---|---|---|
| `id` | required | stable node key; DAG references use it |
| `title` | required | one-line human name |
| `status` | required | `todo` \| `in_progress` \| `blocked` \| `in_review` \| `done` \| `cancelled` — drives the run-loop & resume |
| `depends_on[]` | required | ids this waits on; DAG edges (cycle-checked) |
| `acceptance[]` | required | the verifiable gate; done only when **all** pass |
| `stop_rules` | required | concrete success, failure, max iterations, max cost, and max wall-clock for this node |
| `parallelizable` | recommended | may run concurrently with disjoint-artifact siblings |
| `owner` | recommended | which agent/role executes |
| `priority` | recommended | ordering hint within the ready frontier |
| `artifacts[]` | recommended | files this goal writes → proves parallel goals don't collide |
| `risk` | optional | `low` \| `medium` \| `high` → maps to autonomy tier |
| `updated` | optional | last-touched date |

Template: `assets/goal.md.tmpl`.

## 4. DAG + parallelism

- Edges come from **`depends_on`**; the plan is a **DAG, cycle-checked** before any run (a
  cycle = malformed plan → stop).
- Disjoint `artifacts[]` are **necessary but insufficient** for parallelism. Branches must also
  have no semantic or runtime dependency, have enough independent review capacity, and declare
  an integration order. The **single-writer rule** still applies: no file has two concurrent
  writers. Interdependent or shared-write work stays single-threaded.
- Parallel branches run in **isolated git worktrees**, **cap 3–5** concurrent. Merge each
  branch back and re-verify before continuing.

## 5. Ledger run-loop (resumable)

```
loop:
  frontier = goals where status==todo AND every depends_on is done
  if frontier empty: break (done, or blocked → escalate)
  pick highest-priority ready goal → status:in_progress → execute
  fresh-context VERIFY (checker ≠ maker: re-run acceptance, surface raw output+exit)
  pass → status:done ; fail → status:blocked/todo per escalation ramp
  recompute frontier
```

- **The files are the state.** A restart / crash / new session recovers by **re-reading the
  `.goals/` files** — no in-memory plan to lose. That is what "resumable" means here.
- Verification is **fresh-context**: the agent that verifies is not the one that made the
  change, and it re-runs the gate rather than trusting a claim.
- **Where `in_review` / `cancelled` enter:** the maker sets **`in_review`** when it finishes
  but before the fresh-context verify signs off (the handoff between `execute` and `VERIFY`
  above — explicit whenever a review checkpoint sits between maker and checker, e.g.
  human-gated mode); the verifier then moves it to `done` or back to `todo`/`blocked`.
  **`cancelled`** is a terminal state set during replan (§6–§7) when a sub-goal no longer
  serves any `_objective.md` acceptance line — the frontier skips it and it never counts as
  `done`.

## 6. Between goals — reflect + replan from real state

- **Replan from REAL repo state**, not from the plan you imagined. Read what actually landed.
- **Fix-before-feature:** if the last goal introduced a regression, the next goal is the fix —
  regressions outrank new features.
- **Entry re-verify:** before building on a dependency, **re-run the previous goal's gate**.
  Never trust the ledger's `done` — a stale/optimistic mark is exactly the failure mode.

## 7. Anti-drift

- Every replanned sub-goal must **trace back to `_objective.md`** (its acceptance serves some
  objective acceptance). A sub-goal that serves nothing in the objective is scope creep — cut
  it.
- **Changing the objective is a human checkpoint** (Class-3 action) — never rewrite
  `_objective.md` unattended to make the plan "fit".

## 8. Bounded escalation ramp (guaranteed termination)

A blocked goal climbs a fixed ladder — it never loops forever:

```
retry (transient?) → replan (wrong approach?) → single-owner (serialize contested work)
  → human (needs a decision/secret/spec)
```

- **Hard caps** on iterations **and** cost **and** wall-clock — hitting any cap stops the chain.
- **De-dup identical actions:** if the next action equals one already tried with no change in
  repo state, that's **no-progress → escalate**, not re-retry. Re-running the same failing
  command is not iteration.

## See also

- `shared/author-goal.md` — the per-goal anatomy each node instantiates
- `shared/gates.md` — the deterministic gate a node's `acceptance[]` runs behind
- `shared/autonomy.md` — the 5-class action model behind the escalation ramp & Class-3 stops
