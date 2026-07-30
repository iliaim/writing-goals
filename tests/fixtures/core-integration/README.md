# G07 protected core fixtures

Each case is a deliberately small, deterministic input to the host-owned core
validator. `core.env` is an immutable contract, not a scheduler instruction:
the host selects the next node only after it has validated the protected
authority, activation binding, and frozen execution order.

The G07 CLI seam is:

```sh
assets/runtime-check.sh --authority ABS --identity ID --plan pNN --run RUN \
  --core-fixture tests/fixtures/core-integration/CASE/core.env --resume
```

For an accepted case it prints the exact `result`, `parent_state`,
`current_or_next`, `role`, and `execution_order` records. A rejected case
prints `result=reject` and its declared `reason` then exits non-zero. Fixture
values are intentionally explicit so stale, untrusted, or altered metadata
cannot silently become an implicit-latest selection.

Each case derives an authority-owned `activation.env` in the mode-700
authority (mode 600). It binds identity, plan, run, generation, objective
digest, plan digest, and execution order before a case is resumed. The
`activation-*drift` cases alone contain an explicit `activation_*` value for
the one field that differs from the resume value; every other binding is
identical and must still be compared unconditionally.
