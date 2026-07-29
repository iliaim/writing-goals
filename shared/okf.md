# OKF workspace contract

`writing-goals` uses [OKF](https://okfn.org/) concepts for repository-owned Markdown while
keeping host-owned documents in their native schemas. This contract is deliberately small: it
defines routes and validation boundaries, not an execution engine or a second state system.

## Repository-owned documents

Repository-owned Markdown begins with a YAML-style frontmatter block and `okf_version: "0.2"`.
Goal and objective contracts additionally provide a stable `id` and `type`. The validator accepts
unknown OKF keys and unknown `type` values so compatible extensions do not require a validator
release. A `writing_goals` profile declaration, when present, must declare profile `0.1`; a goal
profile also carries its exact objective-binding manifest, required frozen state, and SHA-256
algorithm.

The ordinary validator route is for repository-owned Markdown. It rejects missing or unterminated
frontmatter and invalid identifiers, but it does not rewrite files or infer missing metadata.

## Reserved routes

The per-objective workspace is local and has this identity form:

```text
.writing-goals/<YYYYMMDD>-<six-uppercase-Crockford-Base32>--<slug>/
```

The slug is lower-case and at most 32 characters. Plan revisions are `pNN`; local receipt or
report revisions are `rNN`. There is no `latest` route. An activation names one exact frozen `pNN`
and its manifest digest.

`objective.md`, plan indexes, and revision indexes are reserved navigation routes. They may link
to the objective snapshot, manifest, declared node order, dependencies, and revision mapping, but
must not duplicate normative requirements or lifecycle policy.

## Narrow owner-schema allowlist

The validator delegates only these paths to their externally owned schemas:

- `claude/SKILL.md`
- `codex/SKILL.md`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `claude/agents/writing-goals-*.md`
- `assets/roles/writing-goals-*.md`

Every other Markdown file supplied to the validator is repository-owned. There is no catch-all
host exemption.

## Command

Run the non-mutating validator against one Markdown file or a directory:

```bash
bash assets/validate-markdown.sh path/to/document-or-directory
```

An exit status of zero means every routed document was structurally valid. A non-zero status names
the rejected path and reason. Validation is structural evidence only; it does not select work,
authorize activation, or create lifecycle state.
