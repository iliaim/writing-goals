# writing-goals — as-built record

This file records the implemented design as of 2026-07-27. It is a decision and compatibility
record, not a promise of future work and not a replacement for the executable contracts in
`tests/`.

## Intent

The repository supplies one platform-neutral method for writing bounded, verifiable goals, plus
small Claude Code and Codex adapters. It deliberately improves verification and resumability
without becoming an orchestration framework.

The canonical flow is:

1. triage whether a goal is useful;
2. investigate the real repository and classify MUST-ASK versus derivable facts;
3. author one observable slice with exact acceptance evidence and complete stop rules;
4. add a deterministic lifecycle gate for unattended work;
5. decompose only an approved large specification;
6. apply autonomy according to blast radius and explicit authority.

`shared/method.md` owns that policy. Platform adapters own only invocation, trust, and hook
mechanics.

## As-built decisions

| Decision | Implemented choice | Reason |
|---|---|---|
| Source layout | Canonical `shared/` method with thin adapters | Avoids divergent Claude/Codex policy |
| Installation | Live symlinks from this checkout | One development source of truth |
| Collision handling | Refuse by default; `--force` replaces only the selected target | Preserves user-owned skill content |
| Verification | Trusted command Stop hook with explicit cap and surface | Gives the maker an independent, bounded checker |
| Gate state | Session-keyed, mode-0600 state and failure log | Avoids model-facing command output and cross-session counters |
| Surface protection | Digest from a trusted baseline plus sandbox permissions | A first untrusted digest or writable state is not protection |
| Retry outcome | `decision:block` below the configured cap | Requests another bounded iteration |
| Terminal outcome | `continue:false` with a needs-human reason | Stops invalid, corrupt, or exhausted loops |
| Safety policy | Deny-list as defense in depth inside an OS sandbox | Shell matching cannot provide containment |
| Chaining | Persisted shallow DAG guidance only | Native cross-goal orchestration is not assumed |
| Dependencies | Bash, `jq`, and a SHA-256 utility | Keeps the implementation portable and auditable |

## Compatibility matrix

| Surface | Claude Code | Codex | Repository contract |
|---|---|---|---|
| Skill invocation | `/writing-goals` | `$writing-goals`, `/skills`, or description match | Adapter-specific |
| Install target | `~/.claude/skills/writing-goals` | `${CODEX_HOME:-$HOME/.codex}/skills/writing-goals` | `sync.sh` preflights before mutation |
| Installed shape | Directory containing three canonical links | Symlink to the self-contained `codex/` directory | Re-running the same layout is idempotent |
| Project hook file | `.claude/settings.json` | `.codex/hooks.json` or platform-supported config | User reviews and trusts hook source |
| Repository root | `CLAUDE_PROJECT_DIR` | Hook input `cwd` | Missing or invalid root fails closed |
| Retry signal | `{"decision":"block","reason":"..."}` | Same | Clean exit with no JSON is green |
| Terminal signal | `{"continue":false,"stopReason":"..."}` | Same | Configuration/state/cap failures need human |
| Pre-use matching | Platform command-hook coverage | `Bash`, `apply_patch`, MCP, and most local tools; documented exceptions | `deny-list.sh` handles its supported shell input |
| Platform bound | Default eight consecutive no-progress Stop blocks | No repository-assumed implicit bound | Set explicit `GOAL_GATE_CAP`; keep Claude limits compatible |

The adapters cite the current official platform documentation for facts that can change. The
portable contract suite verifies repository behavior; it does not claim compatibility with every
past or future platform release.

## Delivered architecture

```text
shared/method.md
  ├── investigate.md
  ├── author-goal.md
  ├── gates.md
  ├── chaining.md
  ├── autonomy.md
  └── modes.md

claude/SKILL.md ── loads canonical method + Claude mechanics
codex/SKILL.md  ── loads canonical method + Codex mechanics
assets/         ── gate adapters, deny-list, goal template
tests/          ── portable installer, gate, deny-list, and documentation contracts
```

The shared method contains no platform commands or lifecycle quirks. The adapters do not restate
the method. Gate implementations remain separate because their repository-root inputs and
platform constraints differ.

## Audit remediation history

- Added a dependency-free Bash contract harness covering installer, gates, deny-list, and docs.
- Made installation preflighted, idempotent only for the canonical layout, and non-destructive by
  default.
- Made gate configuration explicit; bounded and validated counter state; protected state writes;
  persisted failure output; and failed closed on configuration, state, hashing, and surface errors.
- Expanded the deny-list's ordinary-footgun parsing while keeping it explicitly best effort.
- Established `shared/method.md` as the policy source and reconciled both platform adapters.
- Added operational documentation and lightweight macOS/Linux CI.

Git history and tracked tests are the durable evidence for this work. Temporary task reports and
local audit workspaces are intentionally ignored and are not evidence artifacts.

## Boundaries and residual risk

- An external driver for scheduling, resuming, or advancing a goal graph is out of scope.
- The hooks do not contain a hostile or prompt-injected process. OS isolation and restricted
  credentials remain mandatory for unattended execution.
- `GATE_CMD` is trusted shell code and must never be populated from untrusted text.
- `GATE_SURFACE` uses ordinary shell word splitting and glob expansion; whitespace in filenames
  is unsupported.
- A surface digest is meaningful only after a trusted baseline. Sandbox permissions must protect
  both the verification surface and gate state from the maker.
- Platform hook contracts can change. Update the adapter, its official source link, and contract
  tests together.

## Verification and change policy

The acceptance command is:

```bash
bash tests/run.sh
```

CI runs it on Ubuntu and macOS. Ubuntu additionally installs and runs ShellCheck over the
installer and production hook scripts; SC2294 is excluded because evaluating the explicitly
trusted `GATE_CMD` is the documented interface. Changes to a public environment variable, hook
JSON contract, install target, goal schema, or trust model require corresponding tests and an
update to this record.
