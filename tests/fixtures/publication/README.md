# G11 final-readiness fixtures

`readiness.env` is the explicit local target. The PATH `git` shim supplies only
status, branch, local `remote.origin.url` config, HEAD, tree, local base-ref,
and ancestry facts while recording argv. It fails closed on every `git remote`,
remote query, or mutation command. G11 makes no `gh` invocation and does not
publish: a human may publish only after terminal G13.
