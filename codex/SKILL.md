---
name: writing-goals
description: Use when writing a bounded Codex completion contract, running unattended work, or decomposing a large objective into verifiable sub-goals.
---

# Writing goals for Codex

Follow `shared/method.md` completely. It is the canonical method. Load its linked shared
references as the task requires; this adapter adds only Codex-native integration instructions.

## Invoke and trust

- Invoke as `$writing-goals`, select it from `/skills`, or allow its description to trigger it.
- Use the installed `assets/codex-continuation.sh` as the foreground host-native continuation
  non-interactive entrypoint for the sequential workflow in `shared/workflow.md`. It invokes
  `codex exec resume` only from protected authority and must run outside the maker sandbox.
- A trusted host, never the resumed child, may use the separately pinned
  `assets/core-state-advance.sh` to install a freshly checked, monotonic protected cursor.
- Skill frontmatter contains only `name` and `description`; UI and invocation metadata belong in
  `agents/openai.yaml`.
- Project hooks live in `.codex/hooks.json` or `.codex/config.toml`. Non-managed command hooks
  must be reviewed and trusted; `/hooks` shows their sources and trust state. A changed hook hash
  requires review again.
- Stop and PreToolUse hooks are cooperative backstops, not a security boundary or containment.
  Run unattended work in an OS-level sandbox (for example, a `sandbox-exec` profile where
  available) with only the intended writable source paths.

## Current Codex platform facts

- Stop hooks receive JSON on stdin and can run deterministic verification. A clean exit 0 with no
  block allows the turn to stop; the repository adapter is `assets/gate.codex.sh`.
- This adapter validates only `Bash` (including the documented unified execution payload) and
  `apply_patch`; do not infer coverage for any other tool or payload shape. A supported call can
  be denied using `permissionDecision:"deny"` or exit 2 with the reason on stderr.

## Native Codex goal

For a run that warrants a native Codex goal, bind one native Codex goal to the complete objective/run
only when `/goal` is available in the active Codex surface. Start it with `/goal <objective>`; use
`/goal` to inspect it and the goal progress controls above the composer to pause or resume the goal,
edit the goal text, or clear the goal. If `/goal` is unavailable, use `$writing-goals` and the
repository's custom continuation workflow instead. Native goal tracking is convenience state; the
protected host-owned workflow remains lifecycle authority for full-tier work.

Put a concise, user-legible completion contract in the native `objective` field:

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

Every `Then` criterion is cumulative and parent-level. Native completion requires evidence for all
of them; it does not mean implementation began, a subset passes, or child slices are complete. For
a full plan, derive these criteria from the frozen `objective_acceptance`. State concrete outputs,
access decisions, files, responses, or other observable signals; never use vague criteria such as
“works correctly.” `Details` is navigation only: it may explain a criterion, but never replace
one, redefine scope, or become lifecycle authority. Keep implementation steps, alternatives,
per-slice checks, and lifecycle receipts in the contract or protected plan rather than the native
goal. Do not create a native goal for a direct one-shot edit with no useful verification boundary.

Use literal paths and commands. Do not delete, skip, weaken, narrow, or rewrite tests or other
verification surfaces to make the goal pass; do not refactor unrelated code or add dependencies.
Do not create a new ADR or decision record without human approval. If a product decision, absolute
target, irreversible/external action, new dependency/ADR, or objective change is required, pause
and ask before proceeding.

A child handoff can never complete the parent; native completion is rejected while the parent rollup is incomplete.

For coordinated or multi-turn work, the native `Checkpoint` sentence is only a summary. Persist
the checkpoint's phase, evidence, next gate, and blocker in the `Details` target or frozen
contract before reporting it; the native goal remains navigation and completion evidence, not the
durable lifecycle authority.

Sources: [Codex slash commands](https://learn.chatgpt.com/docs/reference/slash-commands),
[Codex goals](https://learn.chatgpt.com/use-cases/follow-goals), and
[Codex hooks documentation](https://learn.chatgpt.com/docs/hooks).
