# G06 retention fixtures

Each `records/*.receipt` is a line-oriented evidence record with required `identity`, `plan`,
and `recorded_at` fields. `referenced_by` names an authority receipt that depends on the record;
such records are protected even when their identity, plan, and age match an explicit prune.

The protected pruner interface is:

```sh
bash assets/prune-evidence.sh --records-dir DIR --identity ID --plan pNN --cutoff RFC3339 --manifest FILE
```

It may delete only an unreferenced record whose identity and plan exactly match and whose
`recorded_at` is strictly before the cutoff. It must write a byte-for-byte deterministic,
lexically sorted TSV manifest using `deleted<TAB>filename` lines. It must not delete anything
when any selector is absent; pruning is only an explicit invocation, never a periodic task.
