---
okf_version: "0.2"
---

# Changelog

All notable public changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning will begin
when the project publishes its first supported release and declares the compatibility surface for
that release.

## [Unreleased]

### Added

- A local, profile-driven Codex benchmark harness with retained worktrees, ephemeral credential homes,
  JSON evidence, and scenario evaluators.
- Explicit local plugin refresh with source verification and timestamped backups.
- Public quick-start, worked-example, and security-model guides.
- MIT license and community policies for security, support, conduct, and contributions.
- Structured issue forms and a pull request evidence template.
- GitHub-native workflow diagram and public support matrix.
- Private vulnerability reporting and discoverable repository description and topics.
- Documentation contract binding the installer selections advertised in the README and the quick
  start to the selections `install.sh` actually accepts, checked in both directions so neither a
  stale duplicated command nor an undocumented new selection can merge.
- Documentation contract for the local refresh path, binding the selection the docs advertise to the
  selections `scripts/refresh-local.sh` accepts, and binding the documented explicit-flag safety to
  the script that enforces it.

### Fixed

- Bound both Stop-hook gates to a strict protected preflight receipt, rejecting caller-supplied,
  malformed, missing, and stale verification surfaces before acceptance commands run.
- Tightened full-plan linting so evidence commands, dependencies, alternative decisions, task-class
  routes, and maker/oracle path ownership are validated at their structural boundaries.
- Restored public guidance that a README restructure had silently dropped: independent confirmation,
  production changes, explicit authorization, and the coordination-versus-value test for skipping a
  goal.
- Corrected the gate section, which claimed three exhaustive Stop-hook outcomes and attributed a JSON
  payload to a path that emits none, and the installer note, which limited the compensated-rollback
  caveat to `all` when it applies to every selection.
- Raised badge and workflow-diagram contrast to WCAG 2.2 AA and gave the diagram an accessible name.

### Changed

- Aligned lightweight and full-tier guidance around proportional verification, genuinely independent
  multi-slice work, and only host-enforceable time or cost limits.
- Reorganized the README around user outcomes, first use, proof, scope, and trust boundaries.
- Corrected Codex metadata to avoid Claude-only `/goal` terminology.
- Strengthened documentation contracts for public files, links, and adapter wording.
