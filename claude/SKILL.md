---
name: writing-goals
description: Use when writing a `/goal` or completion condition, when making an agent keep working unattended toward an outcome, when a goal or loop needs a verifiable stop condition or iteration cap, when a large objective must be broken into chained sub-goals run in sequence or parallel, or when an autonomous / bypass-mode run needs safety guardrails. For Claude Code `/goal`.
---

# Writing Goals

## Overview

A `/goal` is only as trustworthy as **a stop condition a fresh checker can verify without believing the doer.**

**Core principle:** the maker never certifies its own completion; every goal ends at observable evidence, inside hard bounds; and anything that can't be verified is never guessed.

**Claude-specific reality that shapes everything:** Claude's `/goal` evaluator reads the **transcript only — it runs no tools.** So the goal is judged solely on what the doer *surfaces*; a bare "tests pass" is self-report, not proof. Real verification comes from the doer running the check and pasting raw output, or from a Stop-hook that actually runs it (see `shared/gates.md`). The native evaluator is a **weak checker** — treat it as such.

**Violating the letter of these rules is violating their spirit.** "I noted it's unverified" / "a sensible default is fine" / "it's just a small assumption" are all violations.

## When to use — triage first

```
Multi-turn, unattended, or a verifiable end-state worth enforcing?  → write a goal.
One-shot, you can describe the diff in a sentence?                  → just do it, no goal.
```
Don't wrap a trivial task in a goal. Over-goaling is a failure too.

## The method

1. **Investigate the repo (zero-assumption).** Find the real verification surfaces + exact commands, determinism, and scope by *reading* config (package.json, Makefile, CI, pyproject…). Confirm presence by reading, not by running side-effectful commands. → `shared/investigate.md`
2. **Classify every fact — the line that matters most:**
   - **MUST-ASK (never invent, even under pressure):** absolute business targets (latency SLA, coverage %, "fast enough"), the definition of "done", constraints that must not regress, and **the scope/spec of a decomposition — a one-line request is NOT a spec.** Missing → STOP and ask, or *propose-and-checkpoint*; never arm an unattended loop on an invented fact.
   - **DERIVE-then-CONFIRM (detect, then confirm; log if it resolved ambiguity):** the test/build command, file paths, *relative* improvement targets, iteration caps.
3. **Author the goal** = one verifiable slice + a **pre-written gate** + inherited project Definition-of-Done + an **evidence requirement** + hard bounds. → `shared/author-goal.md`
4. **Gate it.** Offer the deterministic Stop-hook for unattended runs; always bound it with a persisted counter. → `shared/gates.md`
5. **Big objective? Decompose + chain** into atomic `.goals/*.md` files with a dependency DAG and a resumable run-loop. → `shared/chaining.md`
6. **Unattended / bypass mode? Apply the autonomy policy + guardrails.** → `shared/autonomy.md`, `shared/modes.md`

## Anti-gaming — the gate must not be foolable

- The gate command must be **run and its raw output + exit code surfaced** — never paraphrased or asserted.
- **Forbid** editing, skipping, xfailing, or deleting the verification surface to reach green.
- A green **build / typecheck / lint ≠ the feature works.** Gate on behavior, or state plainly that the gate is a weaker proxy.
- A goal without a machine-checkable gate is malformed — do not set it.

## Always bounded

Every goal (and chain) carries three stops: **success** (evidence-based end state), **failure** (same check fails N times / blocked / needs-human), and a **hard cap** (iterations + cost/time). An unbounded loop is a cost risk, not automation.

## Claude specifics

- Condition **≤ 4000 chars**; add `or stop after N turns` (soft — the evaluator judges it, it is not a hard kill).
- Hard stops: `/goal clear`, Ctrl+C, or a Stop-hook that exits clean at the cap.
- Deterministic gate: `.claude/settings.json` `Stop` hook → `{"decision":"block","reason":…}` keeps looping (reason fed back); clean exit 0 allows stop. Bound with a persisted counter + `stop_hook_active` guard. → `shared/gates.md`
- Unattended = pair with auto/bypass mode; then tier-3/4 safety must be a deterministic **`PreToolUse` deny-list** (deny wins even in bypass). → `shared/autonomy.md`
- Invoke this skill as `/writing-goals`.

## Quick reference

| Need | Do |
|---|---|
| One goal | investigate → classify facts → author (slice+gate+DoD+evidence+bounds) → gate |
| A number/threshold you don't have | MUST-ASK — stop or propose-and-checkpoint; never invent an absolute |
| A test command you haven't confirmed | DERIVE-then-CONFIRM — read config / `--collect-only`; if none, stop (vacuous gate) |
| A big objective | decompose to `.goals/*.md` DAG → ledger run-loop → gated chain |
| Unattended run | strongest gate + bounds + `PreToolUse` deny-list + assumption ledger |

## Red flags — STOP

- "The lead said use pytest, I'll just gate on that" → unverified command (vacuous-gate risk)
- "A sensible default target is fine" → invented absolute number
- "It's just a platformer / CRUD app, I know what it needs" → **invented spec** (the #1 failure)
- "I'll note it's unverified" → a note is not a control on a loop no one is watching
- "Make progress now > get the spec" → progress on a guessed spec is negative progress

**All of these mean: the fact is MUST-ASK. Stop and ask, or propose-and-checkpoint. Do not arm the loop.**

## Common mistakes

- **Vacuous gate:** gating on a test suite that doesn't exist / doesn't cover the change → judge sees green having done nothing.
- **Self-graded goal:** trusting the native evaluator (transcript-only, weak) instead of surfacing real evidence or using a Stop-hook.
- **Unbounded chain:** no failure stop or hard cap → runs all night, burns budget.
- **Trusting the ledger:** a chain that believes a prior goal's "done" instead of re-verifying its gate at entry.

## References (load when needed)

- `shared/investigate.md` — zero-assumption repo discovery
- `shared/author-goal.md` — goal anatomy + condition templates + evidence rules
- `shared/gates.md` — deterministic Stop-hook scaffold + iteration counter (Claude)
- `shared/chaining.md` — decompose → `.goals/*.md` schema → DAG → resumable run-loop → escalation
- `shared/autonomy.md` — 5-class action model + decide-and-log ledger + deny-list
- `shared/modes.md` — human-gated / autonomous driver / full-auto
