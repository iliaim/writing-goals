#!/usr/bin/env bash
# Install writing-goals into agent skill trees via SYMLINKS.
# Single source of truth = this build folder; edits here propagate live.
# Usage: ./sync.sh [--force] [claude|codex|all]   (default: all)
set -euo pipefail
BD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

force=0
report_install=1
if [ "${1:-}" = "--force" ]; then
  force=1
  shift
fi

case "$#" in
  0) selection=all ;;
  1) selection="$1" ;;
  *) echo "usage: $0 [--force] [claude|codex|all]" >&2; exit 1 ;;
esac

case "$selection" in
  claude|codex|all) ;;
  *) echo "usage: $0 [--force] [claude|codex|all]" >&2; exit 1 ;;
esac

claude_dest="$HOME/.claude/skills/writing-goals"
codex_root="${CODEX_HOME:-$HOME/.codex}"
codex_dest="$codex_root/skills/writing-goals"
codex_agents_dir="$codex_root/agents"
codex_role_names='planner challenger oracle-author maker verifier reviewer publisher'
fail() {
  echo "ERROR: $*" >&2
  return 1
}

require_file() {
  [ -f "$1" ] || fail "link source missing or not a file: $1"
}

require_dir() {
  [ -d "$1" ] || fail "link source missing or not a directory: $1"
}

# Every ancestor that already exists must resolve to a directory.  This catches
# a later target that mkdir -p would reject before any earlier target mutates.
preflight_ancestors() {
  local path="$1" ancestor
  ancestor="$(dirname "$path")"
  while [ "$ancestor" != / ]; do
    if [ -e "$ancestor" ] || [ -L "$ancestor" ]; then
      if [ ! -d "$ancestor" ]; then
        fail "destination ancestor is not a directory: $ancestor" || return 1
      fi
    fi
    ancestor="$(dirname "$ancestor")"
  done
  [ -d / ] || fail "root directory is unavailable"
}

link_has_target() {
  local path="$1" source="$2" actual
  [ -L "$path" ] || return 1
  actual="$(readlink "$path")" || return 1
  [ "$actual" = "$source" ]
}

# A normal install may only replace links that this installer previously made.
# A Claude target itself is a real directory, but it is installer-owned only
# when every child is one of the expected canonical links.
preflight_claude_destination() {
  local entry name expected

  preflight_ancestors "$claude_dest" || return 1
  [ "$force" -eq 1 ] && return 0

  if [ -L "$claude_dest" ]; then
    fail "existing Claude destination is a symlink: $claude_dest" || return 1
  elif [ -e "$claude_dest" ] && [ ! -d "$claude_dest" ]; then
    fail "existing Claude destination is not a directory: $claude_dest" || return 1
  fi
  [ -d "$claude_dest" ] || return 0

  if ! link_has_target "$claude_dest/SKILL.md" "$BD/claude/SKILL.md" ||
     ! link_has_target "$claude_dest/shared" "$BD/shared" ||
     ! link_has_target "$claude_dest/assets" "$BD/assets"; then
    fail "existing Claude destination is not a complete installer layout: $claude_dest" || return 1
  fi

  for entry in "$claude_dest"/* "$claude_dest"/.[!.]* "$claude_dest"/..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name="${entry##*/}"
    case "$name" in
      SKILL.md) expected="$BD/claude/SKILL.md" ;;
      shared)   expected="$BD/shared" ;;
      assets)   expected="$BD/assets" ;;
      *) fail "existing Claude destination contains user data: $entry" || return 1 ;;
    esac
    if ! link_has_target "$entry" "$expected"; then
      fail "existing Claude destination is not an installer link: $entry" || return 1
    fi
  done
}

preflight_codex_destination() {
  preflight_ancestors "$codex_dest" || return 1
  [ "$force" -eq 1 ] && return 0

  if [ -e "$codex_dest" ] || [ -L "$codex_dest" ]; then
    if ! link_has_target "$codex_dest" "$BD/codex"; then
      fail "existing Codex destination is not an installer link: $codex_dest" || return 1
    fi
  fi
}

preflight_codex_roles() {
  local role destination
  preflight_ancestors "$codex_agents_dir/writing-goals-planner.toml" || return 1
  [ "$force" -eq 1 ] && return 0
  for role in $codex_role_names; do
    destination="$codex_agents_dir/writing-goals-$role.toml"
    if [ -e "$destination" ] || [ -L "$destination" ]; then
      link_has_target "$destination" "$BD/codex/agents/writing-goals-$role.toml" ||
        { fail "existing Codex role destination is not an installer link: $destination"; return 1; }
    fi
  done
}

preflight_claude() {
  require_file "$BD/claude/SKILL.md" || return 1
  require_dir "$BD/shared" || return 1
  require_dir "$BD/assets" || return 1
  preflight_claude_destination
}

preflight_codex() {
  require_dir "$BD/codex" || return 1
  require_file "$BD/codex/SKILL.md" || return 1
  require_file "$BD/codex/agents/openai.yaml" || return 1
  for role in $codex_role_names; do
    require_file "$BD/codex/agents/writing-goals-$role.toml" || return 1
  done
  require_dir "$BD/codex/shared" || return 1
  require_dir "$BD/codex/assets" || return 1
  preflight_codex_destination || return 1
  preflight_codex_roles
}

# Preflight has already established that dst is absent or an exact,
# installer-created link.  Removing a matching link avoids ln following a
# symlink-to-directory on platforms with differing ln -n semantics.
install_link() {
  local source="$1" destination="$2" actual
  if [ -L "$destination" ]; then
    actual="$(readlink "$destination")"
    if [ "$actual" != "$source" ]; then
      fail "refusing to replace unexpected link: $destination" || return 1
    fi
    rm -f -- "$destination" || fail "cannot replace installer link: $destination" || return 1
  fi
  ln -s "$source" "$destination" || fail "cannot create link: $destination" || return 1
  link_has_target "$destination" "$source" || fail "link verification failed: $destination"
}

install_claude() {
  if [ "$force" -eq 1 ] && { [ -e "$claude_dest" ] || [ -L "$claude_dest" ]; }; then
    rm -rf -- "$claude_dest" || fail "cannot replace Claude target: $claude_dest" || return 1
  fi
  mkdir -p "$claude_dest" || fail "cannot create Claude destination: $claude_dest" || return 1
  install_link "$BD/claude/SKILL.md" "$claude_dest/SKILL.md" || return 1
  install_link "$BD/shared" "$claude_dest/shared" || return 1
  install_link "$BD/assets" "$claude_dest/assets" || return 1
  [ "$report_install" -eq 0 ] ||
    echo "Claude  -> $claude_dest  (invoke as /writing-goals)"
}

install_codex() {
  local role destination
  if [ "$force" -eq 1 ] && { [ -e "$codex_dest" ] || [ -L "$codex_dest" ]; }; then
    rm -rf -- "$codex_dest" || fail "cannot replace Codex target: $codex_dest" || return 1
  fi
  mkdir -p "$codex_root/skills" || fail "cannot create Codex skills root: $codex_root/skills" || return 1
  install_link "$BD/codex" "$codex_dest" || return 1
  mkdir -p "$codex_agents_dir" || fail "cannot create Codex agents root: $codex_agents_dir" || return 1
  for role in $codex_role_names; do
    destination="$codex_agents_dir/writing-goals-$role.toml"
    if [ "$force" -eq 1 ] && { [ -e "$destination" ] || [ -L "$destination" ]; }; then
      rm -f -- "$destination" || fail "cannot replace Codex role target: $destination" || return 1
    fi
    install_link "$BD/codex/agents/writing-goals-$role.toml" "$destination" || return 1
  done
  [ "$report_install" -eq 0 ] ||
    echo "Codex   -> $codex_dest  (invoke as \$writing-goals / /skills picker)"
}

# `all` is one transaction. Existing targets are moved aside in the same
# parent directory, then restored if either installation fails. This also
# preserves user-owned destinations when --force was explicitly requested.
BACKUP_RESULT=""
backup_destination() {
  local destination="$1" backup
  BACKUP_RESULT=""
  if [ -e "$destination" ] || [ -L "$destination" ]; then
    backup="${destination}.writing-goals-backup.$$"
    if [ -e "$backup" ] || [ -L "$backup" ]; then
      fail "transaction backup already exists: $backup" || return 1
    fi
    mv -- "$destination" "$backup" ||
      { fail "cannot stage transaction backup: $destination" || return 1; }
    BACKUP_RESULT="$backup"
  fi
}

transaction_claude_owned() {
  local entry name expected
  [ -d "$claude_dest" ] && [ ! -L "$claude_dest" ] || return 1
  for entry in "$claude_dest"/* "$claude_dest"/.[!.]* "$claude_dest"/..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name="${entry##*/}"
    case "$name" in
      SKILL.md) expected="$BD/claude/SKILL.md" ;;
      shared)   expected="$BD/shared" ;;
      assets)   expected="$BD/assets" ;;
      *) return 1 ;;
    esac
    link_has_target "$entry" "$expected" || return 1
  done
}

remove_transaction_destination() {
  local destination="$1" adapter="$2"
  [ -e "$destination" ] || [ -L "$destination" ] || return 0
  case "$adapter" in
    claude) transaction_claude_owned || return 1 ;;
    codex)  link_has_target "$codex_dest" "$BD/codex" || return 1 ;;
    *) return 1 ;;
  esac
  rm -rf -- "$destination"
}

restore_destination() {
  local destination="$1" backup="$2" adapter="$3"
  remove_transaction_destination "$destination" "$adapter" || return 1
  if [ -n "$backup" ]; then
    mv -- "$backup" "$destination" || return 1
  fi
}

rollback_all() {
  local claude_backup="$1" codex_backup="$2" role_backups="$3" failed=0 entry role backup
  for entry in $role_backups; do
    role="${entry%%:*}"
    backup="${entry#*:}"
    remove_transaction_role "$role" || failed=1
    [ "$backup" = '-' ] || mv -- "$backup" "$codex_agents_dir/writing-goals-$role.toml" || failed=1
  done
  restore_destination "$codex_dest" "$codex_backup" codex || failed=1
  restore_destination "$claude_dest" "$claude_backup" claude || failed=1
  [ "$failed" -eq 0 ]
}

remove_transaction_role() {
  local role="$1" destination="$codex_agents_dir/writing-goals-$1.toml"
  [ -e "$destination" ] || [ -L "$destination" ] || return 0
  link_has_target "$destination" "$BD/codex/agents/writing-goals-$role.toml" || return 1
  rm -f -- "$destination"
}

install_all_transactionally() {
  local claude_backup="" codex_backup="" role_backups="" role destination
  report_install=0

  backup_destination "$claude_dest" || return 1
  claude_backup="$BACKUP_RESULT"
  if ! backup_destination "$codex_dest"; then
    restore_destination "$claude_dest" "$claude_backup" claude || true
    return 1
  fi
  codex_backup="$BACKUP_RESULT"
  for role in $codex_role_names; do
    destination="$codex_agents_dir/writing-goals-$role.toml"
    backup_destination "$destination" || { rollback_all "$claude_backup" "$codex_backup" "$role_backups"; return 1; }
    if [ -n "$BACKUP_RESULT" ]; then
      role_backups="$role_backups $role:$BACKUP_RESULT"
    else
      role_backups="$role_backups $role:-"
    fi
  done

  if install_claude && install_codex; then
    for entry in $role_backups; do
      backup="${entry#*:}"
      [ "$backup" = '-' ] || rm -f -- "$backup" || { fail "cannot remove Codex role transaction backup: $backup"; return 1; }
    done
    [ -z "$codex_backup" ] || rm -rf -- "$codex_backup" ||
      { fail "cannot remove Codex transaction backup: $codex_backup" || return 1; }
    [ -z "$claude_backup" ] || rm -rf -- "$claude_backup" ||
      { fail "cannot remove Claude transaction backup: $claude_backup" || return 1; }
    echo "Claude  -> $claude_dest  (invoke as /writing-goals)"
    echo "Codex   -> $codex_dest  (invoke as \$writing-goals / /skills picker)"
    return 0
  fi

  if ! rollback_all "$claude_backup" "$codex_backup" "$role_backups"; then
    fail "installation failed and transaction rollback was incomplete" || return 1
  fi
  return 1
}

# Do every source, destination leaf, and ancestor check before the first mkdir,
# unlink, or rm.  In particular, `all` cannot leave Claude installed if Codex
# has a collision.
case "$selection" in
  claude) preflight_claude || exit 1 ;;
  codex)  preflight_codex || exit 1 ;;
  all)
    preflight_claude || exit 1
    preflight_codex || exit 1
    ;;
esac

case "$selection" in
  claude) install_claude ;;
  codex)  install_codex ;;
  all)    install_all_transactionally ;;
esac
