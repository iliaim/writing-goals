#!/usr/bin/env bash
set -u
. "$(dirname "$0")/testlib.sh"

sync="$REPO_DIR/sync.sh"

# A damaged selected adapter is an error, never a successful skip.
for missing_member in SKILL.md agents/openai.yaml shared assets; do
  source_root="$TEST_TMP/codex-source-${missing_member//\//-}"
  home="$TEST_TMP/codex-source-home-${missing_member//\//-}"
  mkdir -p "$source_root/shared" "$source_root/assets"
  cp "$REPO_DIR/sync.sh" "$source_root/sync.sh"
  cp -R "$REPO_DIR/codex" "$source_root/codex"
  rm -rf "$source_root/codex/$missing_member"
  run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$source_root/sync.sh" codex
  assert_nonzero "Codex install refuses source missing $missing_member"
  assert_path_absent "$home/.codex/skills/writing-goals" "missing $missing_member causes no Codex destination"
done

# A real destination is user data: default installs must never replace it.
home="$TEST_TMP/preserve"
mkdir -p "$home/.claude/skills/writing-goals"
printf 'do not replace\n' > "$home/.claude/skills/writing-goals/SKILL.md"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" claude
assert_nonzero 'default Claude install refuses a real destination'
assert_file_contains "$home/.claude/skills/writing-goals/SKILL.md" '^do not replace$' 'default Claude refusal preserves sentinel'

# Empty and partial real directories are not proof of installer ownership.
home="$TEST_TMP/preserve-empty"
mkdir -p "$home/.claude/skills/writing-goals"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" claude
assert_nonzero 'default Claude install refuses an empty real destination'
assert_path_absent "$home/.claude/skills/writing-goals/SKILL.md" 'empty Claude refusal leaves the destination unchanged'

home="$TEST_TMP/preserve-partial"
mkdir -p "$home/.claude/skills/writing-goals"
ln -s "$REPO_DIR/claude/SKILL.md" "$home/.claude/skills/writing-goals/SKILL.md"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" claude
assert_nonzero 'default Claude install refuses a partial installer layout'
assert_link_target "$home/.claude/skills/writing-goals/SKILL.md" "$REPO_DIR/claude/SKILL.md" 'partial Claude refusal preserves its existing canonical link'
assert_path_absent "$home/.claude/skills/writing-goals/shared" 'partial Claude refusal does not complete the layout'

# all must preflight every requested target before creating the first one.
home="$TEST_TMP/all-atomic"
mkdir -p "$home/.codex/skills/writing-goals"
printf 'codex sentinel\n' > "$home/.codex/skills/writing-goals/KEEP"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" all
assert_nonzero 'all refuses a later real Codex collision'
assert_path_absent "$home/.claude/skills/writing-goals" 'all collision leaves no partial Claude install'
assert_file_contains "$home/.codex/skills/writing-goals/KEEP" '^codex sentinel$' 'all collision preserves Codex sentinel'

# A blocked later ancestor must be detected before the first adapter mutates.
home="$TEST_TMP/all-ancestor-atomic"
mkdir -p "$home/.codex"
printf 'not a directory\n' > "$home/.codex/skills"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" all
assert_nonzero 'all refuses a non-directory later Codex ancestor'
assert_path_absent "$home/.claude/skills/writing-goals" 'all ancestor collision leaves no partial Claude install'
assert_file_contains "$home/.codex/skills" '^not a directory$' 'all ancestor collision preserves Codex ancestor sentinel'

# Existing ancestors may be symlinks when they resolve to directories (as /var
# does on macOS), but broken symlink ancestors must still fail preflight.
real_home="$TEST_TMP/symlink-ancestor-real"
home="$TEST_TMP/symlink-ancestor-home"
mkdir -p "$real_home"
ln -s "$real_home" "$home"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" claude
assert_success 'Claude install accepts a symlink ancestor that resolves to a directory'
assert_link_target "$home/.claude/skills/writing-goals/SKILL.md" "$REPO_DIR/claude/SKILL.md" 'install through a directory symlink uses the canonical source target'

home="$TEST_TMP/broken-symlink-ancestor"
mkdir -p "$home/.claude"
ln -s "$home/missing-skills" "$home/.claude/skills"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" claude
assert_nonzero 'Claude install refuses a broken symlink ancestor'
assert_path_absent "$home/missing-skills" 'broken symlink ancestor refusal makes no destination'

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
printf 'replace me too\n' > "$home/.claude/skills/writing-goals/EXTRA"
printf 'leave me alone\n' > "$home/.codex/skills/writing-goals/KEEP"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" --force claude
assert_success '--force claude replaces the requested Claude target'
assert_symlink "$home/.claude/skills/writing-goals/SKILL.md" '--force claude creates a linked Claude skill'
assert_link_target "$home/.claude/skills/writing-goals/SKILL.md" "$REPO_DIR/claude/SKILL.md" '--force claude uses canonical Claude SKILL target'
assert_path_absent "$home/.claude/skills/writing-goals/EXTRA" '--force claude replaces the exact Claude target'
assert_file_contains "$home/.codex/skills/writing-goals/KEEP" '^leave me alone$' '--force claude does not replace Codex target'

# Installation-time failures in `all` must roll back both clean and forced
# destinations. Inject a deterministic failure only for the Codex link.
real_ln="$(command -v ln)"
shim_dir="$TEST_TMP/failing-ln"
mkdir -p "$shim_dir"
printf '%s\n' \
  '#!/bin/sh' \
  'last_arg=' \
  'for arg do last_arg=$arg; done' \
  'case "$last_arg" in' \
  '  */.codex/skills/writing-goals) exit 72 ;;' \
  'esac' \
  'exec "$REAL_LN" "$@"' > "$shim_dir/ln"
chmod +x "$shim_dir/ln"

home="$TEST_TMP/all-runtime-rollback"
run_command env HOME="$home" CODEX_HOME="$home/.codex" REAL_LN="$real_ln" PATH="$shim_dir:$PATH" bash "$sync" all
assert_nonzero 'all reports a later installation-time Codex failure'
assert_not_contains "$(cat "$RUN_OUT")" 'Claude[[:space:]]+->' 'rolled-back all emits no premature Claude success message'
assert_path_absent "$home/.claude/skills/writing-goals" 'all rolls back a clean Claude install after a later failure'
assert_path_absent "$home/.codex/skills/writing-goals" 'all leaves no failed clean Codex destination'

home="$TEST_TMP/all-idempotent-runtime-rollback"
run_command env HOME="$home" CODEX_HOME="$home/.codex" bash "$sync" all
assert_success 'all establishes an installer-owned layout before rollback testing'
run_command env HOME="$home" CODEX_HOME="$home/.codex" REAL_LN="$real_ln" PATH="$shim_dir:$PATH" bash "$sync" all
assert_nonzero 'idempotent all reports a later installation-time Codex failure'
assert_link_target "$home/.claude/skills/writing-goals/SKILL.md" "$REPO_DIR/claude/SKILL.md" 'idempotent rollback restores the prior Claude layout'
assert_link_target "$home/.codex/skills/writing-goals" "$REPO_DIR/codex" 'idempotent rollback restores the prior Codex layout'

home="$TEST_TMP/all-force-runtime-rollback"
mkdir -p "$home/.claude/skills/writing-goals" "$home/.codex/skills/writing-goals"
printf 'claude sentinel\n' > "$home/.claude/skills/writing-goals/KEEP"
printf 'codex sentinel\n' > "$home/.codex/skills/writing-goals/KEEP"
run_command env HOME="$home" CODEX_HOME="$home/.codex" REAL_LN="$real_ln" PATH="$shim_dir:$PATH" bash "$sync" --force all
assert_nonzero '--force all reports a later installation-time Codex failure'
assert_file_contains "$home/.claude/skills/writing-goals/KEEP" '^claude sentinel$' '--force all restores the original Claude destination'
assert_file_contains "$home/.codex/skills/writing-goals/KEEP" '^codex sentinel$' '--force all restores the original Codex destination'

finish_tests
