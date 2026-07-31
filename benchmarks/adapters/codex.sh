#!/usr/bin/env bash
# Construct and run one non-interactive Codex benchmark arm.
set -euo pipefail

[ "$#" -eq 4 ] || {
  printf 'usage: %s WORKTREE MODEL PROMPT FINAL_MESSAGE\n' "$0" >&2
  exit 2
}

worktree=$1
model=$2
prompt=$3
final_message=$4

set -- codex exec -c 'approval_policy="never"' --model "$model" --cd "$worktree" \
  --ignore-user-config --sandbox workspace-write --json \
  --output-last-message "$final_message"
set -- "$@" -

"$@" < "$prompt"
