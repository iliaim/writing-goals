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
| Goal ledger | Resumable state and dependency visibility | A native scheduler or trusted authority |
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

## Reporting vulnerabilities

Follow [`../SECURITY.md`](../SECURITY.md). Do not put exploit details, secrets, or sensitive paths
in a public issue.

## Canonical policy

This guide summarizes the threat model for public readers. The authoritative operational rules
remain:

- [`../shared/gates.md`](../shared/gates.md)
- [`../shared/autonomy.md`](../shared/autonomy.md)
- the current platform adapter under [`../claude/`](../claude/) or [`../codex/`](../codex/)
