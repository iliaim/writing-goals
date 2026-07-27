#!/usr/bin/env bash
# Install writing-goals into agent skill trees via SYMLINKS.
# Single source of truth = this build folder; edits here propagate live.
# Usage: ./sync.sh [--force] [claude|codex|all]   (default: all)
set -euo pipefail
BD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

force=0
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
codex_enabled=0

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

preflight_claude() {
  require_file "$BD/claude/SKILL.md" || return 1
  require_dir "$BD/shared" || return 1
  require_dir "$BD/assets" || return 1
  preflight_claude_destination
}

preflight_codex() {
  # Codex remains optional until its adapter is present, matching the original
  # installer behaviour.  When present, validate its source before mutation.
  if [ ! -f "$BD/codex/SKILL.md" ]; then
    codex_enabled=0
    return 0
  fi
  codex_enabled=1
  require_dir "$BD/codex" || return 1
  preflight_codex_destination
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
  echo "Claude  -> $claude_dest  (invoke as /writing-goals)"
}

install_codex() {
  [ "$codex_enabled" -eq 1 ] || { echo "Codex   -> adapter not built yet, skipping"; return 0; }
  if [ "$force" -eq 1 ] && { [ -e "$codex_dest" ] || [ -L "$codex_dest" ]; }; then
    rm -rf -- "$codex_dest" || fail "cannot replace Codex target: $codex_dest" || return 1
  fi
  mkdir -p "$codex_root/skills" || fail "cannot create Codex skills root: $codex_root/skills" || return 1
  install_link "$BD/codex" "$codex_dest" || return 1
  echo "Codex   -> $codex_dest  (invoke as \$writing-goals / /skills picker)"
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
  all)    install_claude; install_codex ;;
esac
