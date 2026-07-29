# Workflow — discover, approve, and execute one bounded plan

Discovery is a dialogue: ask one question at a time, record two to four viable alternatives and
why they were rejected, then propose the smallest plan that can produce an observable outcome.
The approval barrier requires a plan approved before dispatch or activation.

Use the existing `research_design` route for decisions that need evidence. Select the highest stable external seam
for verification. Preserve an existing glossary or ADR when one already provides the needed shared
vocabulary or decision record. Use expand-migrate-contract only when unavoidable; otherwise make
the narrow local change.

Plan each goal as a bounded capsule. If it cannot deliver one complete observable outcome inside its
capsule bound, split it and name the integration owner. Start gates must be genuine: prerequisites,
write boundaries, and the exact protected verification surface must be ready before work begins.

Perform one preapproval DAG review. Use sizing and ready-frontier guidance as a heuristic, not state.
Do not create a new spec, ticket, map, or hierarchy as planning state; the approved goal records and
their dependencies are sufficient. scope narrowing requires approval: return the proposal to the user
rather than silently changing the parent objective.
