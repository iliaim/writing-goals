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
assert_link_target "$home/.claude/skills/writing-goals/SKILL.md" "$REPO_DIR/claude/SKILL.md" 'Claude SKILL link uses the canonical source target'
assert_link_target "$home/.claude/skills/writing-goals/shared" "$REPO_DIR/shared" 'Claude shared link uses the canonical source target'
assert_link_target "$home/.claude/skills/writing-goals/assets" "$REPO_DIR/assets" 'Claude assets link uses the canonical source target'
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" claude
assert_success 'reinstalling installer-created Claude links is idempotent'
assert_link_target "$home/.claude/skills/writing-goals/SKILL.md" "$REPO_DIR/claude/SKILL.md" 'idempotent Claude install preserves canonical SKILL target'

# The Codex adapter is a single canonical directory symlink, not a file-link tree.
home="$TEST_TMP/codex-clean"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" codex
assert_success 'first empty Codex install succeeds'
assert_link_target "$home/.codex/skills/writing-goals" "$REPO_DIR/codex" 'Codex install uses the canonical adapter-directory target'

# A clean all install must install both adapters at their canonical sources.
home="$TEST_TMP/all-clean"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" all
assert_success 'first empty all install succeeds'
assert_link_target "$home/.claude/skills/writing-goals/SKILL.md" "$REPO_DIR/claude/SKILL.md" 'all install uses canonical Claude SKILL target'
assert_link_target "$home/.claude/skills/writing-goals/shared" "$REPO_DIR/shared" 'all install uses canonical Claude shared target'
assert_link_target "$home/.claude/skills/writing-goals/assets" "$REPO_DIR/assets" 'all install uses canonical Claude assets target'
assert_link_target "$home/.codex/skills/writing-goals" "$REPO_DIR/codex" 'all install uses canonical Codex adapter target'

# --force is deliberately narrow: it may replace the requested adapter only.
home="$TEST_TMP/force-scope"
mkdir -p "$home/.claude/skills/writing-goals" "$home/.codex/skills/writing-goals"
printf 'replace only me\n' > "$home/.claude/skills/writing-goals/SKILL.md"
printf 'leave me alone\n' > "$home/.codex/skills/writing-goals/KEEP"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" --force claude
assert_success '--force claude replaces the requested Claude target'
assert_symlink "$home/.claude/skills/writing-goals/SKILL.md" '--force claude creates a linked Claude skill'
assert_link_target "$home/.claude/skills/writing-goals/SKILL.md" "$REPO_DIR/claude/SKILL.md" '--force claude uses canonical Claude SKILL target'
assert_file_contains "$home/.codex/skills/writing-goals/KEEP" '^leave me alone$' '--force claude does not replace Codex target'

finish_tests
