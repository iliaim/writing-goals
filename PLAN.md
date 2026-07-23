# `writing-goals` — Design & Build Plan (v2, research-grounded)

> A global, agent-agnostic skill that turns intent into **rigorous, verifiable goals** for the `/goal` command in **both Claude Code and Codex**, and **decomposes + autonomously orchestrates** large objectives into a gated graph of atomic goals — principles-first, zero-assumption, safe under full-permission (bypass) runs.

Status: **v2 draft** — folds in 3 adversarial challengers + 7 research subagents. Ready for your review before build.

---

## 0. Locked decisions
- **D1 = B** author + orchestrate. **D2 = A** conditions + real hook gates. **D3 → two platform-native files + shared neutral references** (not runtime detection). **D4 = A** practical patterns. **D5 = A** one skill family (chaining is a pulled-in module).
- **v1 = autonomy first-class**, built on non-negotiable bounded gates + deterministic guardrails.

---

## 1. Non-negotiable principles (the spine)
1. **Principles over templates** — the method is fixed; the goal is derived per repo/situation.
2. **Zero assumption / zero guess** — verify every command, threshold, path, constraint against the real repo. Unverifiable → **STOP and ask**. Applies to five classes, not just "does the command exist": **surface validity** (green build ≠ feature works), **thresholds** (never invent 80%/200ms), **constraints** (ask, don't derive), **determinism** (flaky → stop/repeat-run), **scope** (monorepo → which package).
3. **Maker–checker separation** — the checker is never the maker. Both native evaluators are weak (self-grading) → require a deterministic hook or fresh-context verifier.
4. **Evidence-based completion** — observable state, confirmable without the doer's judgment ("second-agent test": could a fresh agent confirm from output+criteria alone?).
5. **Always bounded** — every goal & chain has success stop + failure/iteration + cost/time cap.
6. **Minimal footprint** — triage out trivial tasks; don't over-engineer.

---

## 2. Platform facts (verified) — Claude vs Codex

| | **Claude Code (v2.1.177)** | **Codex (0.144.1)** |
|---|---|---|
| Native "done" judge | Small model reads **transcript only**, no tools | **Model-declares** complete via `update_goal("complete")` — not harness-enforced |
| ⇒ both are **weak checkers** | needs deterministic hook / fresh-context verifier | same |
| Goal format | condition; **≤4000 chars**; add "or stop after N turns" | free-text; **≤4000 chars**; recommended 6-part / 3-element (Outcome·Constraints·Verification) |
| Lifecycle | `/goal`, `/goal` (status), `/goal clear` (aliases stop/off/reset/none/cancel) | `/goal`, `/goal edit`, `/goal pause`, `/goal resume`, `/goal clear` |
| Invocation of our skill | **`/writing-goals`** | **`$writing-goals`** or `/skills` picker or auto-by-description (**no typed `/name`**) |
| Skill install dir | `~/.claude/skills/writing-goals/` | `~/.agents/skills/writing-goals/` (canonical; `~/.codex/skills/` legacy-but-read) |
| SKILL.md frontmatter | `name`, `description`, opt `when_to_use`, opt `disable-model-invocation` | **`name`+`description` ONLY**; metadata + manual-invocation (`allow_implicit_invocation:false`) in **`agents/openai.yaml`** |
| Stop-hook config | `.claude/settings.json` → `hooks.Stop[]` | `.codex/hooks.json` → `hooks.Stop[]` (PascalCase events; **on by default**; must be **trusted** via `/hooks` or `--dangerously-bypass-hook-trust`) |
| Stop-hook block contract | `{"decision":"block","reason":…}` / exit 2; clean exit 0 = allow | **`{"continue":false,"stopReason","systemMessage"}` + stdout continuation prompt** — **NOT** `decision:block` |
| Deterministic block confirmed? | Yes | **UNVERIFIED on 0.144.1 → smoke-test (script ready) before relying; fallback to condition-level if notify-only** |

---

## 3. Architecture & files

Source of truth = this build folder; **symlink** into both trees (symlinking across trees already works on this machine).

```
writing-goals/
  shared/                      # platform-NEUTRAL (principles, method, patterns) — referenced on demand
    principles.md              # zero-assumption, DERIVE-vs-MUST-ASK, maker-checker, second-agent test
    investigate.md             # repo discovery checklist (surfaces, exact cmds, determinism, scope, constraints)
    author-goal.md             # well-formed goal = slice + pre-written gate + inherited DoD + evidence + autonomy tag; anti-gaming
    gates.md                   # gate concepts + iteration-counter + safety(PreToolUse deny-list) — platform specifics cross-linked
    chaining.md                # decomposition, DAG, .goals/ schema, ledger run-loop, reflection/replan, escalation
    autonomy.md                # 5-class action model, decide-and-log ledger, tier-3 stop, tier-4 deny-list
    modes.md                   # the 3 execution modes + when to use each
  claude/SKILL.md              # Claude frontmatter + Claude specifics (transcript evaluator, settings.json Stop hook, /writing-goals)
  codex/
    SKILL.md                   # name+description only; Codex specifics (continue:false hook, $-invocation)
    agents/openai.yaml         # Codex metadata + invocation policy
  assets/
    gate.claude.sh             # one concrete runnable gate (decision:block + persisted counter + stop_hook_active guard)
    gate.codex.sh              # concrete Codex gate (continue:false + counter)
    deny-list.sh               # PreToolUse safety hook (both) — tier-4 hard blocks
    goal.md.tmpl               # atomic .goals/ file template
  sync.sh                      # installs (symlinks) claude/→~/.claude, codex/→~/.agents, shared into both
  PLAN.md
```

**Design rule:** `shared/` is 100% platform-neutral; anything platform-specific lives only in the two `SKILL.md`s (+ `openai.yaml`). Keeps both thin. SKILL.md body ≤ ~400 lines / <500 words core; frontmatter ≤1024 chars (safe on both; Claude hard cap is 1536).

---

## 4. The method (what the skill makes the agent do)

```
0. TRIAGE — does this even need a goal? Trivial/one-shot → "just do X", exit. (avoid over-engineering)
1. INVESTIGATE (zero-assumption): verification surfaces + EXACT commands (read package.json/Makefile/CI/
   pyproject/Cargo/go — confirm PRESENCE by reading, not by running side-effectful cmds); determinism?;
   monorepo scope?; constraints. Anything unverifiable/human-only → MUST-ASK.
2. CLASSIFY facts: DERIVE-then-CONFIRM (commands, paths) vs MUST-ASK (thresholds, constraints, definition-of-done).
3. AUTHOR the goal = vertical slice + pre-written acceptance gate (strongest the task allows) + inherited
   project DoD + evidence requirement (raw cmd + exit code pasted) + autonomy/risk tag. Anti-gaming: forbid
   editing the verification surface; never accept paraphrased success; name transcript-fabrication as the enemy.
4. RENDER platform-native (Claude condition ≤4000 | Codex free-text/6-part).
5. GATE — offer the deterministic hook (recommended for unattended). Bound it (counter).
6. VERIFY the draft with the second-agent test (mechanical checklist: exact cmd? specific pass-string/exit/number? a bound?).
   For chains, a fresh-context verifier re-checks each goal before close.
```

---

## 5. Decomposition & orchestration (big objectives)

**Decompose** from a real spec (no spec → get one first; never invent features). Stop-splitting rule = **"is this leaf machine-verifiable?"** (not "is it small?"). Shallow-stable, capped depth. **Walking-skeleton first** (Goal 1 = thinnest end-to-end runnable), then **vertical slices**, **one feature per goal**.

**Atomic goal files** `.goals/*.md` (generated into the target repo), validated against spec-kit/task-master/CrewAI/LangGraph:
```yaml
---
id: auth-session-store            # stable node key (required)
title: Persist sessions in Redis  # (required)
status: todo                      # todo|in_progress|blocked|in_review|done|cancelled (required — drives run-loop & resume)
depends_on: [redis-provision]     # DAG edges, cycle-checked (required)
acceptance:                       # verifiable gate — done only when all pass (required)
  - "test_session_roundtrip green"
parallelizable: true              # (recommended)
owner: backend-agent              # (recommended)
priority: high                    # (recommended)
artifacts: [src/session/*.ts]     # files this goal writes → orchestrator PROVES two parallel goals don't collide (recommended)
risk: medium                      # low|medium|high → autonomy tier (optional)
updated: 2026-07-23               # (optional)
---
# body: goal statement · context · how-to
```
Recursion = **filesystem** (a sub-goal is its own file), not nested arrays. **Immutable `_objective.md`** stored separately from the mutable plan; every replanned sub-goal must **trace back to the objective** (anti-drift).

**Run-loop (ledger-driven, resumable):** pick ready (`status:todo` ∧ all `depends_on` done) → execute → **fresh-context verify** → mark → recompute frontier. Restart = re-read ledger. **Parallelize only low-write-coupling** branches (disjoint `artifacts`) in **isolated worktrees, single-writer, cap 3–5**; interdependent work stays single-threaded.

**Between goals:** reflect + replan from **real repo state**; **fix-before-feature** (regressions first); **entry re-verify** the previous goal's gate (never trust the ledger's "done").

**Bounded escalation ramp (guaranteed termination):** retry → replan → single-owner fallback → human; hard iteration + cost + time caps; **de-dup identical actions** (no-progress → escalate, not re-retry).

---

## 6. Three execution modes
1. **Human-gated stepping** — skill emits the ordered chain; you set each `/goal`, next after it clears. Default; natural checkpoints.
2. **Autonomous driver** — an **external wrapper** (there is no native goal-to-goal chaining) over headless `claude -p "/goal …"` (or `/schedule` cloud routine) / `codex exec`; reads the ledger + gate output and fires the next goal.
3. **Full-auto** — as #2 but decides judgment calls itself from best practices under the autonomy policy (§7).

---

## 7. Autonomy policy (reconciles "act autonomously" with "never guess") — critical under bypass mode

Runs happen in **bypass/full-permission mode** (Claude `--dangerously-skip-permissions`, Codex full-auto) — that *enables* unattended autonomy but **turns the platform's approval prompts OFF**, so safety must be **deterministic**, not model-promised.

**5-class action model (worst dimension wins; confidence NEVER upgrades a class):**
| Class | Trigger | Decision |
|---|---|---|
| 0 read/inert | no state change | AUTO |
| 1 reversible + repo-local | undoable, in-workspace, ~free | AUTO (+log if it resolved ambiguity) |
| 2 reversible but wide | big blast radius / effortful undo | AUTO + checkpoint |
| 3 irreversible / external / costs money / crosses trust boundary | prod, sends, payments, delete-outside-repo, changing the top objective | **CONFIRM ALWAYS** |
| 4 prohibited | deny-list | **DENY** (hard block) |

**Decide-and-log (replaces silent guessing):** on a fork, if Class ≤2 → pick best-practice default, **record `{fork, options, chosen, rationale, undo-path, confidence}` in the goal's `assumptions`**, keep reversible, **surface at next checkpoint**. A decision that is recorded + reversible + surfaced is accountable autonomy; drop any one → it's a silent guess (forbidden).

**Deterministic enforcement (works even in bypass):** a **`PreToolUse` deny-list hook** blocks tier-4 shell actions (delete outside repo, `push --force`, external sends, spend/purchase) — **deny-first precedence beats the allowlist and bypass mode.** Pair with **workspace/dir scoping**. Caveat: Codex `PreToolUse` intercepts **shell only** (not Edit/Write) → scoping covers file dangers. Plus session **cost budget + iteration cap + kill-switch**; recursive to subagents.

---

## 8. Build process (TDD via superpowers:writing-skills — Iron Law: no skill without a failing test first)
- **RED:** baseline a subagent **without** the skill under **3+ stacked pressures** (time + sunk-cost + authority + exhaustion); capture exact rationalizations (esp. "just assume the test command", "green build = done", "I'll invent a threshold").
- **GREEN:** minimal skill addressing those specific failures.
- **REFACTOR:** each new loophole → rationalization-table row + red-flag + description symptom; add "letter vs spirit" principle early; use Authority/Commitment/Social-proof levers. Clone `test-driven-development/SKILL.md` skeleton (the reference discipline skill).

---

## 9. Acceptance criteria (dogfooded — the skill must pass a goal-grade check)
Tested via fresh subagents on **≥4 repos** (Node w/ tests · Python lib · **no-test** repo · **non-code** docs/research goal):
- [ ] Correct platform-native goal for each; **no-test & ambiguous-threshold repos STOP and ask** (never invent).
- [ ] Every goal has success + failure + iteration/cost cap; passes the **fresh-context second-agent test**.
- [ ] Gate scripts **actually gate** on a fixture (pass→allow, fail→block, malformed→caught) — Claude `decision:block` **and** Codex `continue:false`.
- [ ] The **PreToolUse deny-list** blocks a tier-4 action even in bypass mode.
- [ ] Skill **triggers** on goal-writing intent and **does not misfire** on adjacent tasks.
- [ ] Chaining: an objective → valid DAG of `.goals/*.md`, ledger-driven run-loop is **resumable**, parallel goals proven non-colliding via `artifacts`, every sub-goal traces to `_objective.md`.
- [ ] Installs + triggers in **both** (Claude `/writing-goals`; Codex `$writing-goals`/picker); frontmatter valid; body within token target.

---

## 10. Build-time verifications (must run, don't assume)
1. **Codex Stop-hook blocking on 0.144.1** — run the ready smoke-test; if notify-only, Codex mode-2/3 gates at condition-level + fresh-context verifier instead of hook-block.
2. **Codex skills dir precedence** — probe `~/.agents/skills` vs `~/.codex/skills` (drop marker skills, check `/skills`).
3. **Symlink-follow at load** — confirm both loaders resolve symlinked skill dirs.

---

## 11. Future / extensibility (captured, not built now)
- **Platform-adapter model.** `shared/` is the platform-neutral core; each platform is a thin adapter dir (`claude/`, `codex/`, later `hermes/`, others). **Adding a platform is additive** — new adapter + reuse `shared/`, zero core rework. Order: **Claude now → Codex next → Hermes → others.**
- **Open-source distribution (later stage).** Keep this build folder **repo-ready & portable**: no hardcoded absolute paths in `shared/` or adapters (machine-specifics live only in `sync.sh`/install). Future: public GitHub repo (README, LICENSE, CONTRIBUTING, semver, tests/CI) distributed as **plugin / CLI / MCP with one-click install**. Before publishing, research popular analogous repos (Claude/Codex skill + plugin ecosystems, MCP servers) for packaging + contribution conventions. Explicitly deferred.
```
