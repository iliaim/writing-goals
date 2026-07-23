# Investigate — zero-assumption repo discovery

Run this **before** authoring a goal. You are finding the real verification surface, the exact
command, its determinism, and its scope — by **reading**, not guessing. Every finding lands in the
**MUST-ASK vs DERIVE-then-CONFIRM** split (bottom). Anything you cannot confirm by reading is not a
detail to smooth over — it is a STOP.

## 1. Enumerate verification surfaces — then rank, don't grab the first

A *surface* is anything a fresh checker can observe to confirm the outcome without trusting the doer.
List every candidate for **this** outcome, then pick the **strongest available**:

| Strength | Surface | Proves |
|---|---|---|
| strongest | **Behavioral test** (asserts the outcome) | the feature actually works |
| ↑ | **New test written for this outcome** | the specific change is exercised |
| ↑ | **Integration test** | components work together |
| mid | **Typecheck** | types are consistent (not behavior) |
| ↓ | **Build** compiles | it links (not behavior) |
| ↓ | **Lint** clean | style/rules (not behavior) |
| ↓ | **Generated-artifact-exists** | a file/output was produced |
| ↓ | **Empty-queue** / job drained | a process ran to completion |
| weak | **Screenshot / visual diff** | pixels changed |
| weakest | **Human check** | needs a person |

**Rule — surface validity ≠ existence.** A green build / typecheck / lint proves the code *compiles*,
never that the feature *works*. The presence of a surface says nothing about whether it validates the
goal. So: rank surfaces against the outcome; if the goal is **behavioral** but only a weak proxy
exists (build/lint/typecheck), the gate is a proxy — **say so plainly in the goal**, and if nothing
behavioral can be built or the human needs a real guarantee → **MUST-ASK**. Never silently gate a
behavioral outcome on a proxy and call it done.

## 2. Find the EXACT command — by reading config

Confirm the command **exists** by reading, in this order of authority:

| Ecosystem | Read | Look for |
|---|---|---|
| Node | `package.json` → `scripts` | `test`, `test:e2e`, `typecheck`, `build`, `lint` |
| Make | `Makefile` | `test:`, `check:` targets |
| CI (ground truth) | `.github/workflows/*.yml`, `.gitlab-ci.yml` | the command CI actually runs |
| Python | `pyproject.toml`, `tox.ini`, `pytest.ini`, `noxfile.py` | `pytest` args, markers, `[tool.*]` |
| Rust | `Cargo.toml` | `cargo test`, workspace members |
| Go | tree | `go test ./...`, build tags |

- **Confirm PRESENCE by reading** — a command someone "said to use" but that isn't in config is
  **unverified** → vacuous-gate risk. CI yaml is the strongest source: it's what green *actually* means.
- **Only run a command after inspecting exactly what it does.** Reading proves existence; that's enough
  for discovery.
- **Never run side-effectful commands during discovery** — anything that touches a **DB / network**,
  **costs money**, or runs **> ~30s**. Read it; don't fire it.

## 3. Determinism — no single-sample gates on the unconfirmed

- **Flaky, or determinism unknown → MUST-ASK.** Do not assume stable.
- If you must gate anyway, gate on **N consecutive clean runs** or a **known-stable subset**, not one pass.
- **Ban single-sample gates** on any surface you haven't confirmed deterministic — one green run of a
  flaky suite is noise, and a loop will happily exit on that noise.

## 4. Scope — resolve the command where it runs

- **Monorepo → detect workspaces** (`workspaces` in `package.json`, `[workspace]` in `Cargo.toml`,
  pnpm/nx/turbo configs, `go.work`).
- **Ask which package** the outcome lives in (MUST-ASK if ambiguous), then **resolve the command at
  that package's scope** (`pnpm --filter pkg test`, `cargo test -p pkg`).
- **Never confirm-run a whole-monorepo command** — it's slow, often side-effectful, and hides which
  package actually failed.

## 5. Environment baseline — green before you start

- The chosen surface **must be green at baseline in this env** before any work begins.
- Baseline **red = "blocked"**, never "not done" — the env is the problem, not the goal.
- **Never "fix" a red baseline by editing/skipping the test.** Report `blocked`; escalate. Editing the
  verification surface to reach green is the cardinal anti-gaming violation.

## 6. Map findings → classify (feeds SKILL.md)

| Finding | Class |
|---|---|
| Test/build command located in config | **DERIVE-then-CONFIRM** (log if it resolved ambiguity) |
| File paths, iteration cap, *relative* improvement target | **DERIVE-then-CONFIRM** |
| Absolute threshold (coverage %, latency SLA, "fast enough") | **MUST-ASK** — never invent |
| Determinism unknown / suite flaky | **MUST-ASK** (or N-clean-runs) |
| Which package (ambiguous monorepo) | **MUST-ASK** |
| Only a weak proxy for a behavioral goal | **MUST-ASK** |
| Definition-of-done / constraints that must not regress | **MUST-ASK** |

**Worked example.** Goal: "make the checkout API faster." Read `package.json` → `bench:checkout`
script exists (present ✓); `.github/workflows/ci.yml` runs it on a fixed dataset (deterministic ✓);
repo is a pnpm monorepo → resolve to `pnpm --filter @app/checkout bench` (scope ✓); baseline runs
clean locally (baseline green ✓). **But** "faster" has no number → the target is **MUST-ASK**: either
the human gives an absolute p95, or default to *relative* (≥X% below a committed baseline) **and log
it**. Do not invent "200ms."
