---
id: public-front-door
title: Build the public front door
status: done
depends_on: []
acceptance:
  - "bash tests/test_docs.sh exits 0 and reports PASS after checking the README and public guides"
  - "README.md contains a GitHub-native Mermaid workflow and a concrete bounded-goal example"
stop_rules:
  success: "All acceptance checks pass with fresh raw evidence"
  failure: "The same check fails twice without progress, or a factual platform claim cannot be verified"
  max_iterations: 3
  max_cost: "USD 0 external spend"
  max_wall_clock: "90 minutes"
parallelizable: false
owner: primary-agent
priority: high
artifacts:
  - README.md
  - docs/quickstart.md
  - docs/examples.md
  - docs/security-model.md
  - tests/test_docs.sh
risk: low
updated: 2026-07-28
---

# Build the public front door

## Goal statement

Make the landing page explain what writing-goals does, why it matters, how to get a first result,
and where its safety boundary ends before exposing detailed hook mechanics.

## Context

- **Why now / where it sits:** This is the walking skeleton for every public reader journey.
- **Depends on:** none. **Blocks:** `community-baseline`, `accuracy-and-maintenance`.
- **Real repo state:** `README.md` is accurate but begins with prerequisites and development
  symlinks; `shared/method.md` is the canonical policy; `bash tests/test_docs.sh` is the existing
  documentation contract.

## How-to

1. Strengthen the documentation contract with structural and link assertions.
2. Rewrite the README around outcome, proof, quick start, scope, safety, and navigation.
3. Move detailed operational guidance into focused public guides that link to `shared/`.
4. Verify with `bash tests/test_docs.sh`, then set this goal to `in_review`.

## Assumptions log

| # | Fork / ambiguity | Options | Chosen | Rationale | Undo path | Confidence |
|---|---|---|---|---|---|---|
| 1 | Visual format | generated hero / GIF / Mermaid | Mermaid first | Diffable, accessible with adjacent prose, GitHub-native, and explanatory | Replace the fenced diagram later | high |
| 2 | Public install status | imply stable package / document source install | Document source checkout as current distribution | Matches implemented installer and avoids inventing a release channel | Add a release install path when one exists | high |
