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
| Goal contract | Declared outcome, scope, evidence, and bounds | Independent execution or containment |
| Stop-hook gate | Fresh-process execution of a trusted acceptance command | Protection if the command, surface, or state is writable by the maker |
| Surface digest | Detection of changes after a trusted baseline | A trustworthy first baseline by itself |
| Pre-use deny-list | Best-effort blocking of recognized cooperative mistakes | Sound shell parsing or adversarial containment |
| Goal ledger | Resumable state and dependency visibility | A native scheduler or trusted authority |
| OS-level sandbox | The actual containment boundary | Correct goals or verification |

## Required unattended controls

Run the complete agent process inside an OS-level sandbox with:

- a disposable container or virtual machine;
- a non-root user and dropped capabilities;
- read-only mounts outside the scoped workspace;
- no ambient secrets;
- denied network egress by default, with narrow allowlisting when necessary;
- explicit time, cost, and iteration budgets;
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

Gate state outside the repository is not protected merely by location. Filesystem permissions
must prevent the maker from modifying it.

## Reporting vulnerabilities

Follow [`../SECURITY.md`](../SECURITY.md). Do not put exploit details, secrets, or sensitive paths
in a public issue.

## Canonical policy

This guide summarizes the threat model for public readers. The authoritative operational rules
remain:

- [`../shared/gates.md`](../shared/gates.md)
- [`../shared/autonomy.md`](../shared/autonomy.md)
- the current platform adapter under [`../claude/`](../claude/) or [`../codex/`](../codex/)
