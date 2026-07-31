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
codex_skill="$scratch/codex-skill"
git clone --quiet --no-local "$worktree" "$candidate"
candidate="$(CDPATH= cd -- "$candidate" && pwd -P)"
mkdir -p "$home" "$codex_home" "$codex_skill"

snapshot() {
  find "$candidate" "$home" "$codex_home" "$codex_skill" -print | LC_ALL=C sort | while IFS= read -r path; do
    if stat -f '%Lp\t%m' "$path" >/dev/null 2>&1; then
      metadata="$(stat -f '%Lp\t%m' "$path")"
    else
      metadata="$(stat -c '%a\t%Y' "$path")"
    fi
    if [ -L "$path" ]; then
      printf 'symlink\t%s\t%s\t%s\n' "$path" "$metadata" "$(readlink "$path")"
    elif [ -d "$path" ]; then
      printf 'directory\t%s\t%s\n' "$path" "$metadata"
    elif [ -f "$path" ]; then
      printf 'file\t%s\t%s\t%s\n' "$path" "$metadata" "$(shasum -a 256 "$path" | awk '{print $1}')"
    else
      printf 'other\t%s\t%s\n' "$path" "$metadata"
    fi
  done
}

run_status() {
  before="$scratch/before"
  after="$scratch/after"
  snapshot > "$before"
  actual="$scratch/status-output"
  status_error="$scratch/status-error"
  set +e
  HOME="$home" CODEX_HOME="$codex_home" bash "$candidate/scripts/refresh-local.sh" --status > "$actual" 2> "$status_error"
  status=$?
  set -e
  [ "$status" -eq 0 ] || {
    printf 'status mode failed: %s\n' "$status" >&2
    exit 1
  }
  [ ! -s "$status_error" ] || {
    printf '%s\n' 'status mode wrote unexpected stderr output' >&2
    exit 1
  }
  snapshot > "$after"
  cmp -s "$before" "$after" || {
    printf '%s\n' 'status mode changed a candidate or isolated-home file' >&2
    exit 1
  }
  expected="$scratch/status-expected"
  printf '%s\n' "$1" > "$expected"
  cmp -s "$expected" "$actual" || {
    printf 'unexpected status output:\n' >&2
    cat "$actual" >&2
    exit 1
  }
}

run_status $'Claude: missing\nCodex: missing\nLatest archive: none'
mkdir -p "$home/.claude/skills/writing-goals" "$codex_home/skills" \
  "$candidate/.archive/writing-goals/20260730T000000Z" \
  "$candidate/.archive/writing-goals/20260731T000000Z"
ln -s "$codex_skill" "$codex_home/skills/writing-goals"
run_status "Claude: copy
Codex: symlink
Latest archive: $candidate/.archive/writing-goals/20260731T000000Z"

help_output="$scratch/help-output"
help_error="$scratch/help-error"
snapshot > "$scratch/help-before"
set +e
bash "$candidate/scripts/refresh-local.sh" --help > "$help_output" 2> "$help_error"
help_status=$?
set -e
snapshot > "$scratch/help-after"
cmp -s "$scratch/help-before" "$scratch/help-after" || {
  printf '%s\n' 'help mode changed a candidate or isolated-home file' >&2
  exit 1
}
printf 'usage: %s --install [claude|codex|all]\n' "$candidate/scripts/refresh-local.sh" > "$scratch/help-expected"
[ "$help_status" -eq 0 ] && [ ! -s "$help_output" ] && cmp -s "$scratch/help-expected" "$help_error" || {
  printf '%s\n' 'help mode did not preserve its exact install guidance' >&2
  exit 1
}

verify_install() {
  selection=$1
  install_candidate="$scratch/install-$selection-candidate"
  install_home="$scratch/install-$selection-home"
  git clone --quiet --no-local "$candidate" "$install_candidate"
  HOME="$install_home" CODEX_HOME="$install_home/.codex" GIT_TERMINAL_PROMPT=0 \
    bash "$install_candidate/scripts/refresh-local.sh" --install "$selection" > "$scratch/install-$selection-output"
  grep -q 'Refresh complete' "$scratch/install-$selection-output" || {
    printf 'isolated %s installation did not complete\n' "$selection" >&2
    exit 1
  }
  bundle="$(find "$install_candidate/dist" -mindepth 1 -maxdepth 1 -type d -name 'writing-goals-*' -print | LC_ALL=C sort | tail -n 1)"
  [ -n "$bundle" ] || { printf 'isolated %s bundle is missing\n' "$selection" >&2; exit 1; }
  case "$selection" in
    claude)
      [ -d "$install_home/.claude/skills/writing-goals" ] && \
        ! find "$install_home/.claude/skills/writing-goals" -type l -print -quit | grep -q . && \
        diff -qr "$bundle/claude" "$install_home/.claude/skills/writing-goals" >/dev/null || exit 1
      ;;
    codex|all)
      [ -d "$install_home/.codex/skills/writing-goals" ] && \
        ! find "$install_home/.codex/skills/writing-goals" -type l -print -quit | grep -q . && \
        diff -qr "$bundle/codex" "$install_home/.codex/skills/writing-goals" >/dev/null || exit 1
      for role in planner challenger oracle-author maker verifier reviewer publisher; do
        cmp -s "$bundle/codex/agents/writing-goals-$role.toml" "$install_home/.codex/agents/writing-goals-$role.toml" || exit 1
      done
      [ "$selection" != all ] || { \
        [ -d "$install_home/.claude/skills/writing-goals" ] && \
          ! find "$install_home/.claude/skills/writing-goals" -type l -print -quit | grep -q . && \
          diff -qr "$bundle/claude" "$install_home/.claude/skills/writing-goals" >/dev/null; \
      } || exit 1
      ;;
  esac
}

verify_install claude
verify_install codex
verify_install all
