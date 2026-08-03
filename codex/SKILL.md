---
name: writing-goals
description: Use when writing a bounded Codex completion contract, running unattended work, or decomposing a large objective into verifiable sub-goals.
---

# Writing goals for Codex

Follow `shared/method.md` completely. It is the canonical method. Load its linked shared
references as the task requires; this adapter adds no policy.

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
- Bind one native Codex goal to the complete objective/run. A child handoff can never complete the parent;
  native completion is rejected while the parent rollup is incomplete.

Source: [Codex hooks documentation](https://learn.chatgpt.com/docs/hooks).
