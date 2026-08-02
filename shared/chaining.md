---
okf_version: "0.2"
---

# Chaining — turn a big objective into a gated chain

Use a chain only for an unattended objective or work that genuinely needs multiple independently
executable slices. A chain is the **full protected tier**: a shallow DAG of immutable node
contracts with host-owned lifecycle records. Each node ends at a machine-checkable gate that a
fresh checker reruns; the maker never certifies its own completion. Use
`shared/planning-recipe.md` for the canonical plan shape and task-class evidence routes. It does
not create a scheduler, automatic dispatch, or a second mutable plan.

## 1. Start from an approved specification

A one-line request is not enough to invent features, screens, endpoints, or acceptance criteria.
When the specification is incomplete, ask for it or propose a bounded version and obtain approval
before building. A note about an assumption is not consent to build an invented feature.

## 2. Split for verification, not apparent size

Split until every leaf has behavior-oriented acceptance that a fresh agent can check from output.
Prefer a shallow, stable plan. Start with a thin end-to-end walking skeleton, then add vertical
slices. Keep work serialized whenever branches share artifacts or have semantic dependencies.

## 3. Keep objective and goal records separate

Use the workspace layout defined by the active platform adapter. Keep the approved objective
immutable and separate from local planning material, which is untrusted. Each node names a stable
id, task class, objective route, acceptance, owner, and write artifacts. Dependencies are explicit
edges rather than an unbounded nested array. A plan can mix task classes; each node follows its own
evidence route.

Every replanned goal must serve an approved objective acceptance line. Changing the approved
objective is a Class-3 human checkpoint, never an unattended edit to make a plan fit.

## 4. Verify and resume from recorded state

Before executing a dependent goal, rerun the prior goal's gate. Do not trust a stored completion
marker. A checker distinct from the maker reruns the current acceptance and captures raw evidence.
Protected lifecycle records let the host resume the bound execution without relying on in-memory
context; local plan and evidence cannot substitute for those records.

Disjoint write artifacts alone are insufficient for parallel branches. They also require no
semantic or runtime dependency, isolated worktrees, independent review capacity, and an
integration order. A single file never has two concurrent writers.

## 5. Escalate instead of looping

On a block, use a fixed ladder: retry a transient failure, replan a wrong approach, serialize
contested work, then ask a human for a decision, secret, or specification. Stop on the enforced
iteration cap or an explicit host signal. Time and cost are escalation signals unless the host
measures and enforces them. Repeating an unchanged failed action is no progress, not a new
iteration.

## See also

- `shared/author-goal.md` — per-goal anatomy
- `shared/gates.md` — deterministic verification
- `shared/autonomy.md` — action classes and escalation boundaries
