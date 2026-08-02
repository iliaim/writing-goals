---
okf_version: "0.2"
---

# Examples

These examples demonstrate the contract shape. Commands, paths, and targets must be
derived from or approved for the repository where the goal will run.

## Small vertical slice

```text
Done when:     bash tests/test_login.sh exits 0 and reports "PASS: expired session rejected"
Also green:    bash tests/run.sh exits 0
Scope:         only edit src/session.sh; do not edit tests/test_login.sh
Verification:  record each observed exit and pass signal; retain output when useful
Stop:          success = both commands exit 0 with the required result
               failure = test_login.sh fails twice without a new diagnosis
               repeated red without progress = escalate to a human
               stop before changing the session storage schema
```

Why this is well formed:

- it delivers one observable behavior;
- the behavioral check is stronger than the full-suite regression proxy;
- the maker cannot edit the named acceptance test;
- a reviewer can rerun both commands when proportionate; and
- normal work escalates repeated red rather than carrying a universal numeric cap.

## Documentation change

```text
Done when:     bash tests/test_docs.sh exits 0 and reports "PASS"
Also green:    bash tests/run.sh exits 0
Scope:         edit README.md and docs/quickstart.md; do not weaken tests/test_docs.sh
Verification:  record observed exits and pass signals; retain output when useful
Stop:          success = both checks exit 0
               failure = the documentation check fails twice without progress
               repeated red without progress = escalate to a human
```

This is a contract-level check of required documentation structure. It does not prove that every
reader will understand the prose, so a human or fresh-context editorial review remains valuable.

## Larger approved objective

A specification that needs multiple genuinely independent, verifiable slices can use a shallow workspace plan:

```text
plans/p01/
  objective.md
  goals/g01-walking-skeleton.md
  goals/g02-feature-a.md
  goals/g03-feature-b.md
  goals/g04-integration.md
```

Each node has its own task class, exact acceptance command, and protected iteration condition.
Dependencies form an acyclic graph. Goals that write shared files or have semantic dependencies
remain serialized.
See [`../shared/chaining.md`](../shared/chaining.md).

## Evidence

Record the observed result, retaining full output when it helps diagnosis:

```text
$ bash tests/test_login.sh
ok: expired session rejected
PASS: 1 assertion
$ echo $?
0
```

The output above is illustrative, not evidence for this repository. Real completion evidence must
come from a fresh run in the target checkout and include the exact exit code.

## Anti-patterns

| Avoid | Why it fails | Replace with |
|---|---|---|
| “Improve test coverage” | No approved target or exact check | Ask for the target, then name the coverage command and threshold |
| “Make it faster” | No baseline or success number | Use an approved absolute SLA or a recorded relative target |
| “Run the tests” | The command and pass signal are missing | Name the exact scoped command and required exit/result |
| “Keep trying until it works” | An unbounded retry loop | Escalate repeated red; use a protected iteration cap for full-tier work |
| “Build passes, therefore behavior works” | Build is only a proxy | Prefer a behavioral or integration check |
| Maker edits the failing test | Verification surface is compromised | Freeze the acceptance surface before implementation |
| Hook equals sandbox | A cooperative guardrail is mistaken for containment | Use OS isolation and treat hooks as defense in depth |

## Second-agent test

Before execution, ask whether a fresh agent could confirm completion from only:

- the contract;
- the named files; and
- the exact command plus observed exit/result.

If confirmation requires trusting the maker's prose, the goal is not ready.
