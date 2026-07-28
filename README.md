# writing-goals

`writing-goals` is a small, agent-agnostic method for turning intent into bounded,
machine-verifiable goals. The shared method covers investigation, goal authoring,
deterministic gates, optional decomposition, and safe unattended execution. Thin adapters add
the current Claude Code and Codex invocation and hook details.

The core rule is simple: the maker does not certify its own completion. A fresh checker must be
able to rerun an exact acceptance command and reach the same result.

## Requirements

- Bash 3.2 or newer for the installer, gates, and contract tests
- `jq` for either lifecycle gate
- `shasum` or `sha256sum` for verification-surface hashing

No language package manager is required by this repository.

## Development install

The installer creates **live symlinks** back to this checkout. This is a development install:
edits in this repository immediately affect the installed skill.

```bash
./sync.sh claude
./sync.sh codex
# or preflight and install both:
./sync.sh all
```

Claude is installed at `~/.claude/skills/writing-goals`; Codex at
`${CODEX_HOME:-$HOME/.codex}/skills/writing-goals`. A normal install refuses an occupied target
unless it is the complete canonical layout previously created from this checkout. `all`
preflights both targets before changing either one and restores their prior states if a handled
installation command fails. This is compensated rollback, not crash-safe storage: `SIGKILL`,
power loss, and unsupported concurrent changes remain outside the installer contract.

If you have inspected the exact destination and deliberately want to replace it:

```bash
./sync.sh --force claude
./sync.sh --force codex
```

`--force` removes only the selected `writing-goals` target, then recreates its links. It can
delete user content inside that exact target, so back it up first. It does not replace parent
skill directories. For `--force all`, both originals are retained until both replacement layouts
succeed and are restored after a handled installation failure.

Invoke the installed skill as `/writing-goals` in Claude Code or `$writing-goals` (or the
`/skills` picker) in Codex.

## Deterministic gate

The gate is optional for interactive goal writing and recommended for unattended execution.
Copy the platform script into the target repository, make it executable, and configure all
three inputs in the environment that launches the agent:

```bash
export GATE_CMD='bash tests/run.sh'       # trusted, deterministic, non-mutating
export GOAL_GATE_CAP=6                    # explicit positive base-10 integer
export GATE_SURFACE='tests/*.sh'          # mandatory repo-relative shell glob/list
```

`GATE_CMD` is evaluated as shell code, so it is a trusted configuration boundary, not
untrusted input. `GATE_SURFACE` uses whitespace-separated shell words and cannot represent
filenames containing whitespace. Every expansion must resolve to a regular file.

The stored digest only detects changes after a **trusted baseline** exists. The currently
supported safe setup makes the complete verification surface read-only to the maker before work
starts. A trusted orchestrator can establish the first digest only by invoking the hook with the
exact same session payload and state key before maker edits. The scripts have no prime-only
interface, so a manual or pre-session run is not reliable priming. Keeping gate state outside the
repository is not sufficient by itself; sandbox permissions must also prevent the maker from
altering it.

For Claude Code:

```bash
mkdir -p .claude/hooks
cp /path/to/writing-goals/assets/gate.claude.sh .claude/hooks/
chmod +x .claude/hooks/gate.claude.sh
```

Register the minimal project Stop hook in `.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/gate.claude.sh"
      }]
    }]
  }
}
```

Claude normally overrides a Stop hook after eight consecutive blocks without progress, so keep
`GOAL_GATE_CAP <= 8` unless `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` is deliberately raised to at least
the same value.

For Codex:

```bash
mkdir -p .codex/hooks
cp /path/to/writing-goals/assets/gate.codex.sh .codex/hooks/
chmod +x .codex/hooks/gate.codex.sh
```

Register it with an absolute path in `.codex/hooks.json`, then review and trust the hook:

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "/absolute/path/to/repo/.codex/hooks/gate.codex.sh"
      }]
    }]
  }
}
```

On a red check below the cap, either adapter emits `{"decision":"block",...}` and asks for
another iteration. A green check exits cleanly with no JSON. Invalid configuration or state,
and a red check at the cap, are terminal needs-human outcomes emitted as
`{"continue":false,"stopReason":...}`. Failing command output is kept in a session-keyed,
mode-0600 state log rather than returned to the model.

The hook and `assets/deny-list.sh` are defense in depth for cooperative-agent mistakes. They are
not a security boundary. Use an OS sandbox, least privilege, scoped writable mounts, restricted
egress, budgets, and a kill path for unattended work.

## Repository map

| Path | Purpose |
|---|---|
| `shared/method.md` | Canonical platform-neutral method |
| `shared/` | Focused investigation, authoring, gate, chaining, autonomy, and mode references |
| `claude/SKILL.md` | Claude Code adapter |
| `codex/SKILL.md` | Codex adapter and metadata |
| `assets/gate.*.sh` | Deterministic Stop-hook adapters |
| `assets/deny-list.sh` | Best-effort pre-use policy |
| `assets/goal.md.tmpl` | Persisted sub-goal template |
| `sync.sh` | Non-destructive live-symlink installer |
| `PLAN.md` | As-built decisions, compatibility, and scope |

## Verify this checkout

Run the portable contract suite on macOS or Linux:

```bash
bash tests/run.sh
```

CI runs the same suite on Ubuntu and macOS and runs ShellCheck on Ubuntu.

This repository authors goals and provides gate/policy building blocks. A process that advances
a persisted goal DAG, schedules agents, manages budgets, or resumes a chain is an **external
driver** and is intentionally out of scope.
