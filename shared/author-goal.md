# Author-goal — goal anatomy + templates

You've investigated (`shared/investigate.md`) and classified every fact. Now assemble the goal. A
goal a fresh checker cannot verify without believing the doer is malformed — don't set it.

## Anatomy — five parts, all required

A well-formed goal =

1. **One vertical slice** — a single thin end-to-end outcome, not a horizontal layer and not a grab-bag.
2. **A pre-written gate** — the **strongest available** verification surface (from investigate), named
   *before* work starts so it can't be reverse-engineered to fit whatever got built.
3. **Inherited project Definition-of-Done** — the repo's existing bar (lint/typecheck/CI green) rides
   along; the slice's own gate is *added* to it, never *instead of* it.
4. **An evidence requirement** — **run the gate, paste the raw output + exit code.** Never paraphrase,
   never assert "tests pass." The transcript-only evaluator judges what you *surface*; a paraphrase is
   self-report, not proof.
5. **Complete stop rules** — concrete **success**, **failure**, maximum **iterations**, **cost**, and
   **wall-clock** bounds. An unbounded goal is a cost risk.

## Condition template (the goal block)

```
Done when:     <outcome> — <gate> passes on <the specific thing>
Also green:    <repo DoD cmds — lint / typecheck / CI> still pass (inherited Definition-of-Done)
Scope:         only edit <paths>; do NOT touch <verification surface / other packages / config>
Verification:  run <exact cmd>; paste the raw output block + exit code (`echo $?`) — not a cherry-picked last line
Stop:          success = <gate green, output pasted>
               failure = same check fails N× → stop, report blocked (do NOT edit the test)
               max_iterations = <N>; max_cost = <currency/tokens>; max_wall_clock = <duration>
               stop before <high-risk / irreversible action>
```

**Compressed one-line form** (when the slice is small):

```
Done when <cmd> shows <specific result>; <repo DoD — lint/typecheck/CI> still green; only edit <paths>; paste raw output block + exit code (`echo $?`); stop after N fails, M iterations, <cost>, or <wall-clock>.
```

Both forms must survive the second-agent test below. Platform-specific limits and invocation live
only in the relevant adapter.

## Good vs bad

| Bad (unverifiable) | Good (gated + bounded) |
|---|---|
| "Improve coverage" | "Coverage **≥ \<TARGET the human gave\>** per `pytest --cov`, raw output pasted; only edit `src/`; stop after 3 no-gain iters." |
| "Make it faster" | "p95 **≥ 30% below** the committed `BASELINE.md`, `bench` output attached; stop before touching the datastore." |

- **"Improve coverage" → the absolute % is MUST-ASK.** Never invent 80%. The *command* (`pytest --cov`)
  is DERIVE-then-CONFIRM; the *number* comes from the human. No number → STOP or propose-and-checkpoint.
- **"Make it faster" → a relative default is OK if logged.** "≥30% below a committed baseline" is
  self-contained and checkable; an absolute p95 SLA would be MUST-ASK. Record the relative choice in the
  assumption ledger so the human can override.

## The second-agent test — mechanical checklist

Before you set the goal, ask: **could a fresh agent, seeing only the goal + the pasted output, confirm
done — without trusting me?** The gate must name all three:

| # | The gate names… | Blank means |
|---|---|---|
| 1 | an **exact command** (copy-pasteable, scoped) | vacuous gate — "run the tests" isn't a command |
| 2 | a **specific string / exit code / number** to match | "it passes" is self-report, not a criterion |
| 3 | a **bound** (success + failure + cap) | unbounded loop — burns budget all night |

**Any blank → not done. Do not set the goal.** Fix the blank (usually: go back and MUST-ASK a number,
or re-read config for the real command) first.

## Anti-gaming reminders

- Gate on **behavior**; if only a proxy exists (build/typecheck/lint), state plainly that it's a weaker
  proxy — don't dress it up as behavioral.
- **Forbid** editing, skipping, xfailing, or deleting the verification surface to reach green — encode
  that in `Scope: do NOT touch`.
- Raw output **+ exit code**, every time. Paraphrased success is the enemy the transcript evaluator
  can't catch.
