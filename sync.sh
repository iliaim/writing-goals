#!/usr/bin/env bash
# Install writing-goals into agent skill trees via SYMLINKS.
# Single source of truth = this build folder; edits here propagate live.
# Usage: ./sync.sh [claude|codex|all]   (default: all)
set -euo pipefail
BD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install_claude() {
  local dest="$HOME/.claude/skills/writing-goals"
  mkdir -p "$dest"
  ln -sfn "$BD/claude/SKILL.md" "$dest/SKILL.md"   # centerpiece
  ln -sfn "$BD/shared"          "$dest/shared"      # neutral core (referenced on demand)
  ln -sfn "$BD/assets"          "$dest/assets"      # gate hook, deny-list, .goals template
  echo "Claude  -> $dest  (invoke as /writing-goals)"
}

install_codex() {
  # Codex adapter is a later phase; only install if it exists.
  [ -f "$BD/codex/SKILL.md" ] || { echo "Codex   -> adapter not built yet, skipping"; return 0; }
  local dest="$HOME/.agents/skills/writing-goals"   # canonical Codex/agent-skills location
  mkdir -p "$dest"
  ln -sfn "$BD/codex/SKILL.md" "$dest/SKILL.md"
  if [ -f "$BD/codex/agents/openai.yaml" ]; then
    mkdir -p "$dest/agents"; ln -sfn "$BD/codex/agents/openai.yaml" "$dest/agents/openai.yaml"
  fi
  ln -sfn "$BD/shared"  "$dest/shared"
  ln -sfn "$BD/assets"  "$dest/assets"
  echo "Codex   -> $dest  (invoke as \$writing-goals / /skills picker)"
}

case "${1:-all}" in
  claude) install_claude ;;
  codex)  install_codex ;;
  all)    install_claude; install_codex ;;
  *) echo "usage: $0 [claude|codex|all]"; exit 1 ;;
esac
