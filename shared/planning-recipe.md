---
okf_version: "0.2"
---

# Full protected-plan recipe

This recipe applies only to unattended or genuinely independent multi-slice work. It records a bounded, human-approved
decomposition; it is not a scheduler, task queue, or mutable execution state. Normal interactive
work uses the lightweight contract in `assets/goal.md.tmpl` instead.

## Required full-plan fields

The plan records an `id`, `objective_acceptance`, credible `alternatives`, a dependency `dag`, and
the fixed planning `workflow`. Every DAG node names:

- an `id`, one permitted `task_class`, and a structural `evidence_route` compatible with that
  task class;
- requirement and objective-acceptance routes;
- an execution recipe with inputs, outputs, disjoint maker and oracle paths, ordered exact-argv
  evidence commands with expected exits, handoff, fan-in owner, risks, and stop conditions; and
- dependencies on known nodes only.

Commands are copied exactly from investigated repository surfaces, never invented as placeholders.
Plans may mix node task classes. A node—not a whole plan—selects its evidence route:

| task_class | required route |
|---|---|
| behavioral_code | `red_to_green` or `characterization_to_green` |
| docs_config | `red_to_green` or `characterization_to_green` |
| refactor | `characterization_to_green` |
| research_design | `source_and_challenge`; research_design does not invent red/green work |

Every credible alternative considered is recorded with its rejection reason. The alternatives and
their rejection reasons are evidence of a decision, not a fixed quota. Do not manufacture a
fixed number of alternatives; an obvious option may have one rejected alternative, while an
unusually constrained problem may record none with a top-level `no_credible_alternative_reason`.

The DAG has unique node ids, refers only to known dependencies, and is acyclic. The workflow is
`discover, author, lint, challenge, freeze`: lint completes before challenge and freeze. A
navigation index links to the canonical plan but does not duplicate this policy.

## Approval and activation

The host stores approval separately from the immutable plan. Before activation, a protected
approval attestation binds the exact objective digest, plan digest, approver identity, approval
timestamp, and revocation status. A new digest or revocation requires new approval; the receipt
does not duplicate scope or bounds already bound by the plan.

The host also stores a protected preflight record that proves a green verification baseline and
the frozen verification-surface digest before maker work. The full-tier validator checks the
record bindings; it does not select work or create a scheduler.

## Authority and derived records

Planner, challenger, and reviewer read the canonical plan and this recipe rather than copying
policy into prompts. A role capsule and planning receipt are rendered on demand from a plan
manifest and explicit inputs; they are derived, ephemeral outputs, not plan, dispatch, selection,
or approval state.

An activatable successor revision is a complete, self-contained canonical plan: it binds every
retained goal and the complete frozen execution order through its own manifest. A narrow correction
to an already completed revision is untrusted evidence only; it must not claim activation or
terminal/release authority. This prevents a partial patch from silently becoming a second plan.

Do not create a new planning spec, ticket, map, or hierarchy. Heuristics are not state. Scope
narrowing requires approval; return to the user when it changes approved intent.
