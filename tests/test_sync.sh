#!/usr/bin/env bash
set -u
. "$(dirname "$0")/testlib.sh"

sync="$REPO_DIR/sync.sh"

# A real destination is user data: default installs must never replace it.
home="$TEST_TMP/preserve"
mkdir -p "$home/.claude/skills/writing-goals"
printf 'do not replace\n' > "$home/.claude/skills/writing-goals/SKILL.md"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" claude
assert_nonzero 'default Claude install refuses a real destination'
assert_file_contains "$home/.claude/skills/writing-goals/SKILL.md" '^do not replace$' 'default Claude refusal preserves sentinel'

# all must preflight every requested target before creating the first one.
home="$TEST_TMP/all-atomic"
mkdir -p "$home/.codex/skills/writing-goals"
printf 'codex sentinel\n' > "$home/.codex/skills/writing-goals/KEEP"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" all
assert_nonzero 'all refuses a later real Codex collision'
assert_path_absent "$home/.claude/skills/writing-goals" 'all collision leaves no partial Claude install'
assert_file_contains "$home/.codex/skills/writing-goals/KEEP" '^codex sentinel$' 'all collision preserves Codex sentinel'

# Installer-created links are safe to replace repeatedly without --force.
home="$TEST_TMP/idempotent"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" claude
assert_success 'first empty Claude install succeeds'
assert_symlink "$home/.claude/skills/writing-goals/SKILL.md" 'first install creates Claude skill link'
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" claude
assert_success 'reinstalling installer-created Claude links is idempotent'

# --force is deliberately narrow: it may replace the requested adapter only.
home="$TEST_TMP/force-scope"
mkdir -p "$home/.claude/skills/writing-goals" "$home/.codex/skills/writing-goals"
printf 'replace only me\n' > "$home/.claude/skills/writing-goals/SKILL.md"
printf 'leave me alone\n' > "$home/.codex/skills/writing-goals/KEEP"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" --force claude
assert_success '--force claude replaces the requested Claude target'
assert_symlink "$home/.claude/skills/writing-goals/SKILL.md" '--force claude creates a linked Claude skill'
assert_file_contains "$home/.codex/skills/writing-goals/KEEP" '^leave me alone$' '--force claude does not replace Codex target'

finish_tests
