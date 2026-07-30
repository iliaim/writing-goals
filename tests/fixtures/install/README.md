# G09 bundle and installer fixture contract

`protected-preimages.sha256` freezes the exact bytes of the two legacy paths
that the approved G09 plan alone authorizes the maker to remove. It is
evidence established before any deletion; it is not regenerated after the
paths disappear.

The builder seam is deliberately small and deterministic:

```sh
bash scripts/build-bundles.sh OUTPUT_DIRECTORY
```

It publishes a self-contained bundle root at `OUTPUT_DIRECTORY`, containing
`claude/`, `codex/`, `shared/`, `assets/`, `install.sh`, and a sorted
`MANIFEST.sha256`. It must reject an existing output directory, leave no
partial output on a handled failure, and create no symbolic links.

The bundle-local installer seam is:

```sh
bash OUTPUT_DIRECTORY/install.sh [claude|codex|all]
```

It installs copies (never links) at the documented user locations:
`$HOME/.claude/skills/writing-goals`,
`${CODEX_HOME:-$HOME/.codex}/skills/writing-goals`, and the namespaced Codex
agent files under `${CODEX_HOME:-$HOME/.codex}/agents/`. `all` is one
preflighted transaction. A normal installation refuses every occupied exact
target and preserves unrelated agents. Repeating an installer-owned layout
is idempotent. `WG_INSTALL_FAIL_AFTER_STAGE=codex` is a deterministic,
test-only rollback injection: it must fail after staging the Claude changes
but before publishing Codex changes, restoring every preimage exactly.

`failing-mv.sh` is copied into a temporary `PATH` during the protected
regression. With `REAL_MV` and `WG_FAIL_MV_SOURCE` it fails only the matching
backup move. A failed backup is a handled installer failure: no later target
may be published and every already-staged preimage must be restored.
