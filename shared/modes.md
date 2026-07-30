---
okf_version: "0.2"
---

# Execution mode

The host owns one sequential execution path. It activates the recorded next slice only after the
current protected checkpoint passes; it never infers a successor from a local plan or a completion
claim. The normative protocol is [`shared/workflow.md`](workflow.md).

Every slice has explicit success, failure, iteration, cost, and wall-clock stops. Unattended
execution also requires the Class-4 deny-list, scoped writable mounts, protected state, and an
OS-level sandbox. External actions remain governed by [`shared/publication.md`](publication.md).
