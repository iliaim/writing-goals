---
okf_version: "0.2"
---

# Examples

These examples demonstrate the contract shape. Commands, paths, targets, and budgets must be
derived from or approved for the repository where the goal will run.

## Small vertical slice

```text
Done when:     bash tests/test_login.sh exits 0 and reports "PASS: expired session rejected"
Also green:    bash tests/run.sh exits 0
Scope:         only edit src/session.sh; do not edit tests/test_login.sh
Verification:  paste the complete raw output from both commands and each exit code
Stop:          success = both commands exit 0 with the required result
               failure = test_login.sh fails twice without a new diagnosis
               max_iterations = 4
               max_cost = USD 5
               max_wall_clock = 45 minutes
               stop before changing the session storage schema
```

Why this is well formed:

- it delivers one observable behavior;
- the behavioral check is stronger than the full-suite regression proxy;
- the maker cannot edit the named acceptance test;
- a fresh checker can rerun both commands; and
- every loop has explicit bounds.

## Documentation change

```text
Done when:     bash tests/test_docs.sh exits 0 and reports "PASS"
Also green:    bash tests/run.sh exits 0
Scope:         edit README.md and docs/quickstart.md; do not weaken tests/test_docs.sh
Verification:  paste the complete raw output and exit code from both commands
Stop:          success = both checks exit 0
               failure = the documentation check fails twice without progress
               max_iterations = 3
               max_cost = USD 0 external spend
               max_wall_clock = 30 minutes
```

This is a contract-level check of required documentation structure. It does not prove that every
reader will understand the prose, so a human or fresh-context editorial review remains valuable.

## Larger approved objective

A specification that needs multiple independently verifiable slices can use a shallow workspace plan:

```text
plans/p01/
  objective.md
  goals/g01-walking-skeleton.md
  goals/g02-feature-a.md
  goals/g03-feature-b.md
  goals/g04-integration.md
```

Each file has its own exact acceptance command and complete stop rules. Dependencies form an
acyclic graph. Goals that write shared files or have semantic dependencies remain serialized.
See [`../shared/chaining.md`](../shared/chaining.md).

## Evidence

Surface raw output rather than a summary:

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
| “Keep trying until it works” | Unbounded cost and time | Add failure, iteration, cost, and wall-clock stops |
| “Build passes, therefore behavior works” | Build is only a proxy | Prefer a behavioral or integration check |
| Maker edits the failing test | Verification surface is compromised | Freeze the acceptance surface before implementation |
| Hook equals sandbox | A cooperative guardrail is mistaken for containment | Use OS isolation and treat hooks as defense in depth |

## Second-agent test

Before execution, ask whether a fresh agent could confirm completion from only:

- the contract;
- the named files; and
- the raw command output plus exit code.

If confirmation requires trusting the maker's prose, the goal is not ready.
