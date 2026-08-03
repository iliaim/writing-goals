---
okf_version: "0.2"
---

# Security model

`writing-goals` provides a method, lifecycle gates, and a best-effort pre-use policy. It does not
provide process isolation or protect a machine from a hostile or prompt-injected agent.

## Security objective

For unattended execution, reduce accidental scope escape and require an independent, bounded
acceptance check while relying on an OS-level sandbox for containment.

## Threats in scope

- a cooperative agent accidentally writes outside the intended repository;
- the maker edits, skips, or deletes its own verification surface;
- a failing task retries indefinitely;
- malformed or writable gate state removes the intended bound;
- a trusted verification command is replaced with untrusted input; and
- documentation overstates what a hook can guarantee.

## Threats not contained by these scripts

- a malicious or prompt-injected process intentionally bypassing shell-string matching;
- interpreter, quoting, newline, symlink, or environment tricks not recognized by the policy;
- credential theft through ambient filesystem or network access;
- container or VM escape;
- compromised dependencies, runner images, or operating systems; and
- production access already available to the agent.

## Trust boundaries

| Component | What it provides | What it does not provide |
|---|---|---|
| Goal contract | Declared outcome, scope, and evidence | Independent execution or containment |
| Stop-hook gate | Fresh-process execution of a trusted acceptance command | Protection if the command, surface, or state is writable by the maker |
| Surface digest | Detection of changes after a trusted baseline | A trustworthy first baseline by itself |
| Pre-use deny-list | Best-effort blocking of recognized cooperative mistakes | Sound shell parsing or adversarial containment |
| Goal ledger | Resumable state and dependency visibility | A general scheduler or containment |
| Codex continuation supervisor | One exact-session, foreground resume with durable receipts | Containment, daemon recovery, or authority over objective/plan changes |
| OS-level sandbox | The actual containment boundary | Correct goals or verification |

## Required unattended controls

Run the complete agent process inside an OS-level sandbox with:

- a disposable container or virtual machine;
- a non-root user and dropped capabilities;
- read-only mounts outside the scoped workspace;
- no ambient secrets;
- denied network egress by default, with narrow allowlisting when necessary;
- an enforced iteration cap, plus time/cost limits only when the host can measure and enforce them;
- gate state the maker cannot write;
- a read-only verification surface established before maker work; and
- an independent kill path.

The gate and deny-list belong inside that sandbox as defense in depth.

## Trusted configuration

`GATE_CMD` is intentionally evaluated as shell code. Only a trusted operator or orchestrator may
set it. Never derive it from issue text, model output, user-controlled repository content, or
another untrusted source.

`GATE_SURFACE` is a whitespace-separated shell glob/list resolved from the repository root. Every
expansion must be a regular file. Filenames containing whitespace are unsupported.

`GATE_PREFLIGHT_RECORD` is a mode-0600 receipt inside protected `GATE_AUTHORITY`, not a
caller-supplied digest. It carries objective and plan digests, a `sha256:` surface digest, and a
green baseline. The gate validates that receipt and rejects a missing or mismatched surface before
running `GATE_CMD`.

Gate state outside the repository is not protected merely by location. Filesystem permissions
must prevent the maker from modifying it.

The Codex continuation supervisor is trusted host code. Invoke the installed copy, not a
workspace copy, from a tool root the child sandbox cannot write. Its `continuation.env` pins the
controller and checker digests; its profile must deny the child all reads/writes to the authority
and writes to that tool root. [`../assets/codex-continuation.sb.tmpl`](../assets/codex-continuation.sb.tmpl)
is only a minimum macOS profile: the host must still scope workspace writes, secrets, and egress.

### Codex foreground continuation

The trusted host creates mode-0600 `continuation.env` in the authority with exactly these fields:
`identity`, `plan`, `run`, `session_id` (an exact UUID), `workspace`, `codex_bin`,
`sandbox_profile`, `trusted_root`, `controller_sha256`, `runtime_path`, `runtime_sha256`, and a
trusted `advance_path`, `advance_sha256`, and a positive `no_progress_cap`. `runtime_path`, the
advance helper, and the installed controller all live below `trusted_root`; hash them after
installation, not from a mutable workspace. The host also creates mode-0600 `core-state.env` with the current G07 cursor plus a numeric
`transition_generation` and `previous_core_sha256` (`bootstrap` only for the first cursor).

Then invoke the installed controller with no other configuration inputs:

```bash
bash "$CODEX_HOME/skills/writing-goals/assets/codex-continuation.sh" \
  --authority /absolute/protected-authority \
  --identity YYYYMMDD-ABC123 --plan p01 --run protected-run-id
```

It fails closed on an altered tool digest, any absent/unsafe authority record, an ambiguous lease,
a Codex child failure, or a cursor that does not monotonically bind its predecessor. A local test
double proves controller protocol only; before using this with a real run, test the installed
profile and exact-session resume in the intended host environment.

The sandboxed child never writes a cursor. Following a fresh independent check, the trusted host
may write a mode-0600 `core-next.env` in the authority and invoke the installed advance helper
with the SHA-256 of the current `core-state.env`:

```bash
bash "$CODEX_HOME/skills/writing-goals/assets/core-state-advance.sh" \
  --authority /absolute/protected-authority \
  --identity YYYYMMDD-ABC123 --plan p01 --run protected-run-id \
  --expected-core-sha256 CURRENT_CORE_SHA256
```

The helper rejects a stale preimage or non-monotonic cursor, validates the staged record through
the pinned runtime checker in a private authority copy, and atomically replaces the active record
only on success. It does
not derive a successor from model output and must never be callable from the child sandbox.

## Reporting vulnerabilities

Follow [`../SECURITY.md`](../SECURITY.md). Do not put exploit details, secrets, or sensitive paths
in a public issue.

## Canonical policy

This guide summarizes the threat model for public readers. The authoritative operational rules
remain:

- [`../shared/gates.md`](../shared/gates.md)
- [`../shared/autonomy.md`](../shared/autonomy.md)
- the current platform adapter under [`../claude/`](../claude/) or [`../codex/`](../codex/)
