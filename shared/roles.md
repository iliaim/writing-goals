# Role contracts

Host facts were checked on 2026-07-29: Claude role definitions use Markdown files with YAML
frontmatter in `.claude/agents` ([location](https://code.claude.com/docs/en/sub-agents)); the
same source documents `name`, `description`, and tool-pool controls
([fields](https://code.claude.com/docs/en/sub-agents)). Codex agent configuration uses declared
agent entries and config-file paths ([schema](https://github.com/openai/codex/blob/main/codex-rs/config/src/config_toml.rs)).

These host definitions route work; path and prompt restrictions are advisory rather than enforced
unless an OS sandbox enforces them. They are static definitions and therefore proxy evidence, not
proof of host prose compliance. same-model review is correlated evidence, so important conclusions
need independent verification and deterministic checks.

The planner and challenger jointly perform one preapproval DAG review before approval. Discovery
asks one question at a time, and the planner records two to four alternatives with rejected reasons.
The oracle-author owns protected tests; the maker owns only `maker_write_paths` in a bounded worktree;
the verifier and reviewer are fresh and read-only; the publisher has no maker authority.

Before activation, record exactly one classification: `standalone_slice` or `parent_objective`.
`parent_objective` requires the approved objective, selected frozen plan, complete approved DAG, and
protected run authority. A requested scope narrowing returns to the user for approval.
