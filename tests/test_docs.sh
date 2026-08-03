#!/usr/bin/env bash
set -u
. "$(dirname "$0")/testlib.sh"

method="$REPO_DIR/shared/method.md"
claude="$REPO_DIR/claude/SKILL.md"
codex="$REPO_DIR/codex/SKILL.md"
template="$REPO_DIR/assets/goal.md.tmpl"
readme="$REPO_DIR/README.md"
codex_metadata="$REPO_DIR/codex/agents/openai.yaml"

assert_file_contains "$method" 'lightest useful tier|Choose.*tier' 'canonical shared method documents triage'
assert_file_contains "$method" 'investigat' 'canonical shared method documents investigation'
assert_file_contains "$method" 'MUST-ASK|DERIVE' 'canonical shared method documents fact classification'
assert_file_contains "$method" 'Resolve context before authoring|Resolve.*context' 'canonical shared method resolves session context before authoring'
assert_file_contains "$method" 'decision packet' 'canonical shared method presents recommended options for material ambiguity'
assert_file_contains "$method" 'parent.*delivery objective' 'canonical shared method retains an end-to-end parent outcome'
assert_file_contains "$method" 'Present a reviewable delivery plan before implementation' 'canonical shared method requires plan review before coordinated implementation'
assert_file_contains "$method" 'protected host authority remains the only source' 'canonical shared method keeps full-tier cursor selection outside conversational prose'
assert_file_contains "$method" 'Verification and validation' 'canonical shared method distinguishes criteria proof from user-need confirmation'
assert_file_contains "$method" 'Delivery and closure' 'canonical shared method records delivery closure separately from verification'
assert_file_contains "$method" 'gate' 'canonical shared method documents gates'
assert_file_contains "$method" 'multiple independently executable slices|shallow DAG' 'canonical shared method documents full-plan chaining'
assert_file_contains "$method" 'autonom' 'canonical shared method documents autonomy'
assert_file_contains "$method" 'Iteration caps.*enforceable|iteration cap' 'canonical method requires an enforceable iteration limit for the full tier'
assert_file_contains "$method" 'Time and cost.*estimates|time and cost.*estimates' 'canonical method does not promise unenforceable time or cost stops'
assert_file_contains "$method" 'protected preflight.*baseline|preflight record' 'canonical method requires protected preflight before full-tier maker work'
assert_file_contains "$method" 'read first|read-first' 'canonical method records exact sources to read before authoring'
assert_file_contains "$method" 'non-goals|constraints' 'canonical method requires explicit non-goals and constraints'
assert_file_contains "$method" 'documentation-impact|documentation impact' 'canonical method requires a documentation-impact decision'
assert_file_contains "$method" 'terminal stop rule|stop successfully only when' 'canonical method requires one terminal stop rule'
assert_file_contains "$method" 'new ADR|decision record' 'canonical method requires human review for new decision records'
assert_file_contains "$method" 'checkpoint.*current phase|current phase.*checkpoint' 'canonical method binds checkpoints to evidence and the next gate'
assert_file_contains "$method" 'every user-facing status check' 'canonical method requires concise monitoring updates'
assert_file_contains "$claude" 'shared/method.md' 'Claude adapter mandates the canonical shared method'
assert_file_contains "$codex" 'shared/method.md' 'Codex adapter mandates the canonical shared method'
assert_file_contains "$claude" '4,?000' 'Claude adapter documents the official 4,000-character condition limit'
assert_file_contains "$claude" 'stop_hook_active' 'Claude adapter documents stop_hook_active'
assert_file_contains "$claude" 'eight consecutive|8 consecutive' 'Claude adapter documents the eight-consecutive-block limit'
assert_file_contains "$claude" 'By default.*eight consecutive blocks without progress|By default.*8 consecutive blocks without progress' 'Claude adapter states the default no-progress block condition'
assert_file_contains "$claude" 'CLAUDE_CODE_STOP_HOOK_BLOCK_CAP' 'Claude adapter names the platform block-cap override'
assert_file_contains "$claude" 'GOAL_GATE_CAP.*<= 8|GOAL_GATE_CAP.*at least the chosen repository cap' 'Claude adapter keeps repository and platform caps compatible'
assert_file_contains "$codex" 'PreToolUse' 'Codex adapter documents PreToolUse coverage'
assert_file_contains "$codex" 'Bash' 'Codex adapter names Bash PreToolUse coverage'
assert_file_contains "$codex" 'apply_patch' 'Codex adapter names apply_patch PreToolUse coverage'
assert_file_contains "$codex" 'validates only.*Bash' 'Codex adapter explicitly bounds validated PreToolUse coverage'
assert_file_contains "$codex" 'do not infer coverage.*other tool.*payload shape' 'Codex adapter disclaims unvalidated tools and payloads'
assert_not_contains "$(cat "$codex")" 'MCP|Hosted tools|write_stdin' 'Codex adapter makes no stale broad coverage claim'
assert_file_contains "$claude" 'https://code.claude.com/docs/' 'Claude platform facts cite official documentation'
assert_file_contains "$codex" 'https://learn.chatgpt.com/docs/hooks' 'Codex platform facts cite official documentation'
assert_file_contains "$codex" '/goal <objective>' 'Codex adapter documents the conditional native /goal invocation'
assert_file_contains "$codex" '/goal.*pause.*resume.*clear' 'Codex adapter documents native goal controls'
assert_file_contains "$codex" 'only when.*available|when.*available.*active Codex surface' 'Codex adapter bounds native /goal applicability'
assert_file_contains "$codex" 'Codex slash commands|reference/slash-commands' 'Codex adapter cites current native goal command documentation'
assert_not_contains "$(cat "$codex_metadata")" '/goal' 'Codex UI metadata makes no unsupported /goal claim'
assert_not_contains "$(cat "$REPO_DIR/shared/autonomy.md")" 'Codex caveat:.*shell only|PreToolUse.*intercepts.*shell only' 'shared autonomy policy has no stale Codex shell-only claim'
shared_policy="$(cat "$REPO_DIR"/shared/*.md)"
assert_not_contains "$shared_policy" '`/goal|claude -p|codex exec|--dangerously-skip-permissions|CLAUDE_CODE_|stop_hook_active|#47810|transcript-only|transcript evaluator|Claude Code' 'shared policy contains no known platform-specific invocation or mechanics'

assert_file_contains "$template" 'type: lightweight-goal-contract' 'default template is a lightweight contract'
assert_not_contains "$(cat "$template")" 'status:|drives run-loop' 'lightweight template has no lifecycle authority'
assert_file_contains "$template" 'Alternatives considered' 'lightweight template records alternatives'
assert_file_contains "$template" 'Observed verification result' 'lightweight template records observed verification evidence'
assert_file_contains "$template" 'Time and cost.*estimates' 'lightweight template avoids unenforceable hard time/cost stops'
assert_file_contains "$template" 'Read first / sources of truth' 'lightweight template records exact read-first sources'
assert_file_contains "$template" 'Non-goals / constraints' 'lightweight template records explicit constraints'
assert_file_contains "$template" 'Stop condition and checkpoints' 'lightweight template records terminal stops and checkpoints'
assert_file_contains "$template" 'Success stop' 'lightweight template records the cumulative success stop'
assert_file_contains "$template" 'Human-needed stop' 'lightweight template records human escalation stops'
assert_file_contains "$template" 'No-progress stop' 'lightweight template records a no-progress stop'
assert_file_contains "$template" 'Documentation impact' 'lightweight template records documentation impact'
assert_file_contains "$template" 'Do not create a new ADR' 'lightweight template does not create implicit decision records'
assert_file_contains "$method" 'Given' 'canonical shared method requires explicit acceptance criteria'
assert_file_contains "$method" 'When' 'canonical shared method requires explicit acceptance criteria'
assert_file_contains "$method" 'Then' 'canonical shared method requires explicit acceptance criteria'
assert_file_contains "$method" 'all listed criteria.*required|criteria.*all.*required' 'canonical shared method makes acceptance criteria cumulative'
assert_file_contains "$method" 'parent-level outcome' 'canonical shared method keeps native goal completion self-contained'
assert_file_contains "$method" 'final.*check' 'canonical shared method keeps native goal completion self-contained'
assert_file_contains "$method" 'self-contained' 'canonical shared method keeps native goal completion self-contained'
assert_file_contains "$method" 'navigation.*only|pointer.*cannot replace.*criterion' 'canonical shared method keeps contract and plan pointers non-authoritative'
assert_file_contains "$method" 'frozen `objective_acceptance`' 'canonical shared method distinguishes parent acceptance from child completion'
assert_file_contains "$template" '## Completion criteria' 'lightweight template persists explicit completion criteria'
assert_file_contains "$template" 'Then all of the following are true' 'lightweight template makes success criteria cumulative'
assert_file_contains "$template" 'manual observation' 'lightweight template records manual proof when automation is insufficient'
assert_file_contains "$template" '## Delivery plan and user review' 'lightweight template presents a reviewable multi-step delivery plan'
assert_file_contains "$template" 'Context and intent' 'lightweight template records contextual goal resolution'
assert_file_contains "$template" 'Plan and user review' 'lightweight template records a user review gate before implementation'
assert_file_contains "$template" 'Verification and validation' 'lightweight template distinguishes verification from validation'
assert_file_contains "$template" '## Delivery closure' 'lightweight template records delivery completion and follow-up'
assert_file_contains "$codex_metadata" 'end-to-end delivery outcome.*reviewable staged plan' 'Codex default prompt asks for contextual outcome resolution and plan review'
assert_file_contains "$codex_metadata" 'read-first sources.*non-goals.*documentation impact.*checkpoints' 'Codex default prompt carries the complete lightweight contract cues'
for adapter in "$claude" "$codex"; do
  assert_file_contains "$adapter" 'Read first:' 'native goal records exact read-first sources'
  assert_file_contains "$adapter" 'Constraints:' 'native goal records explicit constraints'
  assert_file_contains "$adapter" 'Document:' 'native goal records documentation impact'
  assert_file_contains "$adapter" 'Checkpoint:' 'native goal records checkpoint updates'
  assert_file_contains "$adapter" 'each status check' 'native goal requires concise monitoring updates'
  assert_file_contains "$adapter" 'Stop when:' 'native goal records a terminal stop condition'
  assert_file_contains "$adapter" 'set the goal yourself|self' 'native goal requires inspect-first self-authoring'
  assert_file_contains "$adapter" 'narrow.*verification|weaken, narrow' 'native goal forbids verification-surface narrowing'
  assert_file_contains "$adapter" 'new ADR|decision record' 'native goal requires approval for new decision records'
done
assert_file_contains "$REPO_DIR/shared/autonomy.md" 'Class 3' 'autonomy policy names Class 3 actions'
assert_file_contains "$REPO_DIR/shared/autonomy.md" 'explicit.*bounded.*human|human.*bounded.*authori' 'Class 3 external or spending actions require bounded human authority'
assert_file_contains "$REPO_DIR/shared/autonomy.md" 'Class 4' 'autonomy policy names Class 4 actions'
assert_file_contains "$REPO_DIR/shared/autonomy.md" 'unattended' 'Class 4 policy is scoped to unattended execution'
assert_file_contains "$REPO_DIR/shared/autonomy.md" 'any `push`' 'Class 4 policy denies every unattended git push'
assert_file_contains "$REPO_DIR/shared/autonomy.md" 'commit.*authori|authori.*commit' 'commits require user or repository authority'
assert_file_contains "$REPO_DIR/shared/chaining.md" 'insufficient' 'disjoint artifacts are explicitly insufficient for parallelism'

for gate in "$REPO_DIR/assets/gate.claude.sh" "$REPO_DIR/assets/gate.codex.sh"; do
  assert_not_contains "$(cat "$gate")" 'GATE_CMD:-pytest' 'gate has no stale implicit pytest command default'
  assert_file_contains "$gate" 'GATE_CMD' 'gate names explicit GATE_CMD configuration'
  assert_file_contains "$gate" 'GOAL_GATE_CAP' 'gate names explicit GOAL_GATE_CAP configuration'
done
assert_file_contains "$REPO_DIR/shared/gates.md" 'GATE_SURFACE' 'gate guide names mandatory GATE_SURFACE configuration'
assert_file_contains "$REPO_DIR/shared/gates.md" 'GATE_PREFLIGHT_RECORD' 'gate guide requires the protected preflight record'
assert_file_contains "$REPO_DIR/shared/gates.md" 'ordinary shell word splitting.*glob expansion|shell glob/list' 'gate guide documents exact surface expansion semantics'
assert_file_contains "$REPO_DIR/shared/gates.md" 'read-only.*maker' 'gate guide requires a protected surface before maker work'
assert_file_contains "$REPO_DIR/shared/gates.md" 'first post-edit.*never creates|never.*first post-edit' 'gate guide rejects maker-created baselines'
assert_file_contains "$REPO_DIR/shared/gates.md" '[Rr]equired for every full-tier run' 'gate guide requires lifecycle verification for every full-tier run'
assert_not_contains "$(cat "$REPO_DIR/shared/gates.md")" 'relevant script into|mandatory inputs, and use the skill adapter.*mandatory inputs' 'gate guide has no duplicated installation fragment'

assert_file_contains "$readme" 'finish line.*prove|bounded goal contract' 'README leads with a concrete outcome'
assert_file_contains "$readme" 'platform-neutral.*Claude Code.*Codex|Claude Code.*Codex.*platform-neutral' 'README accurately bounds platform support'
assert_not_contains "$(cat "$readme")" 'safe unattended execution' 'README does not make an absolute unattended-safety claim'
assert_file_contains "$readme" '^```mermaid' 'README includes a GitHub-native workflow diagram'
assert_file_contains "$readme" '## Quick start' 'README provides a first-use path'
assert_file_contains "$readme" '## Worked example' 'README demonstrates a bounded goal contract'
assert_file_contains "$readme" '## When to use it' 'README explains when the method is appropriate'
assert_file_contains "$readme" 'not a security boundary|not containment' 'README states the hook safety boundary'
assert_file_contains "$readme" '\[Quick start\]\(docs/quickstart\.md\)' 'README links the detailed quick start'
assert_file_contains "$readme" '\[Examples\]\(docs/examples\.md\)' 'README links checked examples'
assert_file_contains "$readme" '\[Security model\]\(docs/security-model\.md\)' 'README links the security model'
assert_file_contains "$readme" 'scripts/build-bundles\.sh' 'README documents bundle construction'
assert_file_contains "$readme" 'install\.sh' 'README documents bundle-local copy installation'
assert_file_contains "$readme" 'refresh-local\.sh.*--install' 'README documents the explicit local refresh command'
assert_file_contains "$readme" '\.archive/writing-goals' 'README documents the repository-local refresh archive'
assert_file_contains "$readme" 'refuses an occupied target|force-overwrite' 'README documents collision refusal without overwrite'
assert_file_contains "$readme" 'jq' 'README documents jq prerequisite'
assert_file_contains "$readme" 'GATE_CMD' 'README documents trusted GATE_CMD'
assert_file_contains "$readme" 'GOAL_GATE_CAP' 'README documents explicit gate cap'
assert_file_contains "$readme" 'GATE_SURFACE' 'README documents mandatory gate surface'
assert_file_contains "$readme" 'GATE_PREFLIGHT_RECORD' 'README explains the protected preflight receipt'
assert_file_contains "$readme" 'green preflight receipt.*before maker|before maker.*green preflight receipt' 'README gives an operationally safe receipt setup'
assert_file_contains "$readme" 'never.*first post-edit|first post-edit.*never' 'README rejects maker-created baselines'
assert_file_contains "$readme" 'decision.*block' 'README documents retry hook output'
assert_file_contains "$readme" 'continue.*false|needs-human|needs human' 'README documents terminal gate output'
assert_file_contains "$readme" '\.claude/settings\.json' 'README shows Claude hook registration'
assert_file_contains "$readme" '\.codex/hooks\.json' 'README shows Codex hook registration'
assert_file_contains "$readme" 'bash tests/run.sh' 'README names the contract test command'
assert_file_contains "$readme" 'foreground continuation supervisor' 'README documents the bounded Codex continuation controller'
assert_file_contains "$readme" 'reviewable end-to-end delivery plan' 'README explains the review gate before implementation'
assert_file_contains "$readme" 'Deliver and close' 'README includes delivery closure in the public workflow'

assert_file_contains "$REPO_DIR/docs/quickstart.md" '## Install|## Choose' 'quick start documents installation'
assert_file_contains "$REPO_DIR/docs/quickstart.md" 'refresh-local\.sh.*--install' 'quick start documents the explicit local refresh command'
assert_file_contains "$REPO_DIR/docs/quickstart.md" '\.archive/writing-goals' 'quick start documents the repository-local refresh archive'
assert_file_contains "$REPO_DIR/docs/quickstart.md" '/writing-goals' 'quick start documents Claude invocation'
assert_file_contains "$REPO_DIR/docs/quickstart.md" '\$writing-goals' 'quick start documents Codex invocation'

# The installer invocation is the public entry point and is duplicated across the
# README and the quick start, which nothing previously bound together.  Every
# other assertion here is a presence check: it proves a pinned string exists, not
# that the documented command still matches the code.  So derive the accepted
# selections from install.sh and check both directions instead of pinning a
# literal, which would drift with the very code it claims to document.
installer_selections="$(sed -n 's/^case "$selection" in \([^)]*\)).*/\1/p' "$REPO_DIR/install.sh" | head -1)"

TEST_COUNT=$((TEST_COUNT + 1))
if [ -n "$installer_selections" ]; then
  pass 'installer selection set is discoverable for documentation binding'
else
  fail 'installer selection set is discoverable for documentation binding'
fi

assert_file_contains "$readme" 'dist/writing-goals/install\.sh' 'README documents the bundle installer invocation'
assert_file_contains "$REPO_DIR/docs/quickstart.md" 'dist/writing-goals/install\.sh' 'quick start documents the bundle installer invocation'

# Forward: every selection install.sh accepts is documented for the reader.
while read -r installer_selection; do
  [ -n "$installer_selection" ] || continue
  assert_file_contains "$readme" "install\.sh $installer_selection" \
    "README documents the $installer_selection installer selection"
done <<< "$(printf '%s\n' "$installer_selections" | tr '|' '\n')"

# Reverse: every selection the documentation advertises is one install.sh still
# accepts.  This is the direction that catches a stale duplicated block.
documented_selections="$(grep -Eho 'dist/writing-goals/install\.sh [A-Za-z0-9_-]+' \
  "$readme" "$REPO_DIR/docs/quickstart.md" | awk '{ print $2 }' | sort -u)"

TEST_COUNT=$((TEST_COUNT + 1))
if [ -n "$documented_selections" ]; then
  pass 'documented installer invocations are discoverable in README and quick start'
else
  fail 'documented installer invocations are discoverable in README and quick start'
fi

while read -r documented_selection; do
  [ -n "$documented_selection" ] || continue
  TEST_COUNT=$((TEST_COUNT + 1))
  if printf '%s' "|$installer_selections|" | grep -Fq -- "|$documented_selection|"; then
    pass "documented installer selection $documented_selection is accepted by install.sh"
  else
    fail "documented installer selection $documented_selection is accepted by install.sh (accepts $installer_selections)"
  fi
done <<< "$documented_selections"

# scripts/refresh-local.sh is the documented update path and carries the same
# risk as install.sh above: the documentation names a selection, and only the
# script knows which selections are real.
#
# The forward direction deliberately does NOT apply here.  README and the quick
# start show the one recommended `--install all` invocation rather than
# enumerating every accepted selection, so requiring each accepted selection to
# appear in the prose would fight the documents' intent rather than protect the
# reader.  Bind the reverse direction instead, plus the two safety properties
# the surrounding prose actually claims: that --install is a real flag, and that
# the script refuses to touch installed copies without it.
refresh_script="$REPO_DIR/scripts/refresh-local.sh"
refresh_selections="$(sed -n 's/^case "$selection" in \([^)]*\)).*/\1/p' "$refresh_script" | head -1)"

TEST_COUNT=$((TEST_COUNT + 1))
if [ -n "$refresh_selections" ]; then
  pass 'refresh selection set is discoverable for documentation binding'
else
  fail 'refresh selection set is discoverable for documentation binding'
fi

assert_file_contains "$refresh_script" '^  --install\)' 'refresh script implements the documented --install flag'
assert_file_contains "$refresh_script" '^  --status\)' 'refresh script implements the documented offline status flag'
assert_file_contains "$refresh_script" '^  --check-updates\)' 'refresh script implements the documented upstream check flag'
assert_file_contains "$refresh_script" 'explicit --install is required' 'refresh script refuses to run without the documented explicit flag'
assert_file_contains "$readme" 'refresh-local\.sh --status' 'README documents the offline version status command'
assert_file_contains "$readme" 'refresh-local\.sh --check-updates' 'README documents the explicit upstream check command'
assert_file_contains "$REPO_DIR/docs/quickstart.md" 'refresh-local\.sh --status' 'quick start documents the offline version status command'
assert_file_contains "$REPO_DIR/docs/quickstart.md" 'refresh-local\.sh --check-updates' 'quick start documents the explicit upstream check command'

documented_refresh="$(grep -Eho 'refresh-local\.sh --install [A-Za-z0-9_-]+' \
  "$readme" "$REPO_DIR/docs/quickstart.md" | awk '{ print $3 }' | sort -u)"

TEST_COUNT=$((TEST_COUNT + 1))
if [ -n "$documented_refresh" ]; then
  pass 'documented refresh invocations are discoverable in README and quick start'
else
  fail 'documented refresh invocations are discoverable in README and quick start'
fi

while read -r refresh_selection; do
  [ -n "$refresh_selection" ] || continue
  TEST_COUNT=$((TEST_COUNT + 1))
  if printf '%s' "|$refresh_selections|" | grep -Fq -- "|$refresh_selection|"; then
    pass "documented refresh selection $refresh_selection is accepted by refresh-local.sh"
  else
    fail "documented refresh selection $refresh_selection is accepted by refresh-local.sh (accepts $refresh_selections)"
  fi
done <<< "$documented_refresh"

docs_example_contract="$(sed -n '30,55p' "$REPO_DIR/docs/examples.md")"
assert_contains "$docs_example_contract" 'Objective:' 'documentation example includes one agent-facing objective'
assert_contains "$docs_example_contract" 'Read first:' 'documentation example names read-first sources'
assert_contains "$docs_example_contract" 'Constraints:' 'documentation example names explicit constraints'
assert_contains "$docs_example_contract" 'Document:' 'documentation example records documentation impact'
assert_contains "$docs_example_contract" 'Given:|When:|Then all of the following are true' 'documentation example includes cumulative acceptance'
assert_contains "$docs_example_contract" 'Validate:.*tests/test_docs.sh' 'documentation example names exact validation'
assert_contains "$docs_example_contract" 'Checkpoint:' 'documentation example records checkpoint evidence'
assert_contains "$docs_example_contract" 'Stop when:' 'documentation example records terminal stop'
assert_not_contains "$docs_example_contract" 'Done when:|Also green:|Verification:' 'documentation example has no superseded contract labels'
assert_file_contains "$method" 'after each bounded slice.*when practical|each bounded slice.*safe validation' 'canonical method qualifies incremental slice validation'
assert_file_contains "$template" 'Slice validation|slice validation' 'lightweight template records incremental validation or deferral'
assert_file_contains "$REPO_DIR/shared/author-goal.md" 'fresh-context challenge.*reread|reread.*read-first sources' 'authoring guidance makes challenge procedure executable'
assert_file_contains "$template" '## Pre-freeze challenge' 'lightweight template records pre-freeze challenge evidence'
assert_file_contains "$template" 'Challenge result' 'lightweight template records challenge outcome'
assert_file_contains "$claude" 'phase, exact evidence observed, next gate, and blocker' 'Claude binds checkpoint summary to durable evidence fields'
assert_file_contains "$codex" 'phase, exact evidence observed, next gate, and blocker' 'Codex binds checkpoint summary to durable evidence fields'
assert_not_contains "$(sed -n '1,55p' "$REPO_DIR/docs/examples.md")" 'max_iterations' 'ordinary examples do not imply a universal iteration cap'
assert_file_contains "$method" 'freeze it when that result is recorded' 'lightweight drafting is finalized only after observed evidence'
assert_file_contains "$readme" 'full-tier.*fresh checker|full tier.*reruns' 'README scopes fresh verification to the full tier'
assert_file_contains "$readme" 'genuinely independent multi-slice' 'README qualifies the full-tier multi-slice threshold'
assert_file_contains "$REPO_DIR/shared/author-goal.md" 'genuinely independent multi-slice' 'authoring guidance qualifies the full-tier multi-slice threshold'
assert_file_contains "$REPO_DIR/shared/planning-recipe.md" 'genuinely independent multi-slice' 'planning recipe qualifies the full-tier multi-slice threshold'
assert_file_contains "$template" 'genuinely independent multi-slice' 'lightweight template qualifies the full-tier multi-slice threshold'
assert_file_contains "$method" 'genuinely independent executable slices' 'canonical method qualifies the full-tier multi-slice threshold'
assert_file_contains "$REPO_DIR/docs/quickstart.md" 'genuinely independent executable multi-slice' 'quick start qualifies the full-tier multi-slice threshold'
assert_file_contains "$REPO_DIR/docs/examples.md" 'genuinely independent, verifiable slices' 'examples qualify multi-slice workspace plans'
assert_not_contains "$(cat "$codex_metadata")" 'complete stop rules' 'Codex default prompt avoids universal stop-rule friction'
assert_file_contains "$REPO_DIR/shared/skill-quality.md" 'can actually measure and enforce' 'quality policy qualifies host-dependent budgets'
assert_file_contains "$REPO_DIR/docs/security-model.md" 'OS-level sandbox' 'security model names the real unattended boundary'
assert_file_contains "$REPO_DIR/docs/security-model.md" 'threat|Threat' 'security model documents threats'

assert_file_contains "$REPO_DIR/LICENSE" '^MIT License$' 'repository has the standard MIT license'
assert_file_contains "$REPO_DIR/LICENSE" 'Copyright \(c\) 2026 iliaim' 'MIT license identifies the public copyright holder'
assert_file_contains "$REPO_DIR/SECURITY.md" 'private vulnerability reporting|privately' 'security policy provides a private reporting route'
assert_file_contains "$REPO_DIR/SECURITY.md" 'supported|Supported' 'security policy explains supported versions'
assert_file_contains "$REPO_DIR/CONTRIBUTING.md" 'bash tests/run\.sh' 'contributing guide gives the exact verification command'
assert_file_contains "$REPO_DIR/CONTRIBUTING.md" 'trust boundary|security' 'contributing guide calls out safety-sensitive changes'
assert_file_contains "$REPO_DIR/CONTRIBUTING.md" 'install\.sh.*scripts/build-bundles\.sh' 'contributing guide checks current installer scripts'
assert_not_contains "$(cat "$REPO_DIR/CONTRIBUTING.md")" 'sync\.sh' 'contributing guide has no retired sync installer reference'
assert_file_contains "$REPO_DIR/SUPPORT.md" 'issue|Issue' 'support policy names the support channel'
assert_file_contains "$REPO_DIR/CODE_OF_CONDUCT.md" 'Our Standards' 'repository has enforceable conduct standards'
assert_file_contains "$REPO_DIR/CHANGELOG.md" '## \[Unreleased\]' 'changelog has an Unreleased section'
assert_file_contains "$REPO_DIR/.github/PULL_REQUEST_TEMPLATE.md" 'bash tests/run\.sh' 'pull request template requires exact verification'
assert_file_contains "$REPO_DIR/.github/PULL_REQUEST_TEMPLATE.md" 'trust boundary|Security' 'pull request template asks about security impact'
assert_file_contains "$REPO_DIR/.github/ISSUE_TEMPLATE/1-documentation.yml" '^name:' 'documentation issue form is discoverable'
assert_file_contains "$REPO_DIR/.github/ISSUE_TEMPLATE/2-bug.yml" '^name:' 'bug issue form is discoverable'
assert_file_contains "$REPO_DIR/.github/ISSUE_TEMPLATE/2-bug.yml" 'bundle/copy installer' 'bug form names the current installer'
assert_not_contains "$(cat "$REPO_DIR/.github/ISSUE_TEMPLATE/2-bug.yml")" 'sync\.sh' 'bug form has no retired sync installer reference'
assert_file_contains "$REPO_DIR/.github/ISSUE_TEMPLATE/3-compatibility.yml" '^name:' 'compatibility issue form is discoverable'
assert_file_contains "$REPO_DIR/.github/ISSUE_TEMPLATE/4-feature-proposal.yml" '^name:.*[Ff]eature proposal' 'feature proposal issue form is discoverable'
assert_file_contains "$REPO_DIR/.github/ISSUE_TEMPLATE/config.yml" 'blank_issues_enabled: false' 'issue chooser directs reporters to structured forms'
assert_path_absent "$REPO_DIR/.github/ISSUE_TEMPLATE/5-public-moderation.yml" 'repository does not expose a public conduct-report form'
assert_file_contains "$REPO_DIR/.github/ISSUE_TEMPLATE/config.yml" 'reporting-abuse-or-spam' 'issue chooser routes private GitHub abuse to GitHub Support'
assert_file_contains "$REPO_DIR/.github/ISSUE_TEMPLATE/4-feature-proposal.yml" 'security/advisories/new' 'feature form routes vulnerabilities to private vulnerability reporting'
assert_file_contains "$REPO_DIR/.github/ISSUE_TEMPLATE/4-feature-proposal.yml" 'reporting-abuse-or-spam' 'feature form routes private GitHub abuse to GitHub Support'
assert_not_contains "$(cat "$REPO_DIR/.github/ISSUE_TEMPLATE/4-feature-proposal.yml")" 'private conduct reports' 'feature form makes no nonexistent private conduct-route claim'
assert_file_contains "$REPO_DIR/CODE_OF_CONDUCT.md" 'separate private conduct-reporting inbox' 'conduct policy states the private-inbox limitation'
assert_file_contains "$REPO_DIR/CODE_OF_CONDUCT.md" 'reporting-abuse-or-spam' 'conduct policy routes private GitHub abuse to GitHub Support'
assert_file_contains "$REPO_DIR/CODE_OF_CONDUCT.md" 'reserved for security vulnerabilities' 'conduct policy reserves private vulnerability reporting for security'
assert_file_contains "$REPO_DIR/CODE_OF_CONDUCT.md" 'times are not guaranteed' 'conduct policy does not promise unavailable response timing'
assert_not_contains "$(cat "$REPO_DIR/CODE_OF_CONDUCT.md")" 'may be raised through|reviewed promptly' 'conduct policy makes no public-form or prompt-response promise'
assert_file_contains "$REPO_DIR/SUPPORT.md" 'security/advisories/new' 'support policy links the private vulnerability route'
assert_file_contains "$REPO_DIR/SUPPORT.md" 'reporting-abuse-or-spam' 'support policy links the private GitHub abuse route'
assert_file_contains "$readme" 'reporting-abuse-or-spam' 'README routes private GitHub abuse separately'
assert_file_contains "$readme" 'security/advisories/new' 'README routes security vulnerabilities separately'
assert_file_contains "$REPO_DIR/PLAN.md" 'as-built|As-built' 'PLAN is an as-built record'
assert_file_contains "$REPO_DIR/PLAN.md" 'compatibility' 'PLAN contains a compatibility record'
assert_file_contains "$REPO_DIR/PLAN.md" 'Bundle-local `install\.sh all`|Symlink-free copy tree' 'PLAN records bundle copy installation'
assert_not_contains "$(cat "$REPO_DIR/PLAN.md")" 'sync\.sh' 'PLAN has no retired sync installer reference'
assert_not_contains "$(cat "$REPO_DIR/PLAN.md")" 'Live symlinks|live symlink' 'PLAN has no live-link installation semantics'
assert_not_contains "$(cat "$REPO_DIR/PLAN.md")" '`--force`' 'PLAN has no force-overwrite installation semantics'
assert_not_contains "$(cat "$REPO_DIR/PLAN.md")" 'Status:.*draft|Ready for your review before build' 'PLAN does not describe the implemented system as a draft'

assert_file_contains "$REPO_DIR/.github/workflows/ci.yml" 'ubuntu-' 'CI runs on Ubuntu'
assert_file_contains "$REPO_DIR/.github/workflows/ci.yml" 'macos-' 'CI runs on macOS'
assert_file_contains "$REPO_DIR/.github/workflows/ci.yml" 'bash tests/run.sh' 'CI runs the portable contract suite'
assert_file_contains "$REPO_DIR/.github/workflows/ci.yml" 'shellcheck' 'CI installs and runs ShellCheck on Ubuntu'
assert_file_contains "$REPO_DIR/.github/workflows/ci.yml" 'actions/checkout@[0-9a-f]{40}' 'CI pins checkout to a reviewed commit'
assert_file_contains "$REPO_DIR/.github/workflows/ci.yml" 'persist-credentials:[[:space:]]*false' 'CI does not persist checkout credentials'

# G12 public-integration contract.  These are intentionally separate from the
# earlier documentation checks: G12 is the point at which the public reader
# journey must describe the already-canonical v1 workflow without restating it.
assert_file_contains "$readme" '\[Workflow contract\]\(shared/workflow\.md\)' 'G12_WORKFLOW_DOCS: README links the canonical workflow contract'
assert_file_contains "$readme" 'checkpoint-then-continue|checkpoint then continue' 'G12_WORKFLOW_DOCS: README explains checkpoint-then-continue'
assert_file_contains "$readme" 'automatic local commits' 'G12_POST_G13_EXTERNAL_GATE: README states the automatic local-commit boundary'
assert_file_contains "$readme" 'post-G13|after terminal G13' 'G12_POST_G13_EXTERNAL_GATE: README identifies the one post-G13 gate'
assert_file_contains "$readme" 'human external.*gate|external.*human.*gate' 'G12_POST_G13_EXTERNAL_GATE: README reserves external action for the human gate'
assert_file_contains "$REPO_DIR/shared/publication.md" 'Approved execution may create commits automatically' 'G12_POST_G13_EXTERNAL_GATE: canonical publication policy permits automatic local commits'
assert_file_contains "$REPO_DIR/shared/publication.md" 'One final human gate.*only after terminal G13' 'G12_POST_G13_EXTERNAL_GATE: canonical publication policy has one final external gate'
assert_file_contains "$REPO_DIR/docs/security-model.md" 'OS-level sandbox' 'G12_SECURITY_CLAIMS: security guide names the actual containment boundary'
assert_file_contains "$readme" '\[Security model\]\(docs/security-model\.md\)' 'G12_SECURITY_CLAIMS: README links the security model'
assert_file_contains "$readme" 'all v1 state remains local' 'G12_LOCAL_ONLY_NO_EXPORT_OR_RESTORE: README states the local-only durability boundary'
assert_file_contains "$readme" 'single-machine risk' 'G12_FAILURE_DOMAIN_LIMITS: README records the accepted failure domain'
assert_not_contains "$(cat "$readme" "$REPO_DIR/docs"/*.md)" 'cross-host recovery|remote target|remote backup' 'G12_LOCAL_ONLY_NO_EXPORT_OR_RESTORE: public guides make no remote durability claim'
assert_file_contains "$REPO_DIR/CONTEXT.md" 'immutable Goal definitions' 'G12_GOAL_LEDGER_DOMAIN: Goal Ledger includes immutable Goal definitions'
assert_file_contains "$REPO_DIR/CONTEXT.md" 'protected lifecycle records' 'G12_GOAL_LEDGER_DOMAIN: Goal Ledger includes protected lifecycle records'
assert_file_contains "$REPO_DIR/CONTEXT.md" 'local plan/evidence.*untrusted|local plan and evidence.*untrusted' 'G12_GOAL_LEDGER_DOMAIN: local plan and evidence are untrusted'
assert_file_contains "$readme" 'GitHub Issues.*future.*non-authoritative|future.*non-authoritative.*GitHub Issues' 'G12_GITHUB_PROJECTION_FUTURE_ONLY: GitHub collaboration is future and non-authoritative'
assert_not_contains "$(cat "$readme" "$REPO_DIR/docs"/*.md "$REPO_DIR/.github/PULL_REQUEST_TEMPLATE.md")" 'tracker (module|goal|bot|webhook|reverse sync|adapter)' 'G12_NO_TRACKER_SEAM: public surfaces expose no tracker seam'
assert_file_contains "$REPO_DIR/shared/workflow.md" 'host owns activation and continuation' 'G12_HOST_NATIVE_SEQUENTIAL_SINGLE_MODEL: host owns sequential activation'
assert_file_contains "$REPO_DIR/shared/workflow.md" 'parallel-dispatch request fails closed' 'G12_HOST_NATIVE_SEQUENTIAL_SINGLE_MODEL: parallel dispatch is rejected'
assert_not_contains "$(cat "$codex")" 'external goal-chain driver' 'G12_HOST_NATIVE_SEQUENTIAL_SINGLE_MODEL: Codex skill makes no external-driver claim'
assert_file_contains "$codex" 'host-native continuation|host native continuation' 'G12_HOST_NATIVE_SEQUENTIAL_SINGLE_MODEL: Codex skill declares host-native continuation'
assert_file_contains "$codex" 'non-interactive entrypoint' 'G12_HOST_NATIVE_SEQUENTIAL_SINGLE_MODEL: Codex skill retains its non-interactive boundary'
assert_file_contains "$REPO_DIR/shared/workflow.md" 'leaves the parent in progress until every ordered slice is complete' 'G12_PARENT_CHILD_COMPLETION_DOCS: only all slices complete the parent'
assert_file_contains "$REPO_DIR/shared/workflow.md" 'background continuation, or advance the parent' 'G12_PARENT_CHILD_COMPLETION_DOCS: a checker cannot advance the parent'
assert_file_contains "$REPO_DIR/shared/workflow.md" 'codex-continuation\.sh' 'G12_CONTINUATION_CONTROLLER_DOCS: workflow names the protected foreground controller'
assert_file_contains "$REPO_DIR/docs/security-model.md" 'tool root.*child sandbox|child sandbox.*tool root' 'G12_CONTINUATION_CONTROLLER_DOCS: security model protects the trusted controller and checker'

# The protected-red receipt needs a stable, goal-specific failure line rather
# than a generic assertion summary.  Keep it immediately before finish_tests
# so the normal assertion output remains useful to the maker.
if [ "$TEST_FAILURES" -ne 0 ]; then
  printf '%s\n' 'FAIL: G12_PUBLIC_DOCS_MISSING' >&2
fi

finish_tests
