# Writing Goals

This context defines the language used to turn intent into bounded, independently verifiable work for coding agents.

## Language

**Goal**:
One observable outcome with explicit scope, verification evidence, and bounded stop conditions.
_Avoid_: Task, ticket, wish

**Gate**:
A pre-written check whose result determines whether a Goal may be considered verified.
_Avoid_: Self-assessment, completion claim

**Verification Surface**:
Observable evidence a fresh checker can use to evaluate a Gate without believing the maker.
_Avoid_: Proof by assertion, success message

**Goal Chain**:
A dependency graph of atomic Goals that collectively deliver one larger objective.
_Avoid_: Checklist, nested plan

**Goal Ledger**:
The persisted Goal files and statuses that record a Goal Chain's recoverable state.
_Avoid_: In-memory plan, progress summary

## Relationships

- A **Goal** has one or more **Gates**.
- Each **Gate** evaluates a **Verification Surface**.
- A **Goal Chain** contains one or more **Goals**.
- A **Goal Ledger** records one **Goal Chain**.

## Example dialogue

> **Developer:** Is the session work done?
>
> **Domain expert:** The Goal is implemented, but its Gate has not passed on the behavioral Verification Surface yet.
>
> **Developer:** Then keep it in review in the Goal Ledger. The next Goal in the Goal Chain must not start until a fresh checker verifies it.
