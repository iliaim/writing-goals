---
name: writing-goals
description: Use when writing a Claude Code goal or completion condition, running bounded unattended work, or decomposing a large objective into verifiable sub-goals.
---

# Writing goals for Claude Code

Follow `shared/method.md` completely. It is the canonical method. Load its linked shared
references as the task requires; this adapter adds only Claude-native integration instructions.

## Invoke and trust

- Invoke as `/writing-goals`; use `/goal <condition>` for Claude's session-scoped goal.
- For non-interactive execution, invoke `claude -p "/goal <condition>"`. The
  `--dangerously-skip-permissions` flag disables interactive approvals; use it only inside the
  sandbox required by `shared/autonomy.md`.
- `/goal` requires a trusted workspace and the hooks system. Managed `disableAllHooks` makes it
  unavailable.
- Project hooks live in `.claude/settings.json`. Review hook source before trusting it; unattended
  permission modes do not turn a hook into containment. Stop and PreToolUse hooks are cooperative
  backstops, not a security boundary. Run unattended work in an OS-level sandbox (for example,
  a `sandbox-exec` profile where available) with only the intended writable source paths.

## Current Claude platform facts

- A `/goal` condition is limited to **4,000 characters**. Its evaluator reads the conversation
  rather than running tools, so require surfaced evidence or use a deterministic command Stop
  hook.
- Stop-hook input includes `stop_hook_active`, which is true when Claude is already continuing
  because a Stop hook blocked. By default, Claude overrides the hook after **eight consecutive blocks without progress**. Keep `GOAL_GATE_CAP <= 8`, unless
  `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` is deliberately raised to at least the chosen repository cap.
- A command Stop hook blocks with exit 0 and
  `{"decision":"block","reason":"..."}` on stdout (or exit 2 plus stderr); clean exit 0 with no
  block allows stopping. Use `assets/gate.claude.sh`.
- A reported Claude Code bug can bypass pre-use policies after some background-task completions;
  this is another reason the sandbox, not the hook, is the boundary.

## Native Claude goal

For a run that warrants a native Claude goal, set one `/goal` condition for the complete
objective/run. Keep it below the platform's 4,000-character limit and make it a concise,
user-legible completion contract:

If asked to set the goal yourself, inspect the current session, repository guidance, working tree,
tests, and exact verification surface first. Then write the contract from those observed facts;
use a decision packet and ask before committing when a material intent, target, or risk remains
ambiguous.

When monitoring a running goal, make each status check one concise sentence stating the current
activity, whether the run remains on track, and the next gate.

```text
Objective: <single completed outcome>

Read first: <exact repository files, issue, specification, or decision record>

Scope:
- Included: <bounded behaviors, components, or users>
- Excluded: <explicit non-goals>

Constraints: <what must not change, including unrelated refactors, dependencies, interfaces, or data>

Document: <focused documentation to update, or not applicable with a reason>

Details (optional): `<stable workspace-relative path to the persisted contract or frozen plan>`

Given:
- <material starting condition>

When:
- <completed user action or state transition>

Then all of the following are true:
- <independently observable criterion>
- <authorization, edge-case, compatibility, or regression criterion>
- Automated proof: `<exact command>` exits 0 and <relevant pass signal>.
- Manual proof: <specific expected observation>, when automation cannot establish a criterion.
Checkpoint: <one-sentence status summarizing the persisted checkpoint: current phase, exact evidence observed, next gate, and blocker/decision>
Stop when: <all criteria and proof pass>, OR <human/product, irreversible, external, new dependency/ADR, or changed-objective input is required>
```

Every `Then` criterion is cumulative and parent-level: do not treat the goal as complete because
implementation began, a subset passes, or child slices are complete. For a full plan, derive these
criteria from the frozen `objective_acceptance`. State concrete outputs, access decisions, files,
responses, or other observable signals; never use vague criteria such as “works correctly.”
`Details` is navigation only: Claude's evaluator cannot read it independently, so it may explain a
criterion but never replace one, redefine scope, or become lifecycle authority. Claude evaluates
the conversation rather than rerunning tools, so surface the exact command, exit status, and
relevant output in the conversation. For unattended or full-tier work, use
`assets/gate.claude.sh` as the deterministic verification gate; the `/goal` condition is not
independent execution evidence. Keep implementation steps, alternatives, per-slice checks, and
lifecycle receipts in the contract or protected plan rather than the native goal. Do not use
`/goal` for a direct one-shot edit with no useful verification boundary.

For coordinated or multi-turn work, the native `Checkpoint` sentence is only a summary. Persist
the checkpoint's phase, evidence, next gate, and blocker in the `Details` target or frozen
contract before reporting it; the native goal remains navigation and completion evidence, not the
durable lifecycle authority.

Use literal paths and commands. Do not delete, skip, weaken, narrow, or rewrite tests or other
verification surfaces to make the goal pass; do not refactor unrelated code or add dependencies.
Do not create a new ADR or decision record without human approval. If a product decision, absolute
target, irreversible/external action, new dependency/ADR, or objective change is required, pause
and ask before proceeding.

Sources: [Claude goal documentation](https://code.claude.com/docs/en/goal) and
[Claude hooks reference](https://code.claude.com/docs/en/hooks),
[Claude hooks guide](https://code.claude.com/docs/en/hooks-guide), and
[Claude Code issue #47810](https://github.com/anthropics/claude-code/issues/47810).
