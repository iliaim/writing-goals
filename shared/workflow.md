---
okf_version: "0.2"
---

# Full protected workflow — discover, approve, and execute one bounded plan

This workflow is for the full protected tier only. A normal interactive task uses the lightweight
contract and does not create a protected lifecycle run.

Discovery considers and records credible alternatives with rejection reasons, then proposes the
smallest plan that can produce an observable outcome. A human approves the frozen plan before
activation. The host records that approval as a protected attestation bound to the exact objective
and plan digests.

Before approval, render a user-visible review packet from the canonical plan. It shows the parent
delivery objective, scope and non-goals, final acceptance, phase deliverables and dependencies,
verification/validation evidence, risks, and the proposed delivery or closure result. The user may
approve, request revision, change scope, pause, or cancel. A revision that changes the frozen
objective or plan requires a new approval attestation; the review packet is derived from the plan
and never becomes additional lifecycle authority.

Before activation, the oracle author defines and freezes the oracle-owned verification surface.
The host records a protected preflight baseline proving it was green and frozen before maker work.
The maker never writes oracle-owned paths.

Use the existing `research_design` route for decisions that need evidence. Select the highest
stable external seam for verification. Preserve an existing glossary or ADR when one already
provides the needed shared vocabulary or decision record. Use expand-migrate-contract only when
unavoidable; otherwise make the narrow local change.

Plan each node as a bounded capsule. If it cannot deliver one complete observable outcome inside
its capsule bound, split it and name the integration owner. Start gates must be genuine:
prerequisites, write boundaries, approval, preflight baseline, and the exact protected verification
surface must be ready before maker work begins.

Perform one preapproval DAG review. Use sizing and ready-frontier guidance as a heuristic, not
state. Do not create a new spec, ticket, map, or hierarchy as planning state; the approved goal
records and their dependencies are sufficient. Scope narrowing requires approval; return the
proposal to the user rather than silently changing the parent objective.

G13 is terminal only when all goals and final verification are complete. One human
external-publication gate follows terminal G13 and is required before any push, pull request,
merge, release, or deploy; there is no mid-plan human publication gate.

## G07 protected sequential core

The host owns activation and continuation. Each activation is bound to the frozen execution order
and plan digest, plus the approved identity, plan, run, and objective digest. It validates that every declared node
appears once in that order, that no unknown node appears, and that predecessor evidence is current.
A stale predecessor, untrusted report, undeclared successor, missing approval/preflight, or
parallel-dispatch request fails closed.

The host selects the first ready node in frozen order, then records its exact node and role cursor.
The protected runtime handoff sequence is `maker`, `verifier`, `reviewer`; the oracle author is a
pre-activation role. An interrupted run resumes that recorded cursor rather than selecting a
latest task or restarting a role. A completed checkpoint permits only the recorded successor and
leaves the parent in progress until every ordered slice is complete.

`assets/runtime-check.sh --core-fixture PATH --resume` remains a non-mutating **test** seam. It
reports a recorded cursor or an explicit rejection; it does not select work, dispatch an agent,
create background continuation, or advance the parent.

The Codex adapter's `assets/codex-continuation.sh` foreground host supervisor accepts only an
authority, identity, plan, and run; it derives the exact session, sandbox profile, pinned tool
paths, and `core-state.env` cursor from protected authority records. Before every exact-session
host resume, it reruns the protected check, holds one run-wide lease, and appends
intent/exit/advance/block receipts. It never uses a latest session, model prose, a repository
plan, or a caller-selected fixture as lifecycle authority. A changed cursor is progress only when
its transition generation increases and binds the prior core digest; unchanged work reaches the
enforced no-progress cap and blocks.

The child sandbox cannot write this cursor. After a fresh protected check, a separate trusted host
may stage mode-0600 `core-next.env` and invoke `assets/core-state-advance.sh` with the exact
preimage digest. That helper validates a private copy before its one atomic live replacement and
alone installs a valid, monotonic successor; it is never invoked by
the Codex child and does not select the successor from model output.

The supervisor is a synchronous local process, not a daemon, cron service, or general DAG
scheduler. It requires an OS sandbox that denies the resumed child access to the authority and
trusted tool root; a host restart or a stale lease is a human-reconciliation condition.
