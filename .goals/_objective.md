---
objective: Make writing-goals a complete, accurate, accessible, and maintainable public open-source repository whose value, first-use path, safety model, and contribution expectations are clear from its GitHub front page.
acceptance:
  - "bash tests/run.sh exits 0 and reports every contract suite PASS"
  - "README.md presents the problem, value, worked example, quick start, workflow diagram, scope, platform support, safety boundary, and linked documentation map"
  - "The repository contains an OSI-approved root license plus actionable security, contribution, support, conduct, issue, pull-request, and changelog documentation"
  - "Codex-facing metadata contains no Claude-only /goal wording"
  - "A fresh reviewer confirms that public documentation does not duplicate or contradict the canonical policy in shared/"
stop_rules:
  max_iterations: 8
  max_cost: "USD 0 external spend"
  max_wallclock: "4 hours"
  on_block: escalate-to-human
autonomy_policy: shared/autonomy.md
---

# Publish-ready documentation and community baseline

Turn the approved research recommendations into a coherent public front door and community-health
baseline without changing the canonical goal method, hook behavior, installer contract, or supported
platform scope. Repository-local edits are authorized. Commits, pushes, releases, and external
repository-setting mutations remain outside this objective unless separately authorized.
