---
okf_version: "0.2"
type: objective
id: 20260729-GV53BZ
status: stable
writing_goals:
  profile: "0.1"
  kind: objective
  identity: 20260729-GV53BZ
  slug: writing-goals-v1
---

# Fixture objective

The revision manifest binds these exact bytes. Its plan payload frames, in
globally path-byte-sorted order, `objective.md`, `index.md`, and `goals/*.md`:
each record is uint64be path length, path bytes, uint64be content length, and
content bytes.
