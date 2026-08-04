---
okf_version: "0.2"
---

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

Clone the source, build a portable bundle, and install one adapter from that bundle:

```bash
git clone https://github.com/iliaim/writing-goals.git
cd writing-goals

mkdir -p dist
bash scripts/build-bundles.sh dist/writing-goals
bash dist/writing-goals/install.sh codex
# or
bash dist/writing-goals/install.sh claude
```

Use `bash dist/writing-goals/install.sh all` to preflight and install both transactionally. The
bundle and installed targets are real, symlink-free copies, so installation does not depend on the
source checkout remaining available.

The installer refuses an occupied target unless it already contains an identical copy from that
bundle. It has no force-overwrite option: inspect and manually replace only the exact target if an
upgrade must replace user-owned content.

## Make a first request

In Codex:

```text
$writing-goals Turn the authentication migration into one bounded goal. Investigate this
repository for the exact acceptance command, keep existing CI green, record the observed exit
and pass signal, and escalate if the same check fails twice without progress.
```

In Claude Code:

```text
/writing-goals Turn the authentication migration into one bounded goal. Investigate this
repository for the exact acceptance command, keep existing CI green, record the observed exit
and pass signal, and escalate if the same check fails twice without progress.
```

Review the resulting contract before execution. Product scope, irreversible choices, and absolute
targets must come from you; repository paths and commands should come from investigation.

## Check the result

A well-formed contract names:

1. one observable outcome;
2. the exact sources to read first;
3. explicit non-goals and constraints;
4. an exact, copy-pasteable acceptance command;
5. the specific exit code, string, or number that means success;
6. paths that may and may not change;
7. a documentation-impact decision;
8. a terminal success stop, human-needed stop, and no-progress rule;
9. inherited repository checks;
10. observed exit/result evidence, with full output retained or linked when useful; and
11. checkpoint evidence for coordinated or multi-turn work.

If any of these are missing, revise the contract before running it.

## Add full-tier verification

Interactive goal writing does not require a lifecycle hook. For unattended or genuinely independent executable multi-slice work:

1. read [`../shared/gates.md`](../shared/gates.md);
2. select a trusted, deterministic, non-mutating `GATE_CMD`;
3. make the complete `GATE_SURFACE` read-only to the maker before work;
4. protect gate state with sandbox permissions;
5. configure a positive `GOAL_GATE_CAP`, protected `GATE_AUTHORITY`, and its mode-0600
   `GATE_PREFLIGHT_RECORD`; and
6. install the platform-specific gate; use an OS-level sandbox for unattended execution.

The scripts do not create containment. Read the
[security model](security-model.md) before running an unattended permission mode.

## Update

Check the installed copies and the configured upstream first:

```bash
bash scripts/refresh-local.sh --status
bash scripts/refresh-local.sh --check-updates
```

`--status` is offline and reports the source plus installed Claude/Codex version and revision.
`--check-updates` explicitly contacts the configured Git upstream but never pulls or installs.
When it reports an update is available, run the explicit local refresh command:

```bash
git pull --ff-only
bash scripts/refresh-local.sh --install all
```

The update command is explicit; the refresh command refuses a dirty checkout, runs the contract
suite, builds a new bundle, and moves just the replaced writing-goals targets to
`.archive/writing-goals/` inside this repository. It requires the explicit `--install` flag, does not run on a
schedule, and does not change unrelated skills or agents. Restart Codex and Claude Code afterward.
Review changed hooks before trusting them again. Codex records hook trust against the hook
definition's hash; Claude projects should likewise review project hook changes.

## Uninstall

First inspect the exact installed copy:

```bash
find "$HOME/.claude/skills/writing-goals" -type l -print
find "${CODEX_HOME:-$HOME/.codex}/skills/writing-goals" -type l -print
```

Then remove only the confirmed `writing-goals` target using your normal file-management workflow.
Do not recursively remove a parent skills directory.

## Next

- Learn from the checked patterns in [Examples](examples.md).
- Read the platform-neutral [canonical method](../shared/method.md).
- Configure unattended work only after reading the [Security model](security-model.md).
