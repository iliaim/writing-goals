---
okf_version: "0.2"
---

# Planning recipe

This recipe is the single canonical policy for a proposed plan. It records a bounded,
human-approved decomposition; it is not a scheduler, task queue, or mutable execution state.

## Required plan fields

Each canonical plan names an `id`, one permitted `task_class`, `requirements`,
`objective_acceptance`, an `execution_recipe`, a dependency `dag`, and the fixed planning
`workflow`. The execution recipe contains inputs, outputs, disjoint maker and oracle paths,
ordered evidence commands with explicit expected exits, handoff, fan-in owner, risks, and stop
conditions. Commands are copied exactly from investigated repository surfaces, never invented
as placeholders.

`requirements` and `objective_acceptance` provide routes from every slice to approved intent
and acceptance. The DAG has unique node ids, refers only to known dependencies, and is acyclic.
The workflow is `discover, author, lint, challenge, freeze`: lint completes before challenge and
freeze. A navigation index links to the canonical plan but does not duplicate this policy.

## Task-class routes

| task_class | required route |
|---|---|
| behavioral_code | behavioral_code → red or characterization → green |
| docs_config | docs_config → red or characterization → green |
| refactor | refactor → characterization → green |
| research_design | research_design → source and challenge; research_design does not invent red/green work |

The route identifies required evidence shape, not whether a proposal is good. A linter may check
only structure, paths, bindings, and ordering; it never judges semantic quality or prose.

## Authority and derived records

Planner, challenger, and reviewer read the canonical plan and this recipe rather than copying
policy into prompts. Approval remains a bounded human decision. A role capsule and planning
receipt are rendered on demand from a plan manifest and explicit inputs; they are derived,
ephemeral outputs, not plan, dispatch, selection, or approval state.

Do not create a new planning spec, ticket, map, or hierarchy. Heuristics are not state. Scope
narrowing requires approval; return to the user when it changes approved intent.
