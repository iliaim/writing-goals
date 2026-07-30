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

## G07 protected sequential core

The host owns activation and continuation. Activation binds the approved identity, plan, run,
objective digest, plan digest, and frozen execution order; activation also binds the frozen order and digest.
It validates that every declared node appears
once in that order, that no unknown node appears, and that predecessor evidence is current. A stale
predecessor, untrusted report, undeclared successor, or parallel-dispatch request fails closed.

The host selects the first ready node in frozen order, then records its exact node and role cursor. The
protected handoff sequence is `oracle-author`, `maker`, `verifier`, `reviewer`; an interrupted run resumes
that recorded cursor rather than selecting a latest task or restarting a role. A completed checkpoint
permits only the recorded successor and leaves the parent in progress until every ordered slice is complete.

`assets/runtime-check.sh --core-fixture PATH --resume` is a non-mutating validation seam for this protocol.
It reports the recorded cursor or an explicit rejection; it does not select work, dispatch an agent, create
background continuation, or advance the parent. The host performs any selection and dispatch only after a
successful check has returned.
