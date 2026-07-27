# Canonical goal method

This is the platform-neutral contract for writing and running goals. Platform adapters must
load this file and add only invocation, trust, and current hook facts; they must not redefine
the method.

## 1. Triage

Use a goal when work is multi-turn, unattended, or has an end state worth enforcing. Handle a
small, one-shot edit directly. A goal adds coordination cost, so do not create one without a
useful verification boundary.

## 2. Investigate before authoring

Read the repository guidance, current implementation, tests, package scripts, CI configuration,
and working-tree state. Identify the strongest deterministic verification surface and its exact
command. Do not infer a command from a language or framework. Follow `shared/investigate.md`.

Classify each required fact:

- **MUST-ASK:** user intent, scope, Definition of Done, absolute targets, irreversible choices,
  and a missing decomposition specification. Stop for an answer, or propose a bounded
  specification and get approval before execution.
- **DERIVE-then-CONFIRM:** repository facts that can be discovered, such as commands, paths,
  existing conventions, relative baselines, and a proposed execution budget. Read first, record
  ambiguous choices, and confirm any choice that changes product behavior or scope.

## 3. Author one verifiable slice

Write one observable outcome with:

1. exact scope and constraints;
2. an acceptance check chosen before implementation;
3. inherited repository checks;
4. raw command output and exit status as evidence; and
5. concrete `stop_rules` for success, failure, maximum iterations, cost, and wall-clock time.

The maker may not weaken, skip, delete, or rewrite the verification surface to pass. A green
build, typecheck, or lint is only a proxy unless it exercises the required behavior. Use
`shared/author-goal.md` and `assets/goal.md.tmpl`.

## 4. Gate deterministically

For unattended work, configure the platform lifecycle gate to run a trusted, non-mutating
verifier. Set `GATE_CMD`, `GOAL_GATE_CAP`, and `GATE_SURFACE` explicitly; there is no default test
command or iteration budget. `GATE_SURFACE` is a whitespace-separated shell glob/list evaluated
from the repository root: configure repo-relative entries, require at least one expansion, and
ensure every expanded entry resolves to a regular file. A failing check may request another
iteration below the cap. Passing permits a stop. Invalid configuration, invalid state, or reaching
the cap stops the loop and reports needs-human.

The counter is tamper-resistant only when the sandbox prevents the worker from writing its state
directory. An out-of-repository path alone is not protection. Gate logs and state are evidence,
not a security boundary. The surface digest detects only changes made after its trusted baseline:
prime it before maker edits, mount the verification surface read-only to the maker, or pre-record
the baseline through a trusted process. See `shared/gates.md`.

## 5. Chain only when needed

Decompose a large, approved specification into a shallow dependency DAG of persisted sub-goals.
Every node uses the same complete `stop_rules`, acceptance evidence, and fresh verification.
Resume from files, re-check dependencies, and escalate repeated no-progress instead of retrying.

Parallel branches require disjoint write artifacts, no semantic or runtime dependency, isolated
worktrees, sufficient review capacity, and an integration order. Disjoint artifacts are necessary
but insufficient. See `shared/chaining.md`.

## 6. Apply autonomy by blast radius

Use the action classes in `shared/autonomy.md`. Read-only and reversible scoped actions may run
within their bounds. External, spending, irreversible, or trust-boundary actions are Class 3 and
require explicit, bounded human authorization. Class 4 actions are denied during unattended
execution; a human may instead perform or separately authorize an appropriate controlled
workflow. Repository commits require user or repository policy authority.

Hooks are defense in depth, not containment. Unattended execution requires an OS sandbox,
least privilege, scoped writable mounts, restricted egress, budgets, and a kill path. Select the
driver model in `shared/modes.md`; neither platform natively advances a persisted goal DAG.

## Completion checklist

- The goal traces to approved intent and has no invented MUST-ASK facts.
- Acceptance is behavior-oriented, exact, and protected from maker edits.
- Success, failure, iterations, cost, and wall-clock stops are explicit.
- Gate command, cap, state location, permissions, and trust are configured.
- Every Class 3 action has bounded human authorization; unattended Class 4 actions are denied.
- A fresh checker reruns the acceptance check and reviews raw evidence.
