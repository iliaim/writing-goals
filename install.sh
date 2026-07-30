#!/usr/bin/env bash
# Install a writing-goals bundle as real copies, never development links.
set -euo pipefail

usage() {
  printf 'usage: %s [claude|codex|all]\n' "$0" >&2
  exit 2
}

selection="${1:-all}"
[ "$#" -le 1 ] || usage
case "$selection" in claude|codex|all) ;; *) usage ;; esac

bundle_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
roles='planner challenger oracle-author maker verifier reviewer publisher'
claude_target="$HOME/.claude/skills/writing-goals"
codex_root="${CODEX_HOME:-$HOME/.codex}"
codex_target="$codex_root/skills/writing-goals"
agents_dir="$codex_root/agents"
work="$(mktemp -d "${TMPDIR:-/tmp}/writing-goals-install.XXXXXX")"
backup_targets=()
backup_paths=()
created=()

cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT HUP INT TERM

fail() { printf 'ERROR: %s\n' "$*" >&2; return 1; }

require_bundle() {
  local path
  for path in claude/SKILL.md codex/SKILL.md shared/method.md assets/gate.codex.sh; do
    [ -f "$bundle_root/$path" ] && [ ! -L "$bundle_root/$path" ] || { fail "invalid bundle: $path"; return 1; }
  done
  for role in $roles; do
    [ -f "$bundle_root/codex/agents/writing-goals-$role.toml" ] || { fail "invalid bundle role: $role"; return 1; }
  done
  if find "$bundle_root" -type l -print -quit | grep -q .; then
    fail 'invalid bundle: symbolic links are not installable'
    return 1
  fi
}

same_tree() {
  [ -d "$1" ] && [ ! -L "$1" ] && ! find "$1" -type l -print -quit | grep -q . && diff -qr "$1" "$2" >/dev/null 2>&1
}

prepare_sources() {
  mkdir -p "$work/claude" || return 1
  cp -p "$bundle_root/claude/SKILL.md" "$work/claude/SKILL.md" || return 1
  cp -RL "$bundle_root/shared" "$work/claude/shared" || return 1
  cp -RL "$bundle_root/assets" "$work/claude/assets" || return 1
  cp -RL "$bundle_root/codex" "$work/codex" || return 1
  mkdir -p "$work/agents" || return 1
  for role in $roles; do
    cp -p "$bundle_root/codex/agents/writing-goals-$role.toml" "$work/agents/writing-goals-$role.toml" || return 1
  done
}

preflight_ancestors() {
  local path="$1" ancestor
  ancestor="$(dirname -- "$path")"
  while [ "$ancestor" != / ]; do
    if [ -e "$ancestor" ] || [ -L "$ancestor" ]; then
      [ -d "$ancestor" ] || { fail "destination ancestor is not a directory: $ancestor"; return 1; }
    fi
    ancestor="$(dirname -- "$ancestor")"
  done
}

# This is a test-only transaction exercise, deliberately narrow enough that it
# cannot make claude/codex selections overwrite a collision.  Its only path
# through installation is an unconditional failure and rollback after Claude.
controlled_rollback_injection() {
  [ "$selection" = all ] && [ "${WG_INSTALL_FAIL_AFTER_STAGE:-}" = codex ]
}

preflight_target() {
  local target="$1" source="$2"
  preflight_ancestors "$target" || return 1
  if [ -e "$target" ] || [ -L "$target" ]; then
    if same_tree "$target" "$source"; then return 0; fi
    controlled_rollback_injection && return 0
    fail "destination already exists and is not this install: $target"
    return 1
  fi
}

preflight_file() {
  local target="$1" source="$2"
  preflight_ancestors "$target" || return 1
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -f "$target" ] && [ ! -L "$target" ] && cmp -s "$target" "$source"; then return 0; fi
    controlled_rollback_injection && return 0
    fail "destination already exists and is not this install: $target"
    return 1
  fi
}

backup_target() {
  local target="$1" backup
  if [ -e "$target" ] || [ -L "$target" ]; then
    backup="$work/backup-${#backup_targets[@]}"
    mv "$target" "$backup" || return 1
    backup_targets+=("$target")
    backup_paths+=("$backup")
  else
    created+=("$target")
  fi
}

rollback() {
  local index failed=0
  for ((index = ${#created[@]} - 1; index >= 0; index--)); do
    rm -rf -- "${created[$index]}" || failed=1
  done
  for ((index = ${#backup_targets[@]} - 1; index >= 0; index--)); do
    rm -rf -- "${backup_targets[$index]}" || failed=1
    mv -- "${backup_paths[$index]}" "${backup_targets[$index]}" || failed=1
  done
  [ "$failed" -eq 0 ]
}

install_selection() {
  local role target
  case "$selection" in
    claude) backup_target "$claude_target" || return 1 ;;
    codex)
      backup_target "$codex_target" || return 1
      for role in $roles; do backup_target "$agents_dir/writing-goals-$role.toml" || return 1; done
      ;;
    all)
      backup_target "$claude_target" || return 1
      backup_target "$codex_target" || return 1
      for role in $roles; do backup_target "$agents_dir/writing-goals-$role.toml" || return 1; done
      ;;
  esac

  case "$selection" in
    claude)
      mkdir -p "$(dirname -- "$claude_target")" || return 1
      cp -RL "$work/claude" "$claude_target" || return 1
      ;;
    codex)
      mkdir -p "$(dirname -- "$codex_target")" "$agents_dir" || return 1
      cp -RL "$work/codex" "$codex_target" || return 1
      for role in $roles; do
        target="$agents_dir/writing-goals-$role.toml"
        cp -p "$work/agents/writing-goals-$role.toml" "$target" || return 1
      done
      ;;
    all)
      mkdir -p "$(dirname -- "$claude_target")" "$(dirname -- "$codex_target")" "$agents_dir" || return 1
      cp -RL "$work/claude" "$claude_target" || return 1
      if [ "${WG_INSTALL_FAIL_AFTER_STAGE:-}" = codex ]; then
        fail 'controlled failure after Claude stage'
        return 1
      fi
      cp -RL "$work/codex" "$codex_target" || return 1
      for role in $roles; do
        target="$agents_dir/writing-goals-$role.toml"
        cp -p "$work/agents/writing-goals-$role.toml" "$target" || return 1
      done
      ;;
  esac
}

require_bundle
prepare_sources

case "$selection" in
  claude) preflight_target "$claude_target" "$work/claude" ;;
  codex)
    preflight_target "$codex_target" "$work/codex"
    for role in $roles; do preflight_file "$agents_dir/writing-goals-$role.toml" "$work/agents/writing-goals-$role.toml"; done
    ;;
  all)
    preflight_target "$claude_target" "$work/claude"
    preflight_target "$codex_target" "$work/codex"
    for role in $roles; do preflight_file "$agents_dir/writing-goals-$role.toml" "$work/agents/writing-goals-$role.toml"; done
    ;;
esac

if ! install_selection; then
  rollback || fail 'installation failed and rollback was incomplete'
  exit 1
fi
printf 'Installed writing-goals copies for %s.\n' "$selection"
