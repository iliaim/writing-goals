---
id: community-baseline
title: Establish public project expectations
status: done
depends_on: [public-front-door]
acceptance:
  - "bash tests/test_docs.sh exits 0 and reports PASS after checking all community-health files and templates"
  - "LICENSE contains the unmodified standard MIT text and identifies 2026 iliaim"
stop_rules:
  success: "All acceptance checks pass with fresh raw evidence"
  failure: "The same check fails twice without progress or a required private reporting path cannot be documented honestly"
  max_iterations: 3
  max_cost: "USD 0 external spend"
  max_wall_clock: "60 minutes"
parallelizable: false
owner: primary-agent
priority: high
artifacts:
  - LICENSE
  - SECURITY.md
  - CONTRIBUTING.md
  - SUPPORT.md
  - CODE_OF_CONDUCT.md
  - CHANGELOG.md
  - .github/ISSUE_TEMPLATE/
  - .github/PULL_REQUEST_TEMPLATE.md
  - tests/test_docs.sh
risk: medium
updated: 2026-07-28
---

# Establish public project expectations

## Goal statement

Give users and contributors explicit, actionable terms for reuse, support, security reporting,
conduct, issues, pull requests, and release history.

## Context

- **Depends on:** `public-front-door` supplies the reader journey and documentation links.
- **Blocks:** `accuracy-and-maintenance`.
- **Real repo state:** GitHub currently detects only a README in the community profile.

## How-to

1. Add the standard MIT license chosen from authoritative license guidance.
2. Add concise community-health files with repository-specific commands and trust-boundary fields.
3. Add structured forms for factual documentation errors, executable bugs, compatibility reports, and focused feature proposals.
4. Add a PR template requiring exact verification evidence and safety-impact review.
5. Verify with `bash tests/test_docs.sh`, then set this goal to `in_review`.

## Assumptions log

| # | Fork / ambiguity | Options | Chosen | Rationale | Undo path | Confidence |
|---|---|---|---|---|---|---|
| 1 | Permissive license | MIT / Apache-2.0 | MIT | Small method/skill repo; simple reuse and notice obligation; consistent with benchmark peers | Replace only with explicit future relicensing authority | high |
| 2 | Copyright identity | guess legal name / repository owner | `iliaim` | Identifies the public rights holder without exposing or inventing private identity | Update holder with maintainer approval | medium |
| 3 | Security contact | invent email / public details / GitHub private reporting | GitHub private vulnerability reporting with safe fallback | Avoids exposing details and keeps reports off public issues | Add a dedicated security email later | high |

## External setting verification

After explicit bounded authorization, GitHub private vulnerability reporting was enabled for
`iliaim/writing-goals` and verified through the GitHub API. It is reserved for security
vulnerabilities. Private GitHub abuse is routed to GitHub Support, and the repository intentionally
does not operate a separate private maintainer conduct inbox.
