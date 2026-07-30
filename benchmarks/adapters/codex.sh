#!/usr/bin/env bash
# Construct and run one non-interactive Codex benchmark arm.
set -euo pipefail

[ "$#" -eq 6 ] || {
  printf 'usage: %s WORKTREE MODEL SANDBOX PERMISSION PROMPT FINAL_MESSAGE\n' "$0" >&2
  exit 2
}

worktree=$1
model=$2
sandbox=$3
permission=$4
prompt=$5
final_message=$6

case "$sandbox" in read-only|workspace-write|danger-full-access) ;; *) exit 2 ;; esac
case "$permission" in standard|dangerous) ;; *) exit 2 ;; esac

set -- codex exec --model "$model" --cd "$worktree" --ignore-user-config --json \
  --output-last-message "$final_message"
if [ "$permission" = dangerous ]; then
  set -- "$@" --dangerously-bypass-approvals-and-sandbox
else
  set -- "$@" --sandbox "$sandbox"
fi
set -- "$@" -

"$@" < "$prompt"
