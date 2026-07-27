#!/usr/bin/env bash
set -u
. "$(dirname "$0")/testlib.sh"

method="$REPO_DIR/shared/method.md"
claude="$REPO_DIR/claude/SKILL.md"
codex="$REPO_DIR/codex/SKILL.md"
template="$REPO_DIR/assets/goal.md.tmpl"

assert_file_contains "$method" 'Triage|TRIAGE' 'canonical shared method documents triage'
assert_file_contains "$method" 'investigat' 'canonical shared method documents investigation'
assert_file_contains "$method" 'MUST-ASK|DERIVE' 'canonical shared method documents fact classification'
assert_file_contains "$method" 'gate' 'canonical shared method documents gates'
assert_file_contains "$method" 'chain' 'canonical shared method documents chaining'
assert_file_contains "$method" 'autonom' 'canonical shared method documents autonomy'
assert_file_contains "$claude" '4,?000' 'Claude adapter documents the official 4,000-character condition limit'
assert_file_contains "$claude" 'stop_hook_active' 'Claude adapter documents stop_hook_active'
assert_file_contains "$claude" 'eight consecutive|8 consecutive' 'Claude adapter documents the eight-consecutive-block limit'
assert_file_contains "$codex" 'PreToolUse' 'Codex adapter documents PreToolUse coverage'
assert_file_contains "$codex" 'Bash' 'Codex adapter names Bash PreToolUse coverage'
assert_file_contains "$codex" 'apply_patch' 'Codex adapter names apply_patch PreToolUse coverage'
assert_file_contains "$codex" 'MCP' 'Codex adapter names MCP PreToolUse coverage'
assert_file_contains "$codex" 'local function' 'Codex adapter names other local-function PreToolUse coverage'
assert_not_contains "$(cat "$codex")" '/goal[[:space:]]+complete' 'Codex adapter makes no unsupported /goal completion claim'

assert_file_contains "$template" 'stop_rules:' 'persisted sub-goal template has stop_rules'
assert_file_contains "$template" 'success' 'persisted sub-goal template has a success stop rule'
assert_file_contains "$template" 'failure' 'persisted sub-goal template has a failure stop rule'
assert_file_contains "$template" 'iteration' 'persisted sub-goal template has an iteration stop rule'
assert_file_contains "$template" 'cost' 'persisted sub-goal template has a cost stop rule'
assert_file_contains "$template" 'wall.?clock|time' 'persisted sub-goal template has a wall-clock stop rule'
assert_file_contains "$REPO_DIR/shared/autonomy.md" 'Class 3' 'autonomy policy names Class 3 actions'
assert_file_contains "$REPO_DIR/shared/autonomy.md" 'explicit.*bounded.*human|human.*bounded.*authori' 'Class 3 external or spending actions require bounded human authority'
assert_file_contains "$REPO_DIR/shared/autonomy.md" 'Class 4' 'autonomy policy names Class 4 actions'
assert_file_contains "$REPO_DIR/shared/autonomy.md" 'unattended' 'Class 4 policy is scoped to unattended execution'
assert_file_contains "$REPO_DIR/shared/autonomy.md" 'commit.*authori|authori.*commit' 'commits require user or repository authority'
assert_file_contains "$REPO_DIR/shared/chaining.md" 'insufficient' 'disjoint artifacts are explicitly insufficient for parallelism'

for gate in "$REPO_DIR/assets/gate.claude.sh" "$REPO_DIR/assets/gate.codex.sh"; do
  assert_not_contains "$(cat "$gate")" 'GATE_CMD:-pytest' 'gate has no stale implicit pytest command default'
  assert_file_contains "$gate" 'GATE_CMD' 'gate names explicit GATE_CMD configuration'
  assert_file_contains "$gate" 'GOAL_GATE_CAP' 'gate names explicit GOAL_GATE_CAP configuration'
done

assert_file_contains "$REPO_DIR/README.md" 'development install|live symlink' 'README explains live symlink development installs'
assert_file_contains "$REPO_DIR/README.md" '--force' 'README documents default refusal and --force'
assert_file_contains "$REPO_DIR/README.md" 'jq' 'README documents jq prerequisite'
assert_file_contains "$REPO_DIR/README.md" 'GATE_CMD' 'README documents trusted GATE_CMD'
assert_file_contains "$REPO_DIR/README.md" 'GOAL_GATE_CAP' 'README documents explicit gate cap'
assert_file_contains "$REPO_DIR/README.md" 'bash tests/run.sh' 'README names the contract test command'
assert_file_contains "$REPO_DIR/README.md" 'out of scope' 'README says an external driver is out of scope'

finish_tests
