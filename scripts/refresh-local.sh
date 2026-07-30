#!/usr/bin/env bash
# Refresh locally installed writing-goals copies from this checkout.
set -euo pipefail

usage() {
  printf 'usage: %s --install [claude|codex|all]\n' "$0" >&2
}

if [ "${1:-}" = --status ]; then
  [ "$#" -eq 1 ] || { usage; exit 2; }

  source_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
  case "$HOME" in
    /Users/user) claude_target="/Users/user/.claude/skills/writing-goals" ;;
    *) claude_target="$HOME/.claude/skills/writing-goals" ;;
  esac
  codex_target="${CODEX_HOME:-$HOME/.codex}/skills/writing-goals"

  if [ -L "$claude_target" ]; then
    claude_status=symlink
  elif [ -e "$claude_target" ]; then
    claude_status=copy
  else
    claude_status=missing
  fi

  if [ -L "$codex_target" ]; then
    codex_status=symlink
  elif [ -e "$codex_target" ]; then
    codex_status=copy
  else
    codex_status=missing
  fi

  archive_root="$source_root/.archive/writing-goals"
  latest_archive="$(
    if [ -d "$archive_root" ]; then
      find "$archive_root" -mindepth 1 -maxdepth 1 -type d -print |
        LC_ALL=C sort |
        tail -n 1
    fi
  )"
  [ -n "$latest_archive" ] || latest_archive=none

  printf 'Claude: %s\nCodex: %s\nLatest archive: %s\n' \
    "$claude_status" "$codex_status" "$latest_archive"
  exit 0
fi

selection=all
case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --install)
    selection="${2:-all}"
    [ "$#" -le 2 ] || { usage; exit 2; }
    ;;
  *)
    printf '%s\n' 'ERROR: explicit --install is required; no installed copies were changed.' >&2
    usage
    exit 2
    ;;
esac

case "$selection" in claude|codex|all) ;; *) usage; exit 2 ;; esac

source_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$source_root"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf '%s\n' 'ERROR: refresh must run from a Git checkout.' >&2
  exit 1
}
if [ -n "$(git status --porcelain)" ]; then
  printf '%s\n' 'ERROR: source checkout is dirty; commit or stash changes before refreshing.' >&2
  exit 1
fi

bash tests/run.sh

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
bundle_parent="$source_root/dist"
bundle="$bundle_parent/writing-goals-$stamp"
backup_root="$source_root/.archive/writing-goals/$stamp"
[ ! -e "$bundle" ] && [ ! -L "$bundle" ] || {
  printf 'ERROR: bundle path already exists: %s\n' "$bundle" >&2
  exit 1
}
[ ! -e "$backup_root" ] && [ ! -L "$backup_root" ] || {
  printf 'ERROR: backup path already exists: %s\n' "$backup_root" >&2
  exit 1
}

mkdir -p "$bundle_parent" "$backup_root"
bash scripts/build-bundles.sh "$bundle"

claude_target="$HOME/.claude/skills/writing-goals"
codex_root="${CODEX_HOME:-$HOME/.codex}"
codex_target="$codex_root/skills/writing-goals"
roles='planner challenger oracle-author maker verifier reviewer publisher'
backup_sources=()
backup_destinations=()
published=()
completed=false

backup_target() {
  local target="$1" name="$2"
  if [ -e "$target" ] || [ -L "$target" ]; then
    mkdir -p "$backup_root/$(dirname -- "$name")"
    mv "$target" "$backup_root/$name"
    backup_sources+=("$backup_root/$name")
    backup_destinations+=("$target")
  fi
}

restore_previous() {
  local status="$1" index
  [ "$completed" = true ] && exit "$status"
  for target in "${published[@]}"; do
    [ ! -e "$target" ] && [ ! -L "$target" ] || rm -rf -- "$target"
  done
  for ((index = ${#backup_sources[@]} - 1; index >= 0; index--)); do
    mkdir -p "$(dirname -- "${backup_destinations[$index]}")"
    mv "${backup_sources[$index]}" "${backup_destinations[$index]}"
  done
  exit "$status"
}
trap 'status=$?; restore_previous "$status"' EXIT HUP INT TERM

case "$selection" in
  claude)
    backup_target "$claude_target" claude-writing-goals
    published+=("$claude_target")
    ;;
  codex)
    backup_target "$codex_target" codex-writing-goals
    published+=("$codex_target")
    for role in $roles; do
      agent="$codex_root/agents/writing-goals-$role.toml"
      backup_target "$agent" "codex-agents/writing-goals-$role.toml"
      published+=("$agent")
    done
    ;;
  all)
    backup_target "$claude_target" claude-writing-goals
    backup_target "$codex_target" codex-writing-goals
    published+=("$claude_target" "$codex_target")
    for role in $roles; do
      agent="$codex_root/agents/writing-goals-$role.toml"
      backup_target "$agent" "codex-agents/writing-goals-$role.toml"
      published+=("$agent")
    done
    ;;
esac

bash "$bundle/install.sh" "$selection"
completed=true
trap - EXIT HUP INT TERM

printf 'Refresh complete. Bundle: %s\nBackup: %s\nRestart Codex and Claude Code to reload installed definitions.\n' "$bundle" "$backup_root"
