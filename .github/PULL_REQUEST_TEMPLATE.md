## Problem and outcome

<!-- What concrete problem does this solve? What observable outcome should reviewers see? -->

## Scope

<!-- List the files and public contracts changed. Name intentionally excluded follow-up work. -->

## Approach and alternatives

<!-- Explain the chosen approach and any materially different alternative considered. -->

## Compatibility and security

- [ ] I reviewed changes to install targets, hook JSON, environment variables, goal schemas, and
      platform invocation as public compatibility surfaces.
- [ ] I described any security or trust boundary impact below.
- [ ] I did not include secrets, credentials, personal data, or machine-specific paths.

Security or trust-boundary impact:

<!-- Write "None" only after considering gate, installer, policy, permissions, state, and egress. -->

## Verification

Required repository check:

```bash
bash tests/run.sh
```

<!-- Paste complete relevant raw output and the exit code. Do not write only "tests pass." -->

```text
<raw output>
exit code: <code>
```

Additional checks:

```text
<command, raw output, exit code>
```

## Documentation

- [ ] User-facing behavior is documented.
- [ ] `PLAN.md` and `CHANGELOG.md` are updated when a public contract changed.
- [ ] Platform-neutral policy remains in `shared/`; adapters contain only platform mechanics.
