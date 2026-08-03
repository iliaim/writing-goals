---
okf_version: "0.2"
---

# Canonical goal method

This is the platform-neutral contract for writing and running goals. Platform adapters add only
invocation and host facts; they do not redefine the method.

## 1. Choose the lightest useful tier

Do not create a goal for a small one-shot edit with no useful verification boundary. For work that
does need a contract, choose one tier before authoring:

- **Lightweight contract** — the default for normal interactive coding. Persist one concise draft
  with outcome, scope, exact checks, credible alternatives considered, and the observed result;
  freeze it when that result is recorded. It is not lifecycle authority and does not need a
  scheduler, hook, human approval receipt, or mandatory fresh verifier.
- **Full protected plan** — required only for unattended execution or an objective that needs
  multiple genuinely independent executable slices. It has a frozen plan, per-node contracts, a protected
  approval attestation, host-owned lifecycle state, and fresh verification.

The tier describes assurance, not importance. Do not promote routine interactive work merely to
make it look controlled.

## 2. Resolve context before authoring

Read the current session, any active goal or plan, the latest user message, and the repository
state together. The latest message is evidence, not the only source of intent. A message that does
not repeat an objective is not, by itself, a reason to stop or to create a smaller replacement
goal.

- If an active non-terminal delivery objective still matches the session and the user has not
  replaced its scope, retain that parent objective and advance the next appropriate phase.
- If the surrounding context supports one likely outcome but some details remain derivable, state
  the proposed parent delivery objective and continue investigation; do not pretend that a child
  task is the whole outcome.
- If a material choice about outcome, scope, Definition of Done, risk, or acceptance remains
  ambiguous, present a compact **decision packet**: the decision needed, the recommended option
  and why, one or two credible alternatives with their consequences, and the proposed default.
  Ask only the decision-bearing question needed to proceed.
- If no active or credible outcome can be found, say what was checked and ask for a bounded
  objective. Do not silently complete the interaction with only “no new objective.”

For a full protected run, conversational context may explain a request to continue or revise, but
it never selects a plan, run, or cursor. The protected host authority remains the only source of
the exact lifecycle state.

## 3. Investigate before authoring

Read repository guidance, implementation, tests, package scripts, CI configuration, and working
tree state. Identify the strongest practical verification surface and its exact command; never
infer a command from a language or framework. Follow `shared/investigate.md`.

Classify each required fact:

- **MUST-ASK:** user intent, scope, Definition of Done, absolute targets, irreversible choices,
  and a missing decomposition specification. Stop for an answer, or propose a bounded
  specification and get approval before execution.
- **DERIVE-then-CONFIRM:** repository facts that can be discovered, such as commands, paths,
  conventions, relative baselines, and candidate execution limits. Read first, record meaningful
  choices, and confirm a choice that changes product behavior or scope.

For a lightweight contract, run a safe, scoped baseline check when practical. Do not run a slow,
networked, costly, or side-effectful command merely to satisfy a rule; record why it was not run.
A full protected plan requires a host-owned green baseline before maker activation.

## 4. Author a lightweight contract

Persist one concise contract for normal interactive work, then freeze it with its observed result.
It contains:

1. one observable outcome and exact scope, including protected paths;
2. one or more cumulative acceptance criteria: state material starting conditions as **Given**, the
   completed action as **When**, and every independently observable success condition as **Then**;
   all listed criteria are required;
3. an exact acceptance command and explicit pass signal, plus a specific manual observation when
   automation cannot establish a criterion;
4. relevant inherited repository checks, selected from investigation rather than copied blindly;
5. credible alternatives considered and why each was rejected; and
6. the observed exit/result after work, or a concise reason it could not be run.

Record decisions that materially affect behavior, interfaces, data, security, verification, or
irreversible/external actions. Always consider alternatives, but never invent a quota of fake
options. Avoid unverifiable criteria such as “works correctly”; name the expected output, access
decision, file, response, or other observable result instead. A lightweight contract is an
auditable aid to review and resumption, not proof that a maker may self-certify unattended
completion.

Where a host supports a native goal, its parent-level outcome and acceptance criteria must be
self-contained, and its final acceptance check must be explicit. It may include one optional
stable, workspace-relative pointer to the persisted contract or frozen plan for navigation, but
the pointer cannot replace a criterion, redefine scope, or become lifecycle authority. For a full
plan, derive the native parent criteria from the frozen `objective_acceptance`; completing child
slices is intermediate evidence, not the parent outcome.

## 5. Present a reviewable delivery plan before implementation

For work that needs coordination beyond a direct one-shot edit, create one parent **delivery
objective** and a concise, user-visible plan before making implementation changes. The plan is a
review packet, not a second goal or a new lifecycle authority. It names the intended user value,
scope and non-goals, cumulative final acceptance, verification methods, dependencies, risks, and
the deliverable and gate for each applicable phase:

1. **Context and intent** — the active outcome or a resolved decision packet.
2. **Plan and user review** — the delivery objective, proposed work, alternatives, and review
   outcome.
3. **Implementation and integration** — bounded slices that produce concrete evidence.
4. **Verification and validation** — verification proves the stated criteria; validation confirms
   the delivered behavior meets the underlying user need.
5. **Delivery and closure** — final acceptance, authorized handoff or publication where relevant,
   residual risks or unmet requirements, and durable evidence of the result.

Present this packet to the user and give them a clear opportunity to approve it, request a
revision, change scope, pause, or cancel. Do not start implementation until the user has provided
a review outcome, unless the task is a direct one-shot edit or the user has expressly waived plan
review. A user review is ordinary conversational authorization for lightweight work; it does not
replace the protected approval attestation required for a full plan. A phase can enable the next
phase, but neither a completed slice nor a completed phase can complete the parent delivery
objective.

## 6. Author a full protected plan only when needed

A full plan is a shallow DAG of immutable node contracts. Every node has its own task class,
scope, write paths, protected oracle paths, acceptance command, expected exit, and route to the
approved objective acceptance. A plan may mix task classes; its summary is derived from the
nodes. Use `shared/planning-recipe.md` and its structural validator.

Before activation, the host must have:

- an exact frozen objective and plan digest;
- a protected human approval attestation bound to both digests;
- a protected preflight record proving the verification surface was baselined before maker work;
- a protected lifecycle authority and a sandbox that protects it from the maker.

The host, not this skill, selects work, dispatches roles, and resumes a run. See
`shared/workflow.md` and `shared/state.md`.

## 7. Verify proportionately

For lightweight work, record the exact commands, expected pass signals, and observed exit/result.
Retain or link full output when it is useful, and always retain it for a failure or investigation.
A reviewer may rerun the named commands; a bare “tests passed” claim is never evidence.

For full protected work, a trusted verifier reruns the acceptance command in a fresh process. The
maker may not weaken, skip, delete, or rewrite the verification surface to pass. The lifecycle
gate, its retry counter, and surface protection are required for every full-tier run. OS sandbox
and egress containment remain additional controls for unattended execution.

Iteration caps are enforceable controls. Time and cost are planning estimates and escalation
signals unless the host explicitly supplies a trustworthy measurement and enforcement mechanism;
do not describe them as hard stops otherwise.

## 8. Apply autonomy by blast radius

Use the action classes in `shared/autonomy.md`. Read-only and scoped reversible actions may run
within their bounds. External, spending, irreversible, or trust-boundary actions require explicit,
bounded human authorization. Unattended Class 4 actions are denied.

Hooks are defense in depth, not containment. Full protected execution requires an OS sandbox,
least privilege, scoped writable mounts, restricted egress, protected state, and a kill path.

## Completion checklist

- The chosen tier is the lightest one that provides the needed assurance.
- The outcome, scope, exact check, and pass signal trace to approved intent.
- Alternatives were genuinely considered and material choices are recorded.
- A coordinated delivery plan was presented for user review before implementation, or a valid
  one-shot/review-waiver exception is recorded.
- Lightweight evidence names exact commands and observed results; full-tier evidence is rerun
  independently.
- A full plan has approval, preflight, protected state, and fresh verification before completion.
- No claim of a hard time or cost stop is made without actual host enforcement.
