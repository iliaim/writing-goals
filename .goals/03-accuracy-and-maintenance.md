---
id: accuracy-and-maintenance
title: Lock documentation accuracy and maintainability
status: done
depends_on: [public-front-door, community-baseline]
acceptance:
  - "bash tests/run.sh exits 0 and all four suites report PASS"
  - "rg -n '/goal' codex/agents/openai.yaml returns no matches"
  - "A fresh-context reviewer reports no high-confidence contradiction, broken internal link, or duplicated platform policy"
stop_rules:
  success: "All acceptance checks and fresh review pass"
  failure: "The full suite or fresh review fails twice without progress"
  max_iterations: 2
  max_cost: "USD 0 external spend"
  max_wall_clock: "60 minutes"
parallelizable: false
owner: primary-agent
priority: high
artifacts:
  - codex/agents/openai.yaml
  - PLAN.md
  - tests/test_docs.sh
  - .goals/
risk: low
updated: 2026-07-28
---

# Lock documentation accuracy and maintainability

## Goal statement

Remove the Claude-only wording from Codex metadata, document the public architecture decisions, and
make documentation drift visible in the existing contract suite.

## Context

- **Depends on:** both content-producing goals.
- **Real repo state:** `codex/agents/openai.yaml` currently advertises `/goal`; `PLAN.md` is the
  as-built record; CI runs `bash tests/run.sh` on Ubuntu and macOS.

## How-to

1. Correct Codex UI metadata without changing skill invocation behavior.
2. Update the as-built record for the public-documentation architecture and license.
3. Run the full suite and request a fresh-context read-only review.
4. Review `git diff --check`, repository status, and all changes for unrelated churn.

## Assumptions log

| # | Fork / ambiguity | Options | Chosen | Rationale | Undo path | Confidence |
|---|---|---|---|---|---|---|
| 1 | README policy depth | duplicate canonical rules / link to canonical rules | Summarize reader-critical boundaries and link to `shared/` | Prevents rule drift while keeping the front page useful | Expand only with matching contract checks | high |
