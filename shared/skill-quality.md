# Skill and planning quality evaluation

Every skill-related change is evaluated according to the **affected-risk** surface, not a
release cadence.  Package, reference, adapter, runtime, and planning-contract changes must run
the relevant deterministic checks before they can be accepted.  The deterministic surface is the
protected fixture set under `tests/fixtures/skill-evals/` and its three commands:

```bash
bash tests/test_skill_structure.sh
bash tests/test_skill_host_contract.sh
bash tests/test_skill_evals.sh --scorer-contract
```

Those commands verify package structure and reference metadata, exact offline host invocation,
and the fixed scorer/rubric.  They are risk-based checks: a change that can affect a host adapter
also requires the fresh-home host-parity check; a planning or lifecycle change also requires the
planning, execution-invariant, and execution-order fixtures.  They are deterministic validation
and do not prove model behavior: a model result is not deterministic proof of useful behavior.

## Protected deterministic references

The oracle freezes the fixture files, their schemas, and the following fixed rubric assertions:

| Class | Required assertion |
|---|---|
| safety | `G10_LIVE_ALL_SAFETY_INVARIANTS` |
| comparison | `G10_LIVE_WITH_SKILL_COMPARISON` |
| execution | `G10_LIVE_CHECKPOINT_CONTINUES` |
| execution | `G10_LIVE_PARENT_COMPLETION_GUARD` |
| execution | `G10_LIVE_FROZEN_ORDER_TIEBREAK` |
| execution | `G10_LIVE_RESUME_ORDER_PRESERVED` |

The scorer accepts only the named positive and rejection fixtures.  In particular, it covers the
planning recipe and lint cases, activation class and parent binding, checkpoint and successor
guards, scope and correction blocking, and frozen execution-order behavior: first-ready
tie-breaking, missing/unknown/duplicate order rejection, and order-preserving resume.  The
fixture set is protected test input; makers do not edit it to change a score.

## Offline host parity and hermeticity

`scripts/run-skill-behavioral-eval.sh --host-contract` reads only an explicitly supplied fixture
root and invokes the supported hosts with this frozen argv:

```text
claude -p --model claude-fixture-model --max-turns 3 --sandbox read-only
codex exec --model codex-fixture-model --max-turns 3 --sandbox read-only
```

The check is run from a non-source working directory with a new empty `HOME` and `CODEX_HOME`.
It must not install a skill, read a source checkout through home state, or persist any home state.
Fixture shims make this host argv and hermetic fresh-home contract deterministic and offline.

## Held-out live smoke is separate evidence

A live paired smoke is observational evidence, never part of the deterministic docs/config green
claim.  It is required only for a release candidate or a supported host/version change, and has a
with-skill and a without-skill arm for each supported host.  The without-skill arm may not see
skill source, answers, or the other arm's output; both arms use fresh isolated homes.

Run it only through the protected invocation below, with an explicit, bounded authorization for
network access and model spend.  The protected configuration must freeze rubric and prompt
fixture digests, host and model versions, exact argv, sandbox/tool policy, maximum turns, network
budget, spend budget, wall-clock limit, and the append-only evidence destination.

```bash
bash scripts/run-skill-behavioral-eval.sh \
  --protected-config "$PROTECTED_EVAL_CONFIG" \
  --output "$PROTECTED_EVAL_OUTPUT"
```

The runner refuses to execute models itself: a separately authorized controlled runner performs
the bounded trial and appends its result.  The retained result records the frozen environment,
home/path-isolation evidence, paired-arm rubric assertions, and versions.  It does not require
raw model-output hash identity.  Missing credentials, a host/model/version mismatch, unavailable
fresh homes, leakage, control contamination, absent authorization, or exhausted network/spend
budget is a stop, not a reason to weaken the deterministic checks.
