# Security policy

## Supported versions

Until the project publishes versioned releases, only the current `main` branch is supported.
Security fixes are made on `main`; older commits and local modifications are not maintained as
separate supported versions.

## Report a vulnerability

Report vulnerabilities privately through GitHub private vulnerability reporting for
`iliaim/writing-goals`:

1. open the repository's **Security** page;
2. select **Report a vulnerability**; and
3. include the affected commit, platform, impact, reproduction steps, and a minimal redacted
   proof of concept.

If private vulnerability reporting is unavailable, open a public issue containing only a request
for a private contact channel. Do not include exploit details, credentials, private paths, or
other sensitive information in that issue.

The maintainer will validate the report, coordinate a fix when required, and agree on disclosure
timing. Please do not publish the vulnerability before that coordination is complete.

## Security-sensitive areas

Reports are especially useful for:

- execution outside the intended repository scope;
- bypasses in `assets/deny-list.sh` for inputs it claims to recognize;
- gate state, counter, permissions, or verification-surface failures;
- unsafe installer replacement or rollback behavior;
- hook JSON that accidentally permits an invalid state;
- credential or command-output disclosure; and
- documentation that materially misrepresents a security boundary.

The deny-list is explicitly not intended to contain a malicious process. A report that merely
demonstrates the general unsoundness of regex-over-shell is out of scope unless it contradicts a
specific documented guarantee.

## Safe handling

- Use synthetic repositories and data.
- Remove secrets and personal information from logs.
- Do not test against systems or accounts you do not own or have permission to assess.
- Do not create persistence, cause denial of service, or access production data.

See the public [security model](docs/security-model.md) for the supported trust boundaries.
