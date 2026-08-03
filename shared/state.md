---
okf_version: "0.2"
---

# Protected lifecycle state

Lifecycle state belongs only in a local protected authority directory. The repository and its
local planning data are not a fallback source of truth. This v1 boundary accepts a single-machine
risk; it provides no export or cross-host recovery mechanism.
The authority is an absolute, non-symlinked directory that is not writable by
group or other users.

Before activation, the authority additionally contains an immutable approval attestation bound to
the exact objective and plan digests, with approver identity, timestamp, and revocation status. It
also contains an immutable preflight record bound to those digests and the verification-surface
digest. The host creates both; repository documents cannot substitute for either record.

`assets/run-state-cas.sh` is the narrow writer. It accepts an explicit
identity, `pNN` plan, run ID, expected generation and digest, next state, and
candidate. It locks that explicit run, compares the protected preimage, writes
a same-directory private temporary record, then atomically replaces the active
record. It never selects a run or a next node.

The Codex foreground supervisor additionally owns `core-state.env`,
`continuation.env`, `continuation-state.env`, and `continuation-receipts/` inside the same
authority. `core-state.env` is mode 0600, has the G07 cursor fields plus a monotonic
`transition_generation` and `previous_core_sha256`, and is never supplied as a caller path.
`continuation.env` binds one exact UUID session, pinned supervisor/checker digests, a sandbox
profile, a separately pinned trusted advance-helper digest, and a positive no-progress cap. A
trusted host may stage mode-0600 `core-next.env`; `assets/core-state-advance.sh` checks its exact
preimage digest and monotonic fields, validates a private copy with the runtime checker, then
atomically installs it as `core-state.env`. The Codex child never runs that helper. The supervisor holds its per-run lease through the
Codex child, writes append-only mode-0600 intent/exit/advance/block/terminal receipts, and blocks
rather than stealing a stale lease or retrying a non-monotonic cursor.

The vocabulary is `pending`, `implementing`, `reviewing`, `blocked`, `done`,
and `cancelled`. Completion requires current successful check, verifier, and
reviewer receipts bound to the exact candidate. A protected `receipts/` store
is mandatory for completion; each locator is resolved below that directory
without symlinks and its immutable identity, plan, candidate, actor, result,
and binding digest are validated. The binding digest is SHA-256 of the pipe-joined
`receipt|identity|plan|candidate|actor|result` fields. Cancellation requires explicit
abandonment authority. A failed review can return to implementation only for a
different candidate; an unchanged remediation is persisted as `blocked`.

`assets/runtime-check.sh --status` is read-only and returns the derived current
record. It does not expose progress percentages or select work. Reopening is
only considered before a protected binding exists and with revoked approval;
a bootstrap record is itself a binding, so it cannot alter an authority that
contains `bootstrap.env` or an active record.
