# writing-goals

A global, agent-agnostic skill that turns intent into **rigorous, verifiable goals** for the `/goal` command — and decomposes large objectives into a **gated, resumable chain** of atomic goals that can run autonomously and safely.

Built for **Claude Code** today; **Codex** and other agents are additive adapters over a shared, platform-neutral core.

## Core principle

> A `/goal` is only as trustworthy as **a stop condition a fresh checker can verify without believing the doer.**

The maker never certifies its own completion; every goal ends at observable evidence, inside hard bounds; and anything that can't be verified is never guessed.

## Install

```bash
./sync.sh claude    # symlinks the skill into ~/.claude/skills/writing-goals
# then, in a fresh Claude Code session:  /writing-goals
```

`sync.sh` symlinks (single source of truth = this folder), so edits here propagate live. `./sync.sh codex` installs the Codex adapter once it exists.

## What's inside

| Path | Purpose |
|---|---|
| `claude/SKILL.md` | Claude adapter — navigator + discipline core |
| `shared/` | platform-neutral references: `investigate`, `author-goal`, `gates`, `chaining`, `autonomy`, `modes` |
| `assets/` | `gate.claude.sh` (Stop-hook + iteration counter), `deny-list.sh` (PreToolUse tier-4 safety), `goal.md.tmpl` |
| `sync.sh` | symlink installer (Claude / Codex) |
| `PLAN.md` | full design + research provenance |

## What it does

- **Authors one verifiable goal** — investigate the repo (zero-assumption), classify each fact as *must-ask* vs *derive-then-confirm*, then produce a goal = one slice + a pre-written gate + inherited Definition-of-Done + an evidence requirement + three bounds (success / failure / hard cap).
- **Decomposes a big objective** into atomic `.goals/*.md` files with a dependency DAG, a resumable ledger run-loop, and safe parallelism (disjoint artifacts, single-writer, isolated worktrees).
- **Runs autonomously and safely** — a 5-class action model, decide-and-log for reversible choices, and a deterministic `PreToolUse` deny-list that holds even in bypass/full-permission mode.

## Status

- **Claude adapter:** complete, validated (RED → GREEN → REFACTOR).
- **Codex adapter:** planned (`~/.agents/skills/`; `name`+`description` frontmatter only + `agents/openai.yaml`).
- **Distribution (plugin / CLI / MCP), Hermes + other adapters:** later, additive.

## How it was built

Test-driven, following the `superpowers:writing-skills` method: baseline pressure scenarios *without* the skill (to find real failure modes), then a minimal skill addressing them, then adversarial refactor probes until it held under maximum pressure. See `PLAN.md`.
