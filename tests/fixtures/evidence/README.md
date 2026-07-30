# G05 receipt fixtures

Each case contains a line-oriented `key=value` receipt and its independent
expected binding.  The protected checker is invoked as:

```bash
bash assets/record-check.sh --receipt CASE/receipt.tsv --expected CASE/expected.tsv
```

The expected binding describes the approved task class, objective, criterion,
oracle, candidate commit/tree, exact check argv or review scope, and context
constraints.  When supplied, expected `output_sha256` and `receipt_sha256`
are exact binding values, not merely format checks. A completed receipt additionally declares `kind`, `result`,
`role`, `actor`, `context`, bounded `output_bytes`/`output_sha256`, and a
SHA-256 `receipt_sha256`.  Receipt fields are data only: recorded argv must
never be evaluated.
