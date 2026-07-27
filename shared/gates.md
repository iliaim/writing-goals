# Deterministic gates

Platform goal evaluators and model completion signals are not deterministic verification. Real
verification comes from two gate layers. Use both for anything unattended; see the platform
adapter for current wiring and hook contracts.

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

## Mandatory iteration counter (bound the strongest gate)

The strongest gate is also the easiest to turn into an infinite, budget-burning loop.
Bound it with a **persisted counter** — and put that counter **out of the agent's reach**:

- Persist the attempt count **outside the repo** in a state directory that the sandbox policy
  prevents the worker from writing directly. An out-of-repository path alone is not
  tamper-resistant: filesystem permissions are the control.
- Each **fail → block** increments it; each **clean pass** removes it (loop over).
- On **`count ≥ N`**, stop the loop and report **"iteration cap hit — needs human"**. The cap wins.
- A missing counter initializes at zero. **Fail closed on unreadable, malformed, or unwritable
  state:** stop the loop and escalate to a human (needs-human), never continue unbounded.
  The configured cap plus sandbox-protected state is the real bound.
- Require an explicit trusted `GATE_CMD` and an explicit positive `GOAL_GATE_CAP`. There is no
  implicit `pytest` command and no default cap.

## Keep verifiers tiny — run → compare → block/allow

The hook does exactly three things: **run** the command, **read** its exit code,
**block or allow**. Nothing else.

- **NEVER** let the hook silently fix, reformat, auto-`--update-snapshots`, or otherwise
  mutate the verification surface to make it pass — that is the maker cheating *through*
  the checker, and it re-collapses maker and checker into one.
- No paraphrasing of the result. The **exit code is the verdict.**
- The block `reason` should point at the code, e.g. "fix without editing/deleting tests" —
  never suggest weakening the check.

Ready-made scripts are `assets/gate.claude.sh` and `assets/gate.codex.sh`. Copy the relevant
script into the repository hook location, make it executable, configure its trusted command and
cap in the hook environment, and use the adapter's current platform wiring.

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
