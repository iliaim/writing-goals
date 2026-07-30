# Publication

There is no mid-plan human publication gate. Approved execution may create
commits automatically under its repository authority. G11 is a deterministic,
local-only readiness check: `assets/publish-readiness.sh` validates an explicit
repository, remote, base, head, commit, and tree against clean local Git facts.
It never reads authority or lifecycle artifacts and never contacts a remote.

One final human gate occurs only after terminal G13. That gate is required
before every external push, pull request, merge, release, or deploy. G11 does
not publish, query a remote, or create publication state.
