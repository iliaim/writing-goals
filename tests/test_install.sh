#!/usr/bin/env bash
# G09's protected oracle: transactional, copy-only installation from a bundle.
set -u
. "$(dirname "$0")/testlib.sh"

builder="$REPO_DIR/scripts/build-bundles.sh"
root_installer="$REPO_DIR/install.sh"

if [ ! -f "$root_installer" ]; then
  printf 'FAIL: G09_INSTALLER_MISSING: install.sh is absent\n' >&2
  exit 1
fi
if [ ! -f "$builder" ]; then
  printf 'FAIL: G09_INSTALLER_MISSING: scripts/build-bundles.sh is absent\n' >&2
  exit 1
fi

bundle="$TEST_TMP/bundle"
run_command bash "$builder" "$bundle"
assert_success 'G09 installer fixture bundle builds'
installer="$bundle/install.sh"
TEST_COUNT=$((TEST_COUNT + 1))
if [ -f "$installer" ]; then pass 'bundle contains its local installer'; else fail 'bundle lacks its local installer'; fi

roles='planner challenger oracle-author maker verifier reviewer publisher'
assert_copy_tree() {
  local path="$1" label="$2"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ -d "$path" ] && [ ! -L "$path" ] && ! find "$path" -type l -print -quit | grep -q .; then
    pass "$label"
  else
    fail "$label (expected a real symlink-free directory)"
  fi
}

home="$TEST_TMP/clean-home"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$installer" all
assert_success 'G09 all installs to every official user target'
assert_copy_tree "$home/.claude/skills/writing-goals" 'G09 official Claude skill target is a copy'
assert_copy_tree "$home/.codex/skills/writing-goals" 'G09 official Codex skill target is a copy'
for role in $roles; do
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ -f "$home/.codex/agents/writing-goals-$role.toml" ] && [ ! -L "$home/.codex/agents/writing-goals-$role.toml" ]; then
    pass "G09 official Codex $role agent target is a copy"
  else
    fail "G09 official Codex $role agent target is missing or linked"
  fi
done
run_command grep -R -n -E -- "$(printf '%s' "$REPO_DIR" | sed 's/[.[\\*^$()+?{|]/\\\\&/g')|$bundle" "$home/.claude/skills/writing-goals" "$home/.codex/skills/writing-goals" "$home/.codex/agents"
assert_nonzero 'G09 installed targets do not retain source paths'

run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$installer" all
assert_success 'G09 all is idempotent for its own copy layout'

# A rollback-injection flag must never become permission to replace an occupied
# single-host target. These selections do not stage the other host at all.
single_claude_home="$TEST_TMP/single-claude-collision"
mkdir -p "$single_claude_home/.claude/skills/writing-goals"
printf 'single Claude sentinel\n' > "$single_claude_home/.claude/skills/writing-goals/KEEP"
run_command env HOME="$single_claude_home" CODEX_HOME="$single_claude_home/.codex" WG_INSTALL_FAIL_AFTER_STAGE=codex bash "$installer" claude
assert_nonzero 'G09 injected Claude-only collision still refuses replacement'
assert_file_contains "$single_claude_home/.claude/skills/writing-goals/KEEP" '^single Claude sentinel$' 'G09 injected Claude-only collision preserves sentinel'

single_codex_home="$TEST_TMP/single-codex-collision"
mkdir -p "$single_codex_home/.codex/skills/writing-goals"
printf 'single Codex sentinel\n' > "$single_codex_home/.codex/skills/writing-goals/KEEP"
run_command env HOME="$single_codex_home" CODEX_HOME="$single_codex_home/.codex" WG_INSTALL_FAIL_AFTER_STAGE=codex bash "$installer" codex
assert_nonzero 'G09 injected Codex-only collision still refuses replacement'
assert_file_contains "$single_codex_home/.codex/skills/writing-goals/KEEP" '^single Codex sentinel$' 'G09 injected Codex-only collision preserves sentinel'

# Any occupied exact target is a collision: all must change neither host.
collision_home="$TEST_TMP/collision-home"
mkdir -p "$collision_home/.claude/skills/writing-goals" "$collision_home/.codex/skills/writing-goals" "$collision_home/.codex/agents"
printf 'claude sentinel\n' > "$collision_home/.claude/skills/writing-goals/KEEP"
printf 'codex sentinel\n' > "$collision_home/.codex/skills/writing-goals/KEEP"
printf 'agent sentinel\n' > "$collision_home/.codex/agents/writing-goals-maker.toml"
printf 'unrelated agent\n' > "$collision_home/.codex/agents/other-agent.toml"
run_command env HOME="$collision_home" CODEX_HOME="$collision_home/.codex" bash "$installer" all
assert_nonzero 'G09 all refuses occupied targets before mutation'
assert_file_contains "$collision_home/.claude/skills/writing-goals/KEEP" '^claude sentinel$' 'G09 collision preserves Claude preimage'
assert_file_contains "$collision_home/.codex/skills/writing-goals/KEEP" '^codex sentinel$' 'G09 collision preserves Codex preimage'
assert_file_contains "$collision_home/.codex/agents/writing-goals-maker.toml" '^agent sentinel$' 'G09 collision preserves namespaced agent preimage'
assert_file_contains "$collision_home/.codex/agents/other-agent.toml" '^unrelated agent$' 'G09_UNRELATED_AGENTS_PRESERVED: installer never overwrites unrelated agents'

# A controlled late failure exercises rollback after Claude has been staged.
rollback_home="$TEST_TMP/rollback-home"
mkdir -p "$rollback_home/.claude/skills/writing-goals" "$rollback_home/.codex/skills/writing-goals" "$rollback_home/.codex/agents"
printf 'claude preimage\n' > "$rollback_home/.claude/skills/writing-goals/KEEP"
printf 'codex preimage\n' > "$rollback_home/.codex/skills/writing-goals/KEEP"
printf 'role preimage\n' > "$rollback_home/.codex/agents/writing-goals-maker.toml"
run_command env HOME="$rollback_home" CODEX_HOME="$rollback_home/.codex" WG_INSTALL_FAIL_AFTER_STAGE=codex bash "$installer" all
assert_nonzero 'G09 rollback injection reports failure'
assert_file_contains "$rollback_home/.claude/skills/writing-goals/KEEP" '^claude preimage$' 'G09_COLLISION_ROLLBACK: rollback restores Claude preimage'
assert_file_contains "$rollback_home/.codex/skills/writing-goals/KEEP" '^codex preimage$' 'G09_COLLISION_ROLLBACK: rollback restores Codex preimage'
assert_file_contains "$rollback_home/.codex/agents/writing-goals-maker.toml" '^role preimage$' 'G09_COLLISION_ROLLBACK: rollback restores agent preimage'

# Backup moves are part of the transaction. A failed Codex backup must stop
# before any later target is published; it must not be masked by a later move
# or copy. This starts from real installer-owned targets so the exact complete
# preimage (including all namespaced agents) is observable.
backup_failure_home="$TEST_TMP/backup-failure-home"
run_command env HOME="$backup_failure_home" CODEX_HOME="$backup_failure_home/.codex" bash "$installer" all
assert_success 'G09 establishes preimages before backup-move rollback test'
backup_failure_before="$TEST_TMP/backup-failure-before"
mkdir -p "$backup_failure_before"
cp -R "$backup_failure_home/.claude" "$backup_failure_before/.claude"
cp -R "$backup_failure_home/.codex" "$backup_failure_before/.codex"
backup_shim_dir="$TEST_TMP/failing-backup-mv"
mkdir -p "$backup_shim_dir"
cp "$REPO_DIR/tests/fixtures/install/failing-mv.sh" "$backup_shim_dir/mv"
chmod +x "$backup_shim_dir/mv"
real_mv="$(command -v mv)"
run_command env HOME="$backup_failure_home" CODEX_HOME="$backup_failure_home/.codex" REAL_MV="$real_mv" WG_FAIL_MV_SOURCE="$backup_failure_home/.codex/skills/writing-goals" PATH="$backup_shim_dir:$PATH" bash "$installer" all
assert_nonzero 'G09 failed backup move aborts the transaction'
run_command diff -ru "$backup_failure_before/.claude" "$backup_failure_home/.claude"
assert_success 'G09 failed backup move leaves Claude preimage without later mutation'
run_command diff -ru "$backup_failure_before/.codex" "$backup_failure_home/.codex"
assert_success 'G09_COLLISION_ROLLBACK: failed backup move leaves Codex tree and agents unchanged'

# A real copy failure is not allowed to be masked by later successful role
# copies. The wrapper fails only the Codex tree publication; all later copy
# commands remain possible, so a successful installer exit would prove an
# incorrectly ignored intermediate failure. Every installed preimage must be
# restored byte-for-byte.
copy_failure_home="$TEST_TMP/copy-failure-home"
run_command env HOME="$copy_failure_home" CODEX_HOME="$copy_failure_home/.codex" bash "$installer" all
assert_success 'G09 establishes preimages before copy-failure rollback test'
copy_failure_before="$TEST_TMP/copy-failure-before"
mkdir -p "$copy_failure_before"
cp -R "$copy_failure_home/.claude" "$copy_failure_before/.claude"
cp -R "$copy_failure_home/.codex" "$copy_failure_before/.codex"
copy_shim_dir="$TEST_TMP/failing-copy"
mkdir -p "$copy_shim_dir"
printf '%s\n' \
  '#!/bin/sh' \
  'last_arg=' \
  'for arg do last_arg=$arg; done' \
  'if [ "$last_arg" = "$WG_FAIL_CP_TARGET" ]; then exit 91; fi' \
  'exec "$REAL_CP" "$@"' > "$copy_shim_dir/cp"
chmod +x "$copy_shim_dir/cp"
real_cp="$(command -v cp)"
run_command env HOME="$copy_failure_home" CODEX_HOME="$copy_failure_home/.codex" REAL_CP="$real_cp" WG_FAIL_CP_TARGET="$copy_failure_home/.codex/skills/writing-goals" PATH="$copy_shim_dir:$PATH" bash "$installer" all
assert_nonzero 'G09 intermediate Codex copy failure is not masked by later work'
run_command diff -ru "$copy_failure_before/.claude" "$copy_failure_home/.claude"
assert_success 'G09_COLLISION_ROLLBACK: intermediate copy failure restores Claude tree'
run_command diff -ru "$copy_failure_before/.codex" "$copy_failure_home/.codex"
assert_success 'G09_COLLISION_ROLLBACK: intermediate copy failure restores Codex tree and agents'

finish_tests
