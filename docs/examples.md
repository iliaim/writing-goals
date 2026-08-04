---
okf_version: "0.2"
---

# Examples

These examples demonstrate the contract shape. Commands, paths, and targets must be
derived from or approved for the repository where the goal will run.

## Small vertical slice

```text
Objective:     reject expired sessions with a regression-tested authentication change
Read first:    AGENTS.md, src/session.sh, tests/test_login.sh
Scope:         edit only src/session.sh; tests/test_login.sh and all documentation are protected
Constraints:   no new dependencies; do not edit, skip, narrow, or delete tests/test_login.sh
Document:      no documentation path is authorized or required for this code-only slice; derive or obtain an approved target before a separate documentation slice
Given:         expired sessions are part of the authentication behavior under test
When:          the focused authentication change is complete
Then all of the following are true:
- expired sessions are rejected;
- the test reports "ok: expired session rejected" and "PASS: 1 assertion";
- the full suite exits 0
Validate:      bash tests/test_login.sh exits 0 and reports "ok: expired session rejected" and "PASS: 1 assertion"; bash tests/run.sh exits 0 with no FAIL lines
Checkpoint:    current phase=implementation; exact evidence observed=bash tests/test_login.sh exited 0 and reported "ok: expired session rejected" and "PASS: 1 assertion"; next gate=bash tests/run.sh; blocker/decision needed=none
No-progress stop: repeated failure without a new diagnosis or materially different candidate
Alternatives:  expand the session storage schema -- rejected because it is out of scope for this behavior change
Stop when:     both checks exit 0 with the required result, or human/product input is required
```

Why this is well formed:

- it delivers one observable behavior;
- the behavioral check is stronger than the full-suite regression proxy;
- the maker cannot edit the named acceptance test;
- a reviewer can rerun both commands when proportionate; and
- normal work escalates repeated red rather than carrying a universal numeric cap.

## Documentation change

```text
Objective:     update agent-facing documentation without changing the contract or installer behavior
Read first:    shared/method.md, README.md, docs/quickstart.md, tests/test_docs.sh
Scope:         edit README.md and docs/quickstart.md; preserve the existing public contract
Constraints:   do not weaken, skip, narrow, or delete tests/test_docs.sh; no new dependencies
Document:      update README.md and docs/quickstart.md; record any intentionally unchanged guide
Given:         the current documentation contract tests and public guides are the baseline
When:          the focused documentation changes are complete
Then all of the following are true:
- the guides describe the current agent-facing contract and remain internally consistent;
- the installer, safety, and verification boundaries are unchanged; and
- the focused checks pass
Validate:      bash tests/test_docs.sh exits 0 and reports a line matching "PASS: [0-9]+ assertions"; bash tests/run.sh exits 0 with no line matching "^FAIL:"
Checkpoint:    current phase=documentation; exact evidence observed=bash tests/test_docs.sh exited 0 and reported PASS: [0-9]+ assertions; next gate=bash tests/run.sh; blocker/decision needed=none
No-progress stop: repeated failure without a new diagnosis or materially different candidate
Alternatives:  add a new guide or change installer behavior -- rejected because the public contract and installer behavior are out of scope
Stop when:     all listed criteria and checks pass, or human/product input is required
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
