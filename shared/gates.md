# Deterministic gates (Claude Code)

Claude's native `/goal` evaluator reads the **transcript only — it runs no tools.**
So it can be fooled by a confident "tests pass." Real verification comes from one of
two gate layers. Use both for anything unattended.

## Layer 1 — condition-level gate (lives in the goal text)

Force the doer to **run the check and paste the raw stdout + exit code into the
transcript**, so the weak evaluator judges evidence instead of a self-report.

- Name the **exact** command. No paraphrase.
- Require the raw output block **and** `echo $?` (the exit code) pasted verbatim.
- **Forbid** editing, skipping, `xfail`-ing, or deleting the verification surface to reach green.
- Limits: this is still the *maker* surfacing its own evidence. Better than a bare claim,
  but the model chooses what to paste — not sufficient for an unwatched loop.

## Layer 2 — hook-level gate (the real maker ≠ checker)

A **Stop-hook script actually runs the command** in a fresh process, independent of
anything the doer says. The checker is now **code, not the model** — the true
maker/checker separation. Recommended for every unattended / bypass run.

## Claude Stop-hook contract (use exactly)

- Configured in `.claude/settings.json` under `hooks.Stop[].hooks[]` as
  `{"type":"command","command":"…"}`. The **matcher is ignored** for `Stop`.
- **exit 0 + stdout `{"decision":"block","reason":"…"}`** → Claude **KEEPS working**;
  `reason` is fed back to it as guidance.
- **clean exit 0 with no block** → Claude **may stop**.
- **exit 2 + stderr** → also blocks (stderr becomes the guidance).
- The hook's JSON **stdin** carries `stop_hook_active` — `true` when this `Stop` fired
  *because a previous block already made Claude continue*. It is the harness's own
  loop-detection signal; honor it so the gate can never loop forever.

## Mandatory iteration counter (bound the strongest gate)

The strongest gate is also the easiest to turn into an infinite, budget-burning loop.
Bound it with a **persisted counter**:

- Persist the attempt count to a file at repo root, e.g. **`.goal-gate-count`**.
- Each **fail → block** increments it; each **clean pass** removes it (loop over).
- On **`count ≥ N`** emit **allow-stop** with reason
  **"iteration cap hit — needs human"**, *regardless of pass/fail*. The cap wins.
- **Honor `stop_hook_active`** as a fail-safe: if the counter can't be persisted while a
  hook-driven continuation is in flight, **allow the stop** rather than risk an unbounded loop.
- Default **N = 5**. A gate that can loop forever is a cost risk, not automation.

## Keep verifiers tiny — run → compare → block/allow

The hook does exactly three things: **run** the command, **read** its exit code,
**block or allow**. Nothing else.

- **NEVER** let the hook silently fix, reformat, auto-`--update-snapshots`, or otherwise
  mutate the verification surface to make it pass — that is the maker cheating *through*
  the checker, and it re-collapses maker and checker into one.
- No paraphrasing of the result. The **exit code is the verdict.**
- The block `reason` should point at the code, e.g. "fix without editing/deleting tests" —
  never suggest weakening the check.

## Wire it into `.claude/settings.json`

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/gate.claude.sh" }
        ]
      }
    ]
  }
}
```

Notes:
- The `matcher` key is intentionally omitted — it is ignored for `Stop`.
- Use an absolute path or `$CLAUDE_PROJECT_DIR` (Claude sets it to the project root).
- `chmod +x` the script. Ready-made example (gates on `pytest -q`): **`assets/gate.claude.sh`**.

## Pair with a `PreToolUse` deny-list (unattended / bypass)

Bypass mode (`--dangerously-skip-permissions`) turns the approval prompts **off**, so
tier-4 safety must be **deterministic**, not model-promised. Add a `PreToolUse`
deny-list hook — **deny-first precedence beats the allowlist and bypass mode**. Ready-made:
**`assets/deny-list.sh`** (hard-blocks deletes/writes outside the repo, force-push/history
rewrite, external network sends, arbitrary installs, spend, and secrets exfiltration).
