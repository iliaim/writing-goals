# G14 structural lint fixtures

Each directory is an independent canonical-plan input. `valid` must pass.
Every other directory differs by the named structural defect and must fail; the
linter must diagnose structure, not fixture names.
