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

For a run that warrants a native Codex goal, bind one native Codex goal to the complete objective/run.
Put a concise, user-legible completion contract in the native `objective` field:

```text
Objective: <single completed outcome>

Scope:
- Included: <bounded behaviors, components, or users>
- Excluded: <explicit non-goals>

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
```

Every `Then` criterion is cumulative and parent-level. Native completion requires evidence for all
of them; it does not mean implementation began, a subset passes, or child slices are complete. For
a full plan, derive these criteria from the frozen `objective_acceptance`. State concrete outputs,
access decisions, files, responses, or other observable signals; never use vague criteria such as
“works correctly.” `Details` is navigation only: it may explain a criterion, but never replace
one, redefine scope, or become lifecycle authority. Keep implementation steps, alternatives,
per-slice checks, and lifecycle receipts in the contract or protected plan rather than the native
goal. Do not create a native goal for a direct one-shot edit with no useful verification boundary.

A child handoff can never complete the parent; native completion is rejected while the parent rollup is incomplete.

Source: [Codex hooks documentation](https://learn.chatgpt.com/docs/hooks).
