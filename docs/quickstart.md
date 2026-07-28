# Quick start

This guide gets the current source distribution installed and produces a first bounded goal
contract. It does not configure unattended execution automatically.

## Choose a platform

| Platform | Invoke | Install target |
|---|---|---|
| Claude Code | `/writing-goals` | `~/.claude/skills/writing-goals` |
| Codex | `$writing-goals` or `/skills` | `${CODEX_HOME:-$HOME/.codex}/skills/writing-goals` |

The method is platform-neutral. The ready-to-use adapters in this repository support these two
platforms.

## Install

Requirements:

- Bash 3.2 or newer
- `jq` when using a lifecycle gate
- `shasum` or `sha256sum` when using verification-surface hashing

Clone the source and install one adapter:

```bash
git clone https://github.com/iliaim/writing-goals.git
cd writing-goals

./sync.sh codex
# or
./sync.sh claude
```

Use `./sync.sh all` to preflight and install both. The installer creates live symlinks to this
checkout. This is the current distribution model, so moving or deleting the checkout breaks those
links.

The installer refuses an occupied target unless it already contains the complete canonical layout
from this checkout. Read the output before considering `--force`; it replaces the exact selected
`writing-goals` target and can delete content stored there.

## Make a first request

In Codex:

```text
$writing-goals Turn the authentication migration into one bounded goal. Investigate this
repository for the exact acceptance command, keep existing CI green, require raw output and an
exit code, stop if the same check fails twice without progress, and stop after four iterations,
USD 5 of model/API cost, or 45 minutes.
```

In Claude Code:

```text
/writing-goals Turn the authentication migration into one bounded goal. Investigate this
repository for the exact acceptance command, keep existing CI green, require raw output and an
exit code, stop if the same check fails twice without progress, and stop after four iterations,
USD 5 of model/API cost, or 45 minutes.
```

Review the resulting contract before execution. Product scope, irreversible choices, and absolute
targets must come from you; repository paths and commands should come from investigation.

## Check the result

A well-formed contract names:

1. one observable outcome;
2. an exact, copy-pasteable acceptance command;
3. the specific exit code, string, or number that means success;
4. paths that may and may not change;
5. inherited repository checks;
6. raw output and exit-code evidence; and
7. success, failure, iteration, cost, and wall-clock stops.

If any of these are missing, revise the contract before running it.

## Add unattended verification

Interactive goal writing does not require a lifecycle hook. For unattended work:

1. read [`../shared/gates.md`](../shared/gates.md);
2. select a trusted, deterministic, non-mutating `GATE_CMD`;
3. make the complete `GATE_SURFACE` read-only to the maker before work;
4. protect gate state with sandbox permissions;
5. configure a positive `GOAL_GATE_CAP`; and
6. install the platform-specific gate inside an OS-level sandbox.

The scripts do not create containment. Read the
[security model](security-model.md) before running an unattended permission mode.

## Update

Because the install uses live symlinks, update the checkout in place:

```bash
git pull --ff-only
bash tests/run.sh
```

Review changed hooks before trusting them again. Codex records hook trust against the hook
definition's hash; Claude projects should likewise review project hook changes.

## Uninstall

First resolve the exact installed target and confirm it belongs to this checkout:

```bash
readlink "${CODEX_HOME:-$HOME/.codex}/skills/writing-goals"
ls -l "$HOME/.claude/skills/writing-goals"
```

Then remove only the confirmed `writing-goals` target using your normal file-management workflow.
Do not recursively remove a parent skills directory.

## Next

- Learn from the checked patterns in [Examples](examples.md).
- Read the platform-neutral [canonical method](../shared/method.md).
- Configure unattended work only after reading the [Security model](security-model.md).
