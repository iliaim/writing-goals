# Protected lifecycle state

Lifecycle state belongs only in an external protected authority directory. The
repository and its `.writing-goals` data are not a fallback source of truth.
The authority is an absolute, non-symlinked directory that is not writable by
group or other users.

`assets/run-state-cas.sh` is the narrow writer. It accepts an explicit
identity, `pNN` plan, run ID, expected generation and digest, next state, and
candidate. It locks that explicit run, compares the protected preimage, writes
a same-directory private temporary record, then atomically replaces the active
record. It never selects a run or a next node.

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
