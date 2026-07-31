#!/usr/bin/env bash
# Scenario oracle. It writes its own canonical plan and duplicate-key manifest
# after cloning the candidate, so candidate fixtures cannot weaken acceptance.
set -euo pipefail

[ "$#" -eq 1 ] || { printf 'usage: %s WORKTREE\n' "$0" >&2; exit 2; }
worktree=$1
[ -d "$worktree" ] || { printf 'missing worktree: %s\n' "$worktree" >&2; exit 2; }
[ -z "$(git -C "$worktree" status --porcelain)" ] || {
  printf '%s\n' 'candidate worktree is dirty; benchmark requires a local commit' >&2
  exit 1
}

scratch="$(mktemp -d "${TMPDIR:-/tmp}/writing-goals-benchmark-oracle.XXXXXX")"
cleanup() { rm -rf -- "$scratch"; }
trap cleanup EXIT HUP INT TERM
candidate="$scratch/candidate"
git clone --quiet --no-local "$worktree" "$candidate"
candidate="$(CDPATH= cd -- "$candidate" && pwd -P)"

plan="$scratch/plan.yml"
index="$scratch/index.md"
good_manifest="$scratch/good-manifest.json"
duplicate_manifest="$scratch/duplicate-manifest.json"
cat > "$plan" <<'EOF'
id: FIXTURE-PLAN
task_class: docs_config
requirements: [REQ-02]
objective_acceptance: [OBJ-01]
execution_recipe:
  inputs: [objective_snapshot]
  outputs: [updated-policy]
  maker_paths: [shared/example.md]
  oracle_paths: [tests/example.sh]
  evidence:
    - order: 1
      argv: [bash, tests/example.sh]
      expected_exit: 0
  handoff: writing-goals-verifier
  fan_in_owner: writing-goals-reviewer
  risks: [duplicate-authority]
  stop_conditions: [missing-decision]
dag:
  - id: author
    depends_on: []
  - id: verify
    depends_on: [author]
workflow: [discover, author, lint, challenge, freeze]
EOF
cat > "$index" <<'EOF'
# Plan index

Navigation only: [FIXTURE-PLAN](plan.yml)
EOF
printf '%s\n' '{"schema":"writing-goals-plan-manifest/v1","plan_digest":"sha256:31f8a15e57dde626a20d5c4980fdd8dfea1f8f4110d8476482bf3cbb5913ab26"}' > "$good_manifest"
printf '%s\n' '{"schema":"writing-goals-plan-manifest/v1","plan_digest":"sha256:31f8a15e57dde626a20d5c4980fdd8dfea1f8f4110d8476482bf3cbb5913ab26","plan_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000"}' > "$duplicate_manifest"

good_stdout="$scratch/good.stdout"
good_stderr="$scratch/good.stderr"
bash "$candidate/scripts/plan-lint.sh" --plan "$plan" --manifest "$good_manifest" --index "$index" > "$good_stdout" 2> "$good_stderr" || {
  printf '%s\n' 'known-good structural plan was rejected' >&2
  exit 1
}
printf '%s\n' 'plan-lint: structural validation passed' > "$scratch/good.expected"
cmp -s "$scratch/good.expected" "$good_stdout" && [ ! -s "$good_stderr" ] || {
  printf '%s\n' 'known-good structural plan did not preserve exact success output' >&2
  exit 1
}

duplicate_stdout="$scratch/duplicate.stdout"
duplicate_stderr="$scratch/duplicate.stderr"
set +e
bash "$candidate/scripts/plan-lint.sh" --plan "$plan" --manifest "$duplicate_manifest" --index "$index" > "$duplicate_stdout" 2> "$duplicate_stderr"
status=$?
set -e
[ "$status" -ne 0 ] || { printf '%s\n' 'duplicate manifest digest was accepted' >&2; exit 1; }
[ ! -s "$duplicate_stdout" ] || { printf '%s\n' 'duplicate manifest digest wrote stdout' >&2; exit 1; }
printf '%s\n' 'plan-lint: manifest must contain exactly one plan_digest' > "$scratch/duplicate.expected"
cmp -s "$scratch/duplicate.expected" "$duplicate_stderr" || {
  printf '%s\n' 'duplicate manifest digest stderr did not match the required diagnostic' >&2
  exit 1
}

bash "$candidate/tests/test_plan_lint.sh" > "$scratch/candidate-tests.stdout" \
  2> "$scratch/candidate-tests.stderr" || {
  printf '%s\n' 'candidate plan-lint regression test failed' >&2
  cat "$scratch/candidate-tests.stderr" >&2
  exit 1
}
