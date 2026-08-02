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

## 2. Investigate before authoring

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

## 3. Author a lightweight contract

Persist one concise contract for normal interactive work, then freeze it with its observed result.
It contains:

1. one observable outcome and exact scope, including protected paths;
2. an exact acceptance command and explicit pass signal;
3. relevant inherited repository checks, selected from investigation rather than copied blindly;
4. credible alternatives considered and why each was rejected; and
5. the observed exit/result after work, or a concise reason it could not be run.

Record decisions that materially affect behavior, interfaces, data, security, verification, or
irreversible/external actions. Always consider alternatives, but never invent a quota of fake
options. A lightweight contract is an auditable aid to review and resumption, not proof that a
maker may self-certify unattended completion.

## 4. Author a full protected plan only when needed

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

## 5. Verify proportionately

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

## 6. Apply autonomy by blast radius

Use the action classes in `shared/autonomy.md`. Read-only and scoped reversible actions may run
within their bounds. External, spending, irreversible, or trust-boundary actions require explicit,
bounded human authorization. Unattended Class 4 actions are denied.

Hooks are defense in depth, not containment. Full protected execution requires an OS sandbox,
least privilege, scoped writable mounts, restricted egress, protected state, and a kill path.

## Completion checklist

- The chosen tier is the lightest one that provides the needed assurance.
- The outcome, scope, exact check, and pass signal trace to approved intent.
- Alternatives were genuinely considered and material choices are recorded.
- Lightweight evidence names exact commands and observed results; full-tier evidence is rerun
  independently.
- A full plan has approval, preflight, protected state, and fresh verification before completion.
- No claim of a hard time or cost stop is made without actual host enforcement.
