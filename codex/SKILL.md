---
name: writing-goals
description: Use when writing a bounded Codex completion contract, running unattended work, or decomposing a large objective into verifiable sub-goals.
---

# Writing goals for Codex

Follow `shared/method.md` completely. It is the canonical method. Load its linked shared
references as the task requires; this adapter adds no policy.

## Invoke and trust

- Invoke as `$writing-goals`, select it from `/skills`, or allow its description to trigger it.
- Use `codex exec` as the non-interactive entrypoint for an external goal-chain driver.
- Skill frontmatter contains only `name` and `description`; UI and invocation metadata belong in
  `agents/openai.yaml`.
- Project hooks live in `.codex/hooks.json` or `.codex/config.toml`. Non-managed command hooks
  must be reviewed and trusted; `/hooks` shows their sources and trust state. A changed hook hash
  requires review again.

## Current Codex platform facts

- Stop hooks receive JSON on stdin and can run deterministic verification. A clean exit 0 with no
  block allows the turn to stop; the repository adapter is `assets/gate.codex.sh`.
- `PreToolUse` covers shell and unified execution as `Bash`, file edits through `apply_patch`,
  MCP tools, and most other local function tools. Hosted tools such as `WebSearch` are excluded;
  `write_stdin` does not get a second `PreToolUse`, and specialized paths may opt out.
- Matchers may use `Bash`, `apply_patch` (also `Edit` or `Write`), an MCP tool name, or another
  local function tool name. A supported call can be denied using `permissionDecision:"deny"` or
  exit 2 with the reason on stderr.

Source: [Codex hooks documentation](https://learn.chatgpt.com/docs/hooks).
