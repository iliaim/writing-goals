---
okf_version: "0.2"
---

# Verification evidence

The closed task classes are `behavioral_code`, `docs_config`, `refactor`, and `research_design`.
The protected oracle is distinct from maker-owned tests; a fresh verifier and fresh reviewer supply
independent evidence. Each completed receipt binds the objective, criterion, oracle, and candidate.
Checks retain their exact argv (argument vector); reviews retain their exact scope. Output is retained
as a bounded output hash. derive currentness from these exact bindings, never store it as a state.
Failed receipts remain history; a remediation needs a materially different candidate and fresh review.
