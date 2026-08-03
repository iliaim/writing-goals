#!/usr/bin/env bash
# Refresh locally installed writing-goals copies from this checkout.
set -euo pipefail

usage() {
  printf 'usage: %s (--status | --check-updates | --install [claude|codex|all])\n' "$0" >&2
}

source_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

source_identity() {
  [ -f "$source_root/VERSION" ] && [ ! -L "$source_root/VERSION" ] || return 1
  source_version="$(tr -d '\r\n' < "$source_root/VERSION")"
  printf '%s\n' "$source_version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' || return 1
  source_revision="$(git -C "$source_root" rev-parse --verify HEAD 2>/dev/null)" || return 1
}

installed_identity() {
  metadata="$1/shared/release-info.env"
  [ -f "$metadata" ] && [ ! -L "$metadata" ] || return 1

  metadata_format='' metadata_version='' metadata_revision='' metadata_keys=''
  while IFS= read -r metadata_line || [ -n "$metadata_line" ]; do
    metadata_key=${metadata_line%%=*}
    metadata_value=${metadata_line#*=}
    [ "$metadata_key" != "$metadata_line" ] || return 1
    case "|$metadata_keys|" in *"|$metadata_key|"*) return 1 ;; esac
    metadata_keys="${metadata_keys}${metadata_keys:+|}$metadata_key"
    case "$metadata_key" in
      format) metadata_format=$metadata_value ;;
      version) metadata_version=$metadata_value ;;
      revision) metadata_revision=$metadata_value ;;
      *) return 1 ;;
    esac
  done < "$metadata"

  [ "$metadata_format" = 1 ] &&
    printf '%s\n' "$metadata_version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' &&
    printf '%s\n' "$metadata_revision" | grep -Eq '^[0-9a-f]{40}$' || return 1
  printf '%s\t%s\n' "$metadata_version" "$metadata_revision"
}

report_target() {
  target_label="$1"
  target_path="$2"
  if [ ! -e "$target_path" ] && [ ! -L "$target_path" ]; then
    printf '%s: not installed\n' "$target_label"
    return
  fi
  identity="$(installed_identity "$target_path")" || {
    printf '%s: unknown legacy install\n' "$target_label"
    return
  }
  IFS=$'\t' read -r installed_version installed_revision <<EOF
$identity
EOF
  if [ "$installed_version" = "$source_version" ] && [ "$installed_revision" = "$source_revision" ]; then
    printf '%s: version %s revision %s (matches source)\n' "$target_label" "$installed_version" "$installed_revision"
  else
    printf '%s: version %s revision %s (differs from source)\n' "$target_label" "$installed_version" "$installed_revision"
  fi
}

report_status() {
  source_identity || {
    printf '%s\n' 'ERROR: status requires a Git checkout with a valid VERSION file.' >&2
    return 1
  }
  claude_target="$HOME/.claude/skills/writing-goals"
  codex_target="${CODEX_HOME:-$HOME/.codex}/skills/writing-goals"
  printf 'Source: version %s revision %s\n' "$source_version" "$source_revision"
  report_target Claude "$claude_target"
  report_target Codex "$codex_target"
}

check_updates() {
  report_status || return 1
  current_branch="$(git -C "$source_root" symbolic-ref --quiet --short HEAD 2>/dev/null)" || {
    printf '%s\n' 'ERROR: update check requires a checked-out branch with an upstream.' >&2
    return 1
  }
  upstream_remote="$(git -C "$source_root" config --get "branch.$current_branch.remote")"
  upstream_ref="$(git -C "$source_root" config --get "branch.$current_branch.merge")"
  case "$upstream_ref" in refs/heads/*) ;; *) printf '%s\n' 'ERROR: update check requires a branch upstream.' >&2; return 1 ;;
  esac
  [ -n "$upstream_remote" ] || { printf '%s\n' 'ERROR: update check requires a branch upstream.' >&2; return 1; }
  if ! git -C "$source_root" fetch --quiet --no-tags "$upstream_remote" "$upstream_ref"; then
    printf '%s\n' 'ERROR: unable to check the configured upstream; no files were installed or updated.' >&2
    return 1
  fi
  counts="$(git -C "$source_root" rev-list --left-right --count HEAD...FETCH_HEAD)" || return 1
  IFS=$'\t' read -r ahead behind <<EOF
$counts
EOF
  if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
    printf '%s\n' 'Upstream: source checkout is up to date.'
  elif [ "$ahead" -eq 0 ]; then
    printf 'Upstream: update available; source checkout is behind by %s commit(s). Run: git pull --ff-only && bash scripts/refresh-local.sh --install all\n' "$behind"
  elif [ "$behind" -eq 0 ]; then
    printf 'Upstream: local checkout is ahead by %s commit(s); no update to install.\n' "$ahead"
  else
    printf 'Upstream: local checkout has diverged (%s ahead, %s behind); reconcile Git before installing.\n' "$ahead" "$behind"
  fi
}

selection=all
case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --status)
    [ "$#" -eq 1 ] || { usage; exit 2; }
    report_status
    exit $?
    ;;
  --check-updates)
    [ "$#" -eq 1 ] || { usage; exit 2; }
    check_updates
    exit $?
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
