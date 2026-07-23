---
name: writing-goals
description: Use when writing a `/goal` or completion condition, when making an agent keep working unattended toward an outcome, when a goal or loop needs a verifiable stop condition or iteration cap, when a large objective must be broken into chained sub-goals run in sequence or parallel, or when an autonomous / full-auto run needs safety guardrails. For Codex `/goal`.
---

# Writing Goals

## Overview

A `/goal` is only as trustworthy as **a stop condition a fresh checker can verify without believing the doer.**

**Core principle:** the maker never certifies its own completion; every goal ends at observable evidence, inside hard bounds; and anything that can't be verified is never guessed.

**Codex-specific reality that shapes everything:** Codex's `/goal` completion is **model-declared** — the agent itself calls `update_goal("complete")`; the harness does not independently run your tests to confirm it. So a bare "tests pass" is self-report, not proof. Real verification comes from the doer running the check and pasting raw output, or from a `Stop` hook that actually runs it (see `shared/gates.md` + "Codex specifics" below). The native completion signal is a **weak checker** — treat it as such.

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
4. **Gate it.** Offer the deterministic `Stop` hook for unattended runs; always bound it with a persisted counter. → `shared/gates.md` + "Codex specifics" below.
5. **Big objective? Decompose + chain** into atomic `.goals/*.md` files with a dependency DAG and a resumable run-loop. → `shared/chaining.md`
6. **Unattended / full-auto mode? Apply the autonomy policy + guardrails.** → `shared/autonomy.md`, `shared/modes.md`

## Anti-gaming — the gate must not be foolable

- The gate command must be **run and its raw output + exit code surfaced** — never paraphrased or asserted.
- **Forbid** editing, skipping, xfailing, or deleting the verification surface to reach green.
- A green **build / typecheck / lint ≠ the feature works.** Gate on behavior, or state plainly that the gate is a weaker proxy.
- A goal without a machine-checkable gate is malformed — do not set it.

## Always bounded

Every goal (and chain) carries three stops: **success** (evidence-based end state), **failure** (same check fails N times / blocked / needs-human), and a **hard cap** (iterations + cost/time). An unbounded loop is a cost risk, not automation.

## Codex specifics

*(Hook mechanics below were verified by live smoke-test on codex-cli **0.144.1**, 2026-07-23.)*

- **Invoke this skill** as `$writing-goals`, via the `/skills` picker, or let it auto-trigger by description. Codex has **no typed `/name`** for skills.
- **Frontmatter is `name` + `description` ONLY.** UI metadata and manual-invocation policy (`allow_implicit_invocation: false`) live in `agents/openai.yaml`, never in frontmatter.
- Condition is **free-text, ≤ 4000 chars**. Lifecycle: `/goal`, `/goal edit`, `/goal pause`, `/goal resume`, `/goal clear`. Native completion is **model-declared** (`update_goal("complete")`) — a weak checker; gate real verification.
- **Hooks** live in **`.codex/hooks.json`** (project-relative, auto-discovered): `{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"<abs path>"}]}]}}`. Events are **PascalCase** (`Stop`, `PreToolUse`, `SessionStart`, `UserPromptSubmit`, `PostToolUse`, `SubagentStop`, …). Hooks are **on by default** but must be **trusted** — via the `/hooks` trust flow, or `--dangerously-bypass-hook-trust` for vetted automation. `matcher` is optional; only `type:"command"` handlers run today.
- **`Stop`-hook block contract (verified 0.144.1 — it genuinely BLOCKS, not notify-only):** emit **`{"decision":"block","reason":"…"}` on stdout + exit 0** to keep the agent working (the `reason` is fed back); a **clean exit 0 with no stdout** allows the stop. `exit 2` + stderr also blocks. **This matches the Claude contract** — so `assets/gate.codex.sh` is `gate.claude.sh` with one change: it reads the repo root from the stdin **`cwd`** field (Codex sets no `CLAUDE_PROJECT_DIR`). Stop-hook stdin also carries `session_id`, `transcript_path`, `stop_hook_active`, `last_assistant_message`.
- **`PreToolUse`** on Codex intercepts **shell only** (not Edit/Write) → **pair the deny-list with workspace/dir scoping** so file-level dangers are covered. Its stdin is Claude-shaped (`tool_name:"Bash"`, `tool_input.command`, plus an authoritative `cwd`), so the shared **`assets/deny-list.sh`** can be reused — but two things it leans on are **inferred, not yet smoke-tested** on Codex: that the hook runs with cwd = repo root (it derives the root from `$PWD`, since Codex sets no `CLAUDE_PROJECT_DIR`), and that Codex honors the JSON `permissionDecision:"deny"` output (only the exit-2 block is platform-confirmed). Confirm both before an unattended run — or point its repo root at the stdin `cwd`.
- Unattended = pair with full-auto mode. The **`PreToolUse` deny-list is a best-effort backstop against footguns, NOT a boundary** against an adversarial or prompt-injected agent — string-matching over shell can always be defeated. The real boundary is an **OS-level sandbox** (container/VM, read-only mounts outside the repo, non-root, dropped caps, egress only via an allowlisting proxy); the deny-list + gate are extra layers inside it. → `shared/autonomy.md`

## Quick reference

| Need | Do |
|---|---|
| One goal | investigate → classify facts → author (slice+gate+DoD+evidence+bounds) → gate |
| A number/threshold you don't have | MUST-ASK — stop or propose-and-checkpoint; never invent an absolute |
| A test command you haven't confirmed | DERIVE-then-CONFIRM — read config / dry-run collect; if none, stop (vacuous gate) |
| A big objective | decompose to `.goals/*.md` DAG → ledger run-loop → gated chain |
| Unattended run | OS-level sandbox (the real boundary) + strongest gate + bounds + `PreToolUse` deny-list backstop + assumption ledger |

## Red flags — STOP

- "The lead said use pytest, I'll just gate on that" → unverified command (vacuous-gate risk)
- "A sensible default target is fine" → invented absolute number
- "It's just a platformer / CRUD app, I know what it needs" → **invented spec** (the #1 failure)
- "I'll note it's unverified" → a note is not a control on a loop no one is watching
- "Make progress now > get the spec" → progress on a guessed spec is negative progress

**All of these mean: the fact is MUST-ASK. Stop and ask, or propose-and-checkpoint. Do not arm the loop.**

## Common mistakes

- **Vacuous gate:** gating on a test suite that doesn't exist / doesn't cover the change → the completion signal reads green having done nothing.
- **Self-graded goal:** trusting the native model-declared completion (weak) instead of surfacing real evidence or using a `Stop` hook.
- **Unbounded chain:** no failure stop or hard cap → runs all night, burns budget.
- **Trusting the ledger:** a chain that believes a prior goal's "done" instead of re-verifying its gate at entry.

## References (load when needed)

- `shared/investigate.md` — zero-assumption repo discovery
- `shared/author-goal.md` — goal anatomy + condition templates + evidence rules
- `shared/gates.md` — gate concepts (Layer-1 condition gate · Layer-2 hook gate · out-of-repo iteration counter · anti-gaming). Its *wiring examples are Claude-specific* (`.claude/settings.json`, `$CLAUDE_PROJECT_DIR`); for Codex use the `.codex/hooks.json` + `decision:block` + stdin-`cwd` details in "Codex specifics" above.
- `shared/chaining.md` — decompose → `.goals/*.md` schema → DAG → resumable run-loop → escalation
- `shared/autonomy.md` — 5-class action model + decide-and-log ledger + deny-list
- `shared/modes.md` — human-gated / autonomous driver / full-auto
