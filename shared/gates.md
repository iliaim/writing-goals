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
- The hook's JSON **stdin** may carry `stop_hook_active` — reported `true` when this `Stop`
  fired *because a previous block already made Claude continue*. Treat it as a **runtime
  loop-guard flag, not a documented guarantee** (it isn't in the current hooks reference);
  cross-check it against `stop_reason`, and rely on the persisted out-of-repo counter (below)
  as the real bound. Honor it as a *secondary* fail-safe, not the thing that keeps the gate
  from looping.

## Mandatory iteration counter (bound the strongest gate)

The strongest gate is also the easiest to turn into an infinite, budget-burning loop.
Bound it with a **persisted counter** — and put that counter **out of the agent's reach**:

- Persist the attempt count **outside the repo**, in a path the agent under gate can't write
  (e.g. `$XDG_STATE_HOME/goal-gate/<repo-id>.count`) — **never** at repo root. A counter the
  doer can edit is not a bound; it's a suggestion the agent can reset to dodge the cap.
- Each **fail → block** increments it; each **clean pass** removes it (loop over).
- On **`count ≥ N`** emit **allow-stop** with reason
  **"iteration cap hit — needs human"**, *regardless of pass/fail*. The cap wins.
- **Fail closed on unwritable state:** if the out-of-repo counter is missing or can't be
  written, treat the run as unbounded-risk — **stop the loop and escalate to a human**
  (needs-human), never continue looping and never silently pass. The persisted out-of-repo
  counter is the **real bound**; `stop_hook_active` (below) is only a secondary loop-guard.
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

## Pair with a `PreToolUse` deny-list — a backstop, not a boundary (unattended / bypass)

Bypass mode (`--dangerously-skip-permissions`) turns the approval prompts **off**. Add a
`PreToolUse` deny-list hook (ready-made: **`assets/deny-list.sh`** — fail-closed blocks of
deletes/writes outside the repo, force-push/history rewrite, external network sends, arbitrary
installs, spend, and secrets exfiltration). But be clear about what it is: **a best-effort
backstop against a cooperative agent's footguns, NOT a security boundary.** String-matching
over shell is structurally unsound — a determined or prompt-injected agent slips past it
(interpreters, quoting, newlines, `$HOME` writes, allowlisted-host exfil), and a known bug
(claude-code #47810) can even bypass the hook after a background task completes. **The real
boundary is an OS-level sandbox** (container/VM, read-only mounts outside the repo, non-root,
dropped caps, egress only via an allowlisting proxy); the deny-list + gate are extra layers
*inside* it. Full rationale: **`shared/autonomy.md`**.
