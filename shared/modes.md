---
okf_version: "0.2"
---

# Execution mode

The host owns one sequential execution path for the full protected tier. It activates the recorded
next slice only after the current protected checkpoint passes; it never infers a successor from a
local plan or a completion claim. Normal interactive work uses a lightweight contract and does not
need this lifecycle. The normative full-tier protocol is [`shared/workflow.md`](workflow.md).

Full-tier slices have explicit success, failure, and iteration controls. Time and cost are planning
estimates unless the host can actually enforce them. Unattended execution also requires the
Class-4 deny-list, scoped writable mounts, protected state, and an OS-level sandbox. External
actions remain governed by [`shared/publication.md`](publication.md).
