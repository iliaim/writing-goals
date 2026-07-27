---
name: writing-goals
description: Use when writing a Claude Code goal or completion condition, running bounded unattended work, or decomposing a large objective into verifiable sub-goals.
---

# Writing goals for Claude Code

Follow `shared/method.md` completely. It is the canonical method. Load its linked shared
references as the task requires; this adapter adds no policy.

## Invoke and trust

- Invoke as `/writing-goals`; use `/goal <condition>` for Claude's session-scoped goal.
- `/goal` requires a trusted workspace and the hooks system. Managed `disableAllHooks` makes it
  unavailable.
- Project hooks live in `.claude/settings.json`. Review hook source before trusting it; unattended
  permission modes do not turn a hook into a security boundary.

## Current Claude platform facts

- A `/goal` condition is limited to **4,000 characters**. Its evaluator reads the conversation
  rather than running tools, so require surfaced evidence or use a deterministic command Stop
  hook.
- Stop-hook input includes `stop_hook_active`, which is true when Claude is already continuing
  because a Stop hook blocked. Claude overrides a Stop hook after **eight consecutive blocks**.
  Keep the repository's lower explicit cap authoritative.
- A command Stop hook blocks with exit 0 and
  `{"decision":"block","reason":"..."}` on stdout (or exit 2 plus stderr); clean exit 0 with no
  block allows stopping. Use `assets/gate.claude.sh`.

Sources: [Claude goal documentation](https://code.claude.com/docs/en/goal) and
[Claude hooks reference](https://code.claude.com/docs/en/hooks).
