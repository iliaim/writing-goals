---
okf_version: "0.2"
---

# Deterministic gates

Platform completion signals are not deterministic verification. Real verification comes from two
gate layers. Use both for anything unattended; see the platform adapter for current wiring.

## Layer 1 — condition-level gate (lives in the goal text)

Force the doer to **run the check and persist or surface the raw stdout + exit code**, so a
fresh checker can reproduce the verdict instead of trusting self-report.

- Name the **exact** command. No paraphrase.
- Require the raw output block **and** `echo $?` (the exit code) pasted verbatim.
- **Forbid** editing, skipping, `xfail`-ing, or deleting the verification surface to reach green.
- Limits: this is still the *maker* surfacing its own evidence. Better than a bare claim,
  but the model chooses what to paste — not sufficient for an unwatched loop.

## Layer 2 — lifecycle verification gate (the real maker ≠ checker)

A trusted lifecycle script runs the command in a fresh process, independent of anything the
doer says. The checker is now code, not the maker — the true maker/checker separation.
Required for every unattended permission mode.

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
- Require an explicit trusted `GATE_CMD`, an explicit positive `GOAL_GATE_CAP`, and a non-empty
  `GATE_SURFACE`. There is no implicit test command and no default cap.

## Protect the verification surface

`GATE_SURFACE` is a whitespace-separated shell glob/list. Configure repo-relative path or glob
words. The shipped scripts change to the repository root, apply ordinary shell word splitting and
glob expansion, require at least one result, and require every expanded entry to resolve to a
regular file. Unmatched patterns therefore fail; filenames containing whitespace are not
representable by this interface. Absolute words follow shell semantics but are outside the
supported configuration contract.

The stored surface digest detects changes only **after a trusted baseline exists**. The currently
supported safe setup is to make the complete verification surface read-only to the maker before
work starts. A trusted orchestrator may establish the first digest only if it invokes the hook
with the exact same session payload and therefore the same session-keyed state before maker edits.
The scripts expose no separate prime-only interface. Manual or pre-session priming is not
reliable because it may create a different state key. Never let the maker's first post-edit hook
invocation silently establish the accepted baseline.

## Keep verifiers tiny — run → compare → block/allow

The verifier does exactly three things: **run** the command, **read** its exit code,
**block or allow**. Nothing else.

- **NEVER** let the verifier silently fix, reformat, auto-`--update-snapshots`, or otherwise
  mutate the verification surface to make it pass — that is the maker cheating *through*
  the checker, and it re-collapses maker and checker into one.
- No paraphrasing of the result. The **exit code is the verdict.**
- The block `reason` should point at the code, e.g. "fix without editing/deleting tests" —
  never suggest weakening the check.

Ready-made platform adapters are `assets/gate.claude.sh` and `assets/gate.codex.sh`. Copy the
relevant script into the platform lifecycle location, make it executable, configure all three
mandatory inputs, and use the skill adapter's current wiring.

## Pair with a pre-use deny-list — a backstop, not a boundary

Unattended permission modes can remove interactive approval prompts. Add the ready-made
**`assets/deny-list.sh`** pre-use policy — fail-closed blocks of
deletes/writes outside the repo, force-push/history rewrite, external network sends, arbitrary
installs, spend, and secrets exfiltration. But be clear about what it is: **a best-effort
backstop against a cooperative agent's footguns, NOT a security boundary.** String-matching
over shell is structurally unsound — a determined or prompt-injected agent slips past it
(interpreters, quoting, newlines, home-directory writes, allowlisted-host exfil). **The real
boundary is an OS-level sandbox** (container/VM, read-only mounts outside the repo, non-root,
dropped caps, egress only via an allowlisting proxy); the deny-list + gate are extra layers
*inside* it. Full rationale: **`shared/autonomy.md`**.
