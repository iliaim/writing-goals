---
okf_version: "0.2"
---

# Authoring contracts

Investigate first. A contract that a reviewer cannot understand without trusting the maker is not
ready.

## Lightweight contract — the normal path

Use `assets/goal.md.tmpl` for ordinary interactive work. It is persisted so a later reviewer can
see what was intended, but it never drives lifecycle state or authorizes activation.

A lightweight contract requires:

1. **Outcome and scope** — one vertical result, paths that may change, and paths that are
   protected from change.
2. **Delivery plan and user review** — for coordinated multi-step work, one parent delivery
   objective; the applicable context, review, implementation, verification/validation, and
   delivery/closure phases; their deliverables and gates; and the user's approval, revision, or
   recorded review waiver before implementation. This is intent evidence, not lifecycle state.
3. **Acceptance criteria** — identify material starting conditions as **Given**, the completed
   action as **When**, and each independently observable, cumulative success condition as
   **Then**. Every criterion is mandatory; use a concrete expected output, access decision, file,
   response, or other observable result rather than “works correctly.”
4. **Verification** — one exact, copy-pasteable acceptance command with a concrete pass signal,
   plus a specific manual observation where automation cannot establish a criterion; relevant
   repository regression checks are listed separately.
5. **Investigation record** — the selected baseline status, or why a safe baseline run was not
   practical.
6. **Alternatives considered** — record credible approaches and why each was rejected. Do not add
   invented alternatives just to fill a number.
7. **Observed result and closure** — record the executed command, exit status, concise result,
   delivery or handoff evidence where applicable, and any residual risk or unmet requirement. Link or
   retain full output for failures and whenever it is useful for diagnosis.

The maker must not edit, skip, xfail, or delete the verification surface to reach green. A build,
typecheck, or lint is a proxy unless it exercises the requested behavior; label it honestly.

## Full protected plan — exceptional path

Use a full plan only for unattended or genuinely independent multi-slice work. Every node carries the same essentials as
a lightweight contract plus its task class, objective route, maker and oracle write boundaries,
and exact evidence binding. `shared/planning-recipe.md` defines the complete shape.

The protected oracle author creates and freezes oracle-owned tests before activation. The maker
then changes only maker-owned paths. A fresh verifier and reviewer rerun and inspect the result.

## Evidence and escalation

Do not treat a maker’s prose as proof. A lightweight reviewer reruns the named command when the
risk warrants it; the full tier always does. Stop and escalate on a blocked baseline, an unclear
acceptance target, a required external action, or repeated no-progress. An iteration cap may be
enforced by the full-tier host; time and cost are estimates unless the host measures them.
