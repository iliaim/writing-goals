---
okf_version: "0.2"
---

# Contributing

Contributions that improve correctness, portability, clarity, or verification are welcome.
Small, focused changes with reproducible evidence are easiest to review.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Security-sensitive
reports belong in the private channel described by [SECURITY.md](SECURITY.md), not in a public
issue.

## Before opening a change

1. Search existing issues and pull requests.
2. For a behavior change, open an issue describing the concrete problem and expected contract.
3. Read [`PLAN.md`](PLAN.md) for the as-built architecture.
4. Identify which file owns the rule. Platform-neutral policy belongs in `shared/`; platform
   invocation and current hook mechanics belong only in the relevant adapter.

Do not duplicate a rule across the README, guides, shared method, and adapters. Public guides may
summarize a reader journey, but they should link to the canonical source for operational details.

## Development setup

Requirements:

- Bash 3.2 or newer
- `jq`
- `shasum` or `sha256sum`
- ShellCheck for the same static analysis used in Ubuntu CI

Clone the repository and establish a clean baseline:

```bash
git clone https://github.com/iliaim/writing-goals.git
cd writing-goals
bash tests/run.sh
```

The baseline must pass before implementation. Do not edit, skip, or remove a failing contract to
make a change appear green.

## Make a focused change

- Preserve the platform-neutral core and thin-adapter architecture.
- Add or strengthen a regression contract before changing behavior when practical.
- Keep Bash compatible with 3.2 unless the compatibility policy changes explicitly.
- Avoid new dependencies unless the benefit and portability cost are documented.
- Treat install targets, hook JSON, environment variables, goal schemas, and the trust boundary as
  public compatibility surfaces.
- Never include secrets, tokens, personal data, or machine-specific paths.

Changes to `assets/gate.*.sh`, `assets/deny-list.sh`, `install.sh`, `scripts/build-bundles.sh`, or the security model require an
explicit trust-boundary review in the pull request.

## Documentation changes

- Keep [`shared/method.md`](shared/method.md) canonical.
- Cite official platform documentation for volatile Claude Code and Codex claims.
- Use relative links for repository files.
- Give diagrams and images meaningful text alternatives or adjacent equivalent prose.
- Update `PLAN.md`, tests, and `CHANGELOG.md` when a public behavior or contract changes.

## Verify

Run the portable contract suite:

```bash
bash tests/run.sh
```

On a system with ShellCheck:

```bash
shellcheck --exclude=SC2294 install.sh scripts/build-bundles.sh assets/*.sh
```

The SC2294 exclusion is intentional because evaluating explicitly trusted `GATE_CMD` shell source
is the documented interface.

Include the complete relevant command output and exit code in the pull request. A summary such as
“tests pass” is not sufficient evidence.

## Pull requests

Use the pull request template and keep one change focused on one outcome. Explain:

- the concrete problem and why the change belongs here;
- files and public contracts affected;
- alternatives considered;
- trust-boundary or compatibility impact;
- exact verification commands and raw results; and
- follow-up work intentionally left out of scope.

The maintainer may ask for smaller scope, stronger tests, or a canonical-source correction before
merging.
