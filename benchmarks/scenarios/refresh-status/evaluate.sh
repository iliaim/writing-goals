#!/usr/bin/env bash
# Scenario oracle, executed outside the model process after it exits. It copies
# the candidate first so its fixtures cannot change the candidate evidence.
set -euo pipefail

[ "$#" -eq 1 ] || { printf 'usage: %s WORKTREE\n' "$0" >&2; exit 2; }
worktree=$1

[ -d "$worktree" ] || { printf 'missing worktree: %s\n' "$worktree" >&2; exit 2; }
[ -z "$(git -C "$worktree" status --porcelain)" ] || {
  printf '%s\n' 'candidate worktree is dirty; benchmark requires a local commit' >&2
  exit 1
}

scratch="$(mktemp -d "${TMPDIR:-/tmp}/writing-goals-benchmark-oracle.XXXXXX")"
cleanup() { rm -rf -- "$scratch"; }
trap cleanup EXIT HUP INT TERM
candidate="$scratch/candidate"
home="$scratch/home"
codex_home="$scratch/codex-home"
git clone --quiet --no-local "$worktree" "$candidate"
mkdir -p "$home" "$codex_home"

snapshot() {
  find "$candidate" "$home" "$codex_home" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort
}

run_status() {
  before="$scratch/before"
  after="$scratch/after"
  snapshot > "$before"
  actual="$(HOME="$home" CODEX_HOME="$codex_home" bash "$candidate/scripts/refresh-local.sh" --status)"
  snapshot > "$after"
  cmp -s "$before" "$after" || {
    printf '%s\n' 'status mode changed a candidate or isolated-home file' >&2
    exit 1
  }
  [ "$actual" = "$1" ] || {
    printf 'unexpected status output:\n%s\n' "$actual" >&2
    exit 1
  }
}

run_status $'Claude: missing\nCodex: missing\nLatest archive: none'
mkdir -p "$home/.claude/skills/writing-goals" "$codex_home/skills" \
  "$candidate/.archive/writing-goals/20260730T000000Z" \
  "$candidate/.archive/writing-goals/20260731T000000Z"
ln -s "$scratch/codex-skill" "$codex_home/skills/writing-goals"
run_status "Claude: copy
Codex: symlink
Latest archive: $candidate/.archive/writing-goals/20260731T000000Z"
